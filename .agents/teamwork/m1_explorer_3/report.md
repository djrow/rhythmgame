# Milestone 1 Hit Detection, Scoring Engine & UI Feedback Exploration Report

**Author**: `m1_explorer_3` (Teamwork Explorer)  
**Date**: 2026-10-16  
**Scope**: Hit detection, timing windows, combo multipliers, scoring logic, UI feedback animations, and headless test runner for Milestone 1.  
**Target Engine**: Godot v4.7.2.stable.official.ed1daf0bf  

---

## 1. Executive Summary

This report establishes the complete architecture and production-ready GDScript code for the **Hit Detection & Scoring Engine**, **HUD & Visual Judgment Feedback**, and the automated **Headless Verification Runner** (`test_scoring_runner.gd`).

All scoring algorithms, timing windows, multiplier thresholds, and chord/pitch matching rules have been physically prototyped and executed headlessly in Godot 4.7.2, achieving **91 passed assertions, 0 failures, and exit code 0**.

### Key Specifications & Formulas

| Component | Rule / Formula | Details |
| :--- | :--- | :--- |
| **Timing Window: PERFECT** | $|\Delta t| \le 50\text{ ms}$ ($0.050\text{ s}$) | Base: 100 pts $\times$ Multiplier. Increments combo streak. |
| **Timing Window: GOOD** | $50\text{ ms} < |\Delta t| \le 100\text{ ms}$ ($0.100\text{ s}$) | Base: 50 pts $\times$ Multiplier. Increments combo streak. |
| **Timing Window: MISS** | $|\Delta t| > 100\text{ ms}$ ($0.100\text{ s}$) | Base: 0 pts. Resets combo to 0. Resets multiplier to 1x. |
| **Expired Notes** | $T_{\text{current}} > t_{\text{note}} + 0.100\text{ s}$ | Auto-awarded MISS, resets combo streak. |
| **Multiplier: 1x** | $0 \le \text{Combo} \le 9$ | Base points $\times 1$ |
| **Multiplier: 2x** | $10 \le \text{Combo} \le 19$ | Base points $\times 2$ |
| **Multiplier: 3x** | $20 \le \text{Combo} \le 29$ | Base points $\times 3$ |
| **Multiplier: 4x** | $\text{Combo} \ge 30$ | Base points $\times 4$ (Capped at 4x) |
| **Accuracy Formula** | $\frac{\text{Perfect} \times 1.0 + \text{Good} \times 0.5}{\text{Total Notes}} \times 100\%$ | Weighted accuracy percentage |

---

## 2. Decoupled Architecture

The scoring subsystem is architected into 4 cleanly decoupled components:

```
+------------------------------------------------------------------------+
|                          MAIN / HIGHWAY LOOP                           |
+------------------------------------------------------------------------+
           |                                             |
           | (Input pitch / timestamp)                   | (Frame delta / playhead)
           v                                             v
+-----------------------+                    +---------------------------+
|     SCORING ENGINE    |                    |          HIGHWAY          |
| (Pure RefCounted GD)  |                    | (Receptor Pulse & Ripple) |
+-----------------------+                    +---------------------------+
           |                                             ^
           | Signals:                                    |
           | - judgment_recorded(judgment, pts, ...) ----+
           | - score_changed(new_score)
           | - combo_changed(new_combo, multiplier)
           v
+------------------------------------------------------------------------+
|                                HUD UI                                  |
|   - Floating judgment popups ("PERFECT!", "GOOD!", "MISS")             |
|   - Animated score punch / tween interpolation                         |
|   - Combo counter bounce animation                                     |
|   - Multiplier badge with tiered colors (Silver, Cyan, Orange, Gold)   |
+------------------------------------------------------------------------+
```

---

## 3. Production Code Implementations

### 3.1 Scoring Engine: `res://scripts/scoring_engine.gd`

