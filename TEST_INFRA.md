# Test Infrastructure Specification: MicGame-3 Grand Staff Rhythm Game

## 1. Test Philosophy: Opaque-Box, Requirement-Driven

The testing infrastructure for MicGame-3 operates strictly under an **opaque-box, requirement-driven** philosophy:
1. **Specification as Single Source of Truth**: All tests derive their inputs, assertions, and expected outputs directly from the authoritative user specifications in `ORIGINAL_REQUEST.md` and architectural contracts in `PROJECT.md`.
2. **Behavioral Integrity over Internal Implementation**: Tests evaluate the observable interface contracts (mathematical mappings, data schemas, ONNX tensor dimensions, audio buffers, image projections, scoring states, export presets) rather than private, ephemeral implementation details.
3. **No Facade Testing**: Every test exercises concrete algorithms, data pipelines, and validation logic. Tests that unconditionally pass without asserting physical or mathematical invariants are strictly prohibited.
4. **Self-Contained & Deterministic**: Tests are isolated, reproducible, order-independent, and runnable across any desktop or CI environment without requiring live microphone hardware, attached Android devices, or graphical display servers.
5. **Progressive Testability**: Verification uses standardized Python and Godot headless capabilities.

---

## 2. Feature Inventory (Features 1 – 20)

| # | Feature | Scope / Requirement | Verification Strategy | Tier Mapping |
|---|---------|---------------------|-----------------------|--------------|
| 1 | Godot Config Cleanup | PROJECT.md §F1, Explorer Survey | Validate `project.godot` structure, ensure removal of orphaned autoloads/plugins, confirm main scene and audio driver settings | T1, T2, T3, T4 |
| 2 | Grand Staff Highway | ORIGINAL_REQUEST §R1, PROJECT.md §F2 | Validate right-to-left scrolling math, hit line at X=160px, staff vertical spacing, and note travel times | T1, T2, T3, T4 |
| 3 | Diatonic Note Placement | ORIGINAL_REQUEST §R1, PROJECT.md §F3 | Validate diatonic mapping across C2 to C6+, Y=360px center, 18px line spacing, and dynamic ledger lines | T1, T2, T3, T4 |
| 4 | Hit Detection & Scoring | ORIGINAL_REQUEST §R1, PROJECT.md §F4 | Validate timing windows (Perfect $\le 50$ms, Good $\le 100$ms, Miss $> 100$ms), combo counter, multipliers (1x–4x) | T1, T2, T3, T4 |
| 5 | Audio Playhead Sync | ORIGINAL_REQUEST §R1, PROJECT.md §F5 | Validate sub-frame audio synchronization, playhead interpolation, and active note window querying | T1, T2, T3, T4 |
| 6 | Bundled Test Pieces | ORIGINAL_REQUEST §R4, PROJECT.md §F6 | Validate 3 test pieces (monophonic, 2-part harmony, polyphonic chordal) across chart JSON schema, note count, and audio metadata | T1, T2, T3, T4 |
| 7 | Asset Generation Pipeline | PROJECT.md §F7, Explorer 3 | Validate audio synthesis formulas, PCM WAV encoding, chart generation, and score rendering coordinates | T1, T2, T3, T4 |
| 8 | Basic Pitch ONNX Model | ORIGINAL_REQUEST §R2, PROJECT.md §F8 | Validate ONNX model loading, input tensor `[1, 43844, 1]`, output notes/onsets `[1, 172, 88]`, contours `[1, 172, 264]` | T1, T2, T3, T4 |
| 9 | Modular Inference Interface | ORIGINAL_REQUEST §R2, PROJECT.md §F9 | Validate `IAudioPitchModel` polymorphic contract (`push_audio_samples`, `get_detected_pitches`, `get_recent_onsets`) | T1, T2, T3, T4 |
| 10 | Real-Time Polyphonic Pitch Extraction | ORIGINAL_REQUEST §R2, PROJECT.md §F10 | Validate audio resampling to 22.05kHz, peak-picking thresholds, and multi-pitch chord activation extraction | T1, T2, T3, T4 |
| 11 | Microphone Audio Capture | ORIGINAL_REQUEST §R2, PROJECT.md §F11 | Validate `default_bus_layout.tres` Record bus, `AudioEffectCapture` config, buffer sizing, and RMS noise gate thresholding | T1, T2, T3, T4 |
| 12 | Polyphonic Scoring Matcher | ORIGINAL_REQUEST §R2, PROJECT.md §F12 | Validate matching incoming pitch clusters against expected chord notes, handling partial hits, harmonic noise, and multi-instrument chords | T1, T2, T3, T4 |
| 13 | Sheet Music Image Ingestion | ORIGINAL_REQUEST §R3, PROJECT.md §F13 | Validate image loading (PNG/JPEG), dimension checks, binary thresholding, and pixel buffer normalization | T1, T2, T3, T4 |
| 14 | Projection Profiling OMR | ORIGINAL_REQUEST §R3, PROJECT.md §F14 | Validate horizontal projection profile for staff line detection, staff spacing $S$, and notehead centroid pitch extraction | T1, T2, T3, T4 |
| 15 | Audio-Chart Alignment | ORIGINAL_REQUEST §R3, PROJECT.md §F15 | Validate pairing digitized sheet music with audio accompaniment, beat-to-time conversion, and timeline alignment | T1, T2, T3, T4 |
| 16 | Standalone CLI Test Harnesses | ORIGINAL_REQUEST §R4, PROJECT.md §F16 | Validate CLI test harness contracts (OMR $\ge 85\%$, ONNX transcription $\ge 80\%$ F1, scoring engine without mic) | T1, T2, T3, T4 |
| 17 | Android (Pixel 7a) Export | ORIGINAL_REQUEST §R1, PROJECT.md §F17 | Validate `export_presets.cfg` for Android: ARM64-v8a target, `RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`, GL Compatibility renderer | T1, T2, T3, T4 |
| 18 | Windows Desktop Export | ORIGINAL_REQUEST §R1, PROJECT.md §F18 | Validate `export_presets.cfg` for Windows Desktop: x86_64 target, embedded PCK option, runnable executable settings | T1, T2, T3, T4 |
| 19 | Headless Project Validation | ORIGINAL_REQUEST Acceptance Criteria, §F19 | Validate project integrity for headless execution without crashes or missing resource warnings | T1, T2, T3, T4 |
| 20 | E2E Test Suite Validation | PROJECT.md §F20 | Validate self-testing runner, tier execution, pass rate reporting, structured test summary, and exit code 0 | T1, T2, T3, T4 |

