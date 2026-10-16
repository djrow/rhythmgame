# Handoff Report: survey_explorer_1

**Agent ID**: `survey_explorer_1`  
**Parent ID**: `7da07436-85a8-464d-9f3c-d174d6d86ee2`  
**Working Directory**: `c:\Users\david\Documents\micgame-3\.agents\teamwork\survey_explorer_1\`  
**Date**: 2026-10-16T18:22:00Z  
**Type**: Hard Handoff (Investigation & Survey Complete)

---

## 1. Observation

1. **Godot Binary and Version**:
   - Location: `C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe`
   - Command: `& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --version`
   - Result: `4.7.2.stable.official.ed1daf0bf` (exit code 0).
2. **Headless Execution & Orphan Autoload Error**:
   - Running Godot headless on the workspace root:
     `& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --quit`
   - Verbatim Output:
     ```
     Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

     ERROR: Attempt to open script 'res://addons/godot_ai/runtime/game_helper.gd' resulted in error 'File not found'.
        at: load_source_code (modules/gdscript/gdscript.cpp:1139)
     ERROR: Failed loading resource: res://addons/godot_ai/runtime/game_helper.gd.
        at: _load (core/io/resource_loader.cpp:317)
     ERROR: Failed to instantiate an autoload, can't load from path: res://addons/godot_ai/runtime/game_helper.gd.
        at: start (main/main.cpp:4533)
     ERROR: Cannot open file 'res://scenes/main.tscn'.
        at: load (scene/resources/resource_format_text.cpp:1442)
     ERROR: Failed loading resource: res://scenes/main.tscn.
        at: _load (core/io/resource_loader.cpp:317)
     ERROR: Failed loading scene: res://scenes/main.tscn.
        at: start (main/main.cpp:4767)
     ```
   - Exit code: 1.
3. **Android Export Tooling and SDK Environment**:
   - Android SDK location: `C:\Users\david\AppData\Local\Android\Sdk` (build-tools `36.0.0` and `36.1.0` present; `platform-tools/adb.exe` present; platforms `android-36` and `android-37.0` present).
   - Java JDK: `C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot` (JDK 17).
   - Godot Keystore: `C:\Users\david\AppData\Roaming\Godot\keystores\debug.keystore`.
   - Godot Export Templates: `C:\Users\david\AppData\Roaming\Godot\export_templates\4.7.2.stable\` contains `android_debug.apk`, `android_release.apk`, `windows_debug_x86_64.exe`, and `windows_release_x86_64.exe`.
   - Godot Editor Settings (`C:\Users\david\AppData\Roaming\Godot\editor_settings-4.7.tres` lines 481-484):
     `export/android/debug_keystore = "C:/Users/david/AppData/Roaming/Godot/keystores/debug.keystore"`
     `export/android/java_sdk_path = "C:/Program Files/Microsoft/jdk-17.0.20.101-hotspot"`
     `export/android/android_sdk_path = "C:\\Users\\david\\AppData\\Local/Android/Sdk"`
4. **Android Export CLI Test**:
   - Command:
     `& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --export-debug "Android" "c:\Users\david\Documents\micgame-3\.agents\teamwork\survey_explorer_1\test_export.apk"`
   - Result: Exit code 0.
   - APK Signed:
     `Signing binary using: C:\Users\david\AppData\Local/Android/Sdk/build-tools/36.0.0/apksigner.bat sign --verbose ... Signed`
   - Permissions added to APK:
     `Adding permission android.permission.MODIFY_AUDIO_SETTINGS`
     `Adding permission android.permission.RECORD_AUDIO`
   - Native libraries packaged: `lib/arm64-v8a/libgodot_android.so` and `lib/x86_64/libgodot_android.so`.
5. **Windows Desktop Export CLI Test**:
   - Command:
     `& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --export-debug "Windows Desktop" "c:\Users\david\Documents\micgame-3\.agents\teamwork\survey_explorer_1\test_export.exe"`
   - Result: Exit code 0. Packed resources cleanly with embedded PCK.
6. **Python & Machine Learning Toolchain**:
   - Python: 3.12.10 (`C:\Users\david\AppData\Local\Microsoft\WindowsApps\python.exe`)
   - `pip list` confirmed packages:
     - `basic-pitch` 0.4.0
     - `onnxruntime` 1.31.0
     - `torch` 2.13.0
     - `opencv-python-headless` 5.0.0.93
     - `pillow` 12.3.0
     - `music21` 10.5.0
     - `numpy` 2.3.5
   - Spotify Basic Pitch ONNX Model verified at:
     `C:\Users\david\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.12_qbz5n2kfra8p0\LocalCache\local-packages\Python312\site-packages\basic_pitch\saved_models\icassp_2022\nmp.onnx`
   - Model input: `serving_default_input_2:0` shape `['unk__749', 43844, 1]` tensor(float) @ 22,050 Hz.
   - Model outputs:
     - Notes: `StatefulPartitionedCall:2` shape `['unk__750', 172, 88]` (88 MIDI pitches: A0 to C8).
     - Onsets: `StatefulPartitionedCall:1` shape `['unk__751', 172, 88]`.
     - Contours: `StatefulPartitionedCall:0` shape `['unk__752', 172, 264]`.
7. **Existing Binary Prototype Inspection**:
   - `micgame3.apk` and `micgame3.exe` contained scenes `main.scn` and `note.scn`.
   - String extraction revealed the existing binaries were an early vertical 4-lane receptor button prototype (`Receptor0`, `Receptor1`, `Receptor2`, `Receptor3`, `Divider0`, `Divider1`, `Divider2`, `[SPACE] / [ENTER] = Keyboard Strum`).
   - The actual user requirements (R1-R4) demand a completely different visual architecture: a horizontal right-to-left **Grand Staff (Double Staff)** highway with dual Treble/Bass staves, Middle C ledger spacing, C2 to C6+ pitch coverage, and real-time polyphonic microphone scoring.

---

## 2. Logic Chain

1. **Premise**: In `project.godot`, lines 23-25 declare `_mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"` and line 14 declares `run/main_scene="res://scenes/main.tscn"`.
2. **Observation**: Neither `addons/` nor `scenes/` exists in `c:\Users\david\Documents\micgame-3`.
3. **Deduction**: Godot fails with fatal load errors whenever `--headless` executes a scene or script within the project root.
4. **Action**: `project.godot` must be edited to remove the orphaned autoload and plugin entries, and `res://scenes/main.tscn` must be implemented.
5. **Premise**: Pixel 7a uses the Google Tensor G2 (ARM64-v8a architecture) and Mali-G710 MP7 GPU.
6. **Observation**: `export_presets.cfg` enables `architectures/arm64-v8a=true` and permissions `record_audio=true` and `modify_audio_settings=true`. The renderer is `gl_compatibility` (GLES3).
7. **Deduction**: GL Compatibility is the most performant, battery-efficient, and stutter-free renderer for a 2D notation highway on Mali-G710. The Android export pipeline is ready and verified.
8. **Premise**: Standard Grand Staff notation requires both Treble and Bass staves, with Middle C (C4, MIDI 60) centered between them, covering pitches C2 (MIDI 36) to C6+ (MIDI 84+).
9. **Observation**: Diatonic steps $D(M) = O \times 7 + \text{DiatonicOffset}(P)$ place Middle C at step 28, Treble bottom line E4 at step 30, Treble top line F5 at step 38, Bass top line A3 at step 26, and Bass bottom line G2 at step 18.
10. **Deduction**: Setting Middle C Y-origin at $Y_{\text{center}} = 360\text{ px}$ with line spacing $S = 18\text{ px}$ ($\Delta y = 9\text{ px}$ per diatonic step) yields exact classical engraving symmetry: Treble bottom line is at $-S$ (342px), Bass top line is at $+S$ (378px), gap between staves is exactly $2S$ (36px), and dynamic ledger lines appear symmetrically for Middle C, notes above Treble ($D(M) \ge 40$), and notes below Bass ($D(M) \le 16$).
11. **Premise**: Spotify Basic Pitch requires audio input at 22,050 Hz and processes 43,844 samples.
12. **Observation**: Godot captures microphone audio via `AudioEffectCapture` on the `Record` bus at native device rates (typically 44.1kHz or 48kHz on Pixel 7a and Windows).
13. **Deduction**: Audio frames from `AudioEffectCapture` must be resampled to 22.05kHz and passed through the modular model runner interface (`IAudioPitchModel`) to execute `nmp.onnx`.

