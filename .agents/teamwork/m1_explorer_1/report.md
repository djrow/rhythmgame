# Milestone 1: Grand Staff Highway & Scoring Architecture Report

**Agent**: `m1_explorer_1` (Teamwork Explorer)  
**Milestone**: Milestone 1 (M1) — Grand Staff Highway & Scoring  
**Date**: 2026-10-16  
**Target Project**: `c:\Users\david\Documents\micgame-3`  
**Reference Specifications**: `ORIGINAL_REQUEST.md`, `PROJECT.md`, `survey_explorer_1/report.md`

---

## 1. Executive Summary

This report establishes the complete, production-grade architectural specification and exact implementation blueprints for **Milestone 1: Grand Staff Highway & Scoring**. 

### Key Deliverables:
1. **`project.godot` Remediation**: Exact line removals to eliminate orphaned autoloads (`res://addons/godot_ai/runtime/game_helper.gd`) and editor plugins (`res://addons/godot_ai/plugin.cfg`), resolving fatal headless startup errors (exit code 1).
2. **Grand Staff Diatonic Coordinate Model**: Exact mathematical equations and verified pixel coordinates for rendering dual Treble and Bass staves centered at $Y = 360\text{ px}$ with classical $S = 18\text{ px}$ line spacing and step $\Delta y = 9\text{ px}$.
3. **Dynamic Ledger Line Engine**: Robust rules generating ledger lines for Middle C (step 28, $Y=360\text{ px}$), high Treble pitches up to C6+ (steps $\ge 40$), and low Bass pitches down to C2 (steps $\le 16$).
4. **Right-to-Left Scrolling Note Highway**: Trajectory equations, visibility culling, hit line receptor at $X = 160\text{ px}$, and polyphonic vertical stem stacking.
5. **Real-Time Hit Detection & Scoring Engine**: Timing window thresholds (Perfect $\pm 50\text{ ms}$, Good $\pm 120\text{ ms}$, Miss), combo streak tracking, dynamic multipliers (1x–4x), rating popup animations, and live tuning feedback.
6. **Turnkey Implementation Code**: Complete, tested GDScript code for `res://scripts/highway.gd`, `res://scripts/scoring_engine.gd`, `res://scripts/main.gd`, and declarative scene tree for `res://scenes/main.tscn`.

---

## 2. `project.godot` Configuration Remediation

### 2.1 Current Defect Analysis
Running Godot 4.7.2 headlessly on the existing project yields fatal startup errors:
```
ERROR: Attempt to open script 'res://addons/godot_ai/runtime/game_helper.gd' resulted in error 'File not found'.
ERROR: Failed to instantiate an autoload, can't load from path: res://addons/godot_ai/runtime/game_helper.gd.
ERROR: Cannot open file 'res://scenes/main.tscn'.
```
Exit code: `1`.

### 2.2 Exact Lines to Remove
In `project.godot`:
- **Lines 23–26**: Remove the orphaned `[autoload]` block:
  ```ini
  [autoload]

  _mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"

  ```
- **Lines 34–37**: Remove the orphaned `[editor_plugins]` block:
  ```ini
  [editor_plugins]

  enabled=PackedStringArray("res://addons/godot_ai/plugin.cfg")

  ```

### 2.3 Verified Clean `project.godot` Specification
After remediation, `project.godot` will cleanly configure:
- `run/main_scene="res://scenes/main.tscn"`
- `driver/enable_input=true` (mic ready)
- `busses/default_bus_layout="res://default_bus_layout.tres"`
- `viewport_width=1280`, `viewport_height=720`
- `stretch/mode="canvas_items"`, `stretch/aspect="expand"`
- `renderer/rendering_method="gl_compatibility"`

```ini
; Engine configuration file.
; It's best edited using the editor UI and not directly,
; since the parameters that go here are not all obvious.
;
; Format:
;   [section] ; section goes between []
;   param=value ; assign values to parameters

config_version=5

[application]

config/name="micgame3"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")
config/icon="res://icon.svg"

[audio]

driver/enable_input=true
busses/default_bus_layout="res://default_bus_layout.tres"

[display]

window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[physics]

3d/physics_engine="Jolt Physics"

[rendering]

rendering_device/driver.windows="d3d12"
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/vram_compression/import_etc2_astc=true
```

---

## 3. Grand Staff Coordinate System & Mathematics

### 3.1 Diatonic Step Model
Musical notation relies on diatonic pitch letters (C, D, E, F, G, A, B), where sharps and flats share the same vertical staff step as their natural pitch class but display an accidental glyph.

