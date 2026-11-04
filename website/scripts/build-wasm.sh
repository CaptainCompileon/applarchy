#!/bin/bash
# Build the ttfx engine (../engine) for the browser: src/ttfx.wasm, committed so the
# site builds without Rust. WASI rather than bare wasm32: the engine reads the clock
# (std::time::Instant), which only WASI provides; src/engine.ts supplies the calls.
set -euo pipefail
cd "$(dirname "$0")/.."
RUSTUP="${RUSTUP:-$(command -v rustup || echo /opt/homebrew/opt/rustup/bin/rustup)}"
"$RUSTUP" target add wasm32-wasip1 >/dev/null
CARGO="$("$RUSTUP" which cargo --toolchain stable)"
TOOLCHAIN="$(dirname "$(dirname "$CARGO")")"
# rustup's rust-lld on macOS can't find libLLVM.dylib through its own rpath.
export DYLD_FALLBACK_LIBRARY_PATH="$TOOLCHAIN/lib${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"
PATH="$(dirname "$CARGO"):$PATH" "$CARGO" build --release --target wasm32-wasip1 --manifest-path wasm/Cargo.toml
cp wasm/target/wasm32-wasip1/release/ttfx_web.wasm src/ttfx.wasm
ls -l src/ttfx.wasm
