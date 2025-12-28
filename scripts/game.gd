extends Node2D

var plant_scene = preload("res://scenes/plant.tscn")
var seed_count = 10

func _ready():
	update_ui()

func _input(event):
	if event.is_action_pressed("plant") and seed_count > 0:
		plant_seed()

func plant_seed():
	var player = $Player
	if player and seed_count > 0:
		var plant = plant_scene.instantiate()
		plant.position = player.position + Vector2(0, 40)
		add_child(plant)
		seed_count -= 1
		update_ui()

func update_ui():
	var label = $UI/SeedCount
	if label:
		label.text = "Seeds: " + str(seed_count)
