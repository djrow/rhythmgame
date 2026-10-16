"""
E2E Test Utilities for MicGame-3.
Authoritative mathematical models, reference schemas, audio synthesis,
and configuration verification helpers.
"""

import math
import json
import os
import re
import struct
import wave
import numpy as np


class DiatonicMath:
    """Mathematical coordinate system for Grand Staff Right-to-Left Highway."""
    
    Y_CENTER = 360.0        # Y coordinate of Middle C (C4, step 28)
    LINE_SPACING = 18.0     # Distance between adjacent staff lines
    STEP_Y = 9.0            # Distance per diatonic step (half line spacing)
    HIT_LINE_X = 160.0      # Receptor target line X coordinate
    
    # Diatonic offsets for pitch classes C=0, D=1, E=2, F=3, G=4, A=5, B=6
    # Accidentals map to the natural note diatonic offset
    SEMITONE_TO_DIATONIC = {
        0: 0,   # C
        1: 0,   # C# / Db
        2: 1,   # D
        3: 1,   # D# / Eb
        4: 2,   # E
        5: 3,   # F
        6: 3,   # F# / Gb
        7: 4,   # G
        8: 4,   # G# / Ab
        9: 5,   # A
        10: 5,  # A# / Bb
        11: 6   # B
    }
    
    SEMITONE_IS_ACCIDENTAL = {
        0: False, 1: True, 2: False, 3: True, 4: False, 5: False,
        6: True, 7: False, 8: True, 9: False, 10: True, 11: False
    }

    @staticmethod
    def midi_to_diatonic_step(midi_pitch: int) -> int:
        """Returns the absolute diatonic step for a MIDI pitch.
        Middle C (C4, MIDI 60) is step 28.
        """
        octave = (midi_pitch // 12) - 1
        semitone = midi_pitch % 12
        diatonic_offset = DiatonicMath.SEMITONE_TO_DIATONIC[semitone]
        return octave * 7 + diatonic_offset

    @staticmethod
    def is_accidental(midi_pitch: int) -> bool:
        """Returns True if the MIDI pitch is sharp/flat in C major."""
        return DiatonicMath.SEMITONE_IS_ACCIDENTAL[midi_pitch % 12]

    @staticmethod
    def midi_to_y(midi_pitch: int) -> float:
        """Returns the Y pixel coordinate for a MIDI pitch centered at Y=360."""
        step = DiatonicMath.midi_to_diatonic_step(midi_pitch)
        # Higher pitch -> smaller Y (upwards on screen)
        return DiatonicMath.Y_CENTER - (step - 28) * DiatonicMath.STEP_Y

    @staticmethod
    def get_ledger_lines(midi_pitch: int) -> list[float]:
        """Calculates Y positions of ledger lines required for a pitch."""
        step = DiatonicMath.midi_to_diatonic_step(midi_pitch)
        lines = []
        if step == 28:
            # Middle C ledger line
            lines.append(DiatonicMath.Y_CENTER)
        elif step >= 40:
            # Notes above Treble staff (top line F5 is step 38, Y=270)
            # First ledger above is A5 (step 40, Y=252)
            for s in range(40, step + 1, 2):
                lines.append(DiatonicMath.Y_CENTER - (s - 28) * DiatonicMath.STEP_Y)
        elif step <= 16:
            # Notes below Bass staff (bottom line G2 is step 18, Y=450)
            # First ledger below is E2 (step 16, Y=468)
            for s in range(16, step - 1, -2):
                lines.append(DiatonicMath.Y_CENTER - (s - 28) * DiatonicMath.STEP_Y)
        return lines


class HighwayMath:
    """Calculations for Right-to-Left note scrolling and timing."""
    
    DEFAULT_SPEED = 240.0   # Pixels per second

    @staticmethod
    def note_x_position(note_time_sec: float, playhead_time_sec: float,
                        scroll_speed: float = DEFAULT_SPEED,
                        hit_line_x: float = DiatonicMath.HIT_LINE_X) -> float:
        """Calculates note X coordinate relative to hit line."""
        time_to_hit = note_time_sec - playhead_time_sec
        return hit_line_x + (time_to_hit * scroll_speed)

    @staticmethod
    def is_in_hit_window(note_time_sec: float, playhead_time_sec: float,
                         window_sec: float = 0.100) -> bool:
        """Determines if the note is within the hit evaluation window."""
        return abs(note_time_sec - playhead_time_sec) <= window_sec


class ScoringEngine:
    """Reference implementation of timing windows, combo, and scoring."""
    
    PERFECT_WINDOW = 0.050   # +/- 50ms
    GOOD_WINDOW = 0.100      # +/- 100ms
    
    PERFECT_SCORE = 1000
    GOOD_SCORE = 500
    MISS_SCORE = 0

    def __init__(self):
        self.score = 0
        self.combo = 0
        self.max_combo = 0
        self.counts = {"Perfect": 0, "Good": 0, "Miss": 0}

    @property
    def multiplier(self) -> int:
        if self.combo >= 30:
            return 4
        elif self.combo >= 20:
            return 3
        elif self.combo >= 10:
            return 2
        return 1

    def evaluate_hit(self, time_delta: float) -> str:
        """Evaluates hit judgment based on signed or unsigned timing delta."""
        abs_delta = abs(time_delta)
        if abs_delta <= self.PERFECT_WINDOW:
            rating = "Perfect"
            pts = self.PERFECT_SCORE * self.multiplier
            self.combo += 1
        elif abs_delta <= self.GOOD_WINDOW:
            rating = "Good"
            pts = self.GOOD_SCORE * self.multiplier
            self.combo += 1
        else:
            rating = "Miss"
            pts = 0
            self.combo = 0
            
        self.score += pts
        self.counts[rating] += 1
        if self.combo > self.max_combo:
            self.max_combo = self.combo
        return rating


class AudioInferenceUtils:
    """Audio signal synthesis, resampling, and polyphonic pitch matching."""

    @staticmethod
    def midi_to_freq(midi_pitch: int) -> float:
        """Standard equal temperament frequency."""
        return 440.0 * (2.0 ** ((midi_pitch - 69.0) / 12.0))

    @staticmethod
    def synthesize_sine(midi_pitches: list[int], duration_sec: float,
                        sample_rate: int = 22050, amplitude: float = 0.5) -> np.ndarray:
        """Synthesizes mono audio for one or more concurrent MIDI pitches."""
        num_samples = int(duration_sec * sample_rate)
        t = np.linspace(0, duration_sec, num_samples, endpoint=False, dtype=np.float32)
        signal = np.zeros(num_samples, dtype=np.float32)
        
        for pitch in midi_pitches:
            freq = AudioInferenceUtils.midi_to_freq(pitch)
            # Add fundamental plus small second harmonic
            harmonic = (np.sin(2.0 * np.pi * freq * t) + 
                        0.25 * np.sin(4.0 * np.pi * freq * t))
            signal += harmonic.astype(np.float32)
            
        if len(midi_pitches) > 0:
            signal = (signal / len(midi_pitches)) * amplitude
        return signal

    @staticmethod
    def resample_audio(audio: np.ndarray, orig_sr: int, target_sr: int) -> np.ndarray:
        """Pure NumPy 1D linear audio resampling."""
        if orig_sr == target_sr or len(audio) == 0:
            return audio.astype(np.float32)
        target_len = int(len(audio) * target_sr / orig_sr)
        orig_indices = np.linspace(0, len(audio) - 1, len(audio))
        target_indices = np.linspace(0, len(audio) - 1, target_len)
        return np.interp(target_indices, orig_indices, audio).astype(np.float32)

    @staticmethod
    def calculate_rms(audio: np.ndarray) -> float:
        """Calculates Root-Mean-Square energy of audio buffer."""
        if len(audio) == 0:
            return 0.0
        return float(np.sqrt(np.mean(np.square(audio))))

    @staticmethod
    def apply_noise_gate(audio: np.ndarray, threshold_rms: float = 0.01) -> np.ndarray:
        """Applies hard noise gate: zeroes signal if RMS < threshold."""
        rms = AudioInferenceUtils.calculate_rms(audio)
        if rms < threshold_rms:
            return np.zeros_like(audio)
        return audio

    @staticmethod
    def match_polyphonic_clusters(detected: set[int], expected: set[int]) -> dict:
        """Computes Precision, Recall, and F1 score for polyphonic pitch sets."""
        if not detected and not expected:
            return {"precision": 1.0, "recall": 1.0, "f1": 1.0, "tp": 0, "fp": 0, "fn": 0}
        
        tp = len(detected.intersection(expected))
        fp = len(detected - expected)
        fn = len(expected - detected)
        
        precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
        recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
        f1 = (2 * precision * recall) / (precision + recall) if (precision + recall) > 0 else 0.0
        
        return {
            "precision": precision,
            "recall": recall,
            "f1": f1,
            "tp": tp,
            "fp": fp,
            "fn": fn
        }


class OMRUtils:
    """Projection profiling and sheet music image analysis."""

    @staticmethod
    def horizontal_projection(binary_image: np.ndarray) -> np.ndarray:
        """Sums dark/foreground pixels horizontally across each row."""
        return np.sum(binary_image > 0, axis=1)

    @staticmethod
    def find_staff_lines(projection: np.ndarray, min_threshold_ratio: float = 0.5) -> list[int]:
        """Detects staff line Y coordinates from horizontal projection peaks."""
        max_val = np.max(projection) if len(projection) > 0 else 0
        if max_val == 0:
            return []
        threshold = max_val * min_threshold_ratio
        peaks = []
        for y in range(1, len(projection) - 1):
            if projection[y] >= threshold and projection[y] >= projection[y - 1] and projection[y] >= projection[y + 1]:
                peaks.append(y)
        return peaks


class ConfigValidator:
    """Validators for project configuration files."""

    @staticmethod
    def parse_godot_project_file(path: str) -> dict:
        """Parses Godot project.godot key-values and sections."""
        if not os.path.exists(path):
            raise FileNotFoundError(f"File not found: {path}")
        
        sections = {}
        current_section = "root"
        sections[current_section] = {}
        
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith(";"):
                    continue
                if line.startswith("[") and line.endswith("]"):
                    current_section = line[1:-1]
                    if current_section not in sections:
                        sections[current_section] = {}
                elif "=" in line:
                    key, val = line.split("=", 1)
                    sections[current_section][key.strip()] = val.strip()
                    
        return sections

    @staticmethod
    def parse_export_presets(path: str) -> dict:
        """Parses export_presets.cfg."""
        if not os.path.exists(path):
            raise FileNotFoundError(f"File not found: {path}")
        return ConfigValidator.parse_godot_project_file(path)


class ChartValidator:
    """JSON Chart format schema validator."""
    
    REQUIRED_ROOT_KEYS = ["title", "bpm", "time_signature", "audio_file", "notes"]
    REQUIRED_NOTE_KEYS = ["pitch_name", "pitch_midi", "staff", "time_sec", "duration_sec", "measure", "beat"]

    @staticmethod
    def validate_chart_dict(chart: dict) -> tuple[bool, str]:
        for key in ChartValidator.REQUIRED_ROOT_KEYS:
            if key not in chart:
                return False, f"Missing root key: {key}"
        if not isinstance(chart["notes"], list):
            return False, "chart['notes'] must be a list"
        
        for idx, note in enumerate(chart["notes"]):
            for nkey in ChartValidator.REQUIRED_NOTE_KEYS:
                if nkey not in note:
                    return False, f"Note index {idx} missing key: {nkey}"
            if not (21 <= note["pitch_midi"] <= 108):
                return False, f"Note index {idx} pitch_midi {note['pitch_midi']} out of standard range [21, 108]"
            if note["time_sec"] < 0:
                return False, f"Note index {idx} negative time_sec: {note['time_sec']}"
            if note["duration_sec"] <= 0:
                return False, f"Note index {idx} non-positive duration_sec: {note['duration_sec']}"
                
        return True, "Valid"
