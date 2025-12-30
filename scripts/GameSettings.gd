extends Node
class_name GameSettings

# Centralized game settings to allow modular reuse across scenes
var current_flower: String = "purple"
var current_background: String = "earth"
var current_music: String = "default"
var music_speed: float = 1.0

func set_flower(variant: String) -> void:
	current_flower = variant

func set_background(name: String) -> void:
	current_background = name

func set_music(track: String) -> void:
	current_music = track

func set_music_speed(speed: float) -> void:
	music_speed = clampf(speed, 0.5, 2.0)
