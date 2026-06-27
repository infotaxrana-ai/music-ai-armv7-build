#!/data/data/com.termux/files/usr/bin/sh
set -u

export PATH=/data/data/com.termux/files/usr/bin:$PATH

HOME=/data/data/com.termux/files/home
SRC=/sdcard/Download/music_ai_custom_armv7/runtime
MODEL="$HOME/sherpa-model-bn"
DEST="$HOME/music_ai_custom_armv7_runtime"
STAGE="$HOME/music_ai_custom_armv7_runtime.new"
LOG=/sdcard/Download/music_ai_custom_armv7_test.log
STATUS=/sdcard/Download/music_ai_custom_armv7_test.status

rm -f "$LOG" "$STATUS"
exec >"$LOG" 2>&1

finish() {
  code=$?
  if [ "$code" -eq 0 ]; then
    echo SUCCESS >"$STATUS"
  else
    echo "FAILED:$code" >"$STATUS"
  fi
}
trap finish EXIT

fail() {
  echo "ERROR: $1"
  exit "${2:-1}"
}

echo "=== MUSIC AI CUSTOM ARMV7 RUNTIME TEST ==="
date
echo "Device: $(getprop ro.product.model 2>/dev/null)"
echo "ABI: $(getprop ro.product.cpu.abi 2>/dev/null)"
echo "Kernel: $(uname -m)"
echo

[ "$(getprop ro.product.cpu.abi 2>/dev/null)" = "armeabi-v7a" ] ||
  fail "Device ABI is not armeabi-v7a" 10

[ -d "$SRC" ] || fail "Uploaded runtime folder is missing" 11
[ -f "$SRC/SHA256SUMS" ] || fail "SHA256SUMS is missing" 12

for f in encoder.onnx decoder.onnx joiner.onnx tokens.txt; do
  [ -f "$MODEL/$f" ] || fail "Bengali model file is missing: $MODEL/$f" 13
done

echo "Verifying custom runtime files..."
cd "$SRC"
sha256sum -c SHA256SUMS ||
  fail "Custom runtime integrity verification failed" 14

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$SRC"/. "$STAGE"/

chmod 755 "$STAGE/music_ai_sherpa_probe"
chmod 755 "$STAGE/music_ai_sherpa_transcribe"
chmod 644 "$STAGE"/*.so 2>/dev/null || true

if [ -d "$DEST" ]; then
  BACKUP="$HOME/music_ai_custom_armv7_runtime_backup_$(date +%Y%m%d_%H%M%S)"
  mv "$DEST" "$BACKUP"
  echo "Previous custom runtime backup: $BACKUP"
fi

mv "$STAGE" "$DEST"

echo
echo "=== BUILD INFORMATION ==="
cat "$DEST/build-info.json"
echo

echo "=== REAL MODEL AND INFERENCE PROBE ==="
export LD_LIBRARY_PATH="$DEST:/data/data/com.termux/files/usr/lib"

set +e
"$DEST/music_ai_sherpa_probe" "$MODEL"
RC=$?
set -e

echo "PROBE_EXIT=$RC"

if [ "$RC" -eq 135 ]; then
  echo "RESULT=CUSTOM_RUNTIME_STILL_HAS_SIGBUS"
  exit 30
fi

if [ "$RC" -ne 0 ]; then
  echo "RESULT=CUSTOM_RUNTIME_PROBE_FAILED"
  exit 31
fi

echo "RESULT=CUSTOM_ARMV7_RUNTIME_WORKS"
echo "Runtime path: $DEST"
echo "The full Music AI project has not been replaced."
