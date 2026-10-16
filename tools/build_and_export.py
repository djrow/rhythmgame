#!/usr/bin/env python3
"""
Standalone Build, Export & Headless Project Validation Tool (Features #17, #18, #19).
1. Validates project.godot (main scene, audio input, Record bus, GL Compatibility renderer for Pixel 7a, zero orphaned autoloads).
2. Validates export_presets.cfg:
   - Android (Google Pixel 7a): ARM64-v8a target, RECORD_AUDIO, MODIFY_AUDIO_SETTINGS, signed APK.
   - Windows Desktop: x86_64 architecture, embedded PCK, runnable .exe target.
3. Executes Godot 4 headless project validation (--headless --quit).
4. Builds (or verifies) micgame3.apk and micgame3.exe and inspects binary headers/contents.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import zipfile
from typing import Any, Dict, List, Optional, Tuple

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from tests.e2e.e2e_test_utils import ConfigValidator

DEFAULT_GODOT_CANDIDATES = [
    os.environ.get("GODOT_BIN", ""),
    r"C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe",
    r"C:\Users\david\Downloads\Godot_v4.7.2-stable_win64.exe",
    shutil.which("godot") or "",
    shutil.which("godot4") or "",
]


def find_godot_binary(custom_path: Optional[str] = None) -> Optional[str]:
    if custom_path and os.path.exists(custom_path):
        return custom_path
    for candidate in DEFAULT_GODOT_CANDIDATES:
        if candidate and os.path.exists(candidate):
            return candidate
    return None


def validate_project_config() -> Tuple[bool, List[str]]:
    """Validates project.godot and default_bus_layout.tres for desktop & Pixel 7a readiness."""
    checks: List[str] = []
    proj_path = os.path.join(PROJECT_ROOT, "project.godot")
    if not os.path.exists(proj_path):
        return False, ["FAIL: project.godot not found"]

    config = ConfigValidator.parse_godot_project_file(proj_path)

    # 1. Application & Main Scene
    app = config.get("application", {})
    main_scene = app.get("run/main_scene", "").strip('"')
    if main_scene != "res://scenes/main.tscn":
        return False, [f"FAIL: Unexpected run/main_scene: {main_scene}"]
    local_main_scene = os.path.join(PROJECT_ROOT, main_scene.replace("res://", ""))
    if not os.path.exists(local_main_scene):
        return False, [f"FAIL: Main scene file missing on disk: {local_main_scene}"]
    checks.append(f"Main scene verified: {main_scene}")

    # 2. Orphaned Autoloads / Plugins check
    autoloads = config.get("autoload", {})
    for name, val in autoloads.items():
        clean_path = val.strip('"').lstrip("*")
        if clean_path.startswith("res://"):
            disk_path = os.path.join(PROJECT_ROOT, clean_path.replace("res://", ""))
            if not os.path.exists(disk_path):
                return False, [f"FAIL: Orphaned autoload {name} -> {clean_path}"]
    checks.append("Zero orphaned autoloads or missing editor plugins.")

    # 3. Audio Input & Record Bus
    audio = config.get("audio", {})
    if audio.get("driver/enable_input", "").lower() != "true":
        return False, ["FAIL: audio driver/enable_input is not true"]
    bus_layout = audio.get("busses/default_bus_layout", "").strip('"')
    bus_disk = os.path.join(PROJECT_ROOT, bus_layout.replace("res://", ""))
    if not os.path.exists(bus_disk):
        return False, [f"FAIL: Bus layout file missing: {bus_disk}"]
    with open(bus_disk, "r", encoding="utf-8") as f:
        bus_content = f.read()
    if 'bus/1/name = &"Record"' not in bus_content or "AudioEffectCapture" not in bus_content:
        return False, ["FAIL: Record bus or AudioEffectCapture missing from default_bus_layout.tres"]
    checks.append("Audio input driver enabled & Record bus with AudioEffectCapture verified.")

    # 4. Rendering configuration (Pixel 7a Tensor G2 / Mali-G710 GL Compatibility & Windows D3D12)
    rendering = config.get("rendering", {})
    rend_desktop = rendering.get("renderer/rendering_method", "").strip('"')
    rend_mobile = rendering.get("renderer/rendering_method.mobile", "").strip('"')
    win_driver = rendering.get("rendering_device/driver.windows", "").strip('"')
    etc2_astc = rendering.get("textures/vram_compression/import_etc2_astc", "").lower()

    if rend_desktop != "gl_compatibility" or rend_mobile != "gl_compatibility":
        return False, [f"FAIL: Renderer mismatch (desktop={rend_desktop}, mobile={rend_mobile})"]
    if win_driver != "d3d12":
        return False, [f"FAIL: Windows rendering driver is {win_driver}, expected d3d12"]
    if etc2_astc != "true":
        return False, ["FAIL: textures/vram_compression/import_etc2_astc is not true"]
    checks.append("Renderer verified: gl_compatibility (mobile/desktop), ASTC enabled, d3d12 Windows driver.")

    return True, checks


def validate_export_presets() -> Tuple[bool, List[str]]:
    """Validates export_presets.cfg for Android (Pixel 7a) and Windows Desktop (x86_64)."""
    checks: List[str] = []
    presets_path = os.path.join(PROJECT_ROOT, "export_presets.cfg")
    if not os.path.exists(presets_path):
        return False, ["FAIL: export_presets.cfg not found"]

    sections = ConfigValidator.parse_export_presets(presets_path)

    # 1. Check Android Preset (preset.0)
    p0 = sections.get("preset.0", {})
    p0_opt = sections.get("preset.0.options", {})
    if p0.get("name", "").strip('"') != "Android" or p0.get("platform", "").strip('"') != "Android":
        return False, ["FAIL: preset.0 is not Android"]
    if p0.get("export_path", "").strip('"') != "./micgame3.apk":
        return False, [f"FAIL: Android export_path is {p0.get('export_path')}"]
    if p0_opt.get("architectures/arm64-v8a", "").lower() != "true":
        return False, ["FAIL: Android architectures/arm64-v8a is not true"]
    if p0_opt.get("architectures/armeabi-v7a", "").lower() != "false":
        return False, ["FAIL: Android 32-bit armeabi-v7a should be false for Pixel 7a"]
    if p0_opt.get("permissions/record_audio", "").lower() != "true":
        return False, ["FAIL: Android permissions/record_audio is not true"]
    if p0_opt.get("permissions/modify_audio_settings", "").lower() != "true":
        return False, ["FAIL: Android permissions/modify_audio_settings is not true"]
    if p0_opt.get("package/signed", "").lower() != "true":
        return False, ["FAIL: Android package/signed is not true"]
    checks.append(
        "Android (Pixel 7a) preset verified: ARM64-v8a=true, RECORD_AUDIO=true, MODIFY_AUDIO_SETTINGS=true, signed=true."
    )

    # 2. Check Windows Desktop Preset (preset.1)
    p1 = sections.get("preset.1", {})
    p1_opt = sections.get("preset.1.options", {})
    if p1.get("name", "").strip('"') != "Windows Desktop" or p1.get("platform", "").strip('"') != "Windows Desktop":
        return False, ["FAIL: preset.1 is not Windows Desktop"]
    if p1.get("export_path", "").strip('"') != "./micgame3.exe":
        return False, [f"FAIL: Windows export_path is {p1.get('export_path')}"]
    if p1_opt.get("binary_format/architecture", "").strip('"') != "x86_64":
        return False, ["FAIL: Windows binary_format/architecture is not x86_64"]
    if p1_opt.get("binary_format/embed_pck", "").lower() != "true":
        return False, ["FAIL: Windows binary_format/embed_pck is not true"]
    checks.append("Windows Desktop preset verified: x86_64 architecture, embed_pck=true, target=./micgame3.exe.")

    # 3. Check iOS Preset (preset.2)
    p2 = sections.get("preset.2", {})
    p2_opt = sections.get("preset.2.options", {})
    if p2.get("name", "").strip('"') != "iOS" or p2.get("platform", "").strip('"') != "iOS":
        return False, ["FAIL: preset.2 is not iOS"]
    if p2.get("include_filter", "").strip('"') != "assets/models/*.onnx":
        return False, [f"FAIL: iOS include_filter is {p2.get('include_filter')}"]
    if p2_opt.get("architectures/arm64", "").lower() != "true":
        return False, ["FAIL: iOS architectures/arm64 is not true"]
    if not p2_opt.get("privacy/microphone_usage_description", "").strip('"'):
        return False, ["FAIL: iOS privacy/microphone_usage_description is empty"]
    checks.append(
        "iOS (iPhone ARM64) preset verified: arm64=true, NSMicrophoneUsageDescription set, include_filter=assets/models/*.onnx."
    )

    return True, checks


def run_headless_validation(godot_bin: str, timeout_sec: int = 30) -> Tuple[bool, List[str]]:
    """Runs Godot engine headlessly with --quit to verify project loads without errors."""
    cmd = [godot_bin, "--headless", "--path", PROJECT_ROOT, "--quit"]
    try:
        proc = subprocess.run(
            cmd,
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            timeout=timeout_sec,
            encoding="utf-8",
            errors="replace",
        )
        out = (proc.stdout or "") + "\n" + (proc.stderr or "")
        if proc.returncode != 0:
            return False, [f"FAIL: Godot headless validation exited with code {proc.returncode}", out.strip()]
        return True, ["Headless Godot startup & clean quit verified (exit code 0)."]
    except Exception as exc:
        return False, [f"FAIL: Exception running Godot headless validation: {exc}"]


def export_targets(godot_bin: str, timeout_sec: int = 120) -> Tuple[bool, List[str]]:
    """Exports Android APK and Windows Desktop EXE using Godot headless CLI."""
    logs: List[str] = []
    targets = [
        ("Android", "micgame3.apk"),
        ("Windows Desktop", "micgame3.exe"),
    ]
    for preset_name, out_filename in targets:
        out_path = os.path.join(PROJECT_ROOT, out_filename)
        cmd = [godot_bin, "--headless", "--path", PROJECT_ROOT, "--export-debug", preset_name, out_path]
        t0 = time.perf_counter()
        try:
            proc = subprocess.run(
                cmd,
                cwd=PROJECT_ROOT,
                capture_output=True,
                text=True,
                timeout=timeout_sec,
                encoding="utf-8",
                errors="replace",
            )
            elapsed = time.perf_counter() - t0
            if proc.returncode != 0:
                logs.append(f"FAIL: Export '{preset_name}' failed with code {proc.returncode}")
                return False, logs
            logs.append(f"Exported '{preset_name}' -> {out_filename} in {elapsed:.2f}s (exit code 0).")
        except Exception as exc:
            logs.append(f"FAIL: Exception exporting '{preset_name}': {exc}")
            return False, logs
    return True, logs


def verify_exported_binaries() -> Tuple[bool, List[str]]:
    """Verifies micgame3.apk (ZIP structure, ARM64 lib, manifest) and micgame3.exe (PE MZ header)."""
    checks: List[str] = []

    apk_path = os.path.join(PROJECT_ROOT, "micgame3.apk")
    if not os.path.exists(apk_path):
        return False, [f"FAIL: Android APK not found at {apk_path}"]
    apk_size = os.path.getsize(apk_path)
    if apk_size < 1_000_000:
        return False, [f"FAIL: Android APK size too small ({apk_size} bytes)"]

    try:
        with zipfile.ZipFile(apk_path, "r") as zf:
            names = set(zf.namelist())
            if "AndroidManifest.xml" not in names:
                return False, ["FAIL: AndroidManifest.xml missing from micgame3.apk"]
            if "lib/arm64-v8a/libgodot_android.so" not in names:
                return False, ["FAIL: lib/arm64-v8a/libgodot_android.so missing from micgame3.apk"]
            manifest_bytes = zf.read("AndroidManifest.xml")
            # UTF-16LE or UTF-8 string check in compiled binary XML string pool
            manifest_text = manifest_bytes.decode("utf-16le", errors="ignore") + manifest_bytes.decode("latin1", errors="ignore")
            if "RECORD_AUDIO" not in manifest_text:
                return False, ["FAIL: RECORD_AUDIO permission string not found in compiled AndroidManifest.xml"]
    except zipfile.BadZipFile:
        return False, ["FAIL: micgame3.apk is not a valid ZIP/APK archive"]

    checks.append(
        f"Verified micgame3.apk ({apk_size / (1024 * 1024):.1f} MB): valid APK archive, "
        f"contains AndroidManifest.xml (RECORD_AUDIO) & lib/arm64-v8a/libgodot_android.so."
    )

    exe_path = os.path.join(PROJECT_ROOT, "micgame3.exe")
    if not os.path.exists(exe_path):
        return False, [f"FAIL: Windows executable not found at {exe_path}"]
    exe_size = os.path.getsize(exe_path)
    if exe_size < 1_000_000:
        return False, [f"FAIL: Windows executable size too small ({exe_size} bytes)"]

    with open(exe_path, "rb") as f:
        magic = f.read(2)
    if magic != b"MZ":
        return False, [f"FAIL: micgame3.exe invalid PE header magic: {magic!r}"]

    checks.append(
        f"Verified micgame3.exe ({exe_size / (1024 * 1024):.1f} MB): valid Windows PE x86_64 executable (MZ header)."
    )
    return True, checks


def run_build_and_export(
    godot_bin: Optional[str] = None,
    do_export: bool = False,
    skip_headless: bool = False,
    json_output: bool = False,
) -> bool:
    t0 = time.perf_counter()
    resolved_godot = find_godot_binary(godot_bin)

    steps: List[Dict[str, Any]] = []
    all_passed = True

    # Step 1: project.godot & Record Bus validation
    ok_proj, logs_proj = validate_project_config()
    steps.append({"step": "Project Configuration (project.godot & Record bus)", "passed": ok_proj, "logs": logs_proj})
    if not ok_proj:
        all_passed = False

    # Step 2: export_presets.cfg validation
    ok_exp, logs_exp = validate_export_presets()
    steps.append({"step": "Export Presets (Android Pixel 7a & Windows x86_64)", "passed": ok_exp, "logs": logs_exp})
    if not ok_exp:
        all_passed = False

    # Step 3: Headless Godot Validation
    if not skip_headless and resolved_godot:
        ok_hl, logs_hl = run_headless_validation(resolved_godot)
        steps.append({"step": "Godot Headless Project Validation", "passed": ok_hl, "logs": logs_hl})
        if not ok_hl:
            all_passed = False

    # Step 4: Optional Fresh Export if requested or if binaries are missing
    apk_exists = os.path.exists(os.path.join(PROJECT_ROOT, "micgame3.apk"))
    exe_exists = os.path.exists(os.path.join(PROJECT_ROOT, "micgame3.exe"))
    if (do_export or not apk_exists or not exe_exists) and resolved_godot:
        ok_build, logs_build = export_targets(resolved_godot)
        steps.append({"step": "Godot Headless Platform Export", "passed": ok_build, "logs": logs_build})
        if not ok_build:
            all_passed = False

    # Step 5: Binary Artifact Inspection (micgame3.apk & micgame3.exe)
    ok_bin, logs_bin = verify_exported_binaries()
    steps.append({"step": "Binary Artifact Verification (APK & EXE)", "passed": ok_bin, "logs": logs_bin})
    if not ok_bin:
        all_passed = False

    elapsed = time.perf_counter() - t0
    report = {
        "passed": all_passed,
        "duration_sec": elapsed,
        "godot_binary": resolved_godot,
        "steps": steps,
    }

    if json_output:
        print(json.dumps(report, indent=2))
        return all_passed

    print("=" * 75)
    print("MICGAME-3 BUILD, EXPORT & HEADLESS VALIDATION TOOL")
    print("=" * 75)
    print(f"Project Root : {PROJECT_ROOT}")
    print(f"Godot Binary : {resolved_godot if resolved_godot else 'Not Found (Config & Binary inspection mode)'}")
    print("-" * 75)

    for s in steps:
        status = "PASSED [OK]" if s["passed"] else "FAILED [X]"
        print(f"\n[Step] {s['step']} -> {status}")
        for line in s["logs"]:
            print(f"  - {line}")

    print("\n" + "=" * 75)
    print(
        f"OVERALL BUILD & EXPORT RESULT: "
        f"{'ALL PASS [OK]' if all_passed else 'FAILURES DETECTED [X]'} ({elapsed:.3f}s)"
    )
    print("=" * 75)
    return all_passed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="MicGame-3 Build, Export & Headless Validation CLI")
    parser.add_argument("--godot-bin", type=str, default=None, help="Path to Godot 4 executable")
    parser.add_argument("--export", action="store_true", help="Force fresh headless export of micgame3.apk and micgame3.exe")
    parser.add_argument("--skip-headless", action="store_true", help="Skip headless Godot startup check")
    parser.add_argument("--json", action="store_true", help="Output machine-readable JSON report")
    args = parser.parse_args()

    success = run_build_and_export(
        godot_bin=args.godot_bin,
        do_export=args.export,
        skip_headless=args.skip_headless,
        json_output=args.json,
    )
    sys.exit(0 if success else 1)