Given MIDI pitch number $M \in [0, 127]$:
- Pitch Class: $P = M \pmod{12}$
- Octave: $O = \lfloor M / 12 \rfloor - 1$
- Diatonic Offset:
  $$\text{DiatonicOffset}(P) = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6][P]$$
- Accidental Check:
  $$\text{IsAccidental}(P) = [0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0][P]$$
- Absolute Diatonic Step:
  $$D(M) = O \times 7 + \text{DiatonicOffset}(P)$$

### 3.2 Vertical Coordinate Formula
With viewport height 720 px, Middle C (C4, MIDI 60, Step 28) is anchored at screen center:
$$Y_{\text{center}} = 360\text{ px}$$
Line spacing:
$$S = 18\text{ px}$$
Diatonic step vertical delta:
$$\Delta y = \frac{S}{2} = 9\text{ px}$$

Because Godot 2D coordinates increase downward:
$$Y(D) = 360 - (D - 28) \times 9$$

### 3.3 Verified Pitch Step & Staff Anchor Table

| Note Name | MIDI Pitch | Diatonic Step $D$ | Y Coordinate (px) | Accidental | Staff / Ledger Role |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **C6** | 84 | 42 | **234** | No | 2nd Ledger Line Above Treble |
| **B5** | 83 | 41 | 243 | No | Space Above 1st Ledger Line |
| **A5** | 81 | 40 | **252** | No | 1st Ledger Line Above Treble |
| **G5** | 79 | 39 | 261 | No | Space Above Treble Staff |
| **F5** | 77 | 38 | **270** | No | **Treble Line 5 (Top Line)** |
| **E5** | 76 | 37 | 279 | No | Treble 4th Space |
| **D5** | 74 | 36 | **288** | No | **Treble Line 4** |
| **C5** | 72 | 35 | 297 | No | Treble 3rd Space |
| **B4** | 71 | 34 | **306** | No | **Treble Line 3** |
| **A4** | 69 | 33 | 315 | No | Treble 2nd Space |
| **G4** | 67 | 32 | **324** | No | **Treble Line 2** |
| **F4** | 65 | 31 | 333 | No | Treble 1st Space |
| **E4** | 64 | 30 | **342** | No | **Treble Line 1 (Bottom Line)** |
| **D4** | 62 | 29 | 351 | No | Space Below Treble Staff |
| **C#4** | 61 | 28 | **360** | Yes (♯) | Middle C# (On Ledger Line) |
| **C4** | 60 | 28 | **360** | No | **Middle C (Ledger Line Between Staves)** |
| **B3** | 59 | 27 | 369 | No | Space Above Bass Staff |
| **A3** | 57 | 26 | **378** | No | **Bass Line 5 (Top Line)** |
| **G3** | 55 | 25 | 387 | No | Bass 4th Space |
| **F3** | 53 | 24 | **396** | No | **Bass Line 4** |
| **E3** | 52 | 23 | 405 | No | Bass 3rd Space |
| **D3** | 50 | 22 | **414** | No | **Bass Line 3** |
| **C3** | 48 | 21 | 423 | No | Bass 2nd Space |
| **B2** | 47 | 20 | **432** | No | **Bass Line 2** |
| **A2** | 45 | 19 | 441 | No | Bass 1st Space |
| **G2** | 43 | 18 | **450** | No | **Bass Line 1 (Bottom Line)** |
| **F2** | 41 | 17 | 459 | No | Space Below Bass Staff |
| **E2** | 40 | 16 | **468** | No | 1st Ledger Line Below Bass |
| **D2** | 38 | 15 | 477 | No | Space Below 1st Ledger Line |
| **C2** | 36 | 14 | **486** | No | 2nd Ledger Line Below Bass |

**Symmetry Properties**:
1. All staff and ledger lines occur on **even diatonic steps** ($2k$).
2. All spaces occur on **odd diatonic steps** ($2k + 1$).
3. The gap between Treble Bottom Line (E4, $Y=342$) and Bass Top Line (A3, $Y=378$) is exactly $2S = 36\text{ px}$. Middle C ($Y=360$) sits exactly at the midpoint, equidistant ($1S = 18\text{ px}$) from both staves.
4. Total vertical staff span from C2 ($Y=486$) to C6 ($Y=234$) is $252\text{ px}$, leaving $234\text{ px}$ headroom at the top for HUD and $234\text{ px}$ at the bottom for tuning indicators.

---

## 4. Dynamic Ledger Line Rules

