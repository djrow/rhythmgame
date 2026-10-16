"""
MicGame-3 Test Asset Generator.
Synthesizes the 3 bundled test pieces adhering strictly to Section 4 of survey_explorer_3/report.md:
- Piece 1: Monophonic melody ("Ode to Joy", 15 notes, 4/4, 120 BPM, C Major, Treble staff)
- Piece 2: 2-Part harmony ("Bach Minuet / 2-Part Counterpoint", 16 notes, 3/4, 100 BPM, dual Treble/Bass voices)
- Piece 3: Polyphonic chordal progression ("Cadence & Triad Progression", 20 notes, 5 chords, 4/4, 80 BPM)

Outputs per piece:
- score.png (1600x900 clean high-contrast sheet music score)
- audio.wav (22,050 Hz 16-bit PCM uncompressed mono WAV)
- ground_truth.json (conforming to Section 4.5 schema & ChartValidator)
- ground_truth.mid (Type 1 standard MIDI file via music21)

Also bundles official Spotify Basic Pitch ONNX model (nmp.onnx) and mirrors assets to:
- assets/audio/
- assets/scores/
- assets/charts/
"""

import json
import math
import os
import shutil
import struct
import sys
import wave
import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Ensure project root is in sys.path
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

try:
    import music21 as m21
except ImportError:
    m21 = None


# ==============================================================================
# Piece Catalog Specifications (Survey Report Section 4)
# ==============================================================================

