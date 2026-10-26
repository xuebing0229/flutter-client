#!/usr/bin/env bash
set -euo pipefail

SYNCTHING_VERSION="${SYNCTHING_VERSION:-v2.1.7}"
SYNCTHING_COMMIT="${SYNCTHING_COMMIT:-}"
if [[ -z "$SYNCTHING_COMMIT" && "$SYNCTHING_VERSION" == "v2.1.7" ]]; then
  SYNCTHING_COMMIT="d6d0181f7d466381c4b39ec8fd944c364f939b32"
fi
if [[ -z "$SYNCTHING_COMMIT" ]]; then
  echo "SYNCTHING_COMMIT must pin the source commit for $SYNCTHING_VERSION." >&2
  exit 1
fi
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/android/app/src/sync/jniLibs"

EXPECTED=(
  "$OUT_DIR/arm64-v8a/libsyncthing.so"
  "$OUT_DIR/armeabi-v7a/libsyncthing.so"
  "$OUT_DIR/x86_64/libsyncthing.so"
)
BUILD_STAMP="$OUT_DIR/.syncthing-build-id"
EXPECTED_BUILD_ID="$SYNCTHING_VERSION@$SYNCTHING_COMMIT"

all_present=true
for file in "${EXPECTED[@]}"; do
  if [[ ! -s "$file" ]]; then
    all_present=false
    break
  fi
done
if [[ "$all_present" == true &&
      -f "$BUILD_STAMP" &&
      "$(cat "$BUILD_STAMP")" == "$EXPECTED_BUILD_ID" ]]; then
  echo "Embedded Syncthing $EXPECTED_BUILD_ID already present."
  exit 0
fi

# Never let stale binaries from another pinned Syncthing version survive a
# local build or restored CI cache.
rm -f "${EXPECTED[@]}" "$BUILD_STAMP"

SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -z "$SDK_ROOT" ]]; then
  echo "ANDROID_SDK_ROOT or ANDROID_HOME is required." >&2
  exit 1
fi

NDK_ROOT="${ANDROID_NDK_ROOT:-${ANDROID_NDK_HOME:-}}"
if [[ -z "$NDK_ROOT" || ! -d "$NDK_ROOT/toolchains/llvm/prebuilt" ]]; then
  NDK_ROOT="$(find "$SDK_ROOT/ndk" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -n 1)"
fi
if [[ -z "$NDK_ROOT" || ! -d "$NDK_ROOT/toolchains/llvm/prebuilt" ]]; then
  echo "Android NDK was not found." >&2
  exit 1
fi

HOST_TAG="$(find "$NDK_ROOT/toolchains/llvm/prebuilt" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | head -n 1)"
TOOLCHAIN="$NDK_ROOT/toolchains/llvm/prebuilt/$HOST_TAG/bin"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

git clone --quiet --depth 1 --branch "$SYNCTHING_VERSION"   https://github.com/syncthing/syncthing.git   "$WORK_DIR/syncthing"
ACTUAL_COMMIT="$(git -C "$WORK_DIR/syncthing" rev-parse HEAD)"
if [[ "$ACTUAL_COMMIT" != "$SYNCTHING_COMMIT" ]]; then
  echo "Syncthing source pin mismatch: expected $SYNCTHING_COMMIT, got $ACTUAL_COMMIT" >&2
  exit 1
fi

build_one() {
  local abi="$1"
  local goarch="$2"
  local cc="$3"
  local goarm="${4:-}"

  mkdir -p "$OUT_DIR/$abi"
  echo "Building Syncthing $SYNCTHING_VERSION for $abi"

  (
    cd "$WORK_DIR/syncthing"
    export GOOS=android
    export GOARCH="$goarch"
    export CGO_ENABLED=1
    export CC="$TOOLCHAIN/$cc"
    if [[ -n "$goarm" ]]; then
      export GOARM="$goarm"
    else
      unset GOARM || true
    fi
    go build       -trimpath       -tags "noupgrade noassets"       -ldflags "-s -w -checklinkname=0"       -o "$OUT_DIR/$abi/libsyncthing.so"       ./cmd/syncthing
  )
}

# API 28 keeps the core compatible with the Android versions targeted by
# the embedded-service implementation while matching the known-good wrapper.
build_one "arm64-v8a" "arm64" "aarch64-linux-android28-clang"
build_one "armeabi-v7a" "arm" "armv7a-linux-androideabi28-clang" "7"
build_one "x86_64" "amd64" "x86_64-linux-android28-clang"

for file in "${EXPECTED[@]}"; do
  test -s "$file"
done
printf '%s' "$EXPECTED_BUILD_ID" > "$BUILD_STAMP"

echo "Embedded Syncthing $EXPECTED_BUILD_ID is ready."
