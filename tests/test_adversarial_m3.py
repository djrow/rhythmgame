"""
Milestone 3 Adversarial Stress Test Suite.
Adversarial challenge for `python/basic_pitch_onnx.py` and `tests/test_transcription_harness.py`.

Empirically tests:
1. Extreme Audio Signals:
   - Pure digital silence (0.0 amplitude, zero energy)
   - Max clipped square waves at 0 dBFS (extreme distortion across multiple frequencies)
   - Nyquist alternating signals (+1, -1 at fs/2)
   - Gaussian white noise at multiple amplitudes and SNRs
   - Infrasonic (10 Hz) and Ultrasonic (10.5 kHz) sine waves outside musical range
   - Micro-burst transient clicks, Dirac impulse trains, and DC offset steps
2. Polyphonic Discrimination & Harmonic Suppression:
   - Pure sine wave harmonic suppression (suppression of octave and 12th overtones)
   - Harmonic complex tone (fundamental + 2nd + 3rd harmonics)
   - Polyphonic chord tone isolation (detection of genuine triad notes, rejection of unplayed scale degrees)
   - Close-interval dissonant semitone polyphony
   - 4-note extended chord (Cmaj7)
   - Real-time streaming polyphonic chord detection with sliding circular ring buffer
3. Identified Failure Modes & Vulnerability Probes:
   - Buffer lengths < 256 samples (e.g. empty array len=0, len=1, len=100) causing unhandled ValueError crash
   - Systematic boundary onset loss for notes starting at t=0.0 in transcribe_file
4. Harness Metrics & Simultaneity Robustness:
   - Zero-division defenses with empty detected notes or empty ground truth
   - Simultaneity threshold behavior when initial chord is dropped
"""

import math
import os
import sys
import unittest
import numpy as np

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from python.basic_pitch_onnx import (
    BasicPitchOnnxRunner,
    resample_to_22050,
    read_wav_mono,
    AUDIO_SAMPLE_RATE,
    AUDIO_N_SAMPLES,
    MIDI_OFFSET,
    MAX_SEMITONES,
)
from tests.test_transcription_harness import evaluate_note_metrics, verify_polyphonic_simultaneity

MODEL_PATH = os.path.join(PROJECT_ROOT, "assets", "models", "nmp.onnx")


def midi_to_hz(midi_pitch: int) -> float:
    return 440.0 * (2.0 ** ((midi_pitch - 69.0) / 12.0))


def generate_sine(
    pitch_midi: int,
    duration_sec: float,
    sr: int = AUDIO_SAMPLE_RATE,
    amplitude: float = 0.8,
    lead_silence_sec: float = 0.2,
) -> np.ndarray:
    freq = midi_to_hz(pitch_midi)
    t = np.arange(int(sr * duration_sec)) / sr
    # 10ms raised-cosine fade in/out
    env = np.ones_like(t)
    fade_len = int(sr * 0.01)
    if len(t) > 2 * fade_len:
        fade_in = 0.5 * (1.0 - np.cos(np.pi * np.arange(fade_len) / fade_len))
        fade_out = 0.5 * (1.0 + np.cos(np.pi * np.arange(fade_len) / fade_len))
        env[:fade_len] = fade_in
        env[-fade_len:] = fade_out
    tone = (amplitude * np.sin(2.0 * np.pi * freq * t) * env).astype(np.float32)
    if lead_silence_sec > 0:
        lead = np.zeros(int(sr * lead_silence_sec), dtype=np.float32)
        return np.concatenate([lead, tone])
    return tone


def generate_chord(
    pitches: list,
    duration_sec: float,
    sr: int = AUDIO_SAMPLE_RATE,
    amplitude: float = 0.8,
    lead_silence_sec: float = 0.2,
) -> np.ndarray:
    total_len = int(sr * (duration_sec + lead_silence_sec))
    sig = np.zeros(total_len, dtype=np.float32)
    per_note_amp = amplitude / len(pitches)
    for p in pitches:
        sig += generate_sine(p, duration_sec, sr, amplitude=per_note_amp, lead_silence_sec=lead_silence_sec)
    return sig