```gdscript
# res://scripts/scoring_engine.gd
class_name ScoringEngine
extends RefCounted

## Hit detection, timing windows, combo multipliers, and scoring engine.

# Timing Windows (seconds)
const WINDOW_PERFECT_SEC: float = 0.050  # +/- 50ms
const WINDOW_GOOD_SEC: float = 0.100     # +/- 100ms

# Base Points
const POINTS_PERFECT: int = 100
const POINTS_GOOD: int = 50
const POINTS_MISS: int = 0

# Multiplier Combo Thresholds
const COMBO_2X: int = 10
const COMBO_3X: int = 20
const COMBO_4X: int = 30

# Session State
var score: int = 0
var combo: int = 0
var max_combo: int = 0
var count_perfect: int = 0
var count_good: int = 0
var count_miss: int = 0
var total_notes: int = 0

# Signals
signal judgment_recorded(judgment: String, points: int, current_score: int, current_combo: int, current_multiplier: int, note_data: Dictionary)
signal score_changed(new_score: int)
signal combo_changed(new_combo: int, new_multiplier: int)

func reset() -> void:
	score = 0
	combo = 0
	max_combo = 0
	count_perfect = 0
	count_good = 0
	count_miss = 0
	total_notes = 0

func get_multiplier() -> int:
	if combo >= COMBO_4X:
		return 4
	elif combo >= COMBO_3X:
		return 3
	elif combo >= COMBO_2X:
		return 2
	else:
		return 1

func evaluate_timing(time_diff_sec: float) -> String:
	var abs_diff = abs(time_diff_sec)
	if abs_diff <= WINDOW_PERFECT_SEC:
		return "PERFECT"
	elif abs_diff <= WINDOW_GOOD_SEC:
		return "GOOD"
	else:
		return "MISS"

func register_hit(judgment: String, note_data: Dictionary = {}) -> Dictionary:
	total_notes += 1
	var base_pts: int = 0
	
	if judgment == "PERFECT":
		count_perfect += 1
		combo += 1
		base_pts = POINTS_PERFECT
	elif judgment == "GOOD":
		count_good += 1
		combo += 1
		base_pts = POINTS_GOOD
	elif judgment == "MISS":
		count_miss += 1
		combo = 0
		base_pts = POINTS_MISS
	else:
		push_warning("Unknown judgment: " + judgment)
		return {}

	if combo > max_combo:
		max_combo = combo

	var mult = get_multiplier()
	var points_awarded = base_pts * mult
	score += points_awarded

	var result = {
		"judgment": judgment,
		"base_points": base_pts,
		"multiplier": mult,
		"points_awarded": points_awarded,
		"score": score,
		"combo": combo,
		"max_combo": max_combo,
		"note_data": note_data
	}

	judgment_recorded.emit(judgment, points_awarded, score, combo, mult, note_data)
	score_changed.emit(score)
	combo_changed.emit(combo, mult)

	return result

func register_miss(note_data: Dictionary = {}) -> Dictionary:
	return register_hit("MISS", note_data)

## Matches incoming pitch and timestamp against active notes on the highway.
## Note dictionary keys: { "pitch_midi": int, "time_sec": float, "duration_sec": float, "is_hit": bool }
func process_input(input_time: float, pitch_midi: int, notes: Array, semitone_tolerance: int = 0) -> Dictionary:
	var best_index: int = -1
	var min_abs_diff: float = 9999.0
	
	for i in range(notes.size()):
		var note = notes[i]
		if note.get("is_hit", false):
			continue
		
		var note_pitch: int = int(note.get("pitch_midi", 0))
		if abs(note_pitch - pitch_midi) > semitone_tolerance:
			continue
		
		var time_diff = input_time - float(note.get("time_sec", 0.0))
		var abs_diff = abs(time_diff)
		
		# Must be within hit window (+/- 100ms)
		if abs_diff <= WINDOW_GOOD_SEC and abs_diff < min_abs_diff:
			min_abs_diff = abs_diff
			best_index = i
	
	if best_index != -1:
		var target_note = notes[best_index]
		var time_diff = input_time - float(target_note.get("time_sec", 0.0))
		var judgment = evaluate_timing(time_diff)
		target_note["is_hit"] = true
		target_note["hit_time"] = input_time
		target_note["hit_diff"] = time_diff
		target_note["judgment"] = judgment
		
		var result = register_hit(judgment, target_note)
		result["matched_note_index"] = best_index
		result["time_diff"] = time_diff
		return result
	
	return {}

## Evaluates active notes passing beyond the hit window (+100ms) without being hit.
## Triggers MISS and resets combo.
func check_expired_notes(current_time: float, notes: Array) -> Array:
	var expired_events: Array = []
	for i in range(notes.size()):
		var note = notes[i]
		if note.get("is_hit", false) or note.get("is_missed", false):
			continue
		
		var note_time = float(note.get("time_sec", 0.0))
		if current_time > note_time + WINDOW_GOOD_SEC:
			note["is_missed"] = true
			note["is_hit"] = true # Mark processed so it won't be evaluated again
			var result = register_miss(note)
			result["matched_note_index"] = i
			expired_events.append(result)
			
	return expired_events

func get_accuracy() -> float:
	if total_notes == 0:
		return 100.0
	var weighted_hits = (float(count_perfect) * 1.0) + (float(count_good) * 0.5)
	return (weighted_hits / float(total_notes)) * 100.0

func get_summary() -> Dictionary:
	return {
		"score": score,
		"combo": combo,
		"max_combo": max_combo,
		"multiplier": get_multiplier(),
		"total_notes": total_notes,
		"count_perfect": count_perfect,
		"count_good": count_good,
		"count_miss": count_miss,
		"accuracy_pct": get_accuracy()
	}
```

---

### 3.2 HUD Scene & Script: `res://scenes/hud.tscn` & `res://scripts/hud.gd`

