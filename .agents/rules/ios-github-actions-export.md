---
trigger: always_on
description: Guidelines for non-interactive Git operations on Windows and headless Godot 4 iOS IPA builds on GitHub Actions macOS runners.
---

# iOS GitHub Actions Export & Non-Interactive Git Rules

1. **Non-Interactive Git Commands on Windows**:
   - When running `git push`, `git pull`, or `git fetch` in background shell commands on Windows, always set `$env:GIT_TERMINAL_PROMPT="0"` and `$env:GCM_INTERACTIVE="never"` with `git -c credential.interactive=never` so Git Credential Manager never blocks indefinitely on a hidden prompt.
   - When fetching GitHub Actions job logs via the GitHub API (`/actions/jobs/<id>/logs`), use `curl.exe -sL -H "Authorization: Bearer <token>"` rather than `urllib.request`, because `urllib.request` forwards the `Authorization` header across the 302 redirect to Azure Blob Storage (causing HTTP 401).

2. **Godot 4 Headless iOS Export Requirements (`export_presets.cfg`)**:
   - Godot's `EditorExportPlatformAppleEmbedded` rejects iOS exports before generating `.xcodeproj` if `application/app_store_team_id` is empty (`App Store Team ID not specified.`). Always set a 10-character placeholder (`application/app_store_team_id="0000000000"`) and `application/export_project_only=true` when building unsigned `.ipa` packages in CI.
   - Enable `user_data/accessible_from_files_app=true` and `user_data/accessible_from_itunes_sharing=true` so custom sheet music and audio files can be imported via the iOS Files app.

3. **iOS & macOS GDExtension Packaging (`onnx_pitch.gdextension`)**:
   - The official `pod-archive-onnxruntime-c-<version>.zip` archive provides static `.framework` binaries for `ios-arm64`, `ios-arm64_x86_64-simulator`, and `macos-arm64_x86_64`.
   - Compile `native/onnx_pitch_gdextension.c` as C and link each platform slice as a Mach-O `.dylib` (`clang++ -dynamiclib ... -lc++ -framework Foundation -framework CoreFoundation -framework Accelerate`) before wrapping the iOS slices in `onnx_pitch.ios.xcframework`. Also build `libonnx_pitch.macos.dylib` so headless Godot on the macOS CI runner loads the GDExtension without errors during export.
   - Never hide `Godot --export-debug` or `xcodebuild` errors behind `|| true` in `.github/workflows/ios_build.yml`; always assert `test -s build/ios/micgame3-unsigned.ipa` before uploading artifacts.