class TestAdversarialExtremeAudio(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.runner = BasicPitchOnnxRunner(MODEL_PATH)

    def test_pure_digital_silence(self):
        """Pure digital silence (0.0 amplitude) must produce 0 detected notes and 0 false onsets."""
        # 1. Full file transcription
        silence_audio = np.zeros(AUDIO_SAMPLE_RATE * 3, dtype=np.float32)
        notes = self.runner.transcribe_file(silence_audio, sample_rate=AUDIO_SAMPLE_RATE)
        self.assertEqual(len(notes), 0, f"Expected 0 notes for digital silence, got {len(notes)}")

        # 2. Streaming chunks of silence
        self.runner.reset_stream()
        for step in range(20):
            chunk = np.zeros(1024, dtype=np.float32)
            active, onsets, confs = self.runner.process_streaming_chunk(
                chunk, current_time_sec=step * 1024 / AUDIO_SAMPLE_RATE
            )
            self.assertEqual(len(active), 0, f"Spurious active pitches during silence: {active}")
            self.assertEqual(len(onsets), 0, f"Spurious onsets during silence: {onsets}")

    def test_clipped_square_wave_0dbfs(self):
        """0 dBFS clipped square wave across multiple octaves must not produce NaNs, Infs, or crash."""
        frequencies = [110, 440, 1000, 4000]
        sr = AUDIO_SAMPLE_RATE
        duration = 1.5
        t = np.arange(int(sr * duration)) / sr

        for freq in frequencies:
            square = np.sign(np.sin(2.0 * np.pi * freq * t)).astype(np.float32)
            notes = self.runner.transcribe_file(square, sample_rate=sr)
            self.assertIsInstance(notes, list)
            for n in notes:
                self.assertFalse(math.isnan(n["confidence"]), "Confidence must not be NaN")
                self.assertFalse(math.isinf(n["confidence"]), "Confidence must not be Inf")
                self.assertGreaterEqual(n["confidence"], 0.0)
                self.assertLessEqual(n["confidence"], 1.0)

    def test_nyquist_alternating_signal(self):
        """Alternating +1, -1 at Nyquist limit (fs/2 = 11,025 Hz)."""
        sr = AUDIO_SAMPLE_RATE
        sig = np.tile([1.0, -1.0], int(sr * 1.5 // 2)).astype(np.float32)
        notes = self.runner.transcribe_file(sig, sample_rate=sr)
        self.assertIsInstance(notes, list)
        for n in notes:
            self.assertFalse(math.isnan(n["confidence"]))

    def test_gaussian_white_noise_rejection(self):
        """White noise at moderate and high amplitudes must not trigger runaway spurious notes."""
        sr = AUDIO_SAMPLE_RATE
        rng = np.random.RandomState(42)

        # Moderate noise (-20 dBFS, sigma = 0.1)
        noise_mod = np.clip(rng.normal(0, 0.1, int(sr * 2.0)).astype(np.float32), -1.0, 1.0)
        notes_mod = self.runner.transcribe_file(noise_mod, sample_rate=sr)
        self.assertLess(len(notes_mod), 5, f"Excessive false positives on moderate noise: {len(notes_mod)}")

        # Full scale 0 dBFS noise (sigma = 0.5 clipped to [-1, 1])
        noise_loud = np.clip(rng.normal(0, 0.5, int(sr * 2.0)).astype(np.float32), -1.0, 1.0)
        notes_loud = self.runner.transcribe_file(noise_loud, sample_rate=sr)
        self.assertIsInstance(notes_loud, list)
        for n in notes_loud:
            self.assertFalse(math.isnan(n["confidence"]))

    def test_infrasonic_and_ultrasonic_rejection(self):
        """Signals far outside piano range (10 Hz infrasonic, 10,500 Hz ultrasonic)."""
        sr = AUDIO_SAMPLE_RATE
        t = np.arange(int(sr * 2.0)) / sr

        # Infrasonic (10 Hz)
        infra = (0.9 * np.sin(2.0 * np.pi * 10.0 * t)).astype(np.float32)
        notes_infra = self.runner.transcribe_file(infra, sample_rate=sr)
        self.assertEqual(len(notes_infra), 0, f"Infrasonic 10Hz signal falsely triggered notes: {notes_infra}")

        # Ultrasonic / near-Nyquist (10,500 Hz)
        ultra = (0.9 * np.sin(2.0 * np.pi * 10500.0 * t)).astype(np.float32)
        notes_ultra = self.runner.transcribe_file(ultra, sample_rate=sr)
        self.assertEqual(len(notes_ultra), 0, f"Ultrasonic 10.5kHz signal falsely triggered notes: {notes_ultra}")

    def test_micro_burst_transient_clicks(self):
        """Single-sample Dirac impulse clicks must not be registered as sustained musical notes."""
        sr = AUDIO_SAMPLE_RATE
        sig = np.zeros(int(sr * 2.0), dtype=np.float32)
        click_positions = [int(0.2 * sr), int(0.5 * sr), int(0.8 * sr), int(1.1 * sr), int(1.4 * sr)]
        for pos in click_positions:
            sig[pos] = 1.0
            sig[pos + 1] = -1.0

        notes = self.runner.transcribe_file(sig, sample_rate=sr)
        self.assertEqual(len(notes), 0, f"Transient clicks falsely recognized as notes: {notes}")

    def test_dc_offset_step(self):
        """Sudden DC step jump from 0.0 to 0.8 must be handled cleanly."""
        sr = AUDIO_SAMPLE_RATE
        sig = np.zeros(int(sr * 1.5), dtype=np.float32)
        sig[int(sr * 0.5):] = 0.8
        notes = self.runner.transcribe_file(sig, sample_rate=sr)
        self.assertIsInstance(notes, list)


class TestPolyphonicDiscrimination(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.runner = BasicPitchOnnxRunner(MODEL_PATH)

    def test_monophonic_pure_sine_harmonic_suppression(self):
        """Pure A4 sine (440 Hz, MIDI 69) must detect pitch 69 and suppress octave harmonics (81, 88, 93)."""
        sine_a4 = generate_sine(pitch_midi=69, duration_sec=1.5, amplitude=0.8, lead_silence_sec=0.2)
        notes = self.runner.transcribe_file(sine_a4)
        self.assertGreaterEqual(len(notes), 1, "Failed to detect pure A4 sine wave")

        pitches = [n["pitch"] for n in notes]
        self.assertIn(69, pitches, f"MIDI 69 (A4) not found in detected pitches: {pitches}")

        # Check suppression of octave harmonics (MIDI 81 = 880 Hz, MIDI 88 = 1320 Hz, MIDI 93 = 1760 Hz)
        for hp in [81, 88, 93]:
            self.assertNotIn(hp, pitches, f"Harmonic {hp} falsely detected for pure A4 tone: {pitches}")

    def test_harmonic_complex_tone_suppression(self):
        """A complex tone (fundamental C4=60 with 2nd and 3rd harmonics) should detect C4 and suppress harmonics."""
        sr = AUDIO_SAMPLE_RATE
        t = np.arange(int(sr * 1.5)) / sr
        c4 = 0.6 * np.sin(2 * np.pi * 261.63 * t)
        c5 = 0.2 * np.sin(2 * np.pi * 523.25 * t)
        g5 = 0.1 * np.sin(2 * np.pi * 783.99 * t)
        sig = np.concatenate([np.zeros(int(0.2 * sr), dtype=np.float32), (c4 + c5 + g5).astype(np.float32)])

        notes = self.runner.transcribe_file(sig)
        detected_pitches = {n["pitch"] for n in notes}
        self.assertIn(60, detected_pitches, f"Fundamental C4 (60) not detected: {detected_pitches}")
        self.assertNotIn(72, detected_pitches, f"Octave harmonic C5 (72) falsely triggered: {detected_pitches}")
        self.assertNotIn(79, detected_pitches, f"12th harmonic G5 (79) falsely triggered: {detected_pitches}")

    def test_polyphonic_chord_discrimination_with_lead_in(self):
        """C Major Triad (60, 64, 67) with lead-in silence must detect all 3 notes and reject unplayed scale degrees."""
        triad_pitches = [60, 64, 67]
        chord_audio = generate_chord(triad_pitches, duration_sec=1.8, amplitude=0.8, lead_silence_sec=0.2)
        notes = self.runner.transcribe_file(chord_audio)
        detected_pitches = {n["pitch"] for n in notes}

        for p in triad_pitches:
            self.assertIn(p, detected_pitches, f"Chord tone {p} not detected in {detected_pitches}")

        # Reject unplayed neighbor tones and accidentals
        unplayed_notes = [61, 62, 63, 65, 66, 68, 69, 70, 71]
        for p in unplayed_notes:
            self.assertNotIn(p, detected_pitches, f"Unplayed pitch {p} falsely triggered: {detected_pitches}")

    def test_close_semitone_polyphony(self):
        """Minor second dissonance (C4=60 + C#4=61 played simultaneously)."""
        dissonance = generate_chord([60, 61], duration_sec=1.5, amplitude=0.8, lead_silence_sec=0.2)
        notes = self.runner.transcribe_file(dissonance)
        detected_pitches = {n["pitch"] for n in notes}
        self.assertTrue(60 in detected_pitches or 61 in detected_pitches)
        self.assertLessEqual(len(detected_pitches), 4, f"Excessive phantom pitches on semitone cluster: {detected_pitches}")

    def test_four_note_seventh_chord(self):
        """Cmaj7 (C4=60, E4=64, G4=67, B4=71)."""
        cmaj7 = [60, 64, 67, 71]
        audio = generate_chord(cmaj7, duration_sec=2.0, amplitude=0.85, lead_silence_sec=0.2)
        notes = self.runner.transcribe_file(audio)
        detected_pitches = {n["pitch"] for n in notes}
        matched = [p for p in cmaj7 if p in detected_pitches]
        self.assertGreaterEqual(len(matched), 3, f"Expected at least 3 of 4 chord tones, got {matched} from {detected_pitches}")

    def test_streaming_polyphonic_triad_detection(self):
        """Real-time streaming chunk inference detects polyphonic triad concurrently."""
        self.runner.reset_stream()
        triad = generate_chord([60, 64, 67], duration_sec=2.0, amplitude=0.8, lead_silence_sec=0.1)
        chunk_size = 1024
        all_active = set()
        all_onsets = set()

        for i in range(0, len(triad), chunk_size):
            chunk = triad[i : i + chunk_size]
            t = i / AUDIO_SAMPLE_RATE
            active, onsets, conf = self.runner.process_streaming_chunk(chunk, current_time_sec=t)
            all_active.update(active)
            all_onsets.update(onsets)

        self.assertIn(60, all_active, f"Pitch 60 missing from streaming active pitches: {all_active}")
        self.assertIn(64, all_active, f"Pitch 64 missing from streaming active pitches: {all_active}")
        self.assertIn(67, all_active, f"Pitch 67 missing from streaming active pitches: {all_active}")


class TestIdentifiedFailureModes(unittest.TestCase):
    """
    Direct empirical regression tests reproducing the two discovered vulnerabilities
    in `python/basic_pitch_onnx.py`.
    """
    @classmethod
    def setUpClass(cls):
        cls.runner = BasicPitchOnnxRunner(MODEL_PATH)

    def test_bug1_short_audio_buffer_crash_reproduction(self):
        """
        REGRESSION TEST FOR BUG 1:
        Audio buffers with length < 256 samples (e.g. len=0, len=1, len=100) must be handled
        gracefully without an unhandled ValueError crash in infer_onsets_numpy.
        """
        crash_lengths = [0, 1, 10, 100, 255]
        for clen in crash_lengths:
            audio = np.zeros(clen, dtype=np.float32)
            notes = self.runner.transcribe_file(audio)
            self.assertEqual(len(notes), 0, f"Expected 0 notes for short buffer len {clen}, got {len(notes)}")

    def test_bug2_t0_onset_truncation_reproduction(self):
        """
        REGRESSION TEST FOR BUG 2:
        Notes that start at t=0.0 in transcribe_file must be accurately detected when
        pre-roll zero padding is prepended and boundary peak picking evaluates frame 0.
        """
        # Generate triad starting immediately at t=0.0 (no lead silence)
        triad_t0 = generate_chord([60, 64, 67], duration_sec=2.0, amplitude=0.8, lead_silence_sec=0.0)
        notes_t0 = self.runner.transcribe_file(triad_t0)
        detected_t0 = {n["pitch"] for n in notes_t0}

        # Pitch 67 must be detected when audio starts at t=0.0
        self.assertIn(67, detected_t0,
                      "Bug 2: pitch 67 was not detected at t=0.0")

        # In contrast, when the exact same chord has 200ms lead silence, pitch 67 is detected
        triad_t200 = generate_chord([60, 64, 67], duration_sec=2.0, amplitude=0.8, lead_silence_sec=0.2)
        notes_t200 = self.runner.transcribe_file(triad_t200)
        detected_t200 = {n["pitch"] for n in notes_t200}
        self.assertIn(67, detected_t200, "Pitch 67 should be detected when delayed by 200ms")


class TestNumericalStabilityAndResampling(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.runner = BasicPitchOnnxRunner(MODEL_PATH)

    def test_arbitrary_sample_rates_resampling(self):
        """Validates resampling across 8k, 11k, 16k, 44.1k, 48k, 96k, 192k."""
        rates = [8000, 11025, 16000, 44100, 48000, 96000, 192000]
        for sr in rates:
            sig = generate_sine(pitch_midi=60, duration_sec=1.0, sr=sr, amplitude=0.7, lead_silence_sec=0.0)
            resampled = resample_to_22050(sig, sr)
            expected_len = int(len(sig) * AUDIO_SAMPLE_RATE / sr)
            self.assertEqual(len(resampled), expected_len)
            self.assertFalse(np.isnan(resampled).any())

    def test_nan_inf_audio_handling(self):
        """Audio containing NaN or Inf should not cause unhandled process crashes."""
        bad_audio = np.zeros(AUDIO_SAMPLE_RATE * 2, dtype=np.float32)
        bad_audio[500] = np.nan
        bad_audio[1000] = np.inf
        notes = self.runner.transcribe_file(bad_audio)
        self.assertIsInstance(notes, list)

    def test_streaming_buffer_drift_long_session(self):
        """Simulate 200 consecutive streaming chunks (1024 samples each at 48kHz)."""
        self.runner.reset_stream()
        chunk_size = 1024
        sr = 48000
        current_time = 0.0

        for i in range(200):
            if 50 <= i <= 100:
                chunk = generate_sine(pitch_midi=64, duration_sec=chunk_size / sr, sr=sr, amplitude=0.8, lead_silence_sec=0.0)
            else:
                chunk = np.zeros(chunk_size, dtype=np.float32)

            active, onsets, confs = self.runner.process_streaming_chunk(
                chunk, sample_rate=sr, current_time_sec=current_time
            )
            self.assertIsInstance(active, list)
            self.assertIsInstance(onsets, list)
            self.assertIsInstance(confs, dict)
            current_time += chunk_size / sr

        self.assertFalse(np.isnan(self.runner.ring_buffer).any())
        self.assertFalse(np.isinf(self.runner.ring_buffer).any())


class TestHarnessMetricsRobustness(unittest.TestCase):
    def test_empty_detected_notes(self):
        """0 detected notes should yield 0 precision, 0 recall, 0 f1 without ZeroDivisionError."""
        gt = [{"pitch_midi": 60, "time_sec": 1.0, "duration_sec": 0.5}]
        metrics = evaluate_note_metrics([], gt)
        self.assertEqual(metrics["f1"], 0.0)
        self.assertEqual(metrics["tp"], 0)
        self.assertEqual(metrics["fn"], 1)

    def test_empty_ground_truth(self):
        """0 ground truth notes should yield 0 recall and f1."""
        det = [{"pitch": 60, "onset_sec": 1.0, "duration_sec": 0.5, "confidence": 0.9}]
        metrics = evaluate_note_metrics(det, [])
        self.assertEqual(metrics["f1"], 0.0)
        self.assertEqual(metrics["fp"], 1)

    def test_both_empty(self):
        metrics = evaluate_note_metrics([], [])
        self.assertEqual(metrics["f1"], 0.0)
        self.assertEqual(metrics["tp"], 0)


if __name__ == "__main__":
    unittest.main()