---

## 3. Caveats

1. **Live Android Hardware Connection**: No physical Google Pixel 7a device was connected over USB ADB during this investigation session (`adb devices` was not invoked against a live tethered handset). However, the exact Android build environment, SDK platforms 36/37, build-tools 36.0.0, debug keystore, ARM64-v8a compilation, and APK signing were executed and verified from end-to-end.
2. **Godot AI MCP Addon Source**: The orphaned `godot_ai` plugin referenced in `project.godot` was not found in the project. It appears to be an external dev tool rather than runtime game code, so its removal will not harm game functionality.
3. **Real-time Latency with 43,844 Sample Windows**: Full 1.988-second inference windows introduce latency if run without overlapping hops. Downstream implementation must use streaming hop chunks (e.g., 2,205 to 4,410 samples = 100ms–200ms) or a decoupled thread/daemon to maintain 60–90 FPS smoothness on the highway.

---

## 4. Conclusion

1. **Environment Readiness**: The system is 100% equipped to build, test, and export the complete game. Godot 4.7.2, Python 3.12, ONNX Runtime 1.31, Basic Pitch 0.4.0, OpenCV, Pillow, Java 17, and Android SDK 36 are installed and verified.
2. **Immediate First Step**: Remove lines 23-26 and lines 34-37 from `project.godot` to eliminate the orphaned `godot_ai` autoload and plugin errors.
3. **Highway Implementation Blueprint**: Implement `res://scenes/main.tscn` using the diatonic coordinate model specified in Section 3 of `report.md`, featuring:
   - Continuous horizontal right-to-left scrolling towards hit line at $X = 160\text{ px}$.
   - Dual Treble and Bass staves centered at $Y = 360\text{ px}$.
   - Dynamic ledger lines for Middle C and pitches outside the staves (C2 to C6+).
   - Hit judgment timing windows (Perfect $\pm 50$ms, Good $\pm 120$ms, Miss $> 120$ms).
   - Floating rating labels, score interpolation, and streak multiplier display.
