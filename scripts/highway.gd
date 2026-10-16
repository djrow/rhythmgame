class_name Highway
extends Node2D

## Grand Staff Rhythm Highway: manages chart parsing, scrolling, pooling, and sub-frame playhead sync.

signal note_hit(note: NoteData, rating: String, diff_ms: float)
signal note_missed(note: NoteData)
signal playback_finished()

const HIT_X: float = 160.0
const CENTER_Y: float = 360.0
const LINE_SPACING: float = 18.0
const STEP_DY: float = 9.0

# Treble lines: F5(270), D5(288), B4(306), G4(324), E4(342)
const TREBLE_LINES: Array[float] = [270.0, 288.0, 306.0, 324.0, 342.0]
# Bass lines: A3(378), F3(396), D3(414), B2(432), G2(450)
const BASS_LINES: Array[float] = [378.0, 396.0, 414.0, 432.0, 450.0]

const SCREEN_WIDTH: float = 1280.0
const SPAWN_MARGIN_PX: float = 100.0
const DESPAWN_X_THRESHOLD: float = -60.0

@export var scroll_speed: float = 400.0: # px/sec
	set(value):
		scroll_speed = maxf(value, 1.0)
@export var x_hit: float = 160.0
@export var audio_offset_sec: float = 0.0
@export var miss_window_sec: float = 0.100 # Notes passing +100ms evaluate as Miss
@export var audio_player: AudioStreamPlayer

@onready var note_renderer: NoteRenderer = $NoteRenderer

var chart_notes: Array[NoteData] = []
var active_notes: Array[NoteData] = []
var spawn_index: int = 0

var current_song_time: float = 0.0
var is_playing: bool = false
var last_playback_pos: float = 0.0

# Visual feedback: hit ripples and live pitch guide
var hit_effects: Array[Dictionary] = [] # {"pos": Vector2, "time": float, "initial_time": float, "color": Color}
var receptor_flash_alpha: float = 0.0
var live_pitch_y: float = -1.0

func _ready() -> void:
	if note_renderer == null:
		var found = get_node_or_null("NoteRenderer")
		if found is NoteRenderer:
			note_renderer = found
		else:
			note_renderer = NoteRenderer.new()
			note_renderer.name = "NoteRenderer"
			add_child(note_renderer)
	
	if audio_player == null:
		var found_audio = get_node_or_null("AudioPlayer")
		if found_audio is AudioStreamPlayer:
			audio_player = found_audio

func load_chart_dict(chart_dict: Dictionary) -> void:
	var raw_notes: Array = chart_dict.get("notes", [])
	load_notes(raw_notes)

func load_notes(raw_notes: Array) -> void:
	chart_notes.clear()
	active_notes.clear()
	hit_effects.clear()
	spawn_index = 0
	current_song_time = 0.0
	is_playing = false
	last_playback_pos = 0.0

	for i in range(raw_notes.size()):
		var item = raw_notes[i]
		var note: NoteData = null
		if item is Dictionary:
			note = NoteData.from_dict(item, i + 1)
		elif item is NoteData:
			note = item
		if note:
			chart_notes.append(note)

	# Chronological sort (secondary sort by diatonic_step ascending for stable ordering)
	chart_notes.sort_custom(func(a: NoteData, b: NoteData) -> bool:
		if absf(a.time_sec - b.time_sec) > 0.005:
			return a.time_sec < b.time_sec
		return a.diatonic_step < b.diatonic_step
	)

	# Detect chords and offset adjacent diatonic steps in O(N)
	var n_notes: int = chart_notes.size()
	var idx: int = 0
	while idx < n_notes:
		var chord: Array[NoteData] = [chart_notes[idx]]
		var j: int = idx + 1
		while j < n_notes and absf(chart_notes[j].time_sec - chart_notes[idx].time_sec) < 0.005:
			chord.append(chart_notes[j])
			j += 1
		
		if chord.size() > 1:
			chord.sort_custom(func(a: NoteData, b: NoteData) -> bool: return a.diatonic_step < b.diatonic_step)
			
			var k: int = 0
			while k < chord.size():
				var run_end: int = k
				while run_end + 1 < chord.size() and (chord[run_end + 1].diatonic_step - chord[run_end].diatonic_step == 1):
					run_end += 1
				
				if run_end > k:
					# Consecutive seconds run: alternate 0.0, 16.0, 0.0, 16.0...
					for r in range(k, run_end + 1):
						if (r - k) % 2 == 1:
							chord[r].chord_offset_x = 16.0
						else:
							chord[r].chord_offset_x = 0.0
					k = run_end + 1
				else:
					chord[k].chord_offset_x = 0.0
					k += 1
			idx = j
		else:
			chart_notes[idx].chord_offset_x = 0.0
			idx += 1