---

## 3. Test Architecture

### 3.1 Framework & Runner
- **Test Framework**: Standard Python `unittest` framework (Python 3.12+).
- **No Third-Party Framework Required**: Uses standard library `unittest` so the entire suite runs immediately without external test runners or pip dependencies.
- **Discovery Command**:
  ```bash
  python -m unittest discover tests/e2e -p "test_*.py"
  ```
- **Automated Runner Script**:
  ```bash
  python tests/e2e/run_all_e2e_tests.py
  ```

### 3.2 Directory Layout
```
c:\Users\david\Documents\micgame-3\tests\e2e\
├── __init__.py                      # Package marker
├── e2e_test_utils.py               # Reusable test helpers, mock generators, models, and math
├── test_tier1_features.py           # Tier 1: Feature Coverage (20 features x 5 tests = 100 tests)
├── test_tier2_boundaries.py         # Tier 2: Boundary & Corner Cases (20 features x 5 tests = 100 tests)
├── test_tier3_combinations.py       # Tier 3: Cross-Feature Combinations (>= 20 tests)
├── test_tier4_scenarios.py          # Tier 4: Real-World Application Scenarios (>= 10 tests)
└── run_all_e2e_tests.py             # Custom runner printing structured summary and tier metrics
```

---

## 4. Coverage Thresholds & Tier Breakdown

| Tier | Purpose | Requirement | Total Tests |
|---|---|---|---|
| **Tier 1: Feature Coverage** | Verify primary happy path and core behavior for all 20 features | $\ge 5$ test cases per feature across 20 features | **100 tests** |
| **Tier 2: Boundary & Corner Cases** | Stress extreme values, invalid inputs, edge boundaries, empty buffers, and noise | $\ge 5$ test cases per feature across 20 features | **100 tests** |
| **Tier 3: Cross-Feature Combinations** | Verify multi-feature pipelines, inter-module interfaces, and data flow | $\ge 20$ cross-feature integration test cases | **20 tests** |
| **Tier 4: Real-World Scenarios** | Simulate complete end-to-end player journeys, level playthroughs, and CLI workflows | $\ge 10$ full-pipeline scenario test cases | **10 tests** |
| **Total** | Full E2E Test Suite | Cumulative across all 4 tiers | **$\ge 230$ tests** |

---

## 5. Pass/Fail Criteria

1. **Pass Requirement**: 100% of all $\ge 230$ tests must pass (`failures = 0, errors = 0`).
2. **Exit Code**: The test runner returns exit code `0` on 100% pass, and non-zero exit code if any test fails.
3. **Execution Time**: The complete test suite executes within $< 60$ seconds on standard desktop hardware.