#### `res://scenes/hud.tscn`:
```ini
[gd_scene load_steps=2 format=3 uid="uid://hud_m1_scoring"]

[ext_resource type="Script" path="res://scripts/hud.gd" id="1_hud"]

[node name="HUD" type="CanvasLayer"]
script = ExtResource("1_hud")

[node name="ScoreContainer" type="VBoxContainer" parent="."]
anchors_preset = 1
anchor_left = 1.0
anchor_right = 1.0
offset_left = -220.0
offset_top = 30.0
offset_right = -30.0
offset_bottom = 110.0
grow_horizontal = 0
alignment = 2

[node name="ScoreLabel" type="Label" parent="ScoreContainer"]
layout_mode = 2
theme_override_colors/font_color = Color(0.7, 0.75, 0.8, 1)
theme_override_font_sizes/font_size = 14
text = "SCORE"
horizontal_alignment = 2

[node name="ScoreValue" type="Label" parent="ScoreContainer"]
layout_mode = 2
theme_override_colors/font_color = Color(1, 1, 1, 1)
theme_override_font_sizes/font_size = 36
text = "000000"
horizontal_alignment = 2

[node name="ComboContainer" type="VBoxContainer" parent="."]
offset_left = 120.0
offset_top = 80.0
offset_right = 280.0
offset_bottom = 150.0

[node name="ComboLabel" type="Label" parent="ComboContainer"]
layout_mode = 2
theme_override_colors/font_color = Color(1, 1, 1, 1)
theme_override_font_sizes/font_size = 26
text = "0 COMBO"

[node name="MultiplierLabel" type="Label" parent="ComboContainer"]
layout_mode = 2
theme_override_colors/font_color = Color(0.8, 0.8, 0.8, 1)
theme_override_font_sizes/font_size = 20
text = "1x"

[node name="JudgmentLayer" type="Control" parent="."]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
```

#### `res://scripts/hud.gd`:
```gdscript
# res://scripts/hud.gd
class_name HUD
extends CanvasLayer

@onready var score_value: Label = $ScoreContainer/ScoreValue
@onready var combo_container: VBoxContainer = $ComboContainer
@onready var combo_label: Label = $ComboContainer/ComboLabel
@onready var multiplier_label: Label = $ComboContainer/MultiplierLabel
@onready var judgment_layer: Control = $JudgmentLayer

const COLOR_PERFECT = Color(1.0, 0.84, 0.0)     # Gold
const COLOR_GOOD = Color(0.0, 0.9, 1.0)         # Cyan / Neon Blue
const COLOR_MISS = Color(1.0, 0.2, 0.4)         # Crimson

const COLOR_MULT_1X = Color(0.8, 0.8, 0.8)     # Silver
const COLOR_MULT_2X = Color(0.0, 0.9, 1.0)     # Cyan
const COLOR_MULT_3X = Color(1.0, 0.6, 0.0)     # Orange
const COLOR_MULT_4X = Color(1.0, 0.84, 0.0)    # Gold

var displayed_score: int = 0
var score_tween: Tween

func _ready() -> void:
	update_score(0)
	update_combo(0, 1)

func update_score(new_score: int) -> void:
	if score_value == null:
		return
	if score_tween:
		score_tween.kill()
	
	score_tween = create_tween()
	score_tween.tween_method(func(val: int):
		displayed_score = val
		score_value.text = "%06d" % val
	, displayed_score, new_score, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func update_combo(combo: int, multiplier: int) -> void:
	if combo_container == null:
		return
		
	if combo < 2:
		combo_container.modulate.a = 0.0
	else:
		combo_container.modulate.a = 1.0
		combo_label.text = "%d COMBO" % combo
		
		# Scale bounce on combo increment
		var t = create_tween()
		combo_container.scale = Vector2(1.2, 1.2)
		t.tween_property(combo_container, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	multiplier_label.text = "%dx" % multiplier
	match multiplier:
		1:
			multiplier_label.modulate = COLOR_MULT_1X
		2:
			multiplier_label.modulate = COLOR_MULT_2X
		3:
			multiplier_label.modulate = COLOR_MULT_3X
		4:
			multiplier_label.modulate = COLOR_MULT_4X

func spawn_judgment_popup(judgment: String, pos: Vector2) -> void:
	if judgment_layer == null:
		return
		
	var label = Label.new()
	label.text = judgment + "!"
	label.position = pos - Vector2(50, 15)
	label.pivot_offset = Vector2(50, 15)
	
	match judgment:
		"PERFECT":
			label.modulate = COLOR_PERFECT
			label.add_theme_font_size_override("font_size", 30)
		"GOOD":
			label.modulate = COLOR_GOOD
			label.add_theme_font_size_override("font_size", 26)
		"MISS":
			label.text = "MISS"
			label.modulate = COLOR_MISS
			label.add_theme_font_size_override("font_size", 24)
			
	judgment_layer.add_child(label)
	
	var tween = create_tween().set_parallel(true)
	# Float upward
	tween.tween_property(label, "position:y", label.position.y - 35.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Scale punch
	label.scale = Vector2(1.3, 1.3)
	tween.tween_property(label, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Fade out
	var alpha_tween = create_tween()
	alpha_tween.tween_interval(0.2)
	alpha_tween.tween_property(label, "modulate:a", 0.0, 0.25)
	alpha_tween.tween_callback(label.queue_free)
```