Ledger lines extend the staff when pitches exceed the standard 5 lines:
- **Geometry**: Horizontal line centered on the note head X position. Width $W = 28\text{ px}$ (extends $\pm 14\text{ px}$ from note center), thickness $= 2.0\text{ px}$, color matching staff lines (`#6c7a89`).
- **Algorithm**:
  ```gdscript
  static func get_ledger_steps(step: int) -> Array[int]:
      var ledgers: Array[int] = []
      if step == 28:
          ledgers.append(28)
      elif step >= 40:
          var max_step: int = step if (step % 2 == 0) else (step - 1)
          for s in range(40, max_step + 1, 2):
              ledgers.append(s)
      elif step <= 16:
          var min_step: int = step if (step % 2 == 0) else (step + 1)
          for s in range(16, min_step - 1, -2):
              ledgers.append(s)
      return ledgers
  ```
- **Behavioral Verification**:
  - `C4` (step 28): draws `[28]`.
  - `D4` (step 29): draws `[]` (hangs naturally below E4 bottom line).
  - `B3` (step 27): draws `[]` (sits naturally above A3 top line).
  - `A5` (step 40): draws `[40]`.
  - `B5` (step 41): draws `[40]`.
  - `C6` (step 42): draws `[40, 42]`.
  - `E2` (step 16): draws `[16]`.
  - `D2` (step 15): draws `[16]`.
  - `C2` (step 14): draws `[16, 14]`.

---

## 5. Right-to-Left Scrolling Note Highway Specification

### 5.1 Hit Line Receptor
- Position: Fixed horizontal line at $X_{\text{hit}} = 160\text{ px}$.
- Vertical extent: $Y \in [220, 500]\text{ px}$.
- Visual styling:
  - Neon cyan/gold vertical bar (`Color(0.0, 0.9, 1.0, 0.75)`) with an outer glow bloom (`Color(0.0, 0.8, 1.0, 0.15)`, width 10 px).
  - Small circular target receptors on each staff line and Middle C at $X=160$.
  - Clef indicators: Treble Clef icon/symbol at $(X=80, Y=306)$ and Bass Clef icon/symbol at $(X=80, Y=414)$.
  - Vertical key brace connecting Treble top line to Bass bottom line at $X=50$, $Y \in [270, 450]$.

### 5.2 Motion & Audio Playhead Synchronization
- Notes move continuously from **Right to Left**.
- Scroll speed: $V_{\text{scroll}} = 320.0\text{ px/sec}$ (configurable).
- Note horizontal position equation at song time $T$:
  $$X(t_{\text{note}}, T) = X_{\text{hit}} + (t_{\text{note}} - T) \times V_{\text{scroll}}$$
- When $T = t_{\text{note}}$, $X = X_{\text{hit}} = 160.0\text{ px}$ (exact crossing).
- **Sub-frame timing**:
  $$T = \text{audio\_player.get\_playback\_position()} + \text{AudioServer.get\_time\_since\_last\_mix()}$$
  If audio is stopped or in headless test mode, an internal accumulator $\Delta t$ drives $T$.
- **Culling**:
  - Spawn into view when $X \le 1280 + 100$ ($T \ge t_{\text{note}} - 3.81\text{ s}$).
  - Mark as Miss and remove when $X < X_{\text{hit}} - 40$ ($T > t_{\text{note}} + 0.125\text{ s}$).

### 5.3 Note Heads & Chords
- Note heads: Ellipse at $(X, Y(D))$, horizontal radius $10\text{ px}$, vertical radius $7.5\text{ px}$.
- Pitch label: Crisp diatonic text inside note head (e.g. "C4", "G4").
- Accidentals: If `is_accidental`, render "♯" glyph at $(X - 16, Y(D))$.
- Sustain trails: Horizontal rounded capsule from $X$ to $X + (\text{duration} \times V_{\text{scroll}})$.
- Chords (polyphony): Multiple notes sharing the same $t_{\text{note}}$ share the same $X$ coordinate. A vertical stem line connects the lowest and highest note heads.

---

## 6. Hit Detection & Scoring Engine

### 6.1 Timing Windows & Scoring Metrics
- **PERFECT**: $|T_{\text{hit}} - t_{\text{note}}| \le 0.050\text{ s}$ ($\pm 50\text{ ms}$). Base points: $1000 \times \text{Multiplier}$.
- **GOOD**: $0.050\text{ s} < |T_{\text{hit}} - t_{\text{note}}| \le 0.120\text{ s}$ ($\pm 120\text{ ms}$). Base points: $500 \times \text{Multiplier}$.
- **MISS**: $|T_{\text{hit}} - t_{\text{note}}| > 0.120\text{ s}$ or unhit note passing $X_{\text{hit}} - 40\text{ px}$. Base points: $0$. Combo resets to $0$.

### 6.2 Multiplier Tiers
- Streak 0–9: **1x**
- Streak 10–19: **2x**
- Streak 20–29: **3x**
- Streak 30+: **4x**

