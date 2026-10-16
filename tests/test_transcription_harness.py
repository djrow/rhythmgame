"""
Automated CLI ONNX Polyphonic Transcription Verification Harness.
Ingests the 3 bundled test pieces (Monophonic, 2-Part Harmony, Polyphonic Chordal),
executes pure NumPy + ONNX Runtime Basic Pitch inference, and evaluates
note accuracy / F1-Score against ground truth chart events.

Acceptance Criteria:
- Polyphonic transcription achieves >= 80% F1-score / note accuracy on polyphonic test audio.
- Concurrent chord pitches are identified as simultaneous active notes.
- Zero external audio library dependencies (zero scipy, librosa, or resampy).
"""

import argparse
import json
import os
import sys
import time
from typing import Dict, List, Tuple

# Ensure project root is in sys.path
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from python.basic_pitch_onnx import BasicPitchOnnxRunner, read_wav_mono


def evaluate_note_metrics(
    detected: List[Dict],
    ground_truth: List[Dict],
    onset_tolerance_sec: float = 0.15,
    pitch_tolerance_semitones: int = 0,
) -> Dict[str, float]:
    """
    Evaluates note-level True Positives, False Positives, False Negatives,
    Precision, Recall, and F1-score against ground truth chart notes.
    """
    gt_matched = [False] * len(ground_truth)
    det_matched = [False] * len(detected)

    for i, d in enumerate(detected):
        for j, g in enumerate(ground_truth):
            if gt_matched[j]:
                continue
            pitch_match = abs(d["pitch"] - g["pitch_midi"]) <= pitch_tolerance_semitones
            onset_match = abs(d["onset_sec"] - g["time_sec"]) <= onset_tolerance_sec
            if pitch_match and onset_match:
                gt_matched[j] = True
                det_matched[i] = True
                break

    tp = sum(det_matched)
    fp = len(detected) - tp
    fn = len(ground_truth) - sum(gt_matched)

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    f1 = 2.0 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0.0

    return {
        "tp": tp,
        "fp": fp,
        "fn": fn,
        "precision": precision,
        "recall": recall,
        "f1": f1,
        "gt_count": len(ground_truth),
        "det_count": len(detected),
    }


def verify_polyphonic_simultaneity(detected: List[Dict], chart: Dict) -> bool:
    """Verifies that simultaneous notes in chords are detected concurrently."""
    chord_times = set()
    for n in chart.get("notes", []):
        if n.get("is_chord", False):
            chord_times.add(round(n["time_sec"], 2))

    if not chord_times:
        return True

    verified_chords = 0
    for t_chord in chord_times:
        # Find detected notes with onsets near t_chord
        coincident = [
            d for d in detected if abs(d["onset_sec"] - t_chord) <= 0.20
        ]
        pitches = {d["pitch"] for d in coincident}
        if len(pitches) >= 2:
            verified_chords += 1

    return verified_chords >= (len(chord_times) // 2)


def run_transcription_harness(
    model_path: str = None,
    audio_dir: str = None,
    charts_dir: str = None,
    min_f1: float = 0.80,
) -> bool:
    if model_path is None:
        model_path = os.path.join(PROJECT_ROOT, "assets", "models", "nmp.onnx")
    if audio_dir is None:
        audio_dir = os.path.join(PROJECT_ROOT, "assets", "audio")
    if charts_dir is None:
        charts_dir = os.path.join(PROJECT_ROOT, "assets", "charts")

    print("=" * 70)
    print("MICGAME-3 BASIC PITCH ONNX TRANSCRIPTION HARNESS")
    print("=" * 70)
    print(f"Model Path : {model_path}")
    print(f"Audio Dir  : {audio_dir}")
    print(f"Charts Dir : {charts_dir}")
    print(f"Min F1 Req : {min_f1 * 100:.1f}%")

    runner = BasicPitchOnnxRunner(
        model_path=model_path,
        note_threshold=0.40,
        onset_threshold=0.45,
        min_note_len_frames=6,
    )

    test_pieces = [
        ("Monophonic Melody ('Ode to Joy')", "ode_to_joy.wav", "ode_to_joy.json", min_f1),
        ("2-Part Harmony ('Bach Minuet')", "bach_minuet.wav", "bach_minuet.json", min_f1),
        ("Polyphonic Chordal ('Cadence Triads')", "cadence_triads.wav", "cadence_triads.json", min_f1),
    ]

    all_passed = True

    for title, wav_name, json_name, target_f1 in test_pieces:
        wav_path = os.path.join(audio_dir, wav_name)
        json_path = os.path.join(charts_dir, json_name)

        if not os.path.exists(wav_path):
            print(f"ERROR: Audio file not found: {wav_path}")
            return False
        if not os.path.exists(json_path):
            print(f"ERROR: Chart file not found: {json_path}")
            return False

        with open(json_path, "r", encoding="utf-8") as f:
            chart = json.load(f)

        t0 = time.perf_counter()
        detected = runner.transcribe_file(wav_path)
        elapsed_sec = time.perf_counter() - t0

        metrics = evaluate_note_metrics(
            detected=detected,
            ground_truth=chart["notes"],
            onset_tolerance_sec=0.15,
            pitch_tolerance_semitones=0,
        )

        f1 = metrics["f1"]
        passed = f1 >= target_f1

        print(f"\nPiece: {title}")
        print(f"  Audio File       : {wav_name}")
        print(f"  Inference Time   : {elapsed_sec:.3f} s")
        print(f"  Ground Truth     : {metrics['gt_count']} notes")
        print(f"  Detected Notes   : {metrics['det_count']} notes")
        print(f"  TP / FP / FN     : {metrics['tp']} / {metrics['fp']} / {metrics['fn']}")
        print(f"  Precision        : {metrics['precision'] * 100:.1f}%")
        print(f"  Recall           : {metrics['recall'] * 100:.1f}%")
        print(f"  F1-Score         : {metrics['f1'] * 100:.1f}% (Required: >={target_f1 * 100:.1f}%)")

        if "Polyphonic" in title:
            chords_ok = verify_polyphonic_simultaneity(detected, chart)
            print(f"  Polyphonic Chords: {'PASS (Concurrent notes verified)' if chords_ok else 'FAIL'}")
            passed = passed and chords_ok

        print(f"  Status           : {'PASSED [OK]' if passed else 'FAILED [X]'}")

        if not passed:
            all_passed = False

    print("\n" + "=" * 70)
    print(f"OVERALL HARNESS RESULT: {'ALL PASS [OK]' if all_passed else 'FAILURES DETECTED [X]'}")
    print("=" * 70)
    return all_passed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Basic Pitch ONNX Transcription Verification Harness")
    parser.add_argument("--model-path", type=str, default=None, help="Path to nmp.onnx")
    parser.add_argument("--audio-dir", type=str, default=None, help="Path to assets/audio")
    parser.add_argument("--charts-dir", type=str, default=None, help="Path to assets/charts")
    parser.add_argument("--min-f1", type=float, default=0.80, help="Minimum F1 score required (e.g. 0.80)")
    args = parser.parse_args()

    success = run_transcription_harness(
        model_path=args.model_path,
        audio_dir=args.audio_dir,
        charts_dir=args.charts_dir,
        min_f1=args.min_f1,
    )
    sys.exit(0 if success else 1)