---

### 3.3 Hit Line Receptor Pulse & Glow (`res://scripts/highway.gd` snippet)

Integrate the following vector animation properties directly into `highway.gd`'s `_draw()` routine to provide hit line receptor glow and hit ripple feedback:

```gdscript
# Receptor feedback state in highway.gd
var receptor_flash_alpha: float = 0.0
var hit_ring_center: Vector2 = Vector2.ZERO
var hit_ring_radius: float = 0.0
var hit_ring_alpha: float = 0.0
var hit_ring_color: Color = Color(1.0, 0.84, 0.0)

func trigger_hit_pulse(note_y: float, judgment: String) -> void:
	receptor_flash_alpha = 1.0
	hit_ring_center = Vector2(HIT_LINE_X, note_y)
	hit_ring_radius = 12.0
	hit_ring_alpha = 1.0
	
	if judgment == "PERFECT":
		hit_ring_color = Color(1.0, 0.84, 0.0) # Gold
	elif judgment == "GOOD":
		hit_ring_color = Color(0.0, 0.9, 1.0)  # Cyan
	else:
		hit_ring_color = Color(1.0, 0.2, 0.4)  # Crimson

	var t1 = create_tween()
	t1.tween_property(self, "receptor_flash_alpha", 0.0, 0.15)
	
	var t2 = create_tween().set_parallel(true)
	t2.tween_property(self, "hit_ring_radius", 40.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t2.tween_property(self, "hit_ring_alpha", 0.0, 0.25)

func _draw() -> void:
	# ... (Draw Grand Staff lines) ...
	
	# Draw Target Hit Line Receptor
	draw_line(Vector2(HIT_LINE_X, 200), Vector2(HIT_LINE_X, 520), Color(0.0, 0.9, 1.0, 0.6), 3.0)
	
	# Draw Receptor Glow / Flash Pulse
	if receptor_flash_alpha > 0.01:
		draw_line(Vector2(HIT_LINE_X, 200), Vector2(HIT_LINE_X, 520), Color(1.0, 1.0, 1.0, receptor_flash_alpha), 6.0)
		
	# Draw Expanding Hit Ring
	if hit_ring_alpha > 0.01:
		draw_arc(hit_ring_center, hit_ring_radius, 0.0, TAU, 32, Color(hit_ring_color.r, hit_ring_color.g, hit_ring_color.b, hit_ring_alpha), 2.5)
```

---

### 3.4 Headless Verification Runner: `res://tests/test_scoring_runner.gd`