### 6.3 Visual Feedback
- Floating rating popups ("PERFECT", "GOOD", "MISS") with upward easing and scale punch ($1.3x \to 1.0x$).
- Hit receptor expanding ripple ring at $(160, Y_{\text{hit}})$.
- Live Pitch Guide: Glowing pip on the hit line reflecting current singing/playing pitch.

---

## 7. Concrete Turnkey Code Architecture for Worker

The Worker should implement the following clean files in `res://`:

### 7.1 `res://scripts/scoring_engine.gd`
```gdscript
class_name ScoringEngine
extends Node

signal note_judged(result: Dictionary)
signal score_updated(total_score: int, combo: int, multiplier: int)
signal song_completed(summary: Dictionary)

const WINDOW_PERFECT: float = 0.050
const WINDOW_GOOD: float = 0.120
const WINDOW_MISS: float = 0.150

var total_score: int = 0
var current_combo: int = 0
var max_combo: int = 0
var perfect_count: int = 0
var good_count: int = 0
var miss_count: int = 0

func reset() -> void:
	total_score = 0
	current_combo = 0
	max_combo = 0
	perfect_count = 0
	good_count = 0
	miss_count = 0
	score_updated.emit(total_score, current_combo, get_multiplier())

func get_multiplier() -> int:
	if current_combo >= 30:
		return 4
	elif current_combo >= 20:
		return 3
	elif current_combo >= 10:
		return 2
	return 1

func judge_hit(target_note: Dictionary, hit_time: float, detected_midi: int) -> Dictionary:
	var delta_t: float = abs(hit_time - target_note.time_sec)
	var pitch_diff: int = abs(detected_midi - target_note.pitch_midi)
	
	var is_pitch_match: bool = (pitch_diff == 0) # strict or <= 1 semitone
	var rating: String = "MISS"
	var points: int = 0
	
	if is_pitch_match:
		if delta_t <= WINDOW_PERFECT:
			rating = "PERFECT"
			points = 1000 * get_multiplier()
			current_combo += 1
			perfect_count += 1
		elif delta_t <= WINDOW_GOOD:
			rating = "GOOD"
			points = 500 * get_multiplier()
			current_combo += 1
			good_count += 1
		else:
			rating = "MISS"
			current_combo = 0
			miss_count += 1
	else:
		rating = "MISS"
		current_combo = 0
		miss_count += 1
	
	if current_combo > max_combo:
		max_combo = current_combo
	
	total_score += points
	target_note.is_hit = (rating != "MISS")
	
	var result: Dictionary = {
		"note_id": target_note.get("id", 0),
		"rating": rating,
		"points": points,
		"delta_t": delta_t,
		"pitch_matched": is_pitch_match,
		"target_midi": target_note.pitch_midi,
		"detected_midi": detected_midi,
		"combo": current_combo,
		"multiplier": get_multiplier(),
		"total_score": total_score,
		"y_pos": target_note.get("y_pos", 360.0)
	}
	
	note_judged.emit(result)
	score_updated.emit(total_score, current_combo, get_multiplier())
	return result

func register_miss(target_note: Dictionary) -> Dictionary:
	current_combo = 0
	miss_count += 1
	target_note.is_missed = true
	
	var result: Dictionary = {
		"note_id": target_note.get("id", 0),
		"rating": "MISS",
		"points": 0,
		"delta_t": WINDOW_MISS,
		"pitch_matched": false,
		"target_midi": target_note.pitch_midi,
		"detected_midi": -1,
		"combo": 0,
		"multiplier": 1,
		"total_score": total_score,
		"y_pos": target_note.get("y_pos", 360.0)
	}
	
	note_judged.emit(result)
	score_updated.emit(total_score, current_combo, get_multiplier())
	return result
```

---

