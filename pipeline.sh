#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Images → 3D Gaussian Splat (.ply) Pipeline
#
# Uses COLMAP for Structure-from-Motion, then OpenSplat for
# 3D Gaussian Splatting training.
#
# Usage:
#   ./pipeline.sh <image_dir> [output.ply] [options]
#
# Examples:
#   ./pipeline.sh ./my_photos
#   ./pipeline.sh ./my_photos scene.ply --num-iters 10000
#   ./pipeline.sh ./my_photos output.ply --downscale-factor 2
# ============================================================

print_usage() {
    cat <<EOF
Usage: $(basename "$0") <image_dir> [output.ply] [opensplat_options...]

Arguments:
  image_dir           Directory containing input images (jpg/png)
  output.ply          Output file path (default: splat.ply)

OpenSplat options (passed through):
  -n, --num-iters N         Training iterations (default: 30000)
  -d, --downscale-factor N  Downscale input images (default: 1)
  -s, --save-every N        Save checkpoint every N steps
      --cpu                 Force CPU execution
      --val                 Withhold one camera for validation

Dependencies:
  - colmap    (https://colmap.github.io)
  - opensplat (https://github.com/pierotofy/OpenSplat)

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

OPENSPLAT_EXTRA_ARGS=("$@")

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
check_cmd opensplat

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

# Symlink images into workspace (COLMAP expects an 'images' directory)
ln -s "$IMAGE_DIR" "$WORKSPACE/images"

DB_PATH="$WORKSPACE/database.db"
SPARSE_DIR="$WORKSPACE/sparse"
mkdir -p "$SPARSE_DIR"

# ============================================================
# Stage 1: COLMAP — Structure from Motion
# ============================================================
echo ""
echo "=========================================="
echo " Stage 1: COLMAP Structure-from-Motion"
echo "=========================================="

# 1a. Feature extraction
echo "==> [1/3] Extracting features..."
colmap feature_extractor \
    --database_path "$DB_PATH" \
    --image_path "$WORKSPACE/images" \
    --ImageReader.single_camera 1

# 1b. Feature matching
echo "==> [2/3] Matching features (exhaustive)..."
colmap exhaustive_matcher \
    --database_path "$DB_PATH"

# 1c. Sparse reconstruction (mapper)
echo "==> [3/3] Running sparse reconstruction..."
colmap mapper \
    --database_path "$DB_PATH" \
    --image_path "$WORKSPACE/images" \
    --output_path "$SPARSE_DIR"

# Verify COLMAP output
if [[ ! -d "$SPARSE_DIR/0" ]]; then
    echo "ERROR: COLMAP mapper failed to produce a reconstruction."
    echo "       Check that your images have sufficient overlap."
    exit 1
fi

COLMAP_POINTS=$(colmap model_analyzer --path "$SPARSE_DIR/0" 2>&1 | grep -i "points" | head -1 || true)
echo "    COLMAP reconstruction complete."
[[ -n "$COLMAP_POINTS" ]] && echo "    $COLMAP_POINTS"

# ============================================================
# Stage 2: OpenSplat — 3D Gaussian Splatting
# ============================================================
echo ""
echo "=========================================="
echo " Stage 2: OpenSplat Gaussian Splatting"
echo "=========================================="

echo "==> Training 3D Gaussians..."
opensplat "$WORKSPACE" \
    --cpu \
    -o "$OUTPUT" \
    "${OPENSPLAT_EXTRA_ARGS[@]+"${OPENSPLAT_EXTRA_ARGS[@]}"}"

echo ""
echo "=========================================="
echo " Done!"
echo "=========================================="
echo "Output: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
echo ""
echo "View your splat at:"
echo "  - https://playcanvas.com/supersplat/editor"
echo "  - https://antimatter15.com/splat/"
