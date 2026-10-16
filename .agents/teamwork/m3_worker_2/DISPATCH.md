## 2026-10-16T19:56:21Z

You are m3_worker_2, an implementation worker tasked with remediating the defects identified during Milestone 3 adversarial stress testing.
Your working directory is: c:\Users\david\Documents\micgame-3\.agents\teamwork\m3_worker_2\
The authoritative user specification is at: c:\Users\david\Documents\micgame-3\.agents\teamwork\ORIGINAL_REQUEST.md
The project index is at: c:\Users\david\Documents\micgame-3\PROJECT.md
Project root is: c:\Users\david\Documents\micgame-3

Adversarial Challenger Handoffs:
- Challenger 1 (ONNX buffer crash & t=0.0 onset drop): c:\Users\david\Documents\micgame-3\.agents\teamwork\m3_challenger_1\handoff.md
- Challenger 2 (WebSocket reconnect, JSON type guard, pop onsets): c:\Users\david\Documents\micgame-3\.agents\teamwork\m3_challenger_2\handoff.md

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Your write ownership (exclusive):
- `python/basic_pitch_onnx.py`
- `scripts/inference/websocket_driver.gd`
- `scripts/main.gd`

Your tasks:
1. Read ORIGINAL_REQUEST.md, PROJECT.md, and both challenger handoff reports.
2. In `python/basic_pitch_onnx.py`:
   - Fix 1: Guard against audio buffers < 256 samples in `infer_onsets_numpy()` and `predict_raw()`. If `len(audio_samples) < 256`, pad with zeros to at least 256 or return empty arrays gracefully without crashing on `np.maximum.reduce`.
   - Fix 2: In `transcribe_file()`, resolve the t=0.0 onset loss. When pre-roll zero padding is prepended to the audio, ensure the onset detection logic evaluates the boundary at frame 0 so notes starting at t=0.0 (like the first chord in Cadence Triads and downbeats in Bach Minuet) are accurately detected.
3. In `res://scripts/inference/websocket_driver.gd`:
   - Fix 3: In `poll()`, implement functional auto-reconnect: when `peer.get_ready_state() == WebSocketPeer.STATE_CLOSED` and `auto_reconnect == true`, increment `_reconnect_timer += delta` and call `connect_to_server()` once the reconnect interval has elapsed.
   - Fix 4: In `_parse_json_response()`, safely validate types: check `if parsed.get("pitches") is Array:` and `if parsed.get("onsets") is Array:` before iterating or assigning to prevent runtime type errors on malformed server payloads.
4. In `res://scripts/main.gd`:
   - Fix 5: In `_poll_pitch_model()`, use `model.pop_recent_onsets()` (or call `model.get_recent_onsets(true)`) so onsets are atomically cleared/consumed when read. This ensures notes are struck only once upon onset and prevents phantom double-hitting of consecutive notes at the same pitch.
5. VERIFICATION: You MUST execute all verification commands yourself:
   - `python tests/test_adversarial_m3.py` (Must pass all 21 tests with exit code 0)
   - `& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_adversarial_m3.gd"` (Must pass all 108 assertions with exit code 0)
   - `python tests/test_transcription_harness.py --min-f1 0.80` (Must pass all pieces with exit code 0)
   - `& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_inference_scoring_runner.gd"` (Must pass all 63 assertions with exit code 0)
   - `python tests/e2e/run_all_e2e_tests.py` (Must pass 230/230 with exit code 0)
6. Document your changes and verbatim command outputs in `handoff.md` and report back via send_message.