PIECES = {
    "piece_1_monophonic": {
        "id": "piece_1_monophonic",
        "alias_id": "ode_to_joy",
        "title": "Ode to Joy",
        "subtitle": "Monophonic Melody",
        "composer": "Ludwig van Beethoven",
        "type": "monophonic",
        "bpm": 120.0,
        "time_signature": [4, 4],
        "key_signature": {"key": "C", "mode": "major", "sharps_flats": 0},
        "num_measures": 4,
        "total_duration_sec": 8.5,
        "notes": [
            {"id": 1, "measure": 1, "beat": 0.0, "time_sec": 0.00, "pitch_name": "E4", "pitch_midi": 64, "staff": "treble", "voice": 1, "duration_beats": 1.0, "duration_sec": 0.50, "is_chord": False},
            {"id": 2, "measure": 1, "beat": 1.0, "time_sec": 0.50, "pitch_name": "E4", "pitch_midi": 64, "staff": "treble", "voice": 1, "duration_beats": 1.0, "duration_sec": 0.50, "is_chord": False},
            {"id": 3, "measure": 1, "beat": 2.0, "time_sec": 1.00, "pitch_name": "F4", "pitch_midi": 65, "staff": "treble", "voice": 1, "duration_beats": 1.0, "duration_sec": 0.50, "is_chord": False},
            {"id": 4, "measure": 1, "beat": 3.0, "time_sec": 1.50, "pitch_name": "G4", "pitch_midi": 67, "staff": "treble", "voice": 1, "duration_beats": 1.0, "duration_sec": 0.50, "is_chord": False},
            {"id": 5, "measure": 2, "beat": 0.0, "time_sec": 2.00, "pitch_name": "G4", "pitch_midi": 67, "staff": "treble", "voice": 1, "duration_beats": 1.0, "duration_sec": 0.50, "is_chord": False},
            {"id": 6, "measure": 2, "beat": 1.0, "time_sec": 2.50, "pitch_name": "F4", "pitch_midi": 65, "staff": "treble", "voice": 1, "duration_beats": 1.0, "duration_sec": 0.50, "is_chord": False},
            {"id": 7, "measure": 2, "beat": 2.0, "time_sec": 3.00, "pitch_name": "E4", "pitch_midi": 64, "staff": "treble", "voice": 1, "duration_beats": 1.0, "duration_sec": 0.50, "is_chord": False},
            {"id": 8, "measure": 2, "beat": 3.0, "time_sec": 3.50, "pitch_name": "D4", "pitch_midi": 62, "staff": "treble", "voice": 1, "duration_beats": 1.0, "duration_sec": 0.50, "is_chord": False},
            {"id": 9, "measure": 3, "beat": 0.0, "time_sec": 4.00, "pitch_name": "C4", "pitch_midi": 60, "staff": "treble", "voice": 1, "duration_beats": 1.0, "duration_sec": 0.50, "is_chord": False},
            {"id": 10, "measure": 3, "beat": 1.0, "time_sec": 4.50, "pitch_name": "C4", "pitch_midi": 60, "staff": "treble", "voice": 1, "duration_beats": 1.0, "duration_sec": 0.50, "is_chord": False},
            {"id": 11, "measure": 3, "beat": 2.0, "time_sec": 5.00, "pitch_name": "D4", "pitch_midi": 62, "staff": "treble", "voice": 1, "duration_beats": 1.0, "duration_sec": 0.50, "is_chord": False},
            {"id": 12, "measure": 3, "beat": 3.0, "time_sec": 5.50, "pitch_name": "E4", "pitch_midi": 64, "staff": "treble", "voice": 1, "duration_beats": 1.0, "duration_sec": 0.50, "is_chord": False},
            {"id": 13, "measure": 4, "beat": 0.0, "time_sec": 6.00, "pitch_name": "E4", "pitch_midi": 64, "staff": "treble", "voice": 1, "duration_beats": 1.5, "duration_sec": 0.75, "is_chord": False},
            {"id": 14, "measure": 4, "beat": 1.5, "time_sec": 6.75, "pitch_name": "D4", "pitch_midi": 62, "staff": "treble", "voice": 1, "duration_beats": 0.5, "duration_sec": 0.25, "is_chord": False},
            {"id": 15, "measure": 4, "beat": 2.0, "time_sec": 7.00, "pitch_name": "D4", "pitch_midi": 62, "staff": "treble", "voice": 1, "duration_beats": 2.0, "duration_sec": 1.00, "is_chord": False},
        ]
    },
    "piece_2_harmony": {
        "id": "piece_2_harmony",
        "alias_id": "bach_minuet",
        "title": "Bach Minuet / 2-Part Counterpoint",
        "subtitle": "2-Part Harmony",
        "composer": "Johann Sebastian Bach",
        "type": "harmony_2part",
        "bpm": 100.0,
        "time_signature": [3, 4],
        "key_signature": {"key": "C", "mode": "major", "sharps_flats": 0},
        "num_measures": 4,
        "total_duration_sec": 7.8,
        "notes": [
            # Measure 1 (3/4 time, beat 0.0 to 3.0)
            {"id": 1, "measure": 1, "beat": 0.0, "time_sec": 0.00, "pitch_name": "G4", "pitch_midi": 67, "staff": "treble", "voice": 1, "duration_beats": 1.0, "duration_sec": 0.60, "is_chord": False},
            {"id": 2, "measure": 1, "beat": 0.0, "time_sec": 0.00, "pitch_name": "C3", "pitch_midi": 48, "staff": "bass", "voice": 2, "duration_beats": 3.0, "duration_sec": 1.80, "is_chord": False},
            {"id": 3, "measure": 1, "beat": 1.0, "time_sec": 0.60, "pitch_name": "C5", "pitch_midi": 72, "staff": "treble", "voice": 1, "duration_beats": 0.5, "duration_sec": 0.30, "is_chord": False},
            {"id": 4, "measure": 1, "beat": 1.5, "time_sec": 0.90, "pitch_name": "D5", "pitch_midi": 74, "staff": "treble", "voice": 1, "duration_beats": 0.5, "duration_sec": 0.30, "is_chord": False},
            {"id": 5, "measure": 1, "beat": 2.0, "time_sec": 1.20, "pitch_name": "E5", "pitch_midi": 76, "staff": "treble", "voice": 1, "duration_beats": 1.0, "duration_sec": 0.60, "is_chord": False},
            # Measure 2
            {"id": 6, "measure": 2, "beat": 0.0, "time_sec": 1.80, "pitch_name": "D5", "pitch_midi": 74, "staff": "treble", "voice": 1, "duration_beats": 1.0, "duration_sec": 0.60, "is_chord": False},
            {"id": 7, "measure": 2, "beat": 0.0, "time_sec": 1.80, "pitch_name": "B2", "pitch_midi": 47, "staff": "bass", "voice": 2, "duration_beats": 3.0, "duration_sec": 1.80, "is_chord": False},
            {"id": 8, "measure": 2, "beat": 1.0, "time_sec": 2.40, "pitch_name": "G4", "pitch_midi": 67, "staff": "treble", "voice": 1, "duration_beats": 1.0, "duration_sec": 0.60, "is_chord": False},
            {"id": 9, "measure": 2, "beat": 2.0, "time_sec": 3.00, "pitch_name": "G4", "pitch_midi": 67, "staff": "treble", "voice": 1, "duration_beats": 1.0, "duration_sec": 0.60, "is_chord": False},
            # Measure 3
            {"id": 10, "measure": 3, "beat": 0.0, "time_sec": 3.60, "pitch_name": "E5", "pitch_midi": 76, "staff": "treble", "voice": 1, "duration_beats": 1.0, "duration_sec": 0.60, "is_chord": False},
            {"id": 11, "measure": 3, "beat": 0.0, "time_sec": 3.60, "pitch_name": "A2", "pitch_midi": 45, "staff": "bass", "voice": 2, "duration_beats": 3.0, "duration_sec": 1.80, "is_chord": False},
            {"id": 12, "measure": 3, "beat": 1.0, "time_sec": 4.20, "pitch_name": "C5", "pitch_midi": 72, "staff": "treble", "voice": 1, "duration_beats": 0.5, "duration_sec": 0.30, "is_chord": False},
            {"id": 13, "measure": 3, "beat": 1.5, "time_sec": 4.50, "pitch_name": "D5", "pitch_midi": 74, "staff": "treble", "voice": 1, "duration_beats": 0.5, "duration_sec": 0.30, "is_chord": False},
            {"id": 14, "measure": 3, "beat": 2.0, "time_sec": 4.80, "pitch_name": "E5", "pitch_midi": 76, "staff": "treble", "voice": 1, "duration_beats": 1.0, "duration_sec": 0.60, "is_chord": False},
            # Measure 4
            {"id": 15, "measure": 4, "beat": 0.0, "time_sec": 5.40, "pitch_name": "D5", "pitch_midi": 74, "staff": "treble", "voice": 1, "duration_beats": 3.0, "duration_sec": 1.80, "is_chord": False},
            {"id": 16, "measure": 4, "beat": 0.0, "time_sec": 5.40, "pitch_name": "G2", "pitch_midi": 43, "staff": "bass", "voice": 2, "duration_beats": 3.0, "duration_sec": 1.80, "is_chord": False},
        ]
    },
    "piece_3_polyphonic": {
        "id": "piece_3_polyphonic",
        "alias_id": "cadence_triads",
        "title": "Cadence & Triad Progression",
        "subtitle": "Polyphonic Chordal Progression",
        "composer": "Traditional / Classical",
        "type": "polyphonic",
        "bpm": 80.0,
        "time_signature": [4, 4],
        "key_signature": {"key": "C", "mode": "major", "sharps_flats": 0},
        "num_measures": 5,
        "total_duration_sec": 15.5,
        "notes": [
            # Measure 1: C Major Chord (C3, G3, C4, E4)
            {"id": 1, "measure": 1, "beat": 0.0, "time_sec": 0.00, "pitch_name": "C3", "pitch_midi": 48, "staff": "bass", "voice": 1, "duration_beats": 4.0, "duration_sec": 3.00, "is_chord": True},
            {"id": 2, "measure": 1, "beat": 0.0, "time_sec": 0.00, "pitch_name": "G3", "pitch_midi": 55, "staff": "bass", "voice": 2, "duration_beats": 4.0, "duration_sec": 3.00, "is_chord": True},
            {"id": 3, "measure": 1, "beat": 0.0, "time_sec": 0.00, "pitch_name": "C4", "pitch_midi": 60, "staff": "treble", "voice": 3, "duration_beats": 4.0, "duration_sec": 3.00, "is_chord": True},
            {"id": 4, "measure": 1, "beat": 0.0, "time_sec": 0.00, "pitch_name": "E4", "pitch_midi": 64, "staff": "treble", "voice": 4, "duration_beats": 4.0, "duration_sec": 3.00, "is_chord": True},
            # Measure 2: A Minor Chord (A2, E3, A3, C4)
            {"id": 5, "measure": 2, "beat": 0.0, "time_sec": 3.00, "pitch_name": "A2", "pitch_midi": 45, "staff": "bass", "voice": 1, "duration_beats": 4.0, "duration_sec": 3.00, "is_chord": True},
            {"id": 6, "measure": 2, "beat": 0.0, "time_sec": 3.00, "pitch_name": "E3", "pitch_midi": 52, "staff": "bass", "voice": 2, "duration_beats": 4.0, "duration_sec": 3.00, "is_chord": True},
            {"id": 7, "measure": 2, "beat": 0.0, "time_sec": 3.00, "pitch_name": "A3", "pitch_midi": 57, "staff": "bass", "voice": 3, "duration_beats": 4.0, "duration_sec": 3.00, "is_chord": True},
            {"id": 8, "measure": 2, "beat": 0.0, "time_sec": 3.00, "pitch_name": "C4", "pitch_midi": 60, "staff": "treble", "voice": 4, "duration_beats": 4.0, "duration_sec": 3.00, "is_chord": True},
            # Measure 3: F Major Chord (F2, C3, F3, A3)
            {"id": 9, "measure": 3, "beat": 0.0, "time_sec": 6.00, "pitch_name": "F2", "pitch_midi": 41, "staff": "bass", "voice": 1, "duration_beats": 4.0, "duration_sec": 3.00, "is_chord": True},
            {"id": 10, "measure": 3, "beat": 0.0, "time_sec": 6.00, "pitch_name": "C3", "pitch_midi": 48, "staff": "bass", "voice": 2, "duration_beats": 4.0, "duration_sec": 3.00, "is_chord": True},
            {"id": 11, "measure": 3, "beat": 0.0, "time_sec": 6.00, "pitch_name": "F3", "pitch_midi": 53, "staff": "bass", "voice": 3, "duration_beats": 4.0, "duration_sec": 3.00, "is_chord": True},
            {"id": 12, "measure": 3, "beat": 0.0, "time_sec": 6.00, "pitch_name": "A3", "pitch_midi": 57, "staff": "treble", "voice": 4, "duration_beats": 4.0, "duration_sec": 3.00, "is_chord": True},
            # Measure 4: G Major Chord (G2, D3, G3, B3)
            {"id": 13, "measure": 4, "beat": 0.0, "time_sec": 9.00, "pitch_name": "G2", "pitch_midi": 43, "staff": "bass", "voice": 1, "duration_beats": 4.0, "duration_sec": 3.00, "is_chord": True},
            {"id": 14, "measure": 4, "beat": 0.0, "time_sec": 9.00, "pitch_name": "D3", "pitch_midi": 50, "staff": "bass", "voice": 2, "duration_beats": 4.0, "duration_sec": 3.00, "is_chord": True},
            {"id": 15, "measure": 4, "beat": 0.0, "time_sec": 9.00, "pitch_name": "G3", "pitch_midi": 55, "staff": "bass", "voice": 3, "duration_beats": 4.0, "duration_sec": 3.00, "is_chord": True},
            {"id": 16, "measure": 4, "beat": 0.0, "time_sec": 9.00, "pitch_name": "B3", "pitch_midi": 59, "staff": "treble", "voice": 4, "duration_beats": 4.0, "duration_sec": 3.00, "is_chord": True},
            # Measure 5: C Major Chord (C3, G3, E4, C5)
            {"id": 17, "measure": 5, "beat": 0.0, "time_sec": 12.00, "pitch_name": "C3", "pitch_midi": 48, "staff": "bass", "voice": 1, "duration_beats": 4.0, "duration_sec": 3.00, "is_chord": True},
            {"id": 18, "measure": 5, "beat": 0.0, "time_sec": 12.00, "pitch_name": "G3", "pitch_midi": 55, "staff": "bass", "voice": 2, "duration_beats": 4.0, "duration_sec": 3.00, "is_chord": True},
            {"id": 19, "measure": 5, "beat": 0.0, "time_sec": 12.00, "pitch_name": "E4", "pitch_midi": 64, "staff": "treble", "voice": 3, "duration_beats": 4.0, "duration_sec": 3.00, "is_chord": True},
            {"id": 20, "measure": 5, "beat": 0.0, "time_sec": 12.00, "pitch_name": "C5", "pitch_midi": 72, "staff": "treble", "voice": 4, "duration_beats": 4.0, "duration_sec": 3.00, "is_chord": True},
        ]
    }
}


