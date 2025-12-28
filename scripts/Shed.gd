extends Node2D
class_name Shed

@export var ground_height: float = 120.0
var plant: Plant

func _ready() -> void:
	set_process(true)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var view := get_viewport_rect().size
	var ground_y: float = view.y - ground_height
	var canopy_right: float = view.x - 60.0
	var canopy_left: float = canopy_right - 240.0
	var roof_thickness: float = 10.0
	
	# Ensure roof taller than plant at its tallest, including max pot height
	var max_pot_height: float = 50.0 + 2.0 * 18.0  # pot_level up to 2
	var plant_max: float = plant.max_height if plant != null else 345.0
	var margin: float = 24.0
	var post_height: float = plant_max + max_pot_height + margin
	
	# Posts
	var post_color := Color(0.45, 0.34, 0.24)
	var post_w: float = 10.0
	# Front-right, back-right, front-left, back-left posts
	draw_rect(Rect2(canopy_right - post_w, ground_y - post_height, post_w, post_height), post_color)
	draw_rect(Rect2(canopy_right - 80.0 - post_w, ground_y - post_height + 4.0, post_w, post_height - 4.0), post_color)
	draw_rect(Rect2(canopy_left - post_w, ground_y - post_height + 8.0, post_w, post_height - 8.0), post_color)
	draw_rect(Rect2(canopy_left + 80.0 - post_w, ground_y - post_height + 12.0, post_w, post_height - 12.0), post_color)
	
	# Sloped roof (downward to the left)
	var roof_color := Color(0.58, 0.45, 0.32)
	var roof_y_right: float = ground_y - post_height - 6.0
	var roof_y_left: float = roof_y_right + 18.0
	var roof_pts := PackedVector2Array([
		Vector2(canopy_right, roof_y_right),
		Vector2(canopy_left, roof_y_left),
		Vector2(canopy_left, roof_y_left + roof_thickness),
		Vector2(canopy_right, roof_y_right + roof_thickness)
	])
	draw_colored_polygon(roof_pts, roof_color)
	
	# Ground shadow under canopy
	draw_rect(Rect2(canopy_left, ground_y - 10.0, canopy_right - canopy_left, 10.0), Color(0.0, 0.0, 0.0, 0.22))
