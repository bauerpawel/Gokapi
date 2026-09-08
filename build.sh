#!/usr/bin/env bash
#
# Cross-compiles Gokapi (and the gokapi-cli companion tool) for Windows and
# Linux, and copies an example configuration file next to the binaries.
#
# Usage: ./build.sh
#
# Requires only a Go toolchain - no CGO / C compiler needed, since Gokapi
# is CGO-free (modernc.org/sqlite is a pure-Go SQLite implementation).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OUT_DIR="dist"
GOPACKAGE="github.com/forceu/gokapi"
BUILD_TIME="$(date)"
LDFLAGS="-s -w -X '${GOPACKAGE}/internal/environment.Builder=Build Script' -X '${GOPACKAGE}/internal/environment.BuildTime=${BUILD_TIME}'"

# GOOS/GOARCH targets to build. Add more lines to build for more platforms,
# e.g. "darwin amd64" or "windows arm64".
TARGETS=(
  "linux amd64"
  "linux arm64"
  "windows amd64"
)

echo "Running go generate (version numbers, WASM modules, minified assets)..."
go generate ./...

echo "Cleaning ${OUT_DIR}/..."
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

build_binary() {
  local goos="$1" goarch="$2" pkg="$3" name="$4"
  local ext=""
  [ "$goos" = "windows" ] && ext=".exe"
  local out="${OUT_DIR}/${name}-${goos}-${goarch}${ext}"
  echo "Building ${out}..."
  CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" \
    go build -ldflags "$LDFLAGS" -o "$out" "$pkg"
}

for target in "${TARGETS[@]}"; do
  read -r goos goarch <<<"$target"
  build_binary "$goos" "$goarch" "${GOPACKAGE}/cmd/gokapi" "gokapi"
  build_binary "$goos" "$goarch" "${GOPACKAGE}/cmd/cli-uploader" "gokapi-cli"
done

echo "Copying example configuration..."
cp gokapi.env.example "${OUT_DIR}/gokapi.env.example"

echo
echo "Done. Binaries and example config are in ./${OUT_DIR}/:"
ls -la "$OUT_DIR"