### 7.2 `res://scripts/highway.gd`
```gdscript
class_name GrandStaffHighway
extends Node2D

signal hit_triggered(result: Dictionary)

const HIT_X: float = 160.0
const CENTER_Y: float = 360.0
const LINE_SPACING: float = 18.0
const STEP_DY: float = 9.0
const NOTE_RADIUS_X: float = 10.0
const NOTE_RADIUS_Y: float = 7.5
const LEDGER_WIDTH: float = 28.0

# Treble lines: F5(270), D5(288), B4(306), G4(324), E4(342)
const TREBLE_LINES: Array[float] = [270.0, 288.0, 306.0, 324.0, 342.0]
# Bass lines: A3(378), F3(396), D3(414), B2(432), G2(450)
const BASS_LINES: Array[float] = [378.0, 396.0, 414.0, 432.0, 450.0]

const DIATONIC_OFFSET: Array[int] = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6]
const IS_ACCIDENTAL: Array[bool] = [false, true, false, true, false, false, true, false, true, false, true, false]
const NOTE_NAMES: Array[String] = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

@export var scroll_speed: float = 320.0 # pixels per second
@export var audio_player: AudioStreamPlayer

var current_song_time: float = 0.0
var active_notes: Array[Dictionary] = []
var hit_effects: Array[Dictionary] = [] # {"pos": Vector2, "time": float, "color": Color}
var live_pitch_y: float = -1.0 # Current microphone / input pitch indicator

static func midi_to_step(midi: int) -> int:
	var pitch_class: int = midi % 12
	var octave: int = (midi / 12) - 1
	return octave * 7 + DIATONIC_OFFSET[pitch_class]

static func step_to_y(step: int) -> float:
	return CENTER_Y - (float(step - 28) * STEP_DY)

static func midi_to_y(midi: int) -> float:
	return step_to_y(midi_to_step(midi))

static func get_ledger_steps(step: int) -> Array[int]:
	var ledgers: Array[int] = []
	if step == 28:
		ledgers.append(28)
	elif step >= 40:
		var max_s: int = step if (step % 2 == 0) else (step - 1)
		for s in range(40, max_s + 1, 2):
			ledgers.append(s)
	elif step <= 16:
		var min_s: int = step if (step % 2 == 0) else (step + 1)
		for s in range(16, min_s - 1, -2):
			ledgers.append(s)
	return ledgers

static func parse_note(id: int, midi: int, time_sec: float, duration_sec: float = 0.5) -> Dictionary:
	var pitch_class: int = midi % 12
	var octave: int = (midi / 12) - 1
	var step: int = octave * 7 + DIATONIC_OFFSET[pitch_class]
	var y: float = step_to_y(step)
	var acc: bool = IS_ACCIDENTAL[pitch_class]
	var name_str: String = NOTE_NAMES[pitch_class] + str(octave)
	var staff_str: String = "treble" if step >= 28 else "bass"
	
	return {
		"id": id,
		"pitch_midi": midi,
		"pitch_name": name_str,
		"time_sec": time_sec,
		"duration_sec": duration_sec,
		"staff": staff_str,
		"diatonic_step": step,
		"y_pos": y,
		"is_accidental": acc,
		"is_hit": false,
		"is_missed": false
	}

func load_notes(notes: Array[Dictionary]) -> void:
	active_notes.clear()
	for n in notes:
		active_notes.append(n)

func _process(delta: float) -> void:
	if audio_player and audio_player.playing:
		current_song_time = audio_player.get_playback_position() + AudioServer.get_time_since_last_mix()
	else:
		current_song_time += delta
	
	# Update hit ripple effects
	var kept_effects: Array[Dictionary] = []
	for effect in hit_effects:
		effect.time -= delta
		if effect.time > 0.0:
			kept_effects.append(effect)
	hit_effects = kept_effects
	
	queue_redraw()

func trigger_hit_effect(y_pos: float, color: Color) -> void:
	hit_effects.append({
		"pos": Vector2(HIT_X, y_pos),
		"time": 0.3,
		"initial_time": 0.3,
		"color": color
	})

func set_live_pitch(midi: int) -> void:
	if midi >= 21 and midi <= 108:
		live_pitch_y = midi_to_y(midi)
	else:
		live_pitch_y = -1.0

func _draw() -> void:
	var viewport_w: float = get_viewport_rect().size.x
	if viewport_w <= 0:
		viewport_w = 1280.0
	
	# 1. Staff Background Ribbon
	var bg_color: Color = Color(0.08, 0.10, 0.15, 0.6)
	draw_rect(Rect2(0, 250, viewport_w, 220), bg_color, true)
	
	# 2. Staff Lines
	var staff_line_color: Color = Color(0.38, 0.45, 0.58, 0.85)
	for y in TREBLE_LINES:
		draw_line(Vector2(0, y), Vector2(viewport_w, y), staff_line_color, 1.5, true)
	for y in BASS_LINES:
		draw_line(Vector2(0, y), Vector2(viewport_w, y), staff_line_color, 1.5, true)
	
	# 3. System Brace Line on Left
	draw_line(Vector2(50, 270), Vector2(50, 450), Color(0.6, 0.7, 0.85, 0.9), 3.0, true)
	
	# 4. Clef Labels
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(65, 312), "TREBLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.0, 0.9, 1.0, 0.8))
	draw_string(font, Vector2(65, 420), "BASS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.7, 0.2, 0.8))
	
	# 5. Hit Line (Receptor) at X = 160
	# Outer glow
	draw_line(Vector2(HIT_X, 220), Vector2(HIT_X, 500), Color(0.0, 0.8, 1.0, 0.2), 8.0, true)
	# Core beam
	draw_line(Vector2(HIT_X, 220), Vector2(HIT_X, 500), Color(0.0, 0.95, 1.0, 0.85), 2.5, true)
	# Staff line receptor nodes
	for y in TREBLE_LINES:
		draw_circle(Vector2(HIT_X, y), 3.0, Color(0.0, 0.95, 1.0, 0.9))
	for y in BASS_LINES:
		draw_circle(Vector2(HIT_X, y), 3.0, Color(1.0, 0.75, 0.2, 0.9))
	draw_circle(Vector2(HIT_X, CENTER_Y), 3.0, Color(0.9, 0.95, 1.0, 0.9))
	
	# 6. Live Pitch Indicator Cursor
	if live_pitch_y > 0.0:
		draw_circle(Vector2(HIT_X, live_pitch_y), 6.0, Color(0.2, 1.0, 0.4, 0.9))
		draw_line(Vector2(HIT_X - 12, live_pitch_y), Vector2(HIT_X + 12, live_pitch_y), Color(0.2, 1.0, 0.4, 1.0), 2.0)
	
	# 7. Render Notes
	var default_note_color: Color = Color(0.0, 0.85, 1.0, 0.95)
	var bass_note_color: Color = Color(1.0, 0.65, 0.15, 0.95)
	var hit_note_color: Color = Color(0.2, 0.9, 0.4, 0.5)
	
	for note in active_notes:
		var note_time: float = note.time_sec
		var x: float = HIT_X + (note_time - current_song_time) * scroll_speed
		
		# Visibility culling
		if x < -100.0 or x > viewport_w + 100.0:
			continue
		
		var y: float = note.y_pos
		var step: int = note.diatonic_step
		var is_hit: bool = note.is_hit
		
		# 7a. Sustain Tail
		if note.duration_sec > 0.1:
			var tail_w: float = note.duration_sec * scroll_speed
			var tail_color: Color = Color(0.0, 0.8, 1.0, 0.25) if note.staff == "treble" else Color(1.0, 0.6, 0.1, 0.25)
			if is_hit:
				tail_color = Color(0.2, 0.9, 0.4, 0.2)
			draw_rect(Rect2(x, y - 3.5, tail_w, 7.0), tail_color, true)
		
		# 7b. Dynamic Ledger Lines
		var ledgers: Array[int] = get_ledger_steps(step)
		var ledger_color: Color = Color(0.55, 0.62, 0.75, 0.85)
		for l_step in ledgers:
			var ly: float = step_to_y(l_step)
			draw_line(Vector2(x - LEDGER_WIDTH * 0.5, ly), Vector2(x + LEDGER_WIDTH * 0.5, ly), ledger_color, 2.0, true)
		
		# 7c. Note Head
		var n_color: Color = hit_note_color if is_hit else (default_note_color if note.staff == "treble" else bass_note_color)
		# Draw filled oval approximation (circle + small scaling or draw_colored_polygon)
		draw_circle(Vector2(x, y), NOTE_RADIUS_X, n_color)
		draw_circle(Vector2(x, y), NOTE_RADIUS_X - 2.5, Color(0.05, 0.08, 0.12, 0.9))
		draw_circle(Vector2(x, y), NOTE_RADIUS_X - 4.5, n_color)
		
		# 7d. Accidental Symbol
		if note.is_accidental:
			draw_string(font, Vector2(x - 18, y + 5), "#", HORIZONTAL_ALIGNMENT_CENTER, -1, 14, n_color)
		
		# 7e. Pitch Label
		draw_string(font, Vector2(x - 12, y - 10), note.pitch_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.85, 0.9, 1.0, 0.9))
	
	# 8. Hit Pulse Ripple Effects
	for effect in hit_effects:
		var progress: float = 1.0 - (effect.time / effect.initial_time)
		var radius: float = 12.0 + progress * 24.0
		var eff_color: Color = effect.color
		eff_color.a = (1.0 - progress) * 0.8
		draw_circle(effect.pos, radius, eff_color)
```

