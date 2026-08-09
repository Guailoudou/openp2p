#!/usr/bin/env bash
set -Eeuo pipefail

readonly DEFAULT_SOURCE_DIR="/home/nhd/ohos-build/source/openp2p-master"
readonly DEFAULT_OHOS_ROOT="/home/nhd/ohos-build"

SOURCE_DIR="${1:-${OPENP2P_SOURCE_DIR:-$DEFAULT_SOURCE_DIR}}"
OHOS_ROOT="${OPENP2P_OHOS_ROOT:-$DEFAULT_OHOS_ROOT}"
OUTPUT_ROOT="${2:-${OPENP2P_ARTIFACT_ROOT:-$OHOS_ROOT/output/runs}}"

SOURCE_DIR="$(realpath "$SOURCE_DIR")"
OHOS_ROOT="$(realpath "$OHOS_ROOT")"
mkdir -p "$OUTPUT_ROOT"
OUTPUT_ROOT="$(realpath "$OUTPUT_ROOT")"

OHOS_GO_ROOT="$OHOS_ROOT/ohos_golang_go"
OHOS_CC="$OHOS_ROOT/ohos-clang"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
OUTPUT_DIR="$OUTPUT_ROOT/$RUN_ID"
WORK_DIR="/tmp/openp2p-ohos-$RUN_ID"

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "缺少文件: $1" >&2
    exit 1
  fi
}

require_executable() {
  if [[ ! -x "$1" ]]; then
    echo "缺少可执行文件: $1" >&2
    exit 1
  fi
}

require_file "$SOURCE_DIR/go.mod"
require_file "$SOURCE_DIR/go.sum"
require_file "$SOURCE_DIR/cmd/openp2p_ohos.go"
require_executable "$OHOS_GO_ROOT/bin/go"
require_executable "$OHOS_CC"
require_file "$OHOS_ROOT/sysroot-root/sysroot/usr/lib/aarch64-linux-ohos/libc.so"
require_file "$OHOS_ROOT/native-runtime/llvm/lib/clang/15.0.4/lib/aarch64-linux-ohos/libclang_rt.builtins.a"

if ! "$OHOS_GO_ROOT/bin/go" tool dist list | grep -Fxq 'openharmony/arm64'; then
  echo "OpenHarmony-SIG Go 不支持 openharmony/arm64: $OHOS_GO_ROOT" >&2
  exit 1
fi

mkdir "$OUTPUT_DIR"
mkdir "$WORK_DIR"
mkdir "$WORK_DIR/go-cache" "$WORK_DIR/go-path" "$WORK_DIR/tmp"

SOURCE_HASH_BEFORE="$WORK_DIR/source-before.sha256"
SOURCE_HASH_AFTER="$WORK_DIR/source-after.sha256"
(
  cd "$SOURCE_DIR"
  sha256sum go.mod go.sum cmd/openp2p_ohos.go core/openp2p.go > "$SOURCE_HASH_BEFORE"
)

export GOROOT="$OHOS_GO_ROOT"
export PATH="$GOROOT/bin:/usr/local/bin:/usr/bin:/bin"
export GOOS=openharmony
export GOARCH=arm64
export CGO_ENABLED=1
export CC="$OHOS_CC"
export OHOS_NATIVE_ROOT="$OHOS_ROOT/sysroot-root"
export OHOS_CLANG_RESOURCE_VERSION=15.0.4
export GOPATH="$WORK_DIR/go-path"
export GOCACHE="$WORK_DIR/go-cache"
export GOMODCACHE="$WORK_DIR/go-path/pkg/mod"
export TMPDIR="$WORK_DIR/tmp"
export GOTOOLCHAIN=local
unset GOFLAGS CXX

echo "SOURCE_DIR=$SOURCE_DIR"
echo "OUTPUT_DIR=$OUTPUT_DIR"
echo "WORK_DIR=$WORK_DIR"
go version
go env GOOS GOARCH CGO_ENABLED CC GOROOT

cd "$SOURCE_DIR"
go mod download
go build \
  -mod=readonly \
  -tags openharmony \
  -buildmode=c-shared \
  -trimpath \
  -ldflags=-s \
  -o "$OUTPUT_DIR/libopenp2p_ohos.so" \
  ./cmd

SO="$OUTPUT_DIR/libopenp2p_ohos.so"
HEADER="$OUTPUT_DIR/libopenp2p_ohos.h"
require_file "$SO"
require_file "$HEADER"

file "$SO"
readelf -h "$SO"
readelf -d "$SO"
readelf -rW "$SO" | grep -E 'TLS|TLSDESC' || true

readelf -h "$SO" | grep -Eq 'Class:[[:space:]]+ELF64'
readelf -h "$SO" | grep -Eq 'Type:[[:space:]]+DYN'
readelf -h "$SO" | grep -Eq 'Machine:[[:space:]]+AArch64'
if readelf -d "$SO" | grep -Eq 'libc\.so\.6|ld-linux'; then
  echo "检测到 Linux glibc 依赖，拒绝该鸿蒙产物" >&2
  exit 1
fi

SYMBOLS=(
  OpenP2PStart
  OpenP2PStartWithNode
  OpenP2PStop
  OpenP2PGetStatus
  OpenP2PGetLastError
  OpenP2PGetSDWANConfig
  OpenP2PGetNodeName
  OpenP2PReadTun
  OpenP2PWriteTun
  OpenP2PIsRunning
)

nm -D --defined-only "$SO" > "$OUTPUT_DIR/exported-symbols.txt"
for symbol in "${SYMBOLS[@]}"; do
  if ! awk '{print $3}' "$OUTPUT_DIR/exported-symbols.txt" | grep -Fxq "$symbol"; then
    echo "缺少导出符号: $symbol" >&2
    exit 1
  fi
done

(
  cd "$SOURCE_DIR"
  sha256sum go.mod go.sum cmd/openp2p_ohos.go core/openp2p.go > "$SOURCE_HASH_AFTER"
)
diff -u "$SOURCE_HASH_BEFORE" "$SOURCE_HASH_AFTER"

sha256sum "$SO" "$HEADER" | tee "$OUTPUT_DIR/SHA256SUMS"
cp "$SOURCE_HASH_BEFORE" "$OUTPUT_DIR/source-inputs.sha256"

echo "鸿蒙核心构建并校验成功"
echo "OUTPUT_DIR=$OUTPUT_DIR"
echo "注意: WORK_DIR 默认保留，不执行自动删除: $WORK_DIR"
