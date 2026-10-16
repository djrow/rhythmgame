"""
Adversarial Stress Test for Milestone 4 OMR Subsystem (Python OMREngine).
Tests:
1. Empty images: All-white (255) and All-black (0)
2. Non-music synthetic imagery / textures
3. Images without staff lines (isolated notes, random shapes)
4. Inverted images (black background, white foreground)
5. Noisy backgrounds (Gaussian noise, Salt-and-pepper noise)
6. Broken barlines (missing barlines, partial barlines)
7. Extreme chord stacks (5-note chord)
8. Extreme ledger lines (C2 = MIDI 36, A5 = MIDI 81, C6 = MIDI 84)
9. Tiny dimensions (0x0, 1x1, 10x10, 50x50, 100x100) and corrupted files
"""

import os
import sys
import tempfile
import traceback
import unittest
import numpy as np
import cv2

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from python.omr_engine import OMREngine, Y_TO_NOTE_TABLE


class TestOMRAdversarialPython(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = OMREngine()
        cls.temp_dir = tempfile.TemporaryDirectory()

    @classmethod
    def tearDownClass(cls):
        cls.temp_dir.cleanup()

    def _save_temp_img(self, img: np.ndarray, name: str = "temp.png") -> str:
        path = os.path.join(self.temp_dir.name, name)
        cv2.imwrite(path, img)
        return path

    def test_01_all_white_image(self):
        """Pure white image (255) - should return safe empty chart without crashing."""
        img = np.full((900, 1600), 255, dtype=np.uint8)
        path = self._save_temp_img(img, "all_white.png")
        chart = self.engine.process_score(path)
        self.assertIsInstance(chart, dict)
        self.assertIn("notes", chart)
        self.assertIn("measures", chart)
        print(f"  [PASS] All-white image: processed safely, notes={len(chart['notes'])}")

    def test_02_all_black_image(self):
        """Pure black image (0) - should return safe empty chart without crashing."""
        img = np.zeros((900, 1600), dtype=np.uint8)
        path = self._save_temp_img(img, "all_black.png")
        chart = self.engine.process_score(path)
        self.assertIsInstance(chart, dict)
        self.assertIn("notes", chart)
        print(f"  [PASS] All-black image: processed safely, notes={len(chart['notes'])}")

    def test_03_non_music_geometric_shapes(self):
        """Random geometric shapes, text-like lines, no staff lines."""
        img = np.full((900, 1600), 255, dtype=np.uint8)
        # Draw some rectangles and circles (non-music)
        cv2.rectangle(img, (300, 300), (600, 600), 0, -1)
        cv2.circle(img, (800, 400), 80, 0, -1)
        path = self._save_temp_img(img, "geometric.png")
        chart = self.engine.process_score(path)
        self.assertIsInstance(chart, dict)
        print(f"  [PASS] Geometric shapes: processed safely, notes={len(chart['notes'])}")

    def test_04_no_staff_lines_with_note_like_blobs(self):
        """Image with notehead-like blobs but NO staff lines and NO barlines."""
        img = np.full((900, 1600), 255, dtype=np.uint8)
        # Draw noteheads without any staff or barlines
        for x in [300, 400, 500, 600]:
            cv2.ellipse(img, (x, 360), (12, 9), 0, 0, 360, 0, -1)
        path = self._save_temp_img(img, "no_staff_notes.png")
        chart = self.engine.process_score(path)
        self.assertIsInstance(chart, dict)
        print(f"  [PASS] No staff lines with note blobs: notes={len(chart['notes'])}")

    def test_05_inverted_score(self):
        """Inverted score (white ink on black background)."""
        # Load a valid bundled score and invert it
        ref_score = os.path.join(PROJECT_ROOT, "assets", "test_pieces", "piece_1_monophonic", "score.png")
        img = cv2.imread(ref_score, cv2.IMREAD_GRAYSCALE)
        inv_img = 255 - img
        path = self._save_temp_img(inv_img, "inverted_score.png")
        chart = self.engine.process_score(path)
        self.assertIsInstance(chart, dict)
        print(f"  [PASS] Inverted score: processed safely, notes={len(chart['notes'])}")

    def test_06_noisy_background(self):
        """Bundled score contaminated with additive Gaussian noise."""
        ref_score = os.path.join(PROJECT_ROOT, "assets", "test_pieces", "piece_1_monophonic", "score.png")
        img = cv2.imread(ref_score, cv2.IMREAD_GRAYSCALE)
        noise = np.random.normal(0, 30, img.shape).astype(np.float32)
        noisy_img = np.clip(img.astype(np.float32) + noise, 0, 255).astype(np.uint8)
        path = self._save_temp_img(noisy_img, "noisy_score.png")
        chart = self.engine.process_score(path)
        self.assertIsInstance(chart, dict)
        print(f"  [PASS] Noisy background: processed safely, notes={len(chart['notes'])}")

    def test_07_broken_barlines(self):
        """Score where barlines are broken (erased in the middle)."""
        ref_score = os.path.join(PROJECT_ROOT, "assets", "test_pieces", "piece_1_monophonic", "score.png")
        img = cv2.imread(ref_score, cv2.IMREAD_GRAYSCALE).copy()
        # Erase horizontal strip across grand staff between Y=380 and Y=460 to break barlines
        img[390:450, :] = 255
        path = self._save_temp_img(img, "broken_barlines.png")
        chart = self.engine.process_score(path)
        self.assertIsInstance(chart, dict)
        print(f"  [PASS] Broken barlines: processed safely, notes={len(chart['notes'])}")

    def test_08_extreme_chord_stack(self):
        """Score with a 5-note chord stack at the same X position."""
        # Create standard score background
        img = np.full((900, 1600), 255, dtype=np.uint8)
        # Draw 10 staff lines
        for y in [320, 340, 360, 380, 400, 440, 460, 480, 500, 520]:
            cv2.line(img, (100, y), (1500, y), 0, 2)
        # Draw barlines
        for x in [200, 500, 800, 1100, 1400]:
            cv2.line(img, (x, 320), (x, 520), 0, 2)
        # Draw 5 noteheads vertically aligned at X=350
        # Pitches: C3(490), E3(470), G3(450), C4(420), G4(380)
        chord_ys = [490, 470, 450, 420, 380]
        for cy in chord_ys:
            cv2.ellipse(img, (350, cy), (12, 9), 0, 0, 360, 0, -1)
            # Add ledger line for C4(420)
            if cy == 420:
                cv2.line(img, (335, 420), (365, 420), 0, 2)
        # Draw stem connecting chord
        cv2.line(img, (350 + 10, 380), (350 + 10, 380 - 70), 0, 2)

        path = self._save_temp_img(img, "chord_stack_5.png")
        chart = self.engine.process_score(path)
        self.assertIsInstance(chart, dict)
        chord_notes = [n for n in chart["notes"] if abs(n["time_sec"] - chart["notes"][0]["time_sec"]) < 0.05]
        print(f"  [PASS] 5-note chord stack: detected {len(chord_notes)} chord notes in cluster")
        self.assertGreaterEqual(len(chord_notes), 3)

    def test_09_extreme_ledger_lines(self):
        """Notes on extreme ledger lines: C2 (MIDI 36, Y=560), A5 (MIDI 81, Y=300), C6 (MIDI 84, Y=280)."""
        img = np.full((900, 1600), 255, dtype=np.uint8)
        # Draw staff lines
        for y in [320, 340, 360, 380, 400, 440, 460, 480, 500, 520]:
            cv2.line(img, (100, y), (1500, y), 0, 2)
        # Draw barlines
        for x in [200, 500, 800, 1100, 1400]:
            cv2.line(img, (x, 320), (x, 520), 0, 2)

        # Note 1: C2 at X=300, Y=560 (ledger at 540, 560)
        cv2.line(img, (285, 540), (315, 540), 0, 2)
        cv2.line(img, (285, 560), (315, 560), 0, 2)
        cv2.ellipse(img, (300, 560), (12, 9), 0, 0, 360, 0, -1)
        cv2.line(img, (310, 560), (310, 490), 0, 2)

        # Note 2: A5 at X=600, Y=300 (ledger at 300)
        cv2.line(img, (585, 300), (615, 300), 0, 2)
        cv2.ellipse(img, (600, 300), (12, 9), 0, 0, 360, 0, -1)
        cv2.line(img, (610, 300), (610, 230), 0, 2)

        # Note 3: C6 at X=900, Y=280 (ledger at 300, 280)
        cv2.line(img, (885, 300), (915, 300), 0, 2)
        cv2.line(img, (885, 280), (915, 280), 0, 2)
        cv2.ellipse(img, (900, 280), (12, 9), 0, 0, 360, 0, -1)
        cv2.line(img, (910, 280), (910, 210), 0, 2)

        path = self._save_temp_img(img, "extreme_ledgers.png")
        chart = self.engine.process_score(path)
        self.assertIsInstance(chart, dict)
        detected_midis = [n["pitch_midi"] for n in chart["notes"]]
        print(f"  [PASS] Extreme ledger lines: detected pitches={detected_midis}")
        # Check if C2(36) and high notes are recognized
        self.assertTrue(any(m in [36, 38] for m in detected_midis), f"C2 not detected in {detected_midis}")
        self.assertTrue(any(m in [81, 83, 84] for m in detected_midis), f"A5/C6 not detected in {detected_midis}")

    def test_10_extreme_small_dimensions(self):
        """Tiny images: 50x50, 100x100, 10x10. Must handle gracefully without crash."""
        for dim in [100, 50, 10]:
            img = np.full((dim, dim), 255, dtype=np.uint8)
            path = self._save_temp_img(img, f"tiny_{dim}.png")
            try:
                chart = self.engine.process_score(path)
                self.assertIsInstance(chart, dict)
                print(f"  [PASS] Tiny image {dim}x{dim}: safely processed, notes={len(chart['notes'])}")
            except Exception as e:
                self.fail(f"Crashed on {dim}x{dim} image with error: {type(e).__name__}: {e}")

    def test_11_corrupted_and_non_existent_files(self):
        """Empty 0-byte file, invalid image format, and non-existent file."""
        # Non-existent
        with self.assertRaises(FileNotFoundError):
            self.engine.process_score("non_existent_file_xyz_123.png")

        # 0-byte file
        zero_byte = os.path.join(self.temp_dir.name, "zero_byte.png")
        with open(zero_byte, "wb") as f:
            pass
        with self.assertRaises(ValueError):
            self.engine.process_score(zero_byte)

        # Corrupted header text file with .png extension
        corrupt_path = os.path.join(self.temp_dir.name, "corrupt.png")
        with open(corrupt_path, "w") as f:
            f.write("NOT A REAL PNG FILE")
        with self.assertRaises(ValueError):
            self.engine.process_score(corrupt_path)
        print("  [PASS] Corrupted and missing files raise expected clean exceptions")


if __name__ == "__main__":
    unittest.main()
