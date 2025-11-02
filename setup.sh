#!/usr/bin/env bash
set -e
set -o pipefail

ROOT_DIR="$(pwd)"
DEPS_DIR="$ROOT_DIR/deps"
BUILD_DIR="$ROOT_DIR/build"
GEN_DIR="$DEPS_DIR/dear_bindings/generated"

echo "==> Initializing submodules..."
git submodule update --init --recursive

echo "==> Setting up Python virtual environment..."
python3 -m venv .venv
source .venv/bin/activate

echo "==> Installing Python dependencies..."
pip install --upgrade pip
pip install -r "$DEPS_DIR/dear_bindings/requirements.txt"

echo "==> Generating Dear ImGui C bindings..."
pushd "$DEPS_DIR/dear_bindings" > /dev/null
chmod +x BuildAllBindings.sh
./BuildAllBindings.sh
popd > /dev/null

echo "==> Copying generated bindings..."

# Ensure imgui_gen directory exists in deps
mkdir -p "$DEPS_DIR/imgui_gen"

# Copy core bindings to the deps location
cp -v "$GEN_DIR/dcimgui"* "$DEPS_DIR/imgui_gen/" || true
cp -v "$GEN_DIR/dcimgui_internal"* "$DEPS_DIR/imgui_gen/" || true

echo "==> Setup completed successfully."

