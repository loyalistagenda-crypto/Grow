extends Node
class_name MusicManager

@export var player: AudioStreamPlayer

var current_track := "default"
var speed := 1.0

func _ready() -> void:
	if player:
		player.autoplay = false
		player.pitch_scale = speed

func set_track(name: String) -> void:
	current_track = name
	var data := MusicDatabase.get_track(name)
	if player:
		var stream := load(data.get("file", ""))
		if stream:
			player.stream = stream
			player.bus = data.get("bus", "Master")
			player.play()
			player.loop = data.get("loop", true)
			player.pitch_scale = speed

func set_speed(value: float) -> void:
	speed = max(0.5, min(value, 2.0))
	if player:
		player.pitch_scale = speed
		if player.playing:
			player.play()
