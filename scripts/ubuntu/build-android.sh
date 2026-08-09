#!/usr/bin/env bash
set -Eeuo pipefail

readonly DEFAULT_SOURCE_DIR="/home/nhd/ohos-build/source/openp2p-master"
readonly DEFAULT_ANDROID_ROOT="/home/nhd/android-build"
readonly MOBILE_REVISION="7c4916698cc93475ebfea76748ee0faba2deb2a5"

SOURCE_DIR="${1:-${OPENP2P_SOURCE_DIR:-$DEFAULT_SOURCE_DIR}}"
ANDROID_ROOT="${OPENP2P_ANDROID_ROOT:-$DEFAULT_ANDROID_ROOT}"
OUTPUT_ROOT="${2:-${OPENP2P_ARTIFACT_ROOT:-$ANDROID_ROOT/output/runs}}"

SOURCE_DIR="$(realpath "$SOURCE_DIR")"
ANDROID_ROOT="$(realpath "$ANDROID_ROOT")"
mkdir -p "$OUTPUT_ROOT"
OUTPUT_ROOT="$(realpath "$OUTPUT_ROOT")"

STANDARD_GO_ROOT="$ANDROID_ROOT/go1.24.5"
ANDROID_SDK_ROOT="${OPENP2P_ANDROID_SDK_ROOT:-/usr/lib/android-sdk}"
ANDROID_NDK_ROOT="${OPENP2P_ANDROID_NDK_ROOT:-$ANDROID_ROOT/android-sdk/android-ndk-r21e}"
TOOLS_BIN="$ANDROID_ROOT/bin"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
OUTPUT_DIR="$OUTPUT_ROOT/$RUN_ID"
WORK_DIR="/tmp/openp2p-android-$RUN_ID"
SOURCE_COPY="$WORK_DIR/source"

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
require_file "$SOURCE_DIR/core/openp2p.go"
require_executable "$STANDARD_GO_ROOT/bin/go"
require_executable "$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/clang"
require_file "$ANDROID_SDK_ROOT/platforms/android-23/android.jar"
require_executable /usr/bin/java
require_executable /usr/bin/javap
require_executable /usr/bin/unzip

mkdir -p "$TOOLS_BIN"
mkdir "$OUTPUT_DIR"
mkdir "$WORK_DIR"
mkdir "$WORK_DIR/go-cache" "$WORK_DIR/go-path" "$WORK_DIR/tmp" "$SOURCE_COPY"

SOURCE_HASH_BEFORE="$WORK_DIR/source-before.sha256"
SOURCE_HASH_AFTER="$WORK_DIR/source-after.sha256"
(
  cd "$SOURCE_DIR"
  sha256sum go.mod go.sum core/openp2p.go > "$SOURCE_HASH_BEFORE"
)

export GOROOT="$STANDARD_GO_ROOT"
export PATH="$GOROOT/bin:$TOOLS_BIN:/usr/local/bin:/usr/bin:/bin"
export GOPATH="$WORK_DIR/go-path"
export GOBIN="$TOOLS_BIN"
export GOCACHE="$WORK_DIR/go-cache"
export GOMODCACHE="$WORK_DIR/go-path/pkg/mod"
export TMPDIR="$WORK_DIR/tmp"
export GOTOOLCHAIN=local
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export ANDROID_SDK_ROOT
export ANDROID_NDK_HOME="$ANDROID_NDK_ROOT"
unset GOOS GOARCH CC CXX CGO_ENABLED GOFLAGS

echo "SOURCE_DIR=$SOURCE_DIR"
echo "OUTPUT_DIR=$OUTPUT_DIR"
echo "WORK_DIR=$WORK_DIR"
go version
grep -E '^Pkg.Revision' "$ANDROID_NDK_ROOT/source.properties"

if [[ ! -x "$TOOLS_BIN/gomobile" ]]; then
  go install "golang.org/x/mobile/cmd/gomobile@$MOBILE_REVISION"
fi
if [[ ! -x "$TOOLS_BIN/gobind" ]]; then
  go install "golang.org/x/mobile/cmd/gobind@$MOBILE_REVISION"
fi

cp -a "$SOURCE_DIR/." "$SOURCE_COPY/"
cd "$SOURCE_COPY"
go get "golang.org/x/mobile/bind@$MOBILE_REVISION"

cd "$SOURCE_COPY/core"
gomobile bind \
  -target android \
  -v \
  -o "$OUTPUT_DIR/openp2p.aar"

AAR="$OUTPUT_DIR/openp2p.aar"
SOURCES="$OUTPUT_DIR/openp2p-sources.jar"
require_file "$AAR"
require_file "$SOURCES"

CHECK_DIR="$WORK_DIR/aar-check"
mkdir "$CHECK_DIR"
unzip -q "$AAR" -d "$CHECK_DIR"

METHODS="$(javap -classpath "$CHECK_DIR/classes.jar" openp2p.Openp2p)"
for method in runAsModule runAsModuleWithNode stopModule isModuleRunning; do
  if ! grep -Fq "$method" <<< "$METHODS"; then
    echo "AAR 缺少 Java 接口: $method" >&2
    exit 1
  fi
done

ABIS=(armeabi-v7a arm64-v8a x86 x86_64)
for abi in "${ABIS[@]}"; do
  LIBRARY="$CHECK_DIR/jni/$abi/libgojni.so"
  require_file "$LIBRARY"
  file "$LIBRARY"
done

(
  cd "$SOURCE_DIR"
  sha256sum go.mod go.sum core/openp2p.go > "$SOURCE_HASH_AFTER"
)
diff -u "$SOURCE_HASH_BEFORE" "$SOURCE_HASH_AFTER"

sha256sum "$AAR" "$SOURCES" | tee "$OUTPUT_DIR/SHA256SUMS"
cp "$SOURCE_HASH_BEFORE" "$OUTPUT_DIR/source-inputs.sha256"
printf '%s\n' "$METHODS" > "$OUTPUT_DIR/openp2p-javap.txt"

echo "Android AAR 构建并校验成功"
echo "OUTPUT_DIR=$OUTPUT_DIR"
echo "注意: WORK_DIR 默认保留，不执行自动删除: $WORK_DIR"
