# Music AI custom ARMv7 cloud build

This repository builds a custom offline Bengali speech runtime for the
100 Pro Max Android TV Box.

The device uses:

- ABI: `armeabi-v7a`
- Kernel architecture: `armv7l`
- CPU core: Cortex-A53 running in 32-bit mode
- Android SDK property: 28

The official prebuilt Sherpa and ONNX Runtime reached native recognizer
creation but stopped with `SIGBUS`. This workflow rebuilds ONNX Runtime and
Sherpa from source with conservative ARMv7 alignment flags.

## No local WSL or 20 GB build space is required

The build runs on GitHub-hosted Ubuntu runners. The workflow uses two jobs so
the ONNX Runtime and Sherpa builds do not share one runner disk.

## Run the workflow

1. Open the repository on GitHub.
2. Select **Actions**.
3. Select **Build Music AI custom ARMv7 runtime**.
4. Select **Run workflow**.
5. Wait until both jobs are green.
6. Open the completed workflow run.
7. Under **Artifacts**, download the item beginning with:
   `Music_AI_Custom_ARMv7_Runtime_`
8. Extract the downloaded artifact.
9. Extract `Music_AI_Custom_ARMv7_Runtime.zip`.
10. Follow `README_AFTER_BUILD.txt`.

## Repository privacy

No Telegram token, Gemini key, Wi-Fi password, or other secret is used in this
repository. A public repository is suitable for the build files.

## Important

A successful cloud build only proves compilation. The runtime must still pass
the real TV Box model and inference test before it is added to the final Music
AI installer.