```gdscript
# res://tests/test_scoring_runner.gd
extends SceneTree

const ScoringEngineScript = preload("res://scripts/scoring_engine.gd")

var tests_passed: int = 0
var tests_failed: int = 0

func _init() -> void:
	print("==================================================")
	print(" RUNNING SCORING ENGINE HEADLESS VERIFICATION")
	print("==================================================")

	test_timing_windows()
	test_scoring_formulas_and_multipliers()
	test_combo_streak_reset()
	test_pitch_matching_and_polyphony()
	test_expired_notes()
	test_accuracy_calculation()

	print("==================================================")
	print(" RESULTS: %d Passed, %d Failed" % [tests_passed, tests_failed])
	print("==================================================")

	if tests_failed == 0:
		print("ALL SCORING MECHANICS VERIFIED SUCCESSFULLY [OK]")
		quit(0)
	else:
		push_error("SCORING MECHANICS VERIFICATION FAILED with %d errors" % tests_failed)
		quit(1)

func assert_true(condition: bool, message: String) -> void:
	if condition:
		tests_passed += 1
		print("  [PASS] %s" % message)
	else:
		tests_failed += 1
		printerr("  [FAIL] %s" % message)

func assert_eq(actual, expected, message: String) -> void:
	if actual == expected:
		tests_passed += 1
		print("  [PASS] %s (expected %s, got %s)" % [message, str(expected), str(actual)])
	else:
		tests_failed += 1
		printerr("  [FAIL] %s (expected %s, got %s)" % [message, str(expected), str(actual)])

func test_timing_windows() -> void:
	print("\n--- Test Suite 1: Timing Windows (Perfect <= 50ms, Good <= 100ms, Miss > 100ms) ---")
	var engine = ScoringEngineScript.new()

	assert_eq(engine.evaluate_timing(0.0), "PERFECT", "0ms diff should be PERFECT")
	assert_eq(engine.evaluate_timing(0.025), "PERFECT", "+25ms diff should be PERFECT")
	assert_eq(engine.evaluate_timing(-0.045), "PERFECT", "-45ms diff should be PERFECT")
	assert_eq(engine.evaluate_timing(0.050), "PERFECT", "Exact +50ms boundary should be PERFECT")
	assert_eq(engine.evaluate_timing(-0.050), "PERFECT", "Exact -50ms boundary should be PERFECT")

	assert_eq(engine.evaluate_timing(0.051), "GOOD", "+51ms should be GOOD")
	assert_eq(engine.evaluate_timing(-0.075), "GOOD", "-75ms should be GOOD")
	assert_eq(engine.evaluate_timing(0.100), "GOOD", "Exact +100ms boundary should be GOOD")
	assert_eq(engine.evaluate_timing(-0.100), "GOOD", "Exact -100ms boundary should be GOOD")

	assert_eq(engine.evaluate_timing(0.101), "MISS", "+101ms should be MISS")
	assert_eq(engine.evaluate_timing(-0.150), "MISS", "-150ms should be MISS")
	assert_eq(engine.evaluate_timing(0.500), "MISS", "+500ms should be MISS")

func test_scoring_formulas_and_multipliers() -> void:
	print("\n--- Test Suite 2: Scoring Formulas & Multiplier Progression ---")
	var engine = ScoringEngineScript.new()

	# Hits 1 through 9 (Multiplier 1x)
	# 9 Perfect hits: 9 * (100 * 1) = 900 points
	for i in range(9):
		var res = engine.register_hit("PERFECT")
		assert_eq(res["multiplier"], 1, "Hit %d multiplier should be 1x" % (i + 1))
	assert_eq(engine.score, 900, "Score after 9 Perfects at 1x should be 900")
	assert_eq(engine.combo, 9, "Combo should be 9")

	# 10th Hit (Multiplier transitions to 2x: 10 combo = 2x)
	var res10 = engine.register_hit("PERFECT")
	assert_eq(res10["multiplier"], 2, "10th hit triggers 2x multiplier")
	assert_eq(res10["points_awarded"], 200, "10th hit awards 100 * 2 = 200 pts")
	assert_eq(engine.score, 1100, "Total score after 10th hit should be 900 + 200 = 1100")
	assert_eq(engine.combo, 10, "Combo should be 10")

	# Hits 11 through 19 (Combo 11..19, multiplier 2x)
	# 9 more hits: 9 * (100 * 2) = 1800 pts -> 1100 + 1800 = 2900
	for i in range(11, 20):
		var res = engine.register_hit("PERFECT")
		assert_eq(res["multiplier"], 2, "Combo %d multiplier should be 2x" % i)
	assert_eq(engine.combo, 19, "Combo should be 19")
	assert_eq(engine.score, 2900, "Score after 19 hits should be 2900")

	# 20th Hit (Multiplier transitions to 3x: 20 combo = 3x)
	var res20 = engine.register_hit("PERFECT")
	assert_eq(res20["multiplier"], 3, "20th hit triggers 3x multiplier")
	assert_eq(res20["points_awarded"], 300, "20th hit awards 100 * 3 = 300 pts")
	assert_eq(engine.score, 3200, "Total score after 20th hit should be 2900 + 300 = 3200")
	assert_eq(engine.combo, 20, "Combo should be 20")

	# Hits 21 through 29 (Combo 21..29, multiplier 3x)
	# 9 more hits: 9 * (100 * 3) = 2700 pts -> 3200 + 2700 = 5900
	for i in range(21, 30):
		var res = engine.register_hit("PERFECT")
		assert_eq(res["multiplier"], 3, "Combo %d multiplier should be 3x" % i)
	assert_eq(engine.combo, 29, "Combo should be 29")
	assert_eq(engine.score, 5900, "Score after 29 hits should be 5900")

	# 30th Hit (Multiplier transitions to 4x: 30+ combo = 4x)
	var res30 = engine.register_hit("PERFECT")
	assert_eq(res30["multiplier"], 4, "30th hit triggers 4x multiplier")
	assert_eq(res30["points_awarded"], 400, "30th hit awards 100 * 4 = 400 pts")
	assert_eq(engine.score, 6300, "Total score after 30th hit should be 5900 + 400 = 6300")
	assert_eq(engine.combo, 30, "Combo should be 30")

	# 31st Hit with GOOD (Good awards 50 * multiplier = 50 * 4 = 200 pts)
	var res31 = engine.register_hit("GOOD")
	assert_eq(res31["multiplier"], 4, "31st hit multiplier should remain capped at 4x")
	assert_eq(res31["points_awarded"], 200, "Good at 4x awards 50 * 4 = 200 pts")
	assert_eq(engine.score, 6500, "Total score after 31st hit should be 6300 + 200 = 6500")
	assert_eq(engine.combo, 31, "Combo should be 31")

func test_combo_streak_reset() -> void:
	print("\n--- Test Suite 3: Miss & Streak Reset ---")
	var engine = ScoringEngineScript.new()

	# Build up a 15-hit combo (Multiplier is 2x)
	for i in range(15):
		engine.register_hit("PERFECT")
	assert_eq(engine.combo, 15, "Combo should be 15")
	assert_eq(engine.get_multiplier(), 2, "Multiplier should be 2x")
	var score_before_miss = engine.score

	# Register a Miss
	var res_miss = engine.register_miss()
	assert_eq(res_miss["judgment"], "MISS", "Judgment is MISS")
	assert_eq(res_miss["points_awarded"], 0, "Miss awards 0 pts")
	assert_eq(engine.score, score_before_miss, "Score does not increase on miss")
	assert_eq(engine.combo, 0, "Combo immediately resets to 0 on miss")
	assert_eq(engine.get_multiplier(), 1, "Multiplier drops back to 1x")
	assert_eq(engine.max_combo, 15, "Max combo remains preserved at 15")

	# Next hit after miss should be at 1x multiplier
	var res_after = engine.register_hit("PERFECT")
	assert_eq(res_after["multiplier"], 1, "Next hit after miss is at 1x")
	assert_eq(res_after["points_awarded"], 100, "Next hit awards 100 pts")
	assert_eq(engine.combo, 1, "Combo restarts at 1")

func test_pitch_matching_and_polyphony() -> void:
	print("\n--- Test Suite 4: Polyphonic Pitch Matching & Timing Offset ---")
	var engine = ScoringEngineScript.new()

	# Polyphonic chord at time 1.00s: C4 (MIDI 60), E4 (MIDI 64), G4 (MIDI 67)
	var active_notes = [
		{ "pitch_midi": 60, "time_sec": 1.00, "is_hit": false },
		{ "pitch_midi": 64, "time_sec": 1.00, "is_hit": false },
		{ "pitch_midi": 67, "time_sec": 1.00, "is_hit": false }
	]

	# User plays C4 (MIDI 60) at time 1.02s (+20ms offset -> PERFECT)
	var hit1 = engine.process_input(1.02, 60, active_notes)
	assert_eq(hit1["judgment"], "PERFECT", "C4 at +20ms should be judged PERFECT")
	assert_eq(active_notes[0]["is_hit"], true, "Note C4 marked as is_hit")
	assert_eq(active_notes[1]["is_hit"], false, "Note E4 should remain unhit")

	# User plays wrong pitch D4 (MIDI 62) at time 1.03s -> no match
	var hit_wrong = engine.process_input(1.03, 62, active_notes)
	assert_true(hit_wrong.is_empty(), "Wrong pitch MIDI 62 should match nothing")

	# User plays E4 (MIDI 64) at time 1.07s (+70ms offset -> GOOD)
	var hit2 = engine.process_input(1.07, 64, active_notes)
	assert_eq(hit2["judgment"], "GOOD", "E4 at +70ms should be judged GOOD")
	assert_eq(active_notes[1]["is_hit"], true, "Note E4 marked as is_hit")

	# User plays G4 (MIDI 67) at time 1.15s (+150ms offset -> beyond 100ms window -> no match)
	var hit3 = engine.process_input(1.15, 67, active_notes)
	assert_true(hit3.is_empty(), "G4 at +150ms is outside hit window, returns empty")
	assert_eq(active_notes[2]["is_hit"], false, "G4 remains unhit")

func test_expired_notes() -> void:
	print("\n--- Test Suite 5: Note Expiration (Miss on Passing Hit Window) ---")
	var engine = ScoringEngineScript.new()

	var active_notes = [
		{ "pitch_midi": 60, "time_sec": 2.00, "is_hit": false },
		{ "pitch_midi": 64, "time_sec": 2.50, "is_hit": false }
	]

	# Build up 5-combo
	for i in range(5):
		engine.register_hit("PERFECT")
	assert_eq(engine.combo, 5, "Combo is 5")

	# Song time reaches 2.05s (Note 60 is only 50ms past, still within good window <= 100ms)
	var expired_early = engine.check_expired_notes(2.05, active_notes)
	assert_eq(expired_early.size(), 0, "No notes expired at 2.05s")
	assert_eq(engine.combo, 5, "Combo remains 5")

	# Song time reaches 2.12s (Note 60 is 120ms past -> > 100ms -> expired!)
	var expired_late = engine.check_expired_notes(2.12, active_notes)
	assert_eq(expired_late.size(), 1, "1 note expired at 2.12s")
	assert_eq(expired_late[0]["judgment"], "MISS", "Expired note awarded MISS")
	assert_eq(engine.combo, 0, "Combo reset to 0 by expired note")
	assert_eq(active_notes[0]["is_missed"], true, "Note 60 marked is_missed")
	assert_eq(active_notes[1]["is_hit"], false, "Note 64 at 2.50s remains untouched")

	# Second check at 2.15s does not re-expire Note 60
	var expired_again = engine.check_expired_notes(2.15, active_notes)
	assert_eq(expired_again.size(), 0, "No duplicate expiration")

func test_accuracy_calculation() -> void:
	print("\n--- Test Suite 6: Performance Accuracy Percentage ---")
	var engine = ScoringEngineScript.new()

	# 2 Perfect (100% weight each), 2 Good (50% weight each), 0 Miss -> (2*1 + 2*0.5)/4 = 3/4 = 75.0%
	engine.register_hit("PERFECT")
	engine.register_hit("PERFECT")
	engine.register_hit("GOOD")
	engine.register_hit("GOOD")
	assert_eq(engine.get_accuracy(), 75.0, "Accuracy for 2 Perfect + 2 Good out of 4 should be 75.0%")

	# Add 1 Miss -> total 5 notes: (2*1 + 2*0.5 + 0)/5 = 3/5 = 60.0%
	engine.register_miss()
	assert_eq(engine.get_accuracy(), 60.0, "Accuracy with 1 added Miss should be 60.0%")
```

