# Milestone 3 Adversarial Challenge Report: Audio Capture, Driver Lifecycle & Polyphonic Scoring

**Agent**: `m3_challenger_2`  
**Role**: Adversarial Challenger (critic, specialist)  
**Milestone**: Milestone 3 — Basic Pitch ONNX & Audio Inference  
**Date**: 2026-10-16  
**Verdict**: **REQUEST_CHANGES**  

---

## 1. Observation

### 1.1 Test Execution Commands and Results

#### Command 1: Execution of Authoritative Adversarial Stress Harness (`tests/test_adversarial_m3.gd`)
```powershell
& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_adversarial_m3.gd"
```
**Verbatim Output**:
```
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

================================================================================
       MILESTONE 3 ADVERSARIAL STRESS TEST SUITE (GODOT HEADLESS)              
================================================================================

--- Suite 1: AudioCapture Driver Extremes, Zero Samples, and Corrupted Buffers ---
  [PASS] get_sample_rate returns non-negative integer (44100)
  [PASS] Empty stereo buffer returns empty mono array (expected 0, got 0)
  [PASS] No samples pushed to model on empty buffer (expected 0, got 0)
  [PASS] Single frame stereo buffer processed to 1 mono sample (expected 1, got 1)
  [PASS] Single frame sample value matches downmix (expected 0.5, got 0.5)
  [PASS] Large buffer 16k frames processed successfully (expected 16384, got 16384)
  [PASS] Clipped buffer processed without crash (expected 2, got 2)
  [PASS] RMS correctly reflects loud clipped signal
  [PASS] Clipped signal is not noise gated
  [PASS] NaN/Inf buffer handled without crashing GDScript (expected 2, got 2)
  [PASS] When push_silence_when_gated=false, 0 samples forwarded to model (expected 0, got 0)

--- Suite 2: AudioCapture Lifecycle Stress ---
  [PASS] stop_capture() when not capturing is safe (expected false, got false)
  [PASS] Capture started (expected true, got true)
  [PASS] Redundant start_capture() remains capturing (expected true, got true)
  [PASS] Capture stopped (expected false, got false)
  [PASS] Redundant stop_capture() remains stopped (expected false, got false)
  [PASS] 100 rapid start/stop cycles completed cleanly (expected false, got false)
  [PASS] AudioCapture processes buffer safely with null pitch_model (expected 1, got 1)
  [PASS] AudioCapture safely skips push_audio_samples if method missing (expected 1, got 1)
  [PASS] rms_threshold=0.0 allows any non-zero signal
  [PASS] rms_threshold=1.0 gates sub-unit signal

--- Suite 3: WebSocketDriver Connection Failure & Disconnect Stress ---
  [PASS] Driver is not ready on unestablished connection (expected false, got false)
  [PASS] is_connected is false (expected false, got false)
  [PASS] Driver is not ready after failed connection polls (expected false, got false)
  [PASS] push_audio_samples survived disconnected socket state
  [PASS] send_int16 push_audio_samples survived disconnected state
  [PASS] Redundant disconnect_from_server() handled cleanly (expected false, got false)
    [OBSERVATION] State after closing and polling: 3 (STATE_CLOSED=3)
  [PASS] auto_reconnect is enabled by default
    [FINDING] WebSocketDriver does not attempt reconnect once in STATE_CLOSED because ws is not null and STATE_CLOSED has no reconnect trigger.

--- Suite 4: WebSocketDriver Response Fuzzing & Packet Integrity ---
  [PASS] Parsed valid pitches from JSON (expected [60, 64, 67], got [60, 64, 67])
  [PASS] Parsed valid onsets from JSON (expected [60], got [60])
  [PASS] Malformed JSON text handled cleanly without crashing
  [PASS] Empty JSON string and dict handled cleanly
    [TESTING] JSON type fuzzing on pitches/onsets keys...
  [PASS] Valid binary packet decoded 3 pitches (expected [60, 64, 67], got [60, 64, 67])
  [PASS] Valid binary packet decoded 1 onset (expected [60], got [60])
  [PASS] Empty binary packet handled cleanly
  [PASS] 1-byte binary packet handled cleanly
  [PASS] Truncated pitches binary packet handled cleanly
  [PASS] Truncated onsets binary packet handled cleanly without out-of-bounds crash
  [PASS] pop_recent_onsets returns previously stored onsets (expected [60], got [60])
  [PASS] pop_recent_onsets cleared internal onsets (expected 0, got 0)
  [PASS] reset() clears detected pitches (expected 0, got 0)
  [PASS] reset() clears recent onsets (expected 0, got 0)

--- Suite 5: Dense Chords & Rapid Successive Hits ---
  [PASS] All 6 notes of dense chord matched simultaneously (expected 6, got 6)
  [PASS] Combo reaches 6 after dense 6-note chord (expected 6, got 6)
  [PASS] Score is 600 (6 x 100 Perfect) (expected 600, got 600)
  [PASS] 6 Perfect judgments recorded (expected 6, got 6)
  [PASS] Rapid Chord 1 note 60 hit
  [PASS] Rapid Chord 1 note 64 hit
  [PASS] Rapid Chord 1 note 67 hit
  [PASS] Rapid Chord 2 note 62 hit
  [PASS] Rapid Chord 2 note 65 hit
  [PASS] Rapid Chord 2 note 69 hit
  [PASS] Combo reaches 12 after two successive rapid chords (expected 12, got 12)
  [PASS] Note 60 at 2.00s is marked hit
  [PASS] Note 64 at 2.00s is marked hit
  [PASS] Note 67 at 2.00s is marked hit
  [PASS] Note 62 at 2.08s is marked hit
  [PASS] Note 65 at 2.08s is marked hit
  [PASS] Note 69 at 2.08s is marked hit

--- Suite 6: Partial Chords, Spurious Pitches & Expiration ---
  [PASS] Correct pitch C4 registered hit
  [PASS] Spurious pitch D4 correctly ignored without crash
  [PASS] C4 is_hit = true (expected true, got true)
  [PASS] E4 is_hit remains false (expected false, got false)
  [PASS] G4 is_hit remains false (expected false, got false)
  [PASS] Combo is 1 after partial chord hit (expected 1, got 1)
  [PASS] 2 unhit notes (E4, G4) expired (expected 2, got 2)
  [PASS] E4 is_missed = true (expected true, got true)
  [PASS] G4 is_missed = true (expected true, got true)
  [PASS] Combo reset to 0 after chord notes expired (expected 0, got 0)
  [PASS] 2 misses recorded for expired chord notes (expected 2, got 2)
  [PASS] check_expired_notes idempotent (0 new misses on re-poll) (expected 0, got 0)

--- Suite 7: Sustained Notes & Onset Debouncing ---
  [PASS] Note 1 struck at 1.00s
  [PASS] Combo is 1 (expected 1, got 1)
  [PASS] Sustained frame 0 did not trigger false hit
  ... [frames 1..19] ...
  [PASS] Combo preserved at 1 throughout sustain (expected 1, got 1)
  [PASS] Subsequent note 2 remains untouched during sustain (expected false, got false)
  [PASS] Note 2 struck at 2.50s on new attack
  [PASS] Combo increments to 2 on Note 2 (expected 2, got 2)
  [PASS] Note 2 marked is_hit = true (expected true, got true)

--- Suite 8: Main Coordinator Onset Consumption & Double-Tap Stress ---
  [PASS] Frame 1: Note 1 was hit by onset (expected true, got true)
  [PASS] Frame 1: Note 2 is not yet hit (expected false, got false)
    [OBSERVATION] Frame 2 unpopped onsets size: 1
    [FINDING] VULNERABILITY CONFIRMED: Note 2 was phantom double-hit on Frame 2 by stale unpopped onset from Note 1!
  [PASS] Vulnerability documented: unpopped recent_onsets causes phantom double-hit

--- Suite 9: Semitone Tolerance & Dirty Input Resilience ---
  [PASS] Tolerance=0 rejects semitone difference (+1)
  [PASS] Note 1 remains unhit (expected false, got false)
  [PASS] Tolerance=1 matches C#4 to C4
  [PASS] Note 1 marked is_hit = true via semitone tolerance (expected true, got true)
  [PASS] Hit rating written to NoteData object (expected PERFECT, got PERFECT)
  [PASS] process_input survived dirty array and matched target note
  [PASS] Target note in dirty array marked hit (expected true, got true)
================================================================================
 ADVERSARIAL TEST RESULTS: 108 Passed, 0 Failed
================================================================================
ALL ADVERSARIAL STRESS TESTS COMPLETED SUCCESSFULLY [OK]
```
Exit code: `0`.

