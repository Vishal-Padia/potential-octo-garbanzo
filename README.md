# potential-octo-garbanzo

Images → 3D Gaussian Splat (`.ply`) pipeline using [COLMAP](https://colmap.github.io/) and [OpenSplat](https://github.com/pierotofy/OpenSplat).

## Prerequisites

Install both tools before running the pipeline:

### COLMAP

```bash
# macOS
brew install colmap

# Ubuntu/Debian
sudo apt install colmap
```

### OpenSplat

```bash
# macOS (Metal GPU)
brew install cmake opencv pytorch
git clone https://github.com/pierotofy/OpenSplat && cd OpenSplat
mkdir build && cd build
cmake -DCMAKE_PREFIX_PATH=$(brew --prefix pytorch) -DGPU_RUNTIME=MPS .. && make -j$(sysctl -n hw.logicalcpu)
# Add the build directory to your PATH, or copy the 'opensplat' binary somewhere in PATH

# Linux (CUDA) — see OpenSplat README for full instructions
```

## Usage

```bash
# Basic — outputs splat.ply
./pipeline.sh ./my_photos

# Custom output path
./pipeline.sh ./my_photos scene.ply

# Fewer iterations (faster, lower quality)
./pipeline.sh ./my_photos output.ply -n 5000

# Downscale images (useful for large photos)
./pipeline.sh ./my_photos output.ply --downscale-factor 2

# CPU-only (slow, but works without GPU)
./pipeline.sh ./my_photos output.ply --cpu
```

## How It Works

1. **COLMAP SfM** — extracts features from images, matches them, and solves for camera poses + a sparse 3D point cloud
2. **OpenSplat** — trains 3D Gaussian Splatting on the COLMAP output and exports a `.ply` file

## Viewing the Output

Upload your `.ply` file to:
- [SuperSplat Editor](https://playcanvas.com/supersplat/editor)
- [splat viewer](https://antimatter15.com/splat/)
