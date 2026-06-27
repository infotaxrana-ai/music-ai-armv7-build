#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$RUNNER_TEMP/music-ai-sherpa"
ORT="$ROOT/downloaded-onnxruntime"
RELEASE_ROOT="$ROOT/release"
PACKAGE_DIR="$RELEASE_ROOT/Music_AI_Custom_ARMv7_Runtime"
RUNTIME_DIR="$PACKAGE_DIR/runtime"

SHERPA_VERSION="${SHERPA_VERSION:-1.13.3}"
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
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
CC="$TOOLCHAIN/bin/armv7a-linux-androideabi${ANDROID_API}-clang"

if [[ ! -x "$CC" ]]; then
  echo "ARMv7 Android compiler was not found: $CC" >&2
  exit 11
fi

if [[ ! -f "$ORT/lib/libonnxruntime.so" ]]; then
  echo "Downloaded custom ONNX Runtime library is missing." >&2
  find "$ORT" -maxdepth 4 -type f -print || true
  exit 12
fi

if [[ ! -d "$ORT/include" ]]; then
  echo "Downloaded ONNX Runtime headers are missing." >&2
  exit 13
fi

echo "=== CUSTOM SHERPA ARMV7 BUILD ==="
echo "Sherpa version: $SHERPA_VERSION"
echo "Android NDK: $NDK"
echo "Android API: $ANDROID_API"
echo "Build jobs: $BUILD_JOBS"
df -h

rm -rf "$WORK" "$RELEASE_ROOT"
mkdir -p "$WORK" "$RUNTIME_DIR"

git clone \
  --branch "v$SHERPA_VERSION" \
  --depth 1 \
  https://github.com/k2-fsa/sherpa-onnx.git \
  "$WORK/sherpa-onnx"

export SHERPA_ONNXRUNTIME_LIB_DIR="$ORT/lib"
export SHERPA_ONNXRUNTIME_INCLUDE_DIR="$ORT/include"

cmake -S "$WORK/sherpa-onnx" -B "$WORK/build" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS_RELEASE="$CFLAGS_ARMV7" \
  -DCMAKE_CXX_FLAGS_RELEASE="$CXXFLAGS_ARMV7" \
  -DCMAKE_INSTALL_PREFIX="$WORK/install" \
  -DBUILD_SHARED_LIBS=ON \
  -DBUILD_PIPER_PHONMIZE_EXE=OFF \
  -DBUILD_PIPER_PHONMIZE_TESTS=OFF \
  -DBUILD_ESPEAK_NG_EXE=OFF \
  -DBUILD_ESPEAK_NG_TESTS=OFF \
  -DSHERPA_ONNX_ENABLE_TTS=OFF \
  -DSHERPA_ONNX_ENABLE_SPEAKER_DIARIZATION=OFF \
  -DSHERPA_ONNX_ENABLE_BINARY=OFF \
  -DSHERPA_ONNX_ENABLE_PYTHON=OFF \
  -DSHERPA_ONNX_ENABLE_TESTS=OFF \
  -DSHERPA_ONNX_ENABLE_CHECK=OFF \
  -DSHERPA_ONNX_ENABLE_PORTAUDIO=OFF \
  -DSHERPA_ONNX_ENABLE_JNI=OFF \
  -DSHERPA_ONNX_ENABLE_C_API=ON \
  -DSHERPA_ONNX_ENABLE_RKNN=OFF \
  -DSHERPA_ONNX_LINK_LIBSTDCPP_STATICALLY=OFF \
  -DANDROID_ABI=armeabi-v7a \
  -DANDROID_ARM_NEON=ON \
  -DANDROID_ARM_MODE=arm \
  -DANDROID_PLATFORM="android-$ANDROID_API" \
  -DANDROID_STL=c++_shared

cmake --build "$WORK/build" --parallel "$BUILD_JOBS"
cmake --install "$WORK/build" --strip

SHERPA_C_API="$(find "$WORK/install" "$WORK/build" -type f -name libsherpa-onnx-c-api.so | head -n 1)"
SHERPA_CXX_API="$(find "$WORK/install" "$WORK/build" -type f -name libsherpa-onnx-cxx-api.so | head -n 1)"

if [[ -z "$SHERPA_C_API" || ! -f "$SHERPA_C_API" ]]; then
  echo "libsherpa-onnx-c-api.so was not produced." >&2
  find "$WORK" -name 'libsherpa*.so' -print || true
  exit 20
fi

if [[ -z "$SHERPA_CXX_API" || ! -f "$SHERPA_CXX_API" ]]; then
  echo "libsherpa-onnx-cxx-api.so was not produced." >&2
  find "$WORK" -name 'libsherpa*.so' -print || true
  exit 21
fi