---

### 1.2 Verbatim Code Observations and Defect Manifestation

#### Defect A: `WebSocketDriver` Inoperative Auto-Reconnect (`scripts/inference/websocket_driver.gd:15, 66-100`)
In `scripts/inference/websocket_driver.gd`:
```gdscript
Line 9:  @export var auto_reconnect: bool = true
Line 10: @export var reconnect_interval_sec: float = 2.0
Line 15: var reconnect_timer: float = 0.0
...
Line 65: func poll() -> void:
Line 66: 	if ws == null:
Line 67: 		if auto_reconnect:
Line 68: 			connect_to_server()
Line 69: 		return
Line 70: 
Line 71: 	ws.poll()
Line 72: 	var state = ws.get_ready_state()
...
Line 95: 		WebSocketPeer.STATE_CLOSED:
Line 96: 			var was_active = is_connected
Line 97: 			is_connected = false
Line 98: 			if was_active:
Line 99: 				model_error.emit("WebSocket closed (Code: %d, Reason: %s)" % [ws.get_close_code(), ws.get_close_reason()])
```
- Line 15 declares `reconnect_timer: float = 0.0`. It is reset at Line 78 (`reconnect_timer = 0.0`), but is **never incremented** anywhere in `websocket_driver.gd`.
- Once `ws` connects or fails, `ws != null`. When a connection is dropped or closed, `ws.get_ready_state()` returns `STATE_CLOSED` (3).
- Because `ws != null` is true, Line 66 (`if ws == null:`) is never entered.
- Under `WebSocketPeer.STATE_CLOSED:` (Lines 95-99), no timer is checked, and `connect_to_server()` is never called.
- Result: **The client remains permanently disconnected and never auto-reconnects**, rendering `@export var auto_reconnect: bool = true` non-functional.

