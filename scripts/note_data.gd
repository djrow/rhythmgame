class_name NoteData
extends RefCounted

## Represents a single musical note event on the Grand Staff Highway.

const DIATONIC_OFFSETS: Array[int] = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6]
const IS_ACCIDENTAL_TABLE: Array[bool] = [false, true, false, true, false, false, true, false, true, false, true, false]
const PITCH_NAMES: Array[String] = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

const Y_CENTER: float = 360.0
const LINE_SPACING: float = 18.0
const STEP_DY: float = 9.0 # LINE_SPACING / 2.0
const MIDDLE_C_STEP: int = 28 # C4 (MIDI 60)

var id: int = 0
var pitch_midi: int = 60
var pitch_name: String = "C4"
var time_sec: float = 0.0
var duration_sec: float = 0.0
var staff: String = "treble" # "treble" or "bass"

# Precomputed notation properties
var diatonic_step: int = 28
var is_accidental: bool = false
var accidental_type: String = "" # "#" or "b"
var y_pos: float = 360.0
var ledger_y_positions: Array[float] = []
var chord_offset_x: float = 0.0

# Gameplay evaluation state
var is_hit: bool = false
var is_missed: bool = false
var hit_time: float = -1.0
var hit_rating: String = "" # "PERFECT", "GOOD", "MISS"
var hit_score: int = 0

func _init(p_id: int = 0, p_midi: int = 60, p_time: float = 0.0, p_dur: float = 0.0, p_staff: String = "") -> void:
	id = p_id
	pitch_midi = clampi(p_midi, 0, 127)
	time_sec = maxf(0.0, p_time)
	duration_sec = maxf(0.0, p_dur)
	staff = p_staff if p_staff != "" else ("treble" if pitch_midi >= 60 else "bass")
	_compute_notation_properties()

func _compute_notation_properties() -> void:
	var pc: int = pitch_midi % 12
	var oct: int = int(floor(pitch_midi / 12.0)) - 1
	diatonic_step = oct * 7 + DIATONIC_OFFSETS[pc]
	is_accidental = IS_ACCIDENTAL_TABLE[pc]
	accidental_type = "#" if is_accidental else ""
	pitch_name = PITCH_NAMES[pc] + str(oct)
	
	# Middle C is Y=360. Positive Y is down in Godot 2D.
	y_pos = Y_CENTER - float(diatonic_step - MIDDLE_C_STEP) * STEP_DY
	
	ledger_y_positions.clear()
	var steps: Array[int] = get_ledger_steps(diatonic_step)
	for s in steps:
		ledger_y_positions.append(step_to_y(s))

static func midi_to_step(midi: int) -> int:
	var pc: int = midi % 12
	var oct: int = int(floor(midi / 12.0)) - 1
	return oct * 7 + DIATONIC_OFFSETS[pc]

static func step_to_y(step: int) -> float:
	return Y_CENTER - float(step - MIDDLE_C_STEP) * STEP_DY

static func midi_to_y(midi: int) -> float:
	return step_to_y(midi_to_step(midi))

static func midi_to_pitch_name(midi: int) -> String:
	var clamped: int = clampi(midi, 0, 127)
	var pc: int = clamped % 12
	var oct: int = int(floor(float(clamped) / 12.0)) - 1
	return PITCH_NAMES[pc] + str(oct)

static func get_ledger_steps(step: int) -> Array[int]:
	var ledgers: Array[int] = []
	if step == MIDDLE_C_STEP:
		ledgers.append(MIDDLE_C_STEP)
	elif step >= 40:
		var max_even: int = step if (step % 2 == 0) else (step - 1)
		var s: int = 40
		while s <= max_even:
			ledgers.append(s)
			s += 2
	elif step <= 16:
		var min_even: int = step if (step % 2 == 0) else (step + 1)
		var s: int = 16
		while s >= min_even:
			ledgers.append(s)
			s -= 2
	return ledgers

static func from_dict(dict: Dictionary, note_id: int = 0) -> NoteData:
	var midi_val: int = int(dict.get("pitch_midi", dict.get("midi", 60)))
	var t_val: float = float(dict.get("time_sec", dict.get("start_time", 0.0)))
	var d_val: float = float(dict.get("duration_sec", dict.get("duration", 0.0)))
	var st: String = str(dict.get("staff", ""))
	return NoteData.new(note_id, midi_val, t_val, d_val, st)

func to_dict() -> Dictionary:
	return {
		"id": id,
		"pitch_midi": pitch_midi,
		"pitch_name": pitch_name,
		"time_sec": time_sec,
		"duration_sec": duration_sec,
		"staff": staff,
		"diatonic_step": diatonic_step,
		"is_accidental": is_accidental,
		"y_pos": y_pos,
		"is_hit": is_hit,
		"is_missed": is_missed,
		"hit_rating": hit_rating,
		"hit_score": hit_score
	}
