#!/usr/bin/env python3
"""
Automated CLI Scoring & Alignment Verification Harness (Feature #16).
Verifies the scoring, timing window, combo multiplier, audio-chart alignment,
and polyphonic chord cluster matching engines against the 3 bundled test pieces
(ode_to_joy, bach_minuet, cadence_triads) without requiring live microphone hardware.
Also executes the headless Godot GDScript scoring runners:
  - res://tests/test_scoring_runner.gd
  - res://tests/test_inference_scoring_runner.gd
"""

import argparse
import copy
import json
import os
import shutil
import subprocess
import sys
import time
from typing import Any, Dict, List, Optional, Tuple

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from tests.e2e.e2e_test_utils import (
    AudioInferenceUtils,
    ChartValidator,
    DiatonicMath,
    HighwayMath,
)


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


class HeadlessScoringSimulator:
    """
    Python mirror of res://scripts/scoring_engine.gd for deterministic
    chart playthrough and alignment verification without live microphone input.
    """

    WINDOW_PERFECT_SEC = 0.050
    WINDOW_GOOD_SEC = 0.100
    TIMING_EPSILON = 0.000005

    POINTS_PERFECT = 100
    POINTS_GOOD = 50
    POINTS_MISS = 0

    COMBO_2X = 10
    COMBO_3X = 20
    COMBO_4X = 30

    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        self.score: int = 0
        self.combo: int = 0
        self.max_combo: int = 0
        self.count_perfect: int = 0
        self.count_good: int = 0
        self.count_miss: int = 0
        self.total_notes: int = 0

    def get_multiplier(self) -> int:
        if self.combo >= self.COMBO_4X:
            return 4
        elif self.combo >= self.COMBO_3X:
            return 3
        elif self.combo >= self.COMBO_2X:
            return 2
        return 1

    def evaluate_timing(self, time_diff_sec: float) -> str:
        abs_diff = abs(time_diff_sec)
        if abs_diff <= self.WINDOW_PERFECT_SEC + self.TIMING_EPSILON:
            return "PERFECT"
        elif abs_diff <= self.WINDOW_GOOD_SEC + self.TIMING_EPSILON:
            return "GOOD"
        return "MISS"

    def register_hit(self, judgment: str, note_data: Optional[Dict] = None) -> Dict[str, Any]:
        if judgment not in ("PERFECT", "GOOD", "MISS"):
            return {}
        self.total_notes += 1
        base_pts = 0
        if judgment == "PERFECT":
            self.count_perfect += 1
            self.combo += 1
            base_pts = self.POINTS_PERFECT
        elif judgment == "GOOD":
            self.count_good += 1
            self.combo += 1
            base_pts = self.POINTS_GOOD
        elif judgment == "MISS":
            self.count_miss += 1
            self.combo = 0
            base_pts = self.POINTS_MISS

        if self.combo > self.max_combo:
            self.max_combo = self.combo

        mult = self.get_multiplier()
        points_awarded = base_pts * mult
        self.score += points_awarded
        return {
            "judgment": judgment,
            "base_points": base_pts,
            "multiplier": mult,
            "points_awarded": points_awarded,
            "score": self.score,
            "combo": self.combo,
            "max_combo": self.max_combo,
            "note_data": note_data or {},
        }

    def register_miss(self, note_data: Optional[Dict] = None) -> Dict[str, Any]:
        return self.register_hit("MISS", note_data)

    def process_input(
        self,
        input_time: float,
        pitch_midi: int,
        notes: List[Dict[str, Any]],
        semitone_tolerance: int = 0,
    ) -> Dict[str, Any]:
        best_index = -1
        min_abs_diff = 9999.0

        for i, note in enumerate(notes):
            if note.get("is_hit", False) or note.get("is_missed", False):
                continue
            note_pitch = int(note.get("pitch_midi", 0))
            note_time = float(note.get("time_sec", 0.0))

            if abs(note_pitch - pitch_midi) > semitone_tolerance:
                continue

            time_diff = input_time - note_time
            abs_diff = abs(time_diff)
            if abs_diff <= (self.WINDOW_GOOD_SEC + self.TIMING_EPSILON) and abs_diff < min_abs_diff:
                min_abs_diff = abs_diff
                best_index = i

        if best_index != -1:
            target_note = notes[best_index]
            time_diff = input_time - float(target_note.get("time_sec", 0.0))
            judgment = self.evaluate_timing(time_diff)
            target_note["is_hit"] = True
            target_note["hit_time"] = input_time
            target_note["hit_diff"] = time_diff
            target_note["judgment"] = judgment
            res = self.register_hit(judgment, target_note)
            res["matched_note_index"] = best_index
            res["time_diff"] = time_diff
            return res

        return {}

    def check_expired_notes(self, current_time: float, notes: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        expired_events = []
        for i, note in enumerate(notes):
            if note.get("is_hit", False) or note.get("is_missed", False):
                continue
            note_time = float(note.get("time_sec", 0.0))
            if current_time > note_time + self.WINDOW_GOOD_SEC:
                note["is_missed"] = True
                res = self.register_miss(note)
                res["matched_note_index"] = i
                expired_events.append(res)
        return expired_events

    def get_accuracy(self) -> float:
        if self.total_notes == 0:
            return 100.0
        weighted = (float(self.count_perfect) * 1.0) + (float(self.count_good) * 0.5)
        return (weighted / float(self.total_notes)) * 100.0

    def get_summary(self) -> Dict[str, Any]:
        return {
            "score": self.score,
            "combo": self.combo,
            "max_combo": self.max_combo,
            "multiplier": self.get_multiplier(),
            "total_notes": self.total_notes,
            "count_perfect": self.count_perfect,
            "count_good": self.count_good,
            "count_miss": self.count_miss,
            "accuracy_pct": self.get_accuracy(),
        }


def verify_timing_and_multipliers() -> Tuple[bool, List[str]]:
    """Verifies timing windows, multiplier transitions (1x->4x), and streak resets."""
    logs: List[str] = []
    sim = HeadlessScoringSimulator()

    # Timing window checks
    timing_cases = [
        (0.000, "PERFECT"),
        (0.025, "PERFECT"),
        (-0.049, "PERFECT"),
        (0.050, "PERFECT"),
        (-0.050, "PERFECT"),
        (0.051, "GOOD"),
        (-0.075, "GOOD"),
        (0.100, "GOOD"),
        (-0.100, "GOOD"),
        (0.101, "MISS"),
        (-0.150, "MISS"),
    ]
    for delta, expected in timing_cases:
        actual = sim.evaluate_timing(delta)
        if actual != expected:
            logs.append(f"FAIL: evaluate_timing({delta}) -> {actual}, expected {expected}")
            return False, logs

    # Multiplier progression: 35 Perfect hits
    for i in range(1, 36):
        res = sim.register_hit("PERFECT")
        expected_mult = 4 if i >= 30 else (3 if i >= 20 else (2 if i >= 10 else 1))
        if res["multiplier"] != expected_mult:
            logs.append(f"FAIL: Hit {i} multiplier {res['multiplier']} != {expected_mult}")
            return False, logs

    # Miss resets combo and multiplier
    sim.register_miss()
    if sim.combo != 0 or sim.get_multiplier() != 1 or sim.max_combo != 35:
        logs.append("FAIL: Miss did not properly reset combo/multiplier or preserve max_combo")
        return False, logs

    logs.append("Timing windows (+/-50ms Perfect, +/-100ms Good, >100ms Miss) & multipliers (1x-4x) verified.")
    return True, logs


def simulate_piece_playthrough(
    chart_path: str,
    timing_offset_sec: float = 0.015,
    semitone_tolerance: int = 0,
) -> Tuple[bool, Dict[str, Any]]:
    """
    Loads a bundled reference chart, validates schema and beat-to-second alignment,
    and simulates a full headless playthrough at the specified timing offset.
    """
    if not os.path.exists(chart_path):
        return False, {"error": f"Chart not found: {chart_path}"}

    with open(chart_path, "r", encoding="utf-8") as f:
        chart = json.load(f)

    valid, msg = ChartValidator.validate_chart_dict(chart)
    if not valid:
        return False, {"error": f"Invalid chart schema: {msg}"}

    bpm = float(chart["bpm"])
    time_sig = chart["time_signature"]
    beats_per_measure = float(time_sig[0])
    sec_per_beat = 60.0 / bpm

    notes = copy.deepcopy(chart["notes"])
    for n in notes:
        n["is_hit"] = False
        n["is_missed"] = False
        # Verify measure/beat to time_sec alignment
        expected_onset_beat = (int(n["measure"]) - 1) * beats_per_measure + float(n["beat"])
        expected_time_sec = expected_onset_beat * sec_per_beat
        if abs(float(n["time_sec"]) - expected_time_sec) > 0.02:
            return False, {
                "error": f"Alignment mismatch on note {n}: time_sec={n['time_sec']} vs expected={expected_time_sec}"
            }
        # Verify diatonic highway coordinate calculation
        y_coord = DiatonicMath.midi_to_y(int(n["pitch_midi"]))
        x_at_hit = HighwayMath.note_x_position(float(n["time_sec"]), float(n["time_sec"]))
        if abs(x_at_hit - DiatonicMath.HIT_LINE_X) > 1e-4 or not (0.0 < y_coord < 720.0):
            return False, {"error": f"Invalid highway coordinate for note {n}"}

    sim = HeadlessScoringSimulator()

    # Group notes by onset timestamp to simulate polyphonic cluster input
    onset_groups: Dict[float, List[Dict[str, Any]]] = {}
    for n in notes:
        t = round(float(n["time_sec"]), 4)
        onset_groups.setdefault(t, []).append(n)

    for onset_time in sorted(onset_groups.keys()):
        cluster_notes = onset_groups[onset_time]
        pitches = [int(n["pitch_midi"]) for n in cluster_notes]
        playhead_time = onset_time + timing_offset_sec

        # Verify cluster matching metric
        cluster_metrics = AudioInferenceUtils.match_polyphonic_clusters(set(pitches), set(pitches))
        if cluster_metrics["f1"] < 1.0:
            return False, {"error": "Polyphonic cluster self-match F1 < 1.0"}

        for p in pitches:
            sim.process_input(playhead_time, p, cluster_notes, semitone_tolerance=semitone_tolerance)

        sim.check_expired_notes(playhead_time, cluster_notes)

    # Final expiration sweep after song ends
    last_time = max(float(n["time_sec"]) + float(n["duration_sec"]) for n in notes) + 1.0
    sim.check_expired_notes(last_time, notes)

    summary = sim.get_summary()
    summary["title"] = chart.get("title", os.path.basename(chart_path))
    summary["bpm"] = bpm
    summary["chart_notes"] = len(notes)
    summary["onset_clusters"] = len(onset_groups)

    expected_judgment = sim.evaluate_timing(timing_offset_sec)
    if expected_judgment == "PERFECT":
        passed = (
            summary["count_perfect"] == len(notes)
            and summary["count_miss"] == 0
            and abs(summary["accuracy_pct"] - 100.0) < 1e-4
        )
    elif expected_judgment == "GOOD":
        passed = (
            summary["count_good"] == len(notes)
            and summary["count_miss"] == 0
            and abs(summary["accuracy_pct"] - 50.0) < 1e-4
        )
    else:
        passed = summary["count_miss"] == len(notes) and summary["combo"] == 0

    return passed, summary


def run_godot_headless_script(godot_bin: str, script_res_path: str, timeout_sec: int = 30) -> Tuple[bool, str]:
    """Executes a Godot SceneTree script headlessly and checks exit code 0."""
    cmd = [godot_bin, "--headless", "--path", PROJECT_ROOT, "-s", script_res_path]
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
        output = (proc.stdout or "") + "\n" + (proc.stderr or "")
        passed = proc.returncode == 0 and "FAILED" not in output
        return passed, output.strip()
    except Exception as exc:
        return False, str(exc)


def run_scoring_harness(
    charts_dir: Optional[str] = None,
    godot_bin: Optional[str] = None,
    skip_godot: bool = False,
    json_output: bool = False,
) -> bool:
    if charts_dir is None:
        charts_dir = os.path.join(PROJECT_ROOT, "assets", "charts")

    t0 = time.perf_counter()
    results: Dict[str, Any] = {
        "passed": True,
        "suites": [],
        "pieces": [],
        "godot_runners": [],
    }

    # 1. Core Timing Windows & Multiplier Formula Suite
    ok_core, core_logs = verify_timing_and_multipliers()
    results["suites"].append({"name": "Timing Windows & Multipliers", "passed": ok_core, "logs": core_logs})
    if not ok_core:
        results["passed"] = False

    # 2. Bundled Test Pieces Playthroughs (Perfect, Good, and Miss simulations)
    bundled_pieces = [
        ("Monophonic Melody ('Ode to Joy')", "ode_to_joy.json"),
        ("2-Part Harmony ('Bach Minuet')", "bach_minuet.json"),
        ("Polyphonic Chordal ('Cadence Triads')", "cadence_triads.json"),
    ]

    total_notes_evaluated = 0
    for label, filename in bundled_pieces:
        chart_path = os.path.join(charts_dir, filename)
        ok_perf, sum_perf = simulate_piece_playthrough(chart_path, timing_offset_sec=0.015)
        ok_good, sum_good = simulate_piece_playthrough(chart_path, timing_offset_sec=0.075)
        ok_miss, sum_miss = simulate_piece_playthrough(chart_path, timing_offset_sec=0.150)

        piece_ok = ok_perf and ok_good and ok_miss
        if not piece_ok:
            results["passed"] = False

        notes_count = sum_perf.get("chart_notes", 0)
        total_notes_evaluated += notes_count * 3

        results["pieces"].append({
            "label": label,
            "file": filename,
            "passed": piece_ok,
            "notes": notes_count,
            "clusters": sum_perf.get("onset_clusters", 0),
            "perfect_run_score": sum_perf.get("score", 0),
            "perfect_run_max_combo": sum_perf.get("max_combo", 0),
            "good_run_score": sum_good.get("score", 0),
            "miss_run_score": sum_miss.get("score", 0),
        })

    # 3. Headless Godot GDScript Runners
    resolved_godot = find_godot_binary(godot_bin)
    if not skip_godot and resolved_godot:
        for runner_script in ["res://tests/test_scoring_runner.gd", "res://tests/test_inference_scoring_runner.gd"]:
            g_ok, g_out = run_godot_headless_script(resolved_godot, runner_script)
            results["godot_runners"].append({
                "script": runner_script,
                "passed": g_ok,
                "output_tail": g_out.splitlines()[-5:] if g_out else [],
            })
            if not g_ok:
                results["passed"] = False

    elapsed = time.perf_counter() - t0
    results["duration_sec"] = elapsed
    results["notes_evaluated"] = total_notes_evaluated

    if json_output:
        print(json.dumps(results, indent=2))
        return results["passed"]

    print("=" * 75)
    print("MICGAME-3 SCORING & ALIGNMENT VERIFICATION HARNESS")
    print("=" * 75)
    print(f"Charts Dir : {charts_dir}")
    print(f"Godot Bin  : {resolved_godot if resolved_godot else 'Not Found (Python simulation only)'}")
    print("-" * 75)

    for s in results["suites"]:
        status = "PASSED [OK]" if s["passed"] else "FAILED [X]"
        print(f"[Suite] {s['name']}: {status}")
        for line in s["logs"]:
            print(f"  - {line}")

    print("\n[Bundled Test Pieces Playthroughs & Alignment]")
    for p in results["pieces"]:
        status = "PASSED [OK]" if p["passed"] else "FAILED [X]"
        print(f"  Piece: {p['label']} ({p['file']})")
        print(f"    Notes / Clusters : {p['notes']} notes across {p['clusters']} onset events")
        print(f"    Perfect Run (+15ms): Score = {p['perfect_run_score']}, Max Combo = {p['perfect_run_max_combo']} (100.0% Acc)")
        print(f"    Good Run    (+75ms): Score = {p['good_run_score']} (50.0% Acc)")
        print(f"    Miss Run   (+150ms): Score = {p['miss_run_score']} (0.0% Acc, Combo Reset Verified)")
        print(f"    Status             : {status}")

    if results["godot_runners"]:
        print("\n[Godot Headless Scoring & Inference Runners]")
        for gr in results["godot_runners"]:
            status = "PASSED [OK]" if gr["passed"] else "FAILED [X]"
            print(f"  Runner: {gr['script']} -> {status}")
            for tl in gr["output_tail"]:
                print(f"    {tl}")

    print("\n" + "=" * 75)
    print(
        f"OVERALL SCORING HARNESS RESULT: "
        f"{'ALL PASS [OK]' if results['passed'] else 'FAILURES DETECTED [X]'} "
        f"({total_notes_evaluated} simulated note events in {elapsed:.3f}s)"
    )
    print("=" * 75)
    return results["passed"]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Standalone CLI Scoring & Alignment Verification Harness")
    parser.add_argument("--charts-dir", type=str, default=None, help="Path to assets/charts")
    parser.add_argument("--godot-bin", type=str, default=None, help="Path to Godot executable")
    parser.add_argument("--skip-godot", action="store_true", help="Skip Godot headless runner execution")
    parser.add_argument("--json", action="store_true", help="Output structured JSON report")
    args = parser.parse_args()

    ok = run_scoring_harness(
        charts_dir=args.charts_dir,
        godot_bin=args.godot_bin,
        skip_godot=args.skip_godot,
        json_output=args.json,
    )
    sys.exit(0 if ok else 1)