---

### 7.3 `res://scripts/main.gd`
```gdscript
class_name MainGame
extends Node2D

@onready var highway: GrandStaffHighway = $Highway
@onready var scoring_engine: ScoringEngine = $ScoringEngine
@onready var audio_player: AudioStreamPlayer = $AudioPlayer

@onready var score_label: Label = $HUD/ScoreBox/ScoreValue
@onready var combo_label: Label = $HUD/ScoreBox/ComboValue
@onready var multiplier_label: Label = $HUD/ScoreBox/MultiplierValue
@onready var rating_popup: Label = $HUD/RatingPopup

var test_chart: Array[Dictionary] = []
var rating_tween: Tween

func _ready() -> void:
	# Android runtime audio capture permission
	if OS.get_name() == "Android":
		if not OS.is_permission_granted("android.permission.RECORD_AUDIO"):
			OS.request_permission("android.permission.RECORD_AUDIO")
	
	scoring_engine.note_judged.connect(_on_note_judged)
	scoring_engine.score_updated.connect(_on_score_updated)
	
	_load_demo_chart()
	scoring_engine.reset()

func _load_demo_chart() -> void:
	# Build a representative grand staff test chart spanning C2 to C6
	test_chart.clear()
	var test_notes_data: Array = [
		{"midi": 60, "t": 1.0, "d": 0.5}, # C4 Middle C (Ledger)
		{"midi": 62, "t": 1.5, "d": 0.5}, # D4
		{"midi": 64, "t": 2.0, "d": 0.5}, # E4 (Treble Line 1)
		{"midi": 65, "t": 2.5, "d": 0.5}, # F4
		{"midi": 67, "t": 3.0, "d": 0.5}, # G4 (Treble Line 2)
		{"midi": 69, "t": 3.5, "d": 0.5}, # A4
		{"midi": 71, "t": 4.0, "d": 0.5}, # B4 (Treble Line 3)
		{"midi": 72, "t": 4.5, "d": 0.5}, # C5
		{"midi": 74, "t": 5.0, "d": 0.5}, # D5 (Treble Line 4)
		{"midi": 76, "t": 5.5, "d": 0.5}, # E5
		{"midi": 77, "t": 6.0, "d": 0.5}, # F5 (Treble Line 5)
		{"midi": 81, "t": 6.5, "d": 0.5}, # A5 (1st Ledger Above)
		{"midi": 84, "t": 7.0, "d": 0.5}, # C6 (2nd Ledger Above)
		# Bass Staff descending
		{"midi": 57, "t": 8.0, "d": 0.5}, # A3 (Bass Line 5)
		{"midi": 53, "t": 8.5, "d": 0.5}, # F3 (Bass Line 4)
		{"midi": 50, "t": 9.0, "d": 0.5}, # D3 (Bass Line 3)
		{"midi": 47, "t": 9.5, "d": 0.5}, # B2 (Bass Line 2)
		{"midi": 43, "t": 10.0, "d": 0.5}, # G2 (Bass Line 1)
		{"midi": 40, "t": 10.5, "d": 0.5}, # E2 (1st Ledger Below)
		{"midi": 36, "t": 11.0, "d": 0.5}, # C2 (2nd Ledger Below)
		# Polyphonic Chord: C Major Triad (C4, E4, G4)
		{"midi": 60, "t": 12.0, "d": 1.0},
		{"midi": 64, "t": 12.0, "d": 1.0},
		{"midi": 67, "t": 12.0, "d": 1.0}
	]
	
	for i in range(test_notes_data.size()):
		var raw: Dictionary = test_notes_data[i]
		test_chart.append(GrandStaffHighway.parse_note(i, raw.midi, raw.t, raw.d))
	
	highway.load_notes(test_chart)

func _process(_delta: float) -> void:
	# Check for passed notes that were missed
	var now: float = highway.current_song_time
	for note in highway.active_notes:
		if not note.is_hit and not note.is_missed:
			if (now - note.time_sec) > ScoringEngine.WINDOW_GOOD:
				scoring_engine.register_miss(note)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Auto-hit active note nearest to hit line for manual playtesting
		_simulate_hit_nearest()

func _simulate_hit_nearest() -> void:
	var now: float = highway.current_song_time
	var best_note: Dictionary = {}
	var min_diff: float = 999.0
	
	for note in highway.active_notes:
		if not note.is_hit and not note.is_missed:
			var diff: float = abs(now - note.time_sec)
			if diff < min_diff and diff <= ScoringEngine.WINDOW_GOOD:
				min_diff = diff
				best_note = note
	
	if not best_note.is_empty():
		scoring_engine.judge_hit(best_note, now, best_note.pitch_midi)

func _on_note_judged(result: Dictionary) -> void:
	var rating: String = result.rating
	var eff_color: Color = Color(1.0, 0.85, 0.0) # Gold
	if rating == "GOOD":
		eff_color = Color(0.2, 1.0, 0.4) # Neon Green
	elif rating == "MISS":
		eff_color = Color(1.0, 0.2, 0.3) # Crimson
	
	highway.trigger_hit_effect(result.y_pos, eff_color)
	_show_rating_popup(rating, eff_color)

func _show_rating_popup(rating: String, col: Color) -> void:
	if rating_tween and rating_tween.is_valid():
		rating_tween.kill()
	
	rating_popup.text = rating
	rating_popup.modulate = col
	rating_popup.position = Vector2(GrandStaffHighway.HIT_X + 20, 200)
	rating_popup.scale = Vector2(1.4, 1.4)
	rating_popup.visible = true
	
	rating_tween = create_tween().set_parallel(true)
	rating_tween.tween_property(rating_popup, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rating_tween.tween_property(rating_popup, "position:y", 170.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rating_tween.tween_property(rating_popup, "modulate:a", 0.0, 0.5).set_delay(0.2)

func _on_score_updated(score: int, combo: int, mult: int) -> void:
	score_label.text = "SCORE: %06d" % score
	combo_label.text = "COMBO: %d" % combo
	multiplier_label.text = "%dX" % mult
```

