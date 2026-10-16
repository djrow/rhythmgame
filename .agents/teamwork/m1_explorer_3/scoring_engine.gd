# scoring_engine.gd
# Hit detection, timing windows, combo multipliers, and scoring engine.
class_name ScoringEngine
extends RefCounted

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

# State
var score: int = 0
var combo: int = 0
var max_combo: int = 0
var count_perfect: int = 0
var count_good: int = 0
var count_miss: int = 0
var total_notes: int = 0

# Signals (when used in scene tree)
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

## Checks if an incoming input (time, pitch) matches any active note in the notes array.
## Notes array elements are Dictionaries with keys:
## { "pitch_midi": int, "time_sec": float, "duration_sec": float, "is_hit": bool }
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

## Checks for notes that passed beyond the hit window (+100ms) without being hit.
## Marks them as missed and triggers MISS judgment.
func check_expired_notes(current_time: float, notes: Array) -> Array:
	var expired_events: Array = []
	for i in range(notes.size()):
		var note = notes[i]
		if note.get("is_hit", false) or note.get("is_missed", false):
			continue
		
		var note_time = float(note.get("time_sec", 0.0))
		# If current time has passed the note time by more than WINDOW_GOOD_SEC (100ms)
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