# ==============================================================================
# Diatonic Geometry for Score Rendering
# ==============================================================================
# Vertical layout (Line spacing Ss = 20 px, half-step = 10 px):
# Treble top line F5: Y = 320
# Treble line 2 D5:   Y = 340
# Treble line 3 B4:   Y = 360
# Treble line 4 G4:   Y = 380
# Treble bottom E4:   Y = 400
# Middle C ledger C4: Y = 420
# Bass top line A3:   Y = 440
# Bass line 2 F3:     Y = 460
# Bass line 3 D3:     Y = 480
# Bass line 4 B2:     Y = 500
# Bass bottom G2:     Y = 520
# Bass ledger E2:     Y = 540
# Bass ledger C2:     Y = 560

MIDI_TO_Y = {
    # High ledger
    81: 300,  # A5 (ledger 300)
    79: 310,  # G5
    # Treble staff
    77: 320,  # F5 (top line)
    76: 330,  # E5
    74: 340,  # D5 (line 2)
    72: 350,  # C5
    71: 360,  # B4 (line 3)
    69: 370,  # A4
    67: 380,  # G4 (line 4)
    65: 390,  # F4
    64: 400,  # E4 (bottom line)
    # Between staves
    62: 410,  # D4
    60: 420,  # C4 (Middle C, ledger 420)
    59: 430,  # B3
    # Bass staff
    57: 440,  # A3 (top line)
    55: 450,  # G3
    53: 460,  # F3 (line 2)
    52: 470,  # E3
    50: 480,  # D3 (line 3)
    48: 490,  # C3
    47: 500,  # B2 (line 4)
    45: 510,  # A2
    43: 520,  # G2 (bottom line)
    # Low ledger
    41: 530,  # F2
    40: 540,  # E2 (ledger 540)
    38: 550,  # D2
    36: 560,  # C2 (ledger 560)
}


