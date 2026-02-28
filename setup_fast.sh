#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# One-time setup for FastMap + FastGS pipeline
#
# Clones and installs:
#   - FastMap (fast SfM pose estimation)
#   - FastGS  (fast Gaussian Splatting)
#
# Usage:
#   ./setup_fast.sh
# ============================================================

DEPS_DIR="$(cd "$(dirname "$0")" && pwd)/deps"
mkdir -p "$DEPS_DIR"

# --- Dependency checks ---
check_cmd() {
    if ! command -v "$1" &>/dev/null; then
        echo "ERROR: '$1' not found in PATH."
        echo "       Install it before running setup."
        exit 1
    fi
}

echo "==> Checking prerequisites..."
check_cmd git
check_cmd python3
check_cmd colmap
echo "    All prerequisites found."

# --- Clone FastMap ---
echo ""
echo "==> Setting up FastMap..."
if [[ -d "$DEPS_DIR/fastmap" ]]; then
    echo "    Already cloned at $DEPS_DIR/fastmap, skipping."
else
    git clone https://github.com/pals-ttic/fastmap.git "$DEPS_DIR/fastmap"
fi

echo "    Installing FastMap Python dependencies..."
pip install -r "$DEPS_DIR/fastmap/requirements.txt"

# --- Clone FastGS ---
echo ""
echo "==> Setting up FastGS..."
if [[ -d "$DEPS_DIR/FastGS" ]]; then
    echo "    Already cloned at $DEPS_DIR/FastGS, skipping."
else
    git clone --recursive https://github.com/fastgs/FastGS.git "$DEPS_DIR/FastGS"
fi

echo "    Installing FastGS Python dependencies..."
pip install -r "$DEPS_DIR/FastGS/requirements.txt"

echo ""
echo "=========================================="
echo " Setup complete!"
echo "=========================================="
echo "You can now run:"
echo "  ./fast_pipeline.sh ./my_photos output.ply"
