import os
import sys
import cv2
import numpy as np

# Add project root to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..")))
from python.omr_engine import OMREngine

def test_python_omr_perturbation():
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
    score_path = os.path.join(base_dir, "assets", "test_pieces", "piece_1_monophonic", "score.png")
    assert os.path.exists(score_path), f"Score path not found: {score_path}"

    engine = OMREngine()
    orig_chart = engine.process_score(score_path)
    orig_count = len(orig_chart["notes"])
    print(f"Original notes detected: {orig_count}")
    assert orig_count == 15, f"Expected 15 original notes, got {orig_count}"

    # Load image and draw a synthetic notehead at X=700, Y=360 (B4, MIDI 71)
    img = cv2.imread(score_path)
    # Notehead ellipse with axes (10, 7)
    cv2.ellipse(img, (700, 360), (10, 7), -20, 0, 360, (0, 0, 0), -1)
    # Note stem
    cv2.line(img, (709, 360), (709, 290), (0, 0, 0), 2)

    perturbed_path = os.path.join(os.path.dirname(__file__), "perturbed_score.png")
    cv2.imwrite(perturbed_path, img)

    pert_chart = engine.process_score(perturbed_path)
    pert_count = len(pert_chart["notes"])
    print(f"Perturbed notes detected: {pert_count}")

    # Check that new note was detected
    new_notes = [n for n in pert_chart["notes"] if n["pitch_midi"] == 71]
    print(f"Detected B4 notes: {len(new_notes)}")

    assert pert_count == orig_count + 1, f"Expected {orig_count + 1} notes, got {pert_count}"
    assert len(new_notes) == 1, f"Expected 1 B4 note, got {len(new_notes)}"
    print(f"Newly detected note details: {new_notes[0]}")

    # Clean up temporary test image
    if os.path.exists(perturbed_path):
        os.remove(perturbed_path)
    print("Python OMREngine adversarial perturbation test PASSED cleanly!")

if __name__ == "__main__":
    test_python_omr_perturbation()