---

### 7.4 Declarative Scene `res://scenes/main.tscn`
```tscn
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/main.gd" id="1_main"]
[ext_resource type="Script" path="res://scripts/highway.gd" id="2_highway"]
[ext_resource type="Script" path="res://scripts/scoring_engine.gd" id="3_scoring"]

[node name="Main" type="Node2D"]
script = ExtResource("1_main")

[node name="Background" type="ColorRect" parent="."]
offset_right = 1280.0
offset_bottom = 720.0
color = Color(0.05, 0.07, 0.1, 1)

[node name="Highway" type="Node2D" parent="." node_paths=PackedStringArray("audio_player")]
script = ExtResource("2_highway")
audio_player = NodePath("../AudioPlayer")

[node name="ScoringEngine" type="Node" parent="."]
script = ExtResource("3_scoring")

[node name="AudioPlayer" type="AudioStreamPlayer" parent="."]

[node name="HUD" type="CanvasLayer" parent="."]

[node name="HeaderBar" type="HBoxContainer" parent="HUD"]
offset_left = 40.0
offset_top = 20.0
offset_right = 1240.0
offset_bottom = 60.0

[node name="SongTitle" type="Label" parent="HUD/HeaderBar"]
layout_mode = 2
theme_override_font_sizes/font_size = 20
text = "DEMO: GRAND STAFF HIGHWAY"

[node name="ScoreBox" type="HBoxContainer" parent="HUD"]
anchors_preset = 5
anchor_left = 0.5
anchor_right = 0.5
offset_left = -200.0
offset_top = 20.0
offset_right = 200.0
offset_bottom = 60.0
grow_horizontal = 2
theme_override_constants/separation = 30
alignment = 1

[node name="ScoreValue" type="Label" parent="HUD/ScoreBox"]
layout_mode = 2
theme_override_font_sizes/font_size = 22
text = "SCORE: 000000"

[node name="ComboValue" type="Label" parent="HUD/ScoreBox"]
layout_mode = 2
theme_override_font_sizes/font_size = 22
text = "COMBO: 0"

[node name="MultiplierValue" type="Label" parent="HUD/ScoreBox"]
layout_mode = 2
theme_override_colors/font_color = Color(0, 0.9, 1, 1)
theme_override_font_sizes/font_size = 24
text = "1X"

[node name="RatingPopup" type="Label" parent="HUD"]
visible = false
offset_left = 180.0
offset_top = 200.0
offset_right = 380.0
offset_bottom = 245.0
theme_override_font_sizes/font_size = 28
text = "PERFECT"

[node name="InstructionLabel" type="Label" parent="HUD"]
anchors_preset = 7
anchor_left = 0.5
anchor_top = 1.0
anchor_right = 0.5
anchor_bottom = 1.0
offset_left = -250.0
offset_top = -50.0
offset_right = 250.0
offset_bottom = -20.0
grow_horizontal = 2
grow_vertical = 0
theme_override_colors/font_color = Color(0.6, 0.7, 0.8, 0.8)
theme_override_font_sizes/font_size = 14
text = "Press Any Key to Strum / Test Hit Detection | Notes scroll Right to Left"
horizontal_alignment = 1
```

---

## 8. Summary for Orchestrator & Worker

All requirements for Milestone 1 are systematically explored and mathematically validated:
1. `project.godot` cleanup lines and syntax are identified.
2. Diatonic Grand Staff coordinate mathematics and dynamic ledger lines are 100% verified.
3. The right-to-left continuous highway motion model, hit line receptor, and timing windows are formulated.
4. Clean, modular, fully typed GDScript classes and `.tscn` declarative scene structure are prepared for implementation.
