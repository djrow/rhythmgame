# hud.gd
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
		
		# Pulse animation on combo increment
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
	# Initial scale bump
	label.scale = Vector2(1.3, 1.3)
	tween.tween_property(label, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Fade out after brief hold
	var alpha_tween = create_tween()
	alpha_tween.tween_interval(0.2)
	alpha_tween.tween_property(label, "modulate:a", 0.0, 0.25)
	alpha_tween.tween_callback(label.queue_free)