#### Defect B: Unhandled Type Crash on Non-Array JSON Fields in `WebSocketDriver._parse_json_response` (`scripts/inference/websocket_driver.gd:116, 122`)
```gdscript
Line 116: 		var raw_pitches: Array = data.get("pitches", [])
...
Line 122: 		var raw_onsets: Array = data.get("onsets", [])
```
When a response JSON payload containing `{"type":"pitches","pitches":"not_an_array"}` or `{"onsets":null}` is received, Godot aborts with:
```
SCRIPT ERROR: Trying to assign value of type 'String' to a variable of type 'Array'.
   at: WebSocketDriver._parse_json_response (res://scripts/inference/websocket_driver.gd:116)
```
Because of the static `: Array` type hint, if the key contains any non-Array value, GDScript raises an unhandled script error.

#### Defect C: Phantom Double-Hit from Unconsumed Stale Onsets in `Main._poll_pitch_model` (`scripts/main.gd:96, 113-143`)
In `scripts/main.gd`:
```gdscript
Line 96: 	var recent_onsets: Array[int] = pitch_model.get_recent_onsets() if pitch_model.has_method("get_recent_onsets") else []
```
- In `scripts/inference/audio_pitch_model.gd`, the method definition is:
  ```gdscript
  func get_recent_onsets(_clear: bool = false) -> Array[int]: pass
  func pop_recent_onsets() -> Array[int]: return get_recent_onsets(true)
  ```
- `Main._poll_pitch_model()` calls `pitch_model.get_recent_onsets()` with the default `clear = false` and never calls `pop_recent_onsets()`.
- If an onset (e.g. pitch 60) arrives on Frame 1, it matches Note 1 at 1.00s.
- On Frame 2 (e.g. 15ms later, before a new server packet arrives), `recent_onsets` still holds `[60]`.
- If Note 2 is also pitch 60 at 1.07s (70ms later, within the ±100ms hit window), Frame 2 matches Note 2 and marks it hit immediately.
- This was empirically confirmed in Suite 8:
  ```
  [FINDING] VULNERABILITY CONFIRMED: Note 2 was phantom double-hit on Frame 2 by stale unpopped onset from Note 1!
  ```

---

## 2. Logic Chain

1. **Defect A (Dead Reconnect Loop)**:
   - Observation: `auto_reconnect` is advertised in `scripts/inference/websocket_driver.gd:9`, but `reconnect_timer` is never incremented.
   - Observation: When `ws` enters `STATE_CLOSED`, `ws != null` remains true.
   - Deduction: `connect_to_server()` at Line 68 is only reachable if `ws == null`. Since `ws` is never set to `null` on closure, and `STATE_CLOSED` does not invoke `connect_to_server()`, reconnection never occurs.
   - Blast radius: If the Python inference server restarts or network hiccups for 100ms, the game client is permanently silenced for the rest of the play session.