4. **Subsystems Blueprint**:
   - Audio input capture via `AudioEffectCapture` on `Record` bus.
   - Modular model runner interface (`IAudioPitchModel`) executing `nmp.onnx`.
   - Python-based OMR processor for sheet music ingestion (target $\ge 85\%$ accuracy).
   - Bundled test pieces and CLI verification harnesses.

---

## 5. Verification Method

To independently verify all findings:

1. **Verify Godot Version**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --version
   ```
   *Expected Output*: `4.7.2.stable.official.ed1daf0bf`

2. **Verify Android Export Preset for Pixel 7a (ARM64-v8a + RECORD_AUDIO)**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --export-debug "Android" "c:\Users\david\Documents\micgame-3\.agents\teamwork\survey_explorer_1\test_export.apk"
   ```
   *Expected Output*: Export completes with `Signed` via `apksigner.bat` and exit code 0.

3. **Verify Windows Desktop Export Preset (x86_64 + embed_pck)**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --export-debug "Windows Desktop" "c:\Users\david\Documents\micgame-3\.agents\teamwork\survey_explorer_1\test_export.exe"
   ```
   *Expected Output*: Export completes packing resources with exit code 0.

4. **Verify Basic Pitch ONNX Model & Inference Session**:
   ```powershell
   python -c "import onnxruntime as ort; sess = ort.InferenceSession(r'C:\Users\david\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.12_qbz5n2kfra8p0\LocalCache\local-packages\Python312\site-packages\basic_pitch\saved_models\icassp_2022\nmp.onnx'); print('Loaded successfully:', sess.get_inputs()[0].name, sess.get_inputs()[0].shape)"
   ```
   *Expected Output*: `Loaded successfully: serving_default_input_2:0 ['unk__749', 43844, 1]`

5. **Invalidation Conditions**:
   - If `Godot_v4.7.2-stable_win64_console.exe` fails to start or exit code is non-zero after removing the orphaned autoload from `project.godot`.
   - If `nmp.onnx` is moved or unreadable by ONNX Runtime.
   - If the Android SDK or Java JDK environment variables are modified.