---

## 4. Headless Execution & Verification Evidence

The test suite was executed against Godot Engine `v4.7.2.stable.official.ed1daf0bf` using the console executable:

```powershell
& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --script "c:\Users\david\Documents\micgame-3\.agents\teamwork\m1_explorer_3\test_scoring_runner.gd"
```

### Execution Log Output:
```
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

==================================================
 RUNNING SCORING ENGINE HEADLESS VERIFICATION
==================================================

--- Test Suite 1: Timing Windows (Perfect <= 50ms, Good <= 100ms, Miss > 100ms) ---
  [PASS] 0ms diff should be PERFECT (expected PERFECT, got PERFECT)
  [PASS] +25ms diff should be PERFECT (expected PERFECT, got PERFECT)
  [PASS] -45ms diff should be PERFECT (expected PERFECT, got PERFECT)
  [PASS] Exact +50ms boundary should be PERFECT (expected PERFECT, got PERFECT)
  [PASS] Exact -50ms boundary should be PERFECT (expected PERFECT, got PERFECT)
  [PASS] +51ms should be GOOD (expected GOOD, got GOOD)
  [PASS] -75ms should be GOOD (expected GOOD, got GOOD)
  [PASS] Exact +100ms boundary should be GOOD (expected GOOD, got GOOD)
  [PASS] Exact -100ms boundary should be GOOD (expected GOOD, got GOOD)
  [PASS] +101ms should be MISS (expected MISS, got MISS)
  [PASS] -150ms should be MISS (expected MISS, got MISS)
  [PASS] +500ms should be MISS (expected MISS, got MISS)

--- Test Suite 2: Scoring Formulas & Multiplier Progression ---
  [PASS] Hit 1 multiplier should be 1x (expected 1, got 1)
  [PASS] Hit 2 multiplier should be 1x (expected 1, got 1)
  [PASS] Hit 3 multiplier should be 1x (expected 1, got 1)
  [PASS] Hit 4 multiplier should be 1x (expected 1, got 1)
  [PASS] Hit 5 multiplier should be 1x (expected 1, got 1)
  [PASS] Hit 6 multiplier should be 1x (expected 1, got 1)
  [PASS] Hit 7 multiplier should be 1x (expected 1, got 1)
  [PASS] Hit 8 multiplier should be 1x (expected 1, got 1)
  [PASS] Hit 9 multiplier should be 1x (expected 1, got 1)
  [PASS] Score after 9 Perfects at 1x should be 900 (expected 900, got 900)
  [PASS] Combo should be 9 (expected 9, got 9)
  [PASS] 10th hit triggers 2x multiplier (expected 2, got 2)
  [PASS] 10th hit awards 100 * 2 = 200 pts (expected 200, got 200)
  [PASS] Total score after 10th hit should be 900 + 200 = 1100 (expected 1100, got 1100)
  [PASS] Combo should be 10 (expected 10, got 10)
  [PASS] Combo 11 multiplier should be 2x (expected 2, got 2)
  [PASS] Combo 12 multiplier should be 2x (expected 2, got 2)
  [PASS] Combo 13 multiplier should be 2x (expected 2, got 2)
  [PASS] Combo 14 multiplier should be 2x (expected 2, got 2)
  [PASS] Combo 15 multiplier should be 2x (expected 2, got 2)
  [PASS] Combo 16 multiplier should be 2x (expected 2, got 2)
  [PASS] Combo 17 multiplier should be 2x (expected 2, got 2)
  [PASS] Combo 18 multiplier should be 2x (expected 2, got 2)
  [PASS] Combo 19 multiplier should be 2x (expected 2, got 2)
  [PASS] Combo should be 19 (expected 19, got 19)
  [PASS] Score after 19 hits should be 2900 (expected 2900, got 2900)
  [PASS] 20th hit triggers 3x multiplier (expected 3, got 3)
  [PASS] 20th hit awards 100 * 3 = 300 pts (expected 300, got 300)
  [PASS] Total score after 20th hit should be 2900 + 300 = 3200 (expected 3200, got 3200)
  [PASS] Combo should be 20 (expected 20, got 20)
  [PASS] Combo 21 multiplier should be 3x (expected 3, got 3)
  [PASS] Combo 22 multiplier should be 3x (expected 3, got 3)
  [PASS] Combo 23 multiplier should be 3x (expected 3, got 3)
  [PASS] Combo 24 multiplier should be 3x (expected 3, got 3)
  [PASS] Combo 25 multiplier should be 3x (expected 3, got 3)
  [PASS] Combo 26 multiplier should be 3x (expected 3, got 3)
  [PASS] Combo 27 multiplier should be 3x (expected 3, got 3)
  [PASS] Combo 28 multiplier should be 3x (expected 3, got 3)
  [PASS] Combo 29 multiplier should be 3x (expected 3, got 3)
  [PASS] Combo should be 29 (expected 29, got 29)
  [PASS] Score after 29 hits should be 5900 (expected 5900, got 5900)
  [PASS] 30th hit triggers 4x multiplier (expected 4, got 4)
  [PASS] 30th hit awards 100 * 4 = 400 pts (expected 400, got 400)
  [PASS] Total score after 30th hit should be 5900 + 400 = 6300 (expected 6300, got 6300)
  [PASS] Combo should be 30 (expected 30, got 30)
  [PASS] 31st hit multiplier should remain capped at 4x (expected 4, got 4)
  [PASS] Good at 4x awards 50 * 4 = 200 pts (expected 200, got 200)
  [PASS] Total score after 31st hit should be 6300 + 200 = 6500 (expected 6500, got 6500)
  [PASS] Combo should be 31 (expected 31, got 31)

--- Test Suite 3: Miss & Streak Reset ---
  [PASS] Combo should be 15 (expected 15, got 15)
  [PASS] Multiplier should be 2x (expected 2, got 2)
  [PASS] Judgment is MISS (expected MISS, got MISS)
  [PASS] Miss awards 0 pts (expected 0, got 0)
  [PASS] Score does not increase on miss (expected 2100, got 2100)
  [PASS] Combo immediately resets to 0 on miss (expected 0, got 0)
  [PASS] Multiplier drops back to 1x (expected 1, got 1)
  [PASS] Max combo remains preserved at 15 (expected 15, got 15)
  [PASS] Next hit after miss is at 1x (expected 1, got 1)
  [PASS] Next hit awards 100 pts (expected 100, got 100)
  [PASS] Combo restarts at 1 (expected 1, got 1)

--- Test Suite 4: Polyphonic Pitch Matching & Timing Offset ---
  [PASS] C4 at +20ms should be judged PERFECT (expected PERFECT, got PERFECT)
  [PASS] Note C4 marked as is_hit (expected true, got true)
  [PASS] Note E4 should remain unhit (expected false, got false)
  [PASS] Wrong pitch MIDI 62 should match nothing
  [PASS] E4 at +70ms should be judged GOOD (expected GOOD, got GOOD)
  [PASS] Note E4 marked as is_hit (expected true, got true)
  [PASS] G4 at +150ms is outside hit window, returns empty
  [PASS] G4 remains unhit (expected false, got false)

--- Test Suite 5: Note Expiration (Miss on Passing Hit Window) ---
  [PASS] Combo is 5 (expected 5, got 5)
  [PASS] No notes expired at 2.05s (expected 0, got 0)
  [PASS] Combo remains 5 (expected 5, got 5)
  [PASS] 1 note expired at 2.12s (expected 1, got 1)
  [PASS] Expired note awarded MISS (expected MISS, got MISS)
  [PASS] Combo reset to 0 by expired note (expected 0, got 0)
  [PASS] Note 60 marked is_missed (expected true, got true)
  [PASS] Note 64 at 2.50s remains untouched (expected false, got false)
  [PASS] No duplicate expiration (expected 0, got 0)

--- Test Suite 6: Performance Accuracy Percentage ---
  [PASS] Accuracy for 2 Perfect + 2 Good out of 4 should be 75.0% (expected 75.0, got 75.0)
  [PASS] Accuracy with 1 added Miss should be 60.0% (expected 60.0, got 60.0)
==================================================
 RESULTS: 91 Passed, 0 Failed
==================================================
ALL SCORING MECHANICS VERIFIED SUCCESSFULLY [OK]
```

**Result**: Exit Code 0. 91 assertions evaluated and passed.

---

## 5. Worker Instructions

When implementing Milestone 1, the Worker should execute the following operations:

1. **Create Target Directories**:
   - `scripts/`
   - `scenes/`
   - `tests/`
2. **Deploy Files**:
   - Copy Section 3.1 to `c:\Users\david\Documents\micgame-3\scripts\scoring_engine.gd`.
   - Copy Section 3.2 scene to `c:\Users\david\Documents\micgame-3\scenes\hud.tscn`.
   - Copy Section 3.2 script to `c:\Users\david\Documents\micgame-3\scripts\hud.gd`.
   - Integrate Section 3.3 receptor pulse code into `c:\Users\david\Documents\micgame-3\scripts\highway.gd`.
   - Copy Section 3.4 to `c:\Users\david\Documents\micgame-3\tests\test_scoring_runner.gd`.
3. **Verify Execution**:
   - Run:
     ```powershell
     & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script res://tests/test_scoring_runner.gd
     ```
   - Ensure the process terminates with exit code 0 and reports all tests passed.
