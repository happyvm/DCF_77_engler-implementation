#!/usr/bin/env bash
set -euo pipefail

# One OSS CAD Suite release supplies Icarus, Verilator, Yosys, nextpnr,
# Project Trellis, SymbiYosys and Boolector as a mutually tested tool set.
readonly RELEASE=2025-02-13
readonly STAMP=20250213
readonly DEST="${1:-$HOME/.local/oss-cad-suite-${RELEASE}}"

case "$(uname -m)" in
  x86_64) arch=x64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 2 ;;
esac

archive="oss-cad-suite-linux-${arch}-${STAMP}.tgz"
url="https://github.com/YosysHQ/oss-cad-suite-build/releases/download/${RELEASE}/${archive}"

if [[ ! -x "${DEST}/bin/yosys" ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl --fail --location --retry 3 --output "${tmp}/${archive}" "$url"
  mkdir -p "$DEST"
  tar -xzf "${tmp}/${archive}" --strip-components=1 -C "$DEST"
fi

cat <<EOF
OSS CAD Suite ${RELEASE} installed in ${DEST}
Run: source ${DEST}/environment
EOF
