class_name ScoringEngine
extends RefCounted

## Hit detection, timing windows, combo multipliers, and scoring engine.

# Timing Windows (seconds)
const WINDOW_PERFECT_SEC: float = 0.050  # +/- 50ms
const WINDOW_GOOD_SEC: float = 0.100     # +/- 100ms
const TIMING_EPSILON: float = 0.000005   # 5 microsecond tolerance for IEEE 754 precision

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
	var abs_diff: float = abs(time_diff_sec)
	if abs_diff <= WINDOW_PERFECT_SEC + TIMING_EPSILON:
		return "PERFECT"
	elif abs_diff <= WINDOW_GOOD_SEC + TIMING_EPSILON:
		return "GOOD"
	else:
		return "MISS"

func register_hit(judgment: String, note_data: Dictionary = {}) -> Dictionary:
	if judgment != "PERFECT" and judgment != "GOOD" and judgment != "MISS":
		push_warning("Unknown judgment: " + judgment)
		return {}

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

	if combo > max_combo:
		max_combo = combo

	var mult: int = get_multiplier()
	var points_awarded: int = base_pts * mult
	score += points_awarded

	var result: Dictionary = {
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
## Supports both NoteData instances and Dictionaries.
func process_input(input_time: float, pitch_midi: int, notes: Array, semitone_tolerance: int = 0) -> Dictionary:
	var best_index: int = -1
	var min_abs_diff: float = 9999.0
	
	for i in range(notes.size()):
		var note = notes[i]
		var is_hit: bool = false
		var is_missed: bool = false
		var note_pitch: int = 0
		var note_time: float = 0.0

		if note is Dictionary:
			is_hit = bool(note.get("is_hit", false))
			is_missed = bool(note.get("is_missed", false))
			note_pitch = int(note.get("pitch_midi", 0))
			note_time = float(note.get("time_sec", 0.0))
		elif note is RefCounted and "pitch_midi" in note and "time_sec" in note:
			is_hit = note.is_hit if "is_hit" in note else false
			is_missed = note.is_missed if "is_missed" in note else false
			note_pitch = note.pitch_midi
			note_time = note.time_sec
		else:
			continue
		
		if is_hit or is_missed:
			continue
		
		if abs(note_pitch - pitch_midi) > semitone_tolerance:
			continue
		
		var time_diff: float = input_time - note_time
		var abs_diff: float = abs(time_diff)
		
		# Must be within hit window (+/- 100ms)
		if abs_diff <= (WINDOW_GOOD_SEC + TIMING_EPSILON) and abs_diff < min_abs_diff:
			min_abs_diff = abs_diff
			best_index = i
	
	if best_index != -1:
		var target_note = notes[best_index]
		var time_diff: float = 0.0
		var note_dict: Dictionary = {}

		if target_note is Dictionary:
			time_diff = input_time - float(target_note.get("time_sec", 0.0))
			var judgment: String = evaluate_timing(time_diff)
			target_note["is_hit"] = true
			target_note["hit_time"] = input_time
			target_note["hit_diff"] = time_diff
			target_note["judgment"] = judgment
			note_dict = target_note
			var result: Dictionary = register_hit(judgment, note_dict)
			result["matched_note_index"] = best_index
			result["time_diff"] = time_diff
			return result
		elif target_note is RefCounted and "time_sec" in target_note:
			time_diff = input_time - target_note.time_sec
			var judgment: String = evaluate_timing(time_diff)
			target_note.is_hit = true
			target_note.hit_time = input_time
			target_note.hit_rating = judgment
			if target_note.has_method("to_dict"):
				note_dict = target_note.to_dict()
			var result: Dictionary = register_hit(judgment, note_dict)
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
		if note is Dictionary:
			if note.get("is_hit", false) or note.get("is_missed", false):
				continue
			var note_time: float = float(note.get("time_sec", 0.0))
			if current_time > note_time + WINDOW_GOOD_SEC:
				note["is_missed"] = true
				var result: Dictionary = register_miss(note)
				result["matched_note_index"] = i
				expired_events.append(result)
		elif note is RefCounted and "time_sec" in note:
			var is_hit: bool = note.is_hit if "is_hit" in note else false
			var is_missed: bool = note.is_missed if "is_missed" in note else false
			if is_hit or is_missed:
				continue
			var note_time: float = note.time_sec
			if current_time > note_time + WINDOW_GOOD_SEC:
				if "is_missed" in note:
					note.is_missed = true
				if "hit_rating" in note:
					note.hit_rating = "MISS"
				var note_dict: Dictionary = note.to_dict() if note.has_method("to_dict") else {}
				var result: Dictionary = register_miss(note_dict)
				result["matched_note_index"] = i
				expired_events.append(result)
			
	return expired_events

func get_accuracy() -> float:
	if total_notes == 0:
		return 100.0
	var weighted_hits: float = (float(count_perfect) * 1.0) + (float(count_good) * 0.5)
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
