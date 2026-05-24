#!/bin/bash
# Brian44913/boost-2.5.2 fork build script.
#
# Usage:   ./build.sh
# Output:  boost / boostd / boostx / boostd-data / booster-http / booster-bitswap /
#          devnet / migrate-lid / migrate-curio in this directory.
# Layout requirement:
#     ./extern/filecoin-ffi             (git submodule — run "git submodule update --init --recursive" first)
#     ./extern/boostd-data              (git submodule, already in-tree)
# Toolchain on host (production build host = 192.168.134.91):
#     Go >= 1.24.7, Rust (rustup) >= 1.89, CUDA in /usr/local/cuda, gcc,
#     Node.js 22 or 24, npm (React frontend bundled via "make build").
#
# Background run:
#     nohup ./build.sh > build.log 2>&1 &

set -e
cd "$(dirname "$(readlink -f "$0")")"

source /etc/profile
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"
export PATH=/usr/local/cuda/bin:$PATH

echo "==== build start: $(date -Iseconds) ===="
echo "  go:    $(go version 2>&1)"
echo "  rust:  $(rustc --version 2>&1)"
echo "  nvcc:  $(nvcc --version 2>&1 | grep -i release || echo '<<cuda missing>>')"
echo "  node:  $(node -v 2>&1 || echo '<<node missing>>')"
echo "  npm:   $(npm -v 2>&1 || echo '<<npm missing>>')"
echo ""

env PATH=$PATH \
    LIBRARY_PATH=$LIBRARY_PATH:/usr/local/cuda/targets/x86_64-linux/lib/ \
    RUSTFLAGS="-C target-cpu=native -g" \
    FFI_BUILD_FROM_SOURCE=1 \
    FFI_USE_CUDA=1 \
    FFI_USE_CUDA_SUPRASEAL=1 \
    make clean all 2>&1

echo ""
echo "==== build end: $(date -Iseconds) ===="
ls -lh boost boostd boostx boostd-data booster-http booster-bitswap devnet migrate-lid migrate-curio 2>/dev/null
echo ""
echo "version strings:"
./boost --version 2>&1 | head -1 || true
./boostd --version 2>&1 | head -1 || true
./boostx --version 2>&1 | head -1 || true
./booster-http --version 2>&1 | head -1 || true
./booster-bitswap --version 2>&1 | head -1 || true
