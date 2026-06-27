MUSIC AI CUSTOM ARMV7 RUNTIME

This is a compatibility test package, not the final Music AI installer.

Steps:

1. Extract this folder.
2. Copy the complete Music_AI_Custom_ARMv7_Runtime folder into the same
   platform-tools folder that contains adb.exe.
3. Open PowerShell in platform-tools.
4. Run:

powershell -ExecutionPolicy Bypass -File .\Music_AI_Custom_ARMv7_Runtime\03_DEPLOY_AND_TEST_CUSTOM_ARMV7.ps1

Expected success:

RESULT=CUSTOM_ARMV7_RUNTIME_WORKS

If the result still says SIGBUS, the current 32-bit TV Box cannot use this
Sherpa and ONNX Runtime path reliably.