CXX_SHARED="$(find "$TOOLCHAIN" -type f -path '*arm-linux-androideabi*' -name libc++_shared.so | head -n 1)"
if [[ -z "$CXX_SHARED" || ! -f "$CXX_SHARED" ]]; then
  echo "libc++_shared.so was not found in the Android NDK." >&2
  exit 22
fi

cp -f "$ORT/lib/libonnxruntime.so" "$RUNTIME_DIR/"
cp -f "$SHERPA_C_API" "$RUNTIME_DIR/libsherpa-onnx-c-api.so"
cp -f "$SHERPA_CXX_API" "$RUNTIME_DIR/libsherpa-onnx-cxx-api.so"
cp -f "$CXX_SHARED" "$RUNTIME_DIR/libc++_shared.so"
cp -f "$WORK/sherpa-onnx/sherpa-onnx/c-api/c-api.h" "$RUNTIME_DIR/"

if [[ -d "$WORK/install/lib" ]]; then
  while IFS= read -r library; do
    name="$(basename "$library")"
    if [[ ! -f "$RUNTIME_DIR/$name" ]]; then
      cp -f "$library" "$RUNTIME_DIR/$name"
    fi
  done < <(find "$WORK/install/lib" -maxdepth 1 -type f -name '*.so' | sort)
fi

"$CC" $CFLAGS_ARMV7 -fPIE -pie \
  -I"$RUNTIME_DIR" \
  "$ROOT/native/music_ai_sherpa_probe.c" \
  -L"$RUNTIME_DIR" \
  -Wl,-rpath,'$ORIGIN' \
  -Wl,--no-as-needed \
  -lsherpa-onnx-c-api \
  -lsherpa-onnx-cxx-api \
  -lonnxruntime \
  -lc++_shared \
  -llog \
  -landroid \
  -ldl \
  -lm \
  -o "$RUNTIME_DIR/music_ai_sherpa_probe"

"$CC" $CFLAGS_ARMV7 -fPIE -pie \
  -I"$RUNTIME_DIR" \
  "$ROOT/native/music_ai_sherpa_transcribe.c" \
  -L"$RUNTIME_DIR" \
  -Wl,-rpath,'$ORIGIN' \
  -Wl,--no-as-needed \
  -lsherpa-onnx-c-api \
  -lsherpa-onnx-cxx-api \
  -lonnxruntime \
  -lc++_shared \
  -llog \
  -landroid \
  -ldl \
  -lm \
  -o "$RUNTIME_DIR/music_ai_sherpa_transcribe"

chmod 755 "$RUNTIME_DIR/music_ai_sherpa_probe"
chmod 755 "$RUNTIME_DIR/music_ai_sherpa_transcribe"
chmod 644 "$RUNTIME_DIR"/*.so "$RUNTIME_DIR/c-api.h"

cp -f "$ROOT/deploy/03_DEPLOY_AND_TEST_CUSTOM_ARMV7.ps1" "$PACKAGE_DIR/"
cp -f "$ROOT/deploy/install_custom_armv7_runtime.sh" "$PACKAGE_DIR/"
cp -f "$ROOT/deploy/README_AFTER_BUILD.txt" "$PACKAGE_DIR/"

cat > "$RUNTIME_DIR/build-info.json" <<JSON
{
  "target_device": "100 Pro Max",
  "target_abi": "armeabi-v7a",
  "android_api": "$ANDROID_API",
  "sherpa_onnx_version": "$SHERPA_VERSION",
  "onnxruntime_version": "${ORT_VERSION:-1.24.3}",
  "ndk": "$NDK",
  "c_flags": "$CFLAGS_ARMV7",
  "purpose": "SIGBUS-safe custom Bengali STT compatibility runtime"
}
JSON

(
  cd "$RUNTIME_DIR"
  sha256sum ./* > SHA256SUMS
)

cat > "$RELEASE_ROOT/build-report.txt" <<REPORT
Music AI custom ARMv7 cloud build

Sherpa-ONNX: $SHERPA_VERSION
ONNX Runtime: ${ORT_VERSION:-1.24.3}
ABI: armeabi-v7a
Android API: $ANDROID_API
NDK: $NDK
Flags: $CFLAGS_ARMV7

The artifact must still pass the real TV Box recognizer and inference test.
REPORT

(
  cd "$PACKAGE_DIR"
  find . -type f -print0 | sort -z | xargs -0 sha256sum > "$RELEASE_ROOT/SHA256SUMS.txt"
)

(
  cd "$RELEASE_ROOT"
  zip -9 -r Music_AI_Custom_ARMv7_Runtime.zip Music_AI_Custom_ARMv7_Runtime
)

file "$RUNTIME_DIR/music_ai_sherpa_probe"
file "$RUNTIME_DIR/libonnxruntime.so"
ls -lh "$RELEASE_ROOT/Music_AI_Custom_ARMv7_Runtime.zip"
df -h
echo "CUSTOM_SHERPA_ARMV7_RELEASE_COMPLETE"
