"""
Automated CLI Optical Music Recognition (OMR) Verification Harness.
Ingests sheet music score images, executes OMREngine detection, and evaluates
note recognition accuracy (pitch & onset timing in beats) against ground truth charts.

Acceptance Criteria:
- Note pitch and onset recognition accuracy >= 85.0% on clean score images.
- Exact pitch match: pitch_det == pitch_gt.
- Temporal onset tolerance: abs(onset_beat_det - onset_beat_gt) <= 0.25 beats.
- Evaluates across all 3 bundled test pieces if no specific score is provided.
- Returns exit code 0 on >=85% accuracy, exit code 1 on failure.
"""

import argparse
import json
import os
import sys
import time
from typing import Dict, List, Optional, Tuple


def find_project_root() -> str:
    cur = os.path.abspath(os.path.dirname(__file__))
    while cur and os.path.dirname(cur) != cur:
        if os.path.exists(os.path.join(cur, "PROJECT.md")) or os.path.exists(os.path.join(cur, "project.godot")):
            return cur
        cur = os.path.dirname(cur)
    return os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


PROJECT_ROOT = find_project_root()
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)
current_dir = os.path.abspath(os.path.dirname(__file__))
if current_dir not in sys.path:
    sys.path.insert(0, current_dir)

# Import OMREngine from python.omr_engine
try:
    from python.omr_engine import OMREngine
except ImportError:
    from proposed_omr_engine import OMREngine


def evaluate_omr_metrics(
    detected_notes: List[Dict],
    ground_truth_notes: List[Dict],
    onset_beat_tolerance: float = 0.25,
) -> Dict[str, float]:
    """
    Evaluates True Positives, False Positives, False Negatives,
    Precision, Recall, and Recognition Accuracy between detected and ground truth notes.

    Matching criteria:
    - pitch_det == pitch_gt (exact MIDI pitch)
    - abs(onset_beat_det - onset_beat_gt) <= onset_beat_tolerance (default 0.25 beats)
    """
    gt_matched = [False] * len(ground_truth_notes)
    det_matched = [False] * len(detected_notes)

    for i, d in enumerate(detected_notes):
        d_pitch = d.get("pitch_midi")
        d_beat = d.get("onset_beat", d.get("beat", 0.0))

        for j, g in enumerate(ground_truth_notes):
            if gt_matched[j]:
                continue
            g_pitch = g.get("pitch_midi")
            g_beat = g.get("onset_beat", g.get("beat", 0.0))

            pitch_match = (d_pitch == g_pitch)
            onset_match = abs(d_beat - g_beat) <= onset_beat_tolerance

            if pitch_match and onset_match:
                gt_matched[j] = True
                det_matched[i] = True
                break

    tp = sum(det_matched)
    fp = len(detected_notes) - tp
    fn = len(ground_truth_notes) - sum(gt_matched)

    total_reference = len(ground_truth_notes)
    total_detected = len(detected_notes)

    precision = tp / total_detected if total_detected > 0 else 0.0
    recall = tp / total_reference if total_reference > 0 else 0.0
    # Overall recognition accuracy
    accuracy = tp / max(total_reference, total_detected) if max(total_reference, total_detected) > 0 else 0.0

    return {
        "tp": tp,
        "fp": fp,
        "fn": fn,
        "gt_count": total_reference,
        "det_count": total_detected,
        "precision": precision,
        "recall": recall,
        "accuracy": accuracy,
    }


def run_single_evaluation(
    score_path: str,
    ground_truth_path: str,
    min_accuracy: float = 0.85,
    engine: Optional[OMREngine] = None,
) -> Tuple[bool, Dict[str, float]]:
    """Evaluates OMR engine on a single score image against ground truth chart."""
    if engine is None:
        engine = OMREngine()

    if not os.path.exists(score_path):
        print(f"ERROR: Score file not found: {score_path}")
        return False, {}
    if not os.path.exists(ground_truth_path):
        print(f"ERROR: Ground truth file not found: {ground_truth_path}")
        return False, {}

    with open(ground_truth_path, "r", encoding="utf-8") as f:
        gt_data = json.load(f)
    gt_notes = gt_data.get("notes", [])

    t0 = time.perf_counter()
    chart = engine.process_score(score_path)
    elapsed = time.perf_counter() - t0

    det_notes = chart.get("notes", [])

    metrics = evaluate_omr_metrics(det_notes, gt_notes, onset_beat_tolerance=0.25)
    accuracy = metrics["accuracy"]
    passed = accuracy >= min_accuracy

    print("=" * 70)
    print("OMR VERIFICATION HARNESS REPORT")
    print(f"Score Image  : {os.path.relpath(score_path, PROJECT_ROOT) if score_path.startswith(PROJECT_ROOT) else score_path}")
    print(f"Ground Truth : {os.path.relpath(ground_truth_path, PROJECT_ROOT) if ground_truth_path.startswith(PROJECT_ROOT) else ground_truth_path}")
    print(f"Processing   : {elapsed * 1000.0:.1f} ms")
    print("-" * 70)
    print(f"Ground Truth Notes : {metrics['gt_count']}")
    print(f"Detected Notes     : {metrics['det_count']}")
    print(f"Matched Notes (TP) : {metrics['tp']}")
    print(f"False Positives    : {metrics['fp']}")
    print(f"False Negatives    : {metrics['fn']}")
    print(f"Precision          : {metrics['precision'] * 100.0:.1f}%")
    print(f"Recall             : {metrics['recall'] * 100.0:.1f}%")
    print(
        f"Recognition Accuracy: {accuracy * 100.0:.1f}% "
        f"[TARGET >= {min_accuracy * 100.0:.1f}%] -> {'PASS' if passed else 'FAIL'}"
    )
    print("=" * 70)

    return passed, metrics


