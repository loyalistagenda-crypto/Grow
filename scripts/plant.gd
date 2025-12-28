extends Node2D

var growth_stage = 0
var max_growth_stage = 3
var growth_timer = 0.0
var growth_interval = 3.0  # seconds between growth stages

func _ready():
	update_visual()

func _process(delta):
	if growth_stage < max_growth_stage:
		growth_timer += delta
		if growth_timer >= growth_interval:
			growth_timer = 0.0
			grow()

func grow():
	growth_stage += 1
	update_visual()
	if growth_stage >= max_growth_stage:
		print("Plant fully grown!")

func update_visual():
	var sprite = $Sprite2D
	if sprite:
		# Scale the plant as it grows
		var scale_factor = 1.0 + (growth_stage * 0.5)
		sprite.scale = Vector2(scale_factor, scale_factor)
