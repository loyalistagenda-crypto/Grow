extends Node2D
class_name BackgroundRenderer

var background_name := "earth"
var phases := ["dawn", "day", "dusk", "night"]
var phase_index := 1

func _ready() -> void:
	hide()

func set_background(name: String) -> void:
	background_name = name
	queue_redraw()

func set_phase(phase: String) -> void:
	var idx := phases.find(phase)
	if idx != -1:
		phase_index = idx
		queue_redraw()

func next_phase() -> void:
	phase_index = (phase_index + 1) % phases.size()
	queue_redraw()

func prev_phase() -> void:
	phase_index = (phase_index - 1 + phases.size()) % phases.size()
	queue_redraw()

func _draw() -> void:
	var data := BackgroundDatabase.get_background(background_name)
	var phase_key := "sky_%s" % phases[phase_index]
	var sky_color := data.get(phase_key, Color(0.5, 0.7, 0.9))
	var ground_color := data.get("ground", Color(0.2, 0.4, 0.2))

	var view_size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view_size), sky_color)

	var ground_height := view_size.y * 0.25
	draw_rect(Rect2(Vector2(0, view_size.y - ground_height), Vector2(view_size.x, ground_height)), ground_color)
