# Original User Request

## 2026-10-16T18:11:08Z

A cross-platform (Windows & Android, specifically tested/validated for stock Google Pixel 7a) Godot rhythm game cloning the Guitar Hero formula with right-to-left horizontal grand staff (double staff) notation, real-time polyphonic microphone scoring using Spotify's Basic Pitch ONNX model, and an integrated on-device Optical Music Recognition (OMR) system pairing digitized sheet music with user audio. The audio inference architecture must be modular to accommodate future pluggable pretrained instrument neural networks, source separation, and fine-tuning.

Working directory: c:/Users/david/Documents/micgame-3
Integrity mode: development

## Requirements

### R1. Grand Staff Right-to-Left Note Highway (Godot 4)
- Deliver a Godot 4 game client supporting both Windows desktop and Android mobile form factors, specifically compatible with stock Google Pixel 7a hardware (ARM64-v8a, Vulkan Mobile / Compatibility renderer).
- Render a continuous right-to-left scrolling musical highway displaying standard grand staff notation (both Treble and Bass staves simultaneously).
- Place notes, accidentals, and chords at accurate vertical staff positions corresponding to standard musical pitches (C2 through C6+) scrolling into a designated hit/target line on the left.
- Provide real-time hit detection, combo tracking, and scoring feedback based on timing accuracy windows (e.g., Perfect, Good, Miss).

### R2. Polyphonic Microphone Input & Spotify Basic Pitch Scoring
- Capture live microphone audio across supported platforms with low latency on both Windows and Android (Pixel 7a audio input permissions and sample rate handling).
- Run inference with Spotify's Basic Pitch ONNX model (`basic-pitch`) to perform real-time or streaming polyphonic pitch and onset detection.
- Design the audio inference subsystem with a modular model runner interface so future instrument-specific neural networks, source separation models, and fine-tuning pipelines can be cleanly plugged in.
- Support simultaneous multi-player / multi-instrument sound input received via a single microphone, matching detected polyphonic pitch clusters against expected chart notes at the current playhead position.
- Grade performance based on detected pitch accuracy, onset timing, and note duration.

### R3. Integrated On-Device Optical Music Recognition (OMR)
- Ingest user-submitted sheet music images (PNG/JPEG) directly within the game.
- Execute an on-device OMR pipeline to detect staves, clefs, key signatures, measure bars, and note events (pitches, onsets, durations).
- Pair digitized sheet music charts with user-provided audio accompaniment files (WAV, MP3, or OGG), aligning audio playback with the digitized visual note highway.

### R4. Bundled Test Assets & Standalone Verification Harnesses
- Supply at least 3 varied test pieces (monophonic melody, 2-part harmony, polyphonic chordal progression) with matched sheet music images, audio files, and reference ground-truth note charts.
- Provide automated CLI test harnesses to verify:
  1. The OMR engine against ground-truth sheet music charts.
  2. The ONNX transcription pipeline against pre-recorded reference audio.
  3. The scoring and alignment engine without requiring live microphone interaction.

## Acceptance Criteria

### Highway & Notation Engine
- [ ] Running the game displays a dual treble-and-bass clef staff scrolling smoothly from right to left toward a target hit zone on the left.
- [ ] Notes and chords render at correct staff line/space positions matching musical pitch conventions (e.g., Middle C / C4 on ledger line between staves).
- [ ] Test chart playback triggers visual feedback for hit states (Perfect, Good, Miss) synchronized to playhead audio.

### Polyphonic Transcription & Scoring
- [ ] Automated verification script successfully runs Spotify Basic Pitch ONNX model inference on test audio files without errors.
- [ ] Polyphonic transcription achieves >= 80% F1-score / note accuracy on the bundled polyphonic test audio against ground truth MIDI / chart events.
- [ ] Simultaneous multiple pitches (chords/polyphony) played back into the transcription engine are identified as concurrent active notes.
- [ ] Scoring logic evaluates pitch accuracy (within configurable semitone tolerance) and timing window (e.g. +/- 100ms).
- [ ] Audio model interface is decoupled from the game loop via an abstract interface enabling future pluggable neural models and source separation.

### Sheet Music Digitization (OMR)
- [ ] On-device OMR processor ingests test sheet music images and outputs structured note data (pitch, start time/measure, duration).
- [ ] OMR recognition accuracy on bundled clean test score images achieves >= 85% note pitch and onset recognition compared to reference chart data.
- [ ] User audio file and digitized sheet music can be loaded simultaneously into a playable level.

### Cross-Platform & Android (Pixel 7a) Readiness
- [ ] Godot project passes headless validation and provides an export preset configured for Android (ARM64-v8a target, audio recording permissions, GLES3/Compatibility or Vulkan Mobile renderer verified for Pixel 7a specifications).
- [ ] Windows export preset and local runnable build targets are verified.
- [ ] All external dependencies (ONNX Runtime, models, image processing libraries) are documented and bundled or fetched via reproducible build scripts.
