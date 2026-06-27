#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/onnxruntime-armv7"
WORK="$RUNNER_TEMP/music-ai-ort"
ORT_VERSION="${ORT_VERSION:-1.24.3}"
ANDROID_API="${ANDROID_API:-21}"
BUILD_JOBS="${BUILD_JOBS:-2}"

CFLAGS_ARMV7="-O2 -DNDEBUG -march=armv7-a -mfpu=neon -mno-unaligned-access -fno-strict-aliasing"
CXXFLAGS_ARMV7="$CFLAGS_ARMV7 -fexceptions -frtti"

select_ndk() {
  local candidate=""

  if [[ -n "${ANDROID_NDK_HOME:-}" && -d "${ANDROID_NDK_HOME:-}" ]]; then
    candidate="$ANDROID_NDK_HOME"
  elif [[ -n "${ANDROID_NDK_ROOT:-}" && -d "${ANDROID_NDK_ROOT:-}" ]]; then
    candidate="$ANDROID_NDK_ROOT"
  elif [[ -n "${ANDROID_SDK_ROOT:-}" && -d "$ANDROID_SDK_ROOT/ndk" ]]; then
    candidate="$(find "$ANDROID_SDK_ROOT/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
  fi

  if [[ -z "$candidate" || ! -d "$candidate" ]]; then
    echo "No Android NDK was found on the GitHub runner." >&2
    exit 10
  fi

  printf '%s\n' "$candidate"
}

NDK="$(select_ndk)"
SDK="${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}"

echo "=== CUSTOM ONNX RUNTIME ARMV7 BUILD ==="
echo "ORT version: $ORT_VERSION"
echo "Android SDK: $SDK"
echo "Android NDK: $NDK"
echo "Android API: $ANDROID_API"
echo "Build jobs: $BUILD_JOBS"
echo "C flags: $CFLAGS_ARMV7"
df -h

rm -rf "$WORK" "$OUT"
mkdir -p "$WORK" "$OUT/include" "$OUT/lib"

git clone \
  --branch "v$ORT_VERSION" \
  --depth 1 \
  --recursive \
  --shallow-submodules \
  https://github.com/microsoft/onnxruntime.git \
  "$WORK/onnxruntime"

cd "$WORK/onnxruntime"

./build.sh \
  --config Release \
  --build_dir "$WORK/build" \
  --android \
  --android_sdk_path "$SDK" \
  --android_ndk_path "$NDK" \
  --android_abi armeabi-v7a \
  --android_api "$ANDROID_API" \
  --android_cpp_shared \
  --cmake_generator Ninja \
  --build_shared_lib \
  --disable_ml_ops \
  --skip_tests \
  --compile_no_warning_as_error \
  --parallel "$BUILD_JOBS" \
  --cmake_extra_defines \
    "CMAKE_C_FLAGS_RELEASE=$CFLAGS_ARMV7" \
    "CMAKE_CXX_FLAGS_RELEASE=$CXXFLAGS_ARMV7" \
    "onnxruntime_BUILD_UNIT_TESTS=OFF"

ORT_LIB="$(find "$WORK/build" -type f -name libonnxruntime.so | head -n 1)"

if [[ -z "$ORT_LIB" || ! -f "$ORT_LIB" ]]; then
  echo "libonnxruntime.so was not produced." >&2
  exit 20
fi

cp -f "$ORT_LIB" "$OUT/lib/libonnxruntime.so"
cp -f include/onnxruntime/core/session/*.h "$OUT/include/"

GENERATED_CONFIG="$(find "$WORK/build" -type f -name onnxruntime_config.h | head -n 1 || true)"
if [[ -n "$GENERATED_CONFIG" && -f "$GENERATED_CONFIG" ]]; then
  cp -f "$GENERATED_CONFIG" "$OUT/include/"
fi

cat > "$OUT/build-info.json" <<JSON
{
  "component": "onnxruntime",
  "version": "$ORT_VERSION",
  "target_abi": "armeabi-v7a",
  "android_api": "$ANDROID_API",
  "ndk": "$NDK",
  "c_flags": "$CFLAGS_ARMV7",
  "cxx_flags": "$CXXFLAGS_ARMV7"
}
JSON

(
  cd "$OUT"
  sha256sum lib/libonnxruntime.so include/* build-info.json > SHA256SUMS
)

file "$OUT/lib/libonnxruntime.so"
ls -lh "$OUT/lib/libonnxruntime.so"
df -h
echo "CUSTOM_ONNXRUNTIME_ARMV7_BUILD_COMPLETE"