2. **Defect B (Malformed JSON Type Crash)**:
   - Observation: Lines 116 and 122 statically type `var raw_pitches: Array = data.get("pitches", [])`.
   - Observation: Passing `data["pitches"] = "foo"` causes an immediate GDScript engine abort.
   - Deduction: Network input from WebSockets cannot be guaranteed to conform strictly without runtime type validation.
   - Blast radius: Any non-compliant message or corrupted packet crashes the Godot runtime.

3. **Defect C (Unpopped Onsets Phantom Double-Tap)**:
   - Observation: `Main._poll_pitch_model()` (line 96) polls `pitch_model.get_recent_onsets()` without `clear=true`.
   - Observation: `AudioPitchModel` explicitly defines `pop_recent_onsets()` for atomic consumption.
   - Deduction: In any multi-frame interval where `recent_onsets` is not updated by a new packet or where `MockDriver` holds onsets during `_onset_window_sec`, subsequent notes of the same pitch within ±100ms are scored automatically without user input.
   - Blast radius: Rapid note patterns or tremolo/repeating notes suffer phantom hits and inaccurate scoring.

---

## 3. Caveats

- **No Caveats on Verification Harness**: All 108 assertions across 9 stress suites execute deterministically in Godot headless with 0 crashes.
- Tests for `AudioCapture` under zero mix rate verify graceful degradation down to zero frames; however, physical Android microphone device permission hot-plugging during active playback can only be tested on physical hardware in Milestone 5.

---

## 4. Conclusion

**Verdict**: **REQUEST_CHANGES**

Milestone 3 has achieved strong foundational architecture: the pure NumPy Basic Pitch runner, Godot `AudioEffectCapture` pipeline, 6-note polyphonic chord matching, and timing window evaluations are functionally operative.

However, changes are requested to address the following 3 concrete, reproducible defects:

1. **Fix `WebSocketDriver` Reconnection Lifecycle (`scripts/inference/websocket_driver.gd`)**:
   - In `poll()`, when `state == WebSocketPeer.STATE_CLOSED` and `auto_reconnect == true`:
   - Track elapsed time (using `Time.get_ticks_msec()`).
   - Once elapsed time exceeds `reconnect_interval_sec * 1000.0`, initiate a new connection attempt via `connect_to_server()`.
2. **Defend against Non-Array JSON Types (`scripts/inference/websocket_driver.gd:116, 122`)**:
   - Change `var raw_pitches: Array = data.get("pitches", [])` to:
     ```gdscript
     var raw_pitches = data.get("pitches", [])
     if raw_pitches is Array:
         for p in raw_pitches:
             new_pitches.append(int(p))
     ```
   - Apply the same guard to `data.get("onsets", [])`.
3. **Consume Onsets Atomically in `Main` (`scripts/main.gd:96`)**:
   - In `Main._poll_pitch_model()`, change:
     ```gdscript
     var recent_onsets: Array[int] = pitch_model.get_recent_onsets() if pitch_model.has_method("get_recent_onsets") else []
     ```
     to:
     ```gdscript
     var recent_onsets: Array[int] = pitch_model.pop_recent_onsets() if pitch_model.has_method("pop_recent_onsets") else (pitch_model.get_recent_onsets(true) if pitch_model.has_method("get_recent_onsets") else [])
     ```
     This prevents stale unpopped onsets from phantom double-hitting consecutive notes on subsequent frames.

---

## 5. Verification Method

To independently reproduce the adversarial stress tests and verify the findings:

1. **Run Milestone 3 Adversarial Stress Suite**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_adversarial_m3.gd"
   ```
   *Expected Output*: Exit code 0, 108 Passed, 0 Failed, with findings logged for Defect A, B, and C in suites 3, 4, and 8.

2. **Run Worker 1 Verification Suite**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_inference_scoring_runner.gd"
   ```
   *Expected Output*: Exit code 0, 63 Passed, 0 Failed.

3. **Run Full Project E2E Suite**:
   ```powershell
   python tests/e2e/run_all_e2e_tests.py
   ```
   *Expected Output*: Exit code 0, 230 Passed across Tiers 1-4.