func start_playback() -> void:
	is_playing = true
	current_song_time = 0.0
	last_playback_pos = 0.0
	if audio_player and audio_player.stream and audio_player.is_inside_tree():
		audio_player.play()

func pause_playback() -> void:
	is_playing = false
	if audio_player and audio_player.playing:
		audio_player.stop()

func _process(delta: float) -> void:
	if not is_playing:
		# Still update hit effects if idle
		_update_effects(delta)
		queue_redraw()
		return

	# 1. Update playhead with sub-frame precision
	_update_playhead_time(delta)

	# 2. Spawn incoming notes ahead of screen
	var spawn_lookahead: float = (SCREEN_WIDTH - x_hit + SPAWN_MARGIN_PX) / maxf(scroll_speed, 1.0)
	var spawn_threshold_time: float = current_song_time + spawn_lookahead

	while spawn_index < chart_notes.size() and chart_notes[spawn_index].time_sec <= spawn_threshold_time:
		active_notes.append(chart_notes[spawn_index])
		spawn_index += 1

	# 3. Update active notes (miss detection and despawn culling)
	var i: int = active_notes.size() - 1
	while i >= 0:
		var note: NoteData = active_notes[i]
		var head_x: float = x_hit + (note.time_sec - current_song_time) * scroll_speed + note.chord_offset_x
		var tail_x: float = head_x + note.duration_sec * scroll_speed

		# Check miss condition
		if not note.is_hit and not note.is_missed and current_song_time > note.time_sec + miss_window_sec:
			note.is_missed = true
			note.hit_rating = "MISS"
			note_missed.emit(note)

		# Despawn / culling condition
		if tail_x < DESPAWN_X_THRESHOLD:
			active_notes.remove_at(i)
		i -= 1

	# 4. Push updated state to renderer
	if note_renderer:
		note_renderer.update_notes(active_notes, current_song_time, x_hit, scroll_speed)

	# 5. Update feedback animations
	_update_effects(delta)

	# Check end of chart
	if spawn_index >= chart_notes.size() and active_notes.is_empty():
		playback_finished.emit()

	queue_redraw()

func _update_effects(delta: float) -> void:
	if receptor_flash_alpha > 0.0:
		receptor_flash_alpha = maxf(0.0, receptor_flash_alpha - delta * 5.0)

	var kept_effects: Array[Dictionary] = []
	for effect in hit_effects:
		effect.time -= delta
		if effect.time > 0.0:
			kept_effects.append(effect)
	hit_effects = kept_effects

func _update_playhead_time(delta: float) -> void:
	if audio_player and audio_player.playing:
		var pos: float = audio_player.get_playback_position()
		var time_since_mix: float = AudioServer.get_time_since_last_mix()
		var latency: float = AudioServer.get_output_latency()

		var calculated_time: float = pos + time_since_mix - latency + audio_offset_sec

		# Seek detection
		if pos < last_playback_pos - 0.5:
			current_song_time = maxf(0.0, calculated_time)
			_handle_seek()
		elif calculated_time >= current_song_time:
			current_song_time = calculated_time

		last_playback_pos = pos
	else:
		# Fallback clock for testing and headless mode
		current_song_time += delta

func _handle_seek() -> void:
	active_notes.clear()
	spawn_index = 0
	var spawn_lookahead: float = (SCREEN_WIDTH - x_hit + SPAWN_MARGIN_PX) / maxf(scroll_speed, 1.0)
	var spawn_threshold_time: float = current_song_time + spawn_lookahead
	while spawn_index < chart_notes.size() and chart_notes[spawn_index].time_sec < current_song_time - 0.5:
		spawn_index += 1

func trigger_hit_pulse(note_y: float, rating: String) -> void:
	receptor_flash_alpha = 1.0
	var col: Color = Color(1.0, 0.84, 0.0) # Gold for Perfect
	if rating == "GOOD":
		col = Color(0.0, 0.9, 1.0) # Cyan
	elif rating == "MISS":
		col = Color(1.0, 0.2, 0.4) # Crimson

	hit_effects.append({
		"pos": Vector2(x_hit, note_y),
		"time": 0.35,
		"initial_time": 0.35,
		"color": col
	})

func set_live_pitch(midi: int) -> void:
	if midi >= 0 and midi <= 127:
		live_pitch_y = NoteData.midi_to_y(midi)
		live_pitches_midi = [midi]
	else:
		live_pitch_y = -1.0
		live_pitches_midi.clear()
	queue_redraw()

func set_live_pitches(pitches: Array[int]) -> void:
	live_pitches_midi.clear()
	for p in pitches:
		var m: int = int(p)
		if m >= 0 and m <= 127 and not live_pitches_midi.has(m):
			live_pitches_midi.append(m)
	if not live_pitches_midi.is_empty():
		live_pitch_y = NoteData.midi_to_y(live_pitches_midi[0])
	else:
		live_pitch_y = -1.0
	queue_redraw()

