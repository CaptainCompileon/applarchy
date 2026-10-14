# Sourced by the build scripts: builds the ttfx engine as a static library and
# sets ENGINE_LIB and ARCHS. Universal (Apple Silicon + Intel) when rustup has the
# x86_64-apple-darwin target installed; Apple Silicon only otherwise, or with ARM64_ONLY=1.
ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../engine" && pwd)"
export MACOSX_DEPLOYMENT_TARGET=13.0
RUSTUP="${RUSTUP:-$(command -v rustup || echo /opt/homebrew/opt/rustup/bin/rustup)}"
if [ "${ARM64_ONLY:-}" != 1 ] && [ -x "$RUSTUP" ] && "$RUSTUP" target list --installed 2>/dev/null | grep -q x86_64-apple-darwin; then
  # rustup's own cargo and rustc, explicitly: another Rust (e.g. Homebrew's) may come first on PATH.
  RUSTUP_CARGO="$("$RUSTUP" which cargo --toolchain stable)"
  RUSTUP_RUSTC="$("$RUSTUP" which rustc --toolchain stable)"
  for target in aarch64-apple-darwin x86_64-apple-darwin; do
    (cd "$ENGINE_DIR" && RUSTC="$RUSTUP_RUSTC" "$RUSTUP_CARGO" build --release --lib --quiet --target "$target") || exit 1
  done
  mkdir -p "$ENGINE_DIR/target/universal"
  lipo -create "$ENGINE_DIR/target/aarch64-apple-darwin/release/libttfx.a" \
               "$ENGINE_DIR/target/x86_64-apple-darwin/release/libttfx.a" \
       -output "$ENGINE_DIR/target/universal/libttfx.a"
  ENGINE_LIB="$ENGINE_DIR/target/universal/libttfx.a"
  ARCHS="arm64 x86_64"
else
  (cd "$ENGINE_DIR" && cargo build --release --lib --quiet)
  ENGINE_LIB="$ENGINE_DIR/target/release/libttfx.a"
  ARCHS="arm64"
  echo "note: building for Apple Silicon only (for Intel too: rustup target add x86_64-apple-darwin)" >&2
fi
