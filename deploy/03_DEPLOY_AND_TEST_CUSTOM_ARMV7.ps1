$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
$Adb = Join-Path $Root "adb.exe"
$Runtime = Join-Path $Root "runtime"
$Installer = Join-Path $Root "install_custom_armv7_runtime.sh"

if (-not (Test-Path $Adb)) {
    throw "adb.exe was not found. Copy this extracted folder into platform-tools."
}

if (-not (Test-Path $Runtime)) {
    throw "The runtime folder is missing."
}

if (-not (Test-Path $Installer)) {
    throw "install_custom_armv7_runtime.sh is missing."
}

$Required = @(
    "libonnxruntime.so",
    "libsherpa-onnx-c-api.so",
    "libsherpa-onnx-cxx-api.so",
    "libc++_shared.so",
    "music_ai_sherpa_probe",
    "music_ai_sherpa_transcribe",
    "SHA256SUMS",
    "build-info.json"
)

foreach ($Name in $Required) {
    if (-not (Test-Path (Join-Path $Runtime $Name))) {
        throw "Required runtime file is missing: $Name"
    }
}

$Devices = & $Adb devices
$Devices

if (-not ($Devices | Select-String "`tdevice$")) {
    throw "No authorized ADB device is connected."
}

$Abi = ((& $Adb shell getprop ro.product.cpu.abi) | Out-String).Trim()
$Model = ((& $Adb shell getprop ro.product.model) | Out-String).Trim()

Write-Host "Device: $Model" -ForegroundColor Cyan
Write-Host "ABI: $Abi" -ForegroundColor Cyan

if ($Abi -ne "armeabi-v7a") {
    throw "This package is only for armeabi-v7a."
}

Write-Host "Uploading custom ARMv7 runtime..." -ForegroundColor Cyan

& $Adb shell rm -rf /sdcard/Download/music_ai_custom_armv7
& $Adb shell mkdir -p /sdcard/Download/music_ai_custom_armv7
& $Adb push "$Runtime\." /sdcard/Download/music_ai_custom_armv7/runtime/ | Out-Host
& $Adb push $Installer /sdcard/Download/music_ai_custom_armv7/install_custom_armv7_runtime.sh | Out-Host

& $Adb shell rm -f /sdcard/Download/music_ai_custom_armv7_test.log
& $Adb shell rm -f /sdcard/Download/music_ai_custom_armv7_test.status

Write-Host "Opening Termux and starting compatibility test..." -ForegroundColor Cyan

& $Adb shell monkey -p com.termux -c android.intent.category.LAUNCHER 1 | Out-Null
Start-Sleep -Seconds 3
& $Adb shell input text "sh%s/sdcard/Download/music_ai_custom_armv7/install_custom_armv7_runtime.sh"
& $Adb shell input keyevent 66

$Deadline = (Get-Date).AddMinutes(15)
$LastLog = ""

while ((Get-Date) -lt $Deadline) {
    Start-Sleep -Seconds 3

    $Log = ((& $Adb shell "tail -n 90 /sdcard/Download/music_ai_custom_armv7_test.log 2>/dev/null") | Out-String).Trim()
    $Status = ((& $Adb shell "cat /sdcard/Download/music_ai_custom_armv7_test.status 2>/dev/null") | Out-String).Trim()

    if ($Log -and $Log -ne $LastLog) {
        Clear-Host
        Write-Host "Custom ARMv7 runtime test is running..." -ForegroundColor Cyan
        Write-Host ""
        Write-Host $Log
        $LastLog = $Log
    }

    if ($Status -eq "SUCCESS") {
        Write-Host ""
        Write-Host "CUSTOM ARMV7 RUNTIME WORKS" -ForegroundColor Green
        & $Adb shell "tail -n 180 /sdcard/Download/music_ai_custom_armv7_test.log"
        exit 0
    }

    if ($Status -like "FAILED:*") {
        Write-Host ""
        Write-Host "CUSTOM RUNTIME TEST FAILED: $Status" -ForegroundColor Red
        & $Adb shell "tail -n 220 /sdcard/Download/music_ai_custom_armv7_test.log"
        exit 1
    }
}

Write-Host "Runtime test monitor timed out." -ForegroundColor Red
& $Adb shell "tail -n 220 /sdcard/Download/music_ai_custom_armv7_test.log"
exit 1