var live_pitches_midi: Array[int] = []

## Interface contract: Query unhit notes active around a target timestamp within tolerance
func get_active_notes_at(time: float, tolerance: float = 0.1) -> Array[NoteData]:
	var results: Array[NoteData] = []
	for note in active_notes:
		if note.is_hit:
			continue
		var onset_diff: float = absf(note.time_sec - time)
		if onset_diff <= tolerance:
			results.append(note)
		elif note.duration_sec > 0.0 and note.time_sec <= time and time <= (note.time_sec + note.duration_sec):
			results.append(note)
	return results

func _draw() -> void:
	var viewport_w: float = get_viewport_rect().size.x
	if viewport_w <= 0:
		viewport_w = SCREEN_WIDTH

	# 1. Staff Background Ribbon
	var bg_color: Color = Color(0.07, 0.09, 0.14, 0.65)
	draw_rect(Rect2(0, 245, viewport_w, 230), bg_color, true)

	# 2. Staff Lines (Treble & Bass)
	var staff_line_color: Color = Color(0.38, 0.45, 0.58, 0.85)
	for y in TREBLE_LINES:
		draw_line(Vector2(0, y), Vector2(viewport_w, y), staff_line_color, 1.5, true)
	for y in BASS_LINES:
		draw_line(Vector2(0, y), Vector2(viewport_w, y), staff_line_color, 1.5, true)

	# 3. System Brace Line on Left
	draw_line(Vector2(50, 270), Vector2(50, 450), Color(0.6, 0.7, 0.85, 0.9), 3.0, true)

	# 4. Clef Labels
	var font: Font = ThemeDB.fallback_font
	if font:
		draw_string(font, Vector2(65, 312), "TREBLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.0, 0.9, 1.0, 0.85))
		draw_string(font, Vector2(65, 420), "BASS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.7, 0.2, 0.85))

	# 5. Hit Line Receptor at X = 160
	# Outer glow
	draw_line(Vector2(x_hit, 220), Vector2(x_hit, 500), Color(0.0, 0.8, 1.0, 0.2), 8.0, true)
	# Core beam
	draw_line(Vector2(x_hit, 220), Vector2(x_hit, 500), Color(0.0, 0.95, 1.0, 0.85), 2.5, true)

	# Receptor flash pulse on hit
	if receptor_flash_alpha > 0.01:
		draw_line(Vector2(x_hit, 220), Vector2(x_hit, 500), Color(1.0, 1.0, 1.0, receptor_flash_alpha * 0.8), 6.0, true)

	# Staff line receptor nodes
	for y in TREBLE_LINES:
		draw_circle(Vector2(x_hit, y), 3.0, Color(0.0, 0.95, 1.0, 0.9))
	for y in BASS_LINES:
		draw_circle(Vector2(x_hit, y), 3.0, Color(1.0, 0.75, 0.2, 0.9))
	draw_circle(Vector2(x_hit, CENTER_Y), 3.0, Color(0.9, 0.95, 1.0, 0.9))

	# 6. Live Polyphonic Pitch Indicator Cursors
	if not live_pitches_midi.is_empty():
		for m in live_pitches_midi:
			var py: float = NoteData.midi_to_y(m)
			draw_circle(Vector2(x_hit, py), 9.5, Color(0.15, 1.0, 0.45, 0.28))
			draw_circle(Vector2(x_hit, py), 6.5, Color(0.2, 1.0, 0.45, 0.95))
			draw_line(Vector2(x_hit - 16, py), Vector2(x_hit + 16, py), Color(0.2, 1.0, 0.45, 1.0), 2.2)
			if font:
				var p_name: String = NoteData.midi_to_pitch_name(m)
				draw_string(font, Vector2(x_hit - 44, py + 4), p_name, HORIZONTAL_ALIGNMENT_RIGHT, 28, 12, Color(0.25, 1.0, 0.55, 0.98))
	elif live_pitch_y > 0.0:
		draw_circle(Vector2(x_hit, live_pitch_y), 6.5, Color(0.2, 1.0, 0.4, 0.95))
		draw_line(Vector2(x_hit - 14, live_pitch_y), Vector2(x_hit + 14, live_pitch_y), Color(0.2, 1.0, 0.4, 1.0), 2.0)

	# 7. Hit Pulse Ripple Effects
	for effect in hit_effects:
		var progress: float = 1.0 - (effect.time / effect.initial_time)
		var radius: float = 12.0 + progress * 32.0
		var eff_color: Color = effect.color
		eff_color.a = (1.0 - progress) * 0.8
		draw_arc(effect.pos, radius, 0.0, TAU, 32, eff_color, 2.5)
