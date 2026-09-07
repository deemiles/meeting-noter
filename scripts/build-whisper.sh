#!/bin/zsh
# Rebuilds the bundled whisper-cli from source as a self-contained binary.
# The result is committed to Resources/bin/ so users never need Homebrew.
# Requires cmake (brew install cmake) — build machine only, not end users.
set -euo pipefail

PROJECT_DIR="${0:a:h:h}"
WHISPER_VERSION="${WHISPER_VERSION:-v1.8.6}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone --depth 1 --branch "$WHISPER_VERSION" https://github.com/ggml-org/whisper.cpp.git "$WORK/whisper.cpp"
cd "$WORK/whisper.cpp"

# Static libs + embedded Metal shaders = one binary with no dylib dependencies
# beyond the system frameworks.
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0
cmake --build build --config Release --target whisper-cli -j "$(sysctl -n hw.ncpu)"

mkdir -p "$PROJECT_DIR/Resources/bin"
cp build/bin/whisper-cli "$PROJECT_DIR/Resources/bin/whisper-cli"
chmod +x "$PROJECT_DIR/Resources/bin/whisper-cli"

echo "Bundled whisper-cli updated ($WHISPER_VERSION):"
otool -L "$PROJECT_DIR/Resources/bin/whisper-cli" | tail -n +2 | grep -v "^\s*/System\|^\s*/usr/lib" || echo "  no external dylibs"
