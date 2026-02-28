#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Images → 3D Gaussian Splat (.ply) — Fast Pipeline
#
# Uses COLMAP (feature extraction/matching only), FastMap for
# pose estimation, and FastGS for Gaussian Splatting training.
#
# Usage:
#   ./fast_pipeline.sh <image_dir> [output.ply] [options]
#
# Examples:
#   ./fast_pipeline.sh ./my_photos
#   ./fast_pipeline.sh ./my_photos scene.ply --iterations 5000
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPS_DIR="$SCRIPT_DIR/deps"

print_usage() {
    cat <<EOF
Usage: $(basename "$0") <image_dir> [output.ply] [fastgs_options...]

Arguments:
  image_dir           Directory containing input images (jpg/png)
  output.ply          Output file path (default: splat.ply)

FastGS options (passed through):
  --iterations N      Training iterations (default: 7000)

Dependencies (install via setup_fast.sh):
  - colmap    (https://colmap.github.io)
  - FastMap   (deps/fastmap)
  - FastGS    (deps/FastGS)

EOF
    exit 1
}

# --- Argument parsing ---
if [[ $# -lt 1 ]]; then
    print_usage
fi

IMAGE_DIR="$(cd "$1" && pwd)"
shift

# Determine output file
OUTPUT="splat.ply"
if [[ $# -gt 0 && "$1" != -* ]]; then
    OUTPUT="$1"
    shift
fi

FASTGS_EXTRA_ARGS=("$@")

# --- Default training iterations ---
ITERATIONS=7000
for i in "${!FASTGS_EXTRA_ARGS[@]}"; do
    if [[ "${FASTGS_EXTRA_ARGS[$i]}" == "--iterations" ]]; then
        ITERATIONS="${FASTGS_EXTRA_ARGS[$((i+1))]}"
        break
    fi
done

# --- Dependency checks ---
check_cmd() {
    if ! command -v "$1" &>/dev/null; then
        echo "ERROR: '$1' not found in PATH."
        echo "       Install it before running this pipeline."
        exit 1
    fi
}

echo "==> Checking dependencies..."
check_cmd colmap
check_cmd python3

if [[ ! -d "$DEPS_DIR/fastmap" ]]; then
    echo "ERROR: FastMap not found at $DEPS_DIR/fastmap"
    echo "       Run ./setup_fast.sh first."
    exit 1
fi

if [[ ! -d "$DEPS_DIR/FastGS" ]]; then
    echo "ERROR: FastGS not found at $DEPS_DIR/FastGS"
    echo "       Run ./setup_fast.sh first."
    exit 1
fi
echo "    All dependencies found."

# --- Validate input ---
IMAGE_COUNT=$(find "$IMAGE_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.tif' -o -iname '*.tiff' \) | wc -l | tr -d ' ')

if [[ "$IMAGE_COUNT" -lt 3 ]]; then
    echo "ERROR: Found only $IMAGE_COUNT images in '$IMAGE_DIR'."
    echo "       Need at least 3 overlapping images for reconstruction."
    exit 1
fi
echo "    Found $IMAGE_COUNT images in '$IMAGE_DIR'"

# --- Set up workspace ---
WORKSPACE="$(mktemp -d)"
trap 'echo "==> Workspace preserved at: $WORKSPACE"' EXIT

echo "==> Workspace: $WORKSPACE"

# Symlink images into workspace
ln -s "$IMAGE_DIR" "$WORKSPACE/images"

DB_PATH="$WORKSPACE/database.db"
SPARSE_DIR="$WORKSPACE/sparse"
mkdir -p "$SPARSE_DIR"

# ============================================================
# Stage 1: COLMAP — Feature Extraction & Matching
# ============================================================
echo ""
echo "=========================================="
echo " Stage 1: COLMAP Feature Extraction"
echo "=========================================="

echo "==> [1/2] Extracting features..."
colmap feature_extractor \
    --database_path "$DB_PATH" \
    --image_path "$WORKSPACE/images" \
    --ImageReader.single_camera 1

echo "==> [2/2] Matching features (exhaustive)..."
colmap exhaustive_matcher \
    --database_path "$DB_PATH"

# ============================================================
# Stage 2: FastMap — Pose Estimation
# ============================================================
echo ""
echo "=========================================="
echo " Stage 2: FastMap Pose Estimation"
echo "=========================================="

echo "==> Running FastMap..."
python3 "$DEPS_DIR/fastmap/run.py" \
    --database "$DB_PATH" \
    --image_dir "$WORKSPACE/images" \
    --output_dir "$WORKSPACE" \
    --headless

# Verify FastMap output
if [[ ! -d "$SPARSE_DIR/0" ]]; then
    echo "ERROR: FastMap failed to produce a reconstruction."
    echo "       Check that your images have sufficient overlap."
    exit 1
fi
echo "    FastMap reconstruction complete."

# ============================================================
# Stage 3: FastGS — 3D Gaussian Splatting
# ============================================================
echo ""
echo "=========================================="
echo " Stage 3: FastGS Gaussian Splatting"
echo "=========================================="

MODEL_DIR="$WORKSPACE/fastgs_model"

echo "==> Training 3D Gaussians (iterations: $ITERATIONS)..."
python3 "$DEPS_DIR/FastGS/train.py" \
    -s "$WORKSPACE" \
    -m "$MODEL_DIR" \
    "${FASTGS_EXTRA_ARGS[@]+"${FASTGS_EXTRA_ARGS[@]}"}"

# Copy final PLY to output path
FINAL_PLY="$MODEL_DIR/point_cloud/iteration_${ITERATIONS}/point_cloud.ply"
if [[ ! -f "$FINAL_PLY" ]]; then
    echo "ERROR: Expected output not found at $FINAL_PLY"
    echo "       Searching for any PLY output..."
    FINAL_PLY=$(find "$MODEL_DIR" -name "point_cloud.ply" -type f | sort | tail -1)
    if [[ -z "$FINAL_PLY" ]]; then
        echo "ERROR: No PLY file found in $MODEL_DIR"
        exit 1
    fi
    echo "    Found: $FINAL_PLY"
fi

cp "$FINAL_PLY" "$OUTPUT"

echo ""
echo "=========================================="
echo " Done!"
echo "=========================================="
echo "Output: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
echo ""
echo "View your splat at:"
echo "  - https://playcanvas.com/supersplat/editor"
echo "  - https://antimatter15.com/splat/"