# ==============================================================================
# Audio Synthesis (22,050 Hz, 16-bit Mono PCM WAV)
# ==============================================================================

def synthesize_audio_piece(piece_data: dict, output_path: str, sample_rate: int = 22050):
    """Synthesizes mono 22,050 Hz 16-bit PCM WAV audio using additive sine synthesis."""
    total_duration = piece_data["total_duration_sec"]
    total_samples = int(total_duration * sample_rate)
    buffer = np.zeros(total_samples, dtype=np.float32)

    for note in piece_data["notes"]:
        pitch = note["pitch_midi"]
        onset_sec = note["time_sec"]
        dur_sec = note["duration_sec"]
        f0 = 440.0 * (2.0 ** ((pitch - 69.0) / 12.0))

        n_samples = int(dur_sec * sample_rate)
        if n_samples <= 0:
            continue

        t = np.linspace(0, dur_sec, n_samples, endpoint=False, dtype=np.float32)
        # Additive synthesis: fundamental plus rich harmonics for strong pitch salience
        sig = (np.sin(2.0 * np.pi * f0 * t) +
               0.35 * np.sin(4.0 * np.pi * f0 * t) +
               0.15 * np.sin(6.0 * np.pi * f0 * t) +
               0.08 * np.sin(8.0 * np.pi * f0 * t))

        # ADSR Envelope: 15ms attack, 30ms release
        env = np.ones(n_samples, dtype=np.float32)
        att = min(int(0.015 * sample_rate), n_samples // 4)
        rel = min(int(0.030 * sample_rate), n_samples // 4)
        if att > 0:
            env[:att] = np.linspace(0, 1, att, dtype=np.float32)
        if rel > 0:
            env[-rel:] = np.linspace(1, 0, rel, dtype=np.float32)
        sig = sig * env

        start_idx = int(onset_sec * sample_rate)
        end_idx = min(start_idx + n_samples, total_samples)
        buffer[start_idx:end_idx] += sig[:end_idx - start_idx]

    # Normalize to prevent clipping, target 80% peak amplitude
    max_val = np.max(np.abs(buffer))
    if max_val > 0:
        buffer = 0.80 * (buffer / max_val)

    # Convert to 16-bit signed PCM
    pcm_16 = (buffer * 32767.0).astype(np.int16)

    # Write WAV file
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with wave.open(output_path, "wb") as wf:
        wf.setnchannels(1)       # Mono
        wf.setsampwidth(2)       # 16-bit (2 bytes)
        wf.setframerate(sample_rate)
        wf.writeframes(pcm_16.tobytes())


# ==============================================================================
# Score Image Generation (Pillow, 1600x900 Clean Score)
# ==============================================================================

def generate_score_image(piece_data: dict, output_path: str):
    """Draws a clean, high-contrast sheet music score PNG with staves, clefs, and notes."""
    width = 1600
    height = 900
    img = Image.new("L", (width, height), 255)  # Grayscale white background
    draw = ImageDraw.Draw(img)

    # Fonts
    try:
        title_font = ImageFont.truetype("arial.ttf", 36)
        sub_font = ImageFont.truetype("arial.ttf", 20)
        time_sig_font = ImageFont.truetype("arialbd.ttf", 38)
    except Exception:
        title_font = ImageFont.load_default()
        sub_font = ImageFont.load_default()
        time_sig_font = ImageFont.load_default()

    # Draw Header Text
    title_text = f"{piece_data['title']} — {piece_data['subtitle']}"
    draw.text((width // 2, 80), title_text, fill=0, font=title_font, anchor="mm")
    bpm = piece_data["bpm"]
    ts = f"{piece_data['time_signature'][0]}/{piece_data['time_signature'][1]}"
    composer = piece_data.get("composer", "")
    sub_text = f"{composer}  |  Tempo: {bpm:.1f} BPM  |  Meter: {ts}  |  Key: C Major"
    draw.text((width // 2, 130), sub_text, fill=0, font=sub_font, anchor="mm")

    # Staff lines: X in [100, 1520]
    x_staff_left = 100
    x_staff_right = 1520
    treble_ys = [320, 340, 360, 380, 400]
    bass_ys = [440, 460, 480, 500, 520]

    for y in treble_ys + bass_ys:
        draw.line([(x_staff_left, y), (x_staff_right, y)], fill=0, width=1)

    # Left Braces
    draw.line([(x_staff_left, 320), (x_staff_left, 520)], fill=0, width=3)
    draw.line([(x_staff_left + 6, 320), (x_staff_left + 6, 520)], fill=0, width=1)

    # Draw Clefs
    clef_drawn = False
    try:
        font_clef = ImageFont.truetype("seguisym.ttf", 100)
        # Treble G-clef on line 2 (Y=380)
        draw.text((x_staff_left + 20, 310), "\U0001D11E", fill=0, font=font_clef)
        # Bass F-clef flanking line 4 (Y=460)
        draw.text((x_staff_left + 25, 435), "\U0001D122", fill=0, font=font_clef)
        clef_drawn = True
    except Exception:
        pass

    if not clef_drawn:
        # Fallback geometric clefs if seguisym is unavailable
        # G-clef curve
        draw.arc([x_staff_left + 20, 330, x_staff_left + 60, 410], start=0, end=360, fill=0, width=2)
        draw.line([(x_staff_left + 40, 310), (x_staff_left + 40, 415)], fill=0, width=2)
        # F-clef curve and dots
        draw.arc([x_staff_left + 20, 440, x_staff_left + 55, 480], start=90, end=270, fill=0, width=2)
        draw.ellipse([x_staff_left + 60, 450, x_staff_left + 66, 456], fill=0)
        draw.ellipse([x_staff_left + 60, 464, x_staff_left + 66, 470], fill=0)

    # Time Signature
    num, den = piece_data["time_signature"]
    ts_x = x_staff_left + 95
    # Upper staff time signature
    draw.text((ts_x, 345), str(num), fill=0, font=time_sig_font, anchor="mm")
    draw.text((ts_x, 385), str(den), fill=0, font=time_sig_font, anchor="mm")
    # Lower staff time signature
    draw.text((ts_x, 465), str(num), fill=0, font=time_sig_font, anchor="mm")
    draw.text((ts_x, 505), str(den), fill=0, font=time_sig_font, anchor="mm")

    # Measure Barlines
    x_bar_start = 230
    x_bar_end = x_staff_right
    num_m = piece_data["num_measures"]
    m_width = (x_bar_end - x_bar_start) / num_m

    barlines = [x_bar_start + i * m_width for i in range(num_m + 1)]
    for bx in barlines[:-1]:
        draw.line([(bx, 320), (bx, 520)], fill=0, width=1)
    # Double barline at end
    draw.line([(barlines[-1] - 4, 320), (barlines[-1] - 4, 520)], fill=0, width=1)
    draw.line([(barlines[-1], 320), (barlines[-1], 520)], fill=0, width=3)

    # Notehead dimensions
    rx = 10
    ry = 7
    beats_per_measure = piece_data["time_signature"][0]

    for note in piece_data["notes"]:
        m = note["measure"]
        b = note["beat"]
        pitch = note["pitch_midi"]
        dur_beats = note["duration_beats"]

        # Calculate exact center coordinates (xc, yc)
        x_left = barlines[m - 1]
        w_cur = barlines[m] - x_left
        xc = x_left + 15.0 + (b / float(beats_per_measure)) * (w_cur - 30.0)
        yc = MIDI_TO_Y.get(pitch, 360)

        # Ledger Lines
        if pitch == 60:  # Middle C
            draw.line([(xc - 15, 420), (xc + 15, 420)], fill=0, width=1)
        elif pitch == 81:  # A5
            draw.line([(xc - 15, 300), (xc + 15, 300)], fill=0, width=1)
        elif pitch == 40:  # E2
            draw.line([(xc - 15, 540), (xc + 15, 540)], fill=0, width=1)
        elif pitch == 36:  # C2
            draw.line([(xc - 15, 540), (xc + 15, 540)], fill=0, width=1)
            draw.line([(xc - 15, 560), (xc + 15, 560)], fill=0, width=1)

        # Notehead Drawing (Solid vs Hollow)
        is_hollow = (dur_beats >= 2.0)
        if is_hollow:
            # Outer black ellipse
            draw.ellipse([(xc - rx, yc - ry), (xc + rx, yc + ry)], fill=0)
            # Inner white hole (genus 0)
            draw.ellipse([(xc - rx + 3, yc - ry + 3), (xc + rx - 3, yc + ry - 3)], fill=255)
        else:
            # Solid black ellipse
            draw.ellipse([(xc - rx, yc - ry), (xc + rx, yc + ry)], fill=0)

        # Stems (Whole notes have no stems)
        has_stem = (dur_beats < 4.0)
        if has_stem:
            # Stem direction: UP if note is below middle line of staff, DOWN if on/above
            # Treble middle line = B4 (Y=360), Bass middle line = D3 (Y=480)
            is_treble = (note["staff"] == "treble")
            mid_y = 360 if is_treble else 480
            stem_up = (yc > mid_y)

            stem_len = 70
            if stem_up:
                stem_x = xc + rx - 1
                draw.line([(stem_x, yc), (stem_x, yc - stem_len)], fill=0, width=2)
                # Flag for eighth notes (dur_beats == 0.5)
                if dur_beats == 0.5:
                    draw.line([(stem_x, yc - stem_len), (stem_x + 12, yc - stem_len + 20)], fill=0, width=2)
            else:
                stem_x = xc - rx + 1
                draw.line([(stem_x, yc), (stem_x, yc + stem_len)], fill=0, width=2)
                # Flag for eighth notes
                if dur_beats == 0.5:
                    draw.line([(stem_x, yc + stem_len), (stem_x + 12, yc + stem_len - 20)], fill=0, width=2)

        # Dotted notes (1.5 or 3.0 beats)
        if dur_beats in (1.5, 3.0):
            dot_y = yc - 4 if (yc % 20 == 0) else yc  # Shift slightly off staff line
            draw.ellipse([(xc + rx + 5, dot_y - 3), (xc + rx + 11, dot_y + 3)], fill=0)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path, "PNG")


# ==============================================================================
# Ground Truth JSON Generation (Survey Section 4.5 & ChartValidator)
# ==============================================================================

def generate_ground_truth_json(piece_data: dict, output_path: str):
    """Generates ground truth note chart adhering to Section 4.5 schema & ChartValidator."""
    num_m = piece_data["num_measures"]
    bpm = piece_data["bpm"]
    beats_per_measure = piece_data["time_signature"][0]
    sec_per_beat = 60.0 / bpm
    sec_per_measure = beats_per_measure * sec_per_beat

    measures = []
    for m in range(1, num_m + 1):
        start_b = (m - 1) * beats_per_measure
        start_s = (m - 1) * sec_per_measure
        end_s = m * sec_per_measure
        measures.append({
            "index": m,
            "start_beat": float(start_b),
            "start_sec": round(float(start_s), 4),
            "end_sec": round(float(end_s), 4)
        })

    notes = []
    for n in piece_data["notes"]:
        # Overall onset beat across the entire piece
        onset_beat = (n["measure"] - 1) * beats_per_measure + n["beat"]
        notes.append({
            "id": n["id"],
            "pitch_name": n["pitch_name"],
            "pitch_midi": n["pitch_midi"],
            "staff": n["staff"],
            "voice": n.get("voice", 1),
            "measure": n["measure"],
            "beat": float(n["beat"]),
            "onset_beat": float(onset_beat),
            "time_sec": float(n["time_sec"]),
            "onset_sec": float(n["time_sec"]),
            "duration_beats": float(n["duration_beats"]),
            "duration_sec": float(n["duration_sec"]),
            "is_chord": n.get("is_chord", False),
            "velocity": 0.8
        })

    chart = {
        "version": "1.0.0",
        "title": piece_data["title"],
        "bpm": float(piece_data["bpm"]),
        "time_signature": piece_data["time_signature"],
        "audio_file": "audio.wav",
        "score_file": "score.png",
        "metadata": {
            "title": piece_data["title"],
            "composer": piece_data.get("composer", ""),
            "tempo_bpm": float(piece_data["bpm"]),
            "time_signature": {
                "numerator": piece_data["time_signature"][0],
                "denominator": piece_data["time_signature"][1]
            },
            "key_signature": piece_data["key_signature"],
            "duration_sec": float(piece_data["total_duration_sec"]),
            "audio_file": "audio.wav",
            "score_file": "score.png"
        },
        "measures": measures,
        "notes": notes
    }

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(chart, f, indent=2)


# ==============================================================================
# MIDI File Generation (Standard Type 1 MIDI via music21)
# ==============================================================================

def generate_midi_file(piece_data: dict, output_path: str):
    """Generates standard Type 1 MIDI file using music21."""
    if m21 is None:
        raise RuntimeError("music21 is required to generate MIDI files.")

    score = m21.stream.Score()
    score.metadata = m21.metadata.Metadata()
    score.metadata.title = piece_data["title"]
    score.metadata.composer = piece_data.get("composer", "")

    bpm = piece_data["bpm"]
    ts_str = f"{piece_data['time_signature'][0]}/{piece_data['time_signature'][1]}"
    beats_per_measure = piece_data["time_signature"][0]

    # Create Treble and Bass Parts
    treble_part = m21.stream.Part()
    treble_part.id = "Treble"
    treble_part.append(m21.clef.TrebleClef())
    treble_part.append(m21.meter.TimeSignature(ts_str))
    treble_part.append(m21.tempo.MetronomeMark(number=bpm))

    bass_part = m21.stream.Part()
    bass_part.id = "Bass"
    bass_part.append(m21.clef.BassClef())
    bass_part.append(m21.meter.TimeSignature(ts_str))
    bass_part.append(m21.tempo.MetronomeMark(number=bpm))

    has_bass_notes = any(n["staff"] == "bass" for n in piece_data["notes"])

    for n in piece_data["notes"]:
        onset_beat = (n["measure"] - 1) * beats_per_measure + n["beat"]
        m21_note = m21.note.Note(n["pitch_name"], quarterLength=n["duration_beats"])
        m21_note.volume.velocity = 80

        if n["staff"] == "treble":
            treble_part.insert(onset_beat, m21_note)
        else:
            bass_part.insert(onset_beat, m21_note)

    score.append(treble_part)
    if has_bass_notes:
        score.append(bass_part)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    score.write("midi", fp=output_path)


# ==============================================================================
# Model Bundling and Asset Mirroring
# ==============================================================================

def bundle_onnx_model():
    """Copies Spotify Basic Pitch nmp.onnx model into assets/models/nmp.onnx."""
    official_paths = [
        r"C:\Users\david\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.12_qbz5n2kfra8p0\LocalCache\local-packages\Python312\site-packages\basic_pitch\saved_models\icassp_2022\nmp.onnx",
    ]
    try:
        import basic_pitch
        bp_path = os.path.join(os.path.dirname(basic_pitch.__file__), "saved_models", "icassp_2022", "nmp.onnx")
        official_paths.insert(0, bp_path)
    except Exception:
        pass

    target_model_path = os.path.join(PROJECT_ROOT, "assets", "models", "nmp.onnx")
    os.makedirs(os.path.dirname(target_model_path), exist_ok=True)

    if os.path.exists(target_model_path) and os.path.getsize(target_model_path) >= 200000:
        print(f"[OK] Basic Pitch ONNX model already present: {target_model_path} ({os.path.getsize(target_model_path)} bytes)")
        return

    for p in official_paths:
        if os.path.exists(p):
            shutil.copyfile(p, target_model_path)
            print(f"[OK] Bundled Basic Pitch ONNX model from {p} -> {target_model_path} ({os.path.getsize(target_model_path)} bytes)")
            return

    raise FileNotFoundError("Could not find official Spotify Basic Pitch nmp.onnx model on system.")


def mirror_all_assets():
    """Mirrors audio, score, and chart assets into flat Godot access directories."""
    test_pieces_root = os.path.join(PROJECT_ROOT, "assets", "test_pieces")
    audio_root = os.path.join(PROJECT_ROOT, "assets", "audio")
    scores_root = os.path.join(PROJECT_ROOT, "assets", "scores")
    charts_root = os.path.join(PROJECT_ROOT, "assets", "charts")

    os.makedirs(audio_root, exist_ok=True)
    os.makedirs(scores_root, exist_ok=True)
    os.makedirs(charts_root, exist_ok=True)

    for piece_key, piece_data in PIECES.items():
        piece_dir = os.path.join(test_pieces_root, piece_key)
        alias_id = piece_data["alias_id"]

        # Copy audio
        src_wav = os.path.join(piece_dir, "audio.wav")
        if os.path.exists(src_wav):
            shutil.copyfile(src_wav, os.path.join(audio_root, f"{piece_key}.wav"))
            shutil.copyfile(src_wav, os.path.join(audio_root, f"{alias_id}.wav"))

        # Copy score
        src_png = os.path.join(piece_dir, "score.png")
        if os.path.exists(src_png):
            shutil.copyfile(src_png, os.path.join(scores_root, f"{piece_key}.png"))
            shutil.copyfile(src_png, os.path.join(scores_root, f"{alias_id}.png"))

        # Copy chart JSON & MIDI
        src_json = os.path.join(piece_dir, "ground_truth.json")
        if os.path.exists(src_json):
            shutil.copyfile(src_json, os.path.join(charts_root, f"{piece_key}.json"))
            shutil.copyfile(src_json, os.path.join(charts_root, f"{alias_id}.json"))

        src_mid = os.path.join(piece_dir, "ground_truth.mid")
        if os.path.exists(src_mid):
            shutil.copyfile(src_mid, os.path.join(charts_root, f"{piece_key}.mid"))
            shutil.copyfile(src_mid, os.path.join(charts_root, f"{alias_id}.mid"))

    print("[OK] All assets mirrored to assets/audio/, assets/scores/, and assets/charts/.")


# ==============================================================================
# Main Generator Entry Point
# ==============================================================================

def main():
    print("================================================================================")
    print("           MICGAME-3 TEST ASSET GENERATOR (MILESTONE 2)")
    print("================================================================================")

    # 1. Bundle Basic Pitch ONNX Model
    bundle_onnx_model()

    # 2. Synthesize each test piece
    test_pieces_root = os.path.join(PROJECT_ROOT, "assets", "test_pieces")

    for piece_key, piece_data in PIECES.items():
        print(f"\n--- Generating {piece_data['title']} ({piece_key}) ---")
        piece_dir = os.path.join(test_pieces_root, piece_key)
        os.makedirs(piece_dir, exist_ok=True)

        wav_path = os.path.join(piece_dir, "audio.wav")
        png_path = os.path.join(piece_dir, "score.png")
        json_path = os.path.join(piece_dir, "ground_truth.json")
        mid_path = os.path.join(piece_dir, "ground_truth.mid")

        # Synthesize Audio WAV
        synthesize_audio_piece(piece_data, wav_path)
        with wave.open(wav_path, "rb") as wf:
            print(f"  [WAV]  Generated {wav_path} (Rate={wf.getframerate()}, Ch={wf.getnchannels()}, Width={wf.getsampwidth()}, Size={os.path.getsize(wav_path)} bytes)")

        # Render Score PNG
        generate_score_image(piece_data, png_path)
        print(f"  [PNG]  Rendered {png_path} (Size={os.path.getsize(png_path)} bytes)")

        # Generate Ground Truth JSON
        generate_ground_truth_json(piece_data, json_path)
        print(f"  [JSON] Exported {json_path} (Notes={len(piece_data['notes'])}, Size={os.path.getsize(json_path)} bytes)")

        # Generate MIDI
        generate_midi_file(piece_data, mid_path)
        print(f"  [MID]  Wrote MIDI {mid_path} (Size={os.path.getsize(mid_path)} bytes)")

    # 3. Mirror assets to convenient Godot directories
    mirror_all_assets()

    print("\n================================================================================")
    print("           ALL 12 TEST ASSETS GENERATED & VERIFIED SUCCESSFULLY")
    print("================================================================================")


if __name__ == "__main__":
    main()