def run_all_bundled_evaluations(
    assets_dir: Optional[str] = None,
    min_accuracy: float = 0.85,
) -> bool:
    """Evaluates all 3 bundled test pieces."""
    if assets_dir is None:
        assets_dir = os.path.join(PROJECT_ROOT, "assets")

    test_pieces = [
        ("Piece 1: Monophonic Melody ('Ode to Joy')", "piece_1_monophonic"),
        ("Piece 2: 2-Part Harmony ('Bach Minuet')", "piece_2_harmony"),
        ("Piece 3: Polyphonic Progression ('Cadence Triads')", "piece_3_polyphonic"),
    ]

    engine = OMREngine()
    all_passed = True
    summary_results = []

    print("\n" + "#" * 70)
    print("  MICGAME-3 BUNDLED OMR SUITE VERIFICATION")
    print(f"  Target Accuracy Requirement: >= {min_accuracy * 100.0:.1f}%")
    print("#" * 70 + "\n")

    for title, piece_key in test_pieces:
        # Check assets/test_pieces first, then assets/scores & assets/charts
        score_path = os.path.join(assets_dir, "test_pieces", piece_key, "score.png")
        gt_path = os.path.join(assets_dir, "test_pieces", piece_key, "ground_truth.json")

        if not os.path.exists(score_path):
            score_path = os.path.join(assets_dir, "scores", f"{piece_key}.png")
        if not os.path.exists(gt_path):
            gt_path = os.path.join(assets_dir, "charts", f"{piece_key}.json")

        passed, metrics = run_single_evaluation(
            score_path=score_path,
            ground_truth_path=gt_path,
            min_accuracy=min_accuracy,
            engine=engine,
        )

        summary_results.append((title, passed, metrics))
        if not passed:
            all_passed = False

    print("\n" + "=" * 70)
    print("OMR BUNDLED SUITE SUMMARY")
    print("-" * 70)
    for title, passed, metrics in summary_results:
        acc = metrics.get("accuracy", 0.0) * 100.0
        tp = metrics.get("tp", 0)
        gt = metrics.get("gt_count", 0)
        status = "PASSED [OK]" if passed else "FAILED [X]"
        print(f"  {title:<50} : {acc:5.1f}% ({tp}/{gt} notes) -> {status}")

    print("-" * 70)
    print(f"OVERALL OMR HARNESS RESULT: {'ALL PASS [OK]' if all_passed else 'FAILURES DETECTED [X]'}")
    print("=" * 70 + "\n")

    return all_passed


def main():
    parser = argparse.ArgumentParser(
        description="Automated CLI OMR Verification Harness for MicGame-3"
    )
    parser.add_argument("--score", type=str, default=None, help="Path to score image to evaluate")
    parser.add_argument("--ground-truth", type=str, default=None, help="Path to ground truth chart JSON")
    parser.add_argument(
        "--min-accuracy",
        type=float,
        default=0.85,
        help="Minimum recognition accuracy required (default: 0.85)",
    )
    args = parser.parse_args()

    if args.score:
        if not args.ground_truth:
            # Attempt to locate matching ground truth
            base = os.path.splitext(args.score)[0]
            candidate = f"{base}.json"
            if os.path.exists(candidate):
                args.ground_truth = candidate
            else:
                dirname = os.path.dirname(args.score)
                candidate2 = os.path.join(dirname, "ground_truth.json")
                if os.path.exists(candidate2):
                    args.ground_truth = candidate2
                else:
                    print("ERROR: --ground-truth argument is required when specifying --score.")
                    sys.exit(1)

        passed, _ = run_single_evaluation(
            score_path=args.score,
            ground_truth_path=args.ground_truth,
            min_accuracy=args.min_accuracy,
        )
        sys.exit(0 if passed else 1)
    else:
        passed = run_all_bundled_evaluations(min_accuracy=args.min_accuracy)
        sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
