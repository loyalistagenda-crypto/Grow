extends Node
class_name MusicDatabase

static func get_track(name: String) -> Dictionary:
	var db := _get_db()
	if db.has(name):
		return db[name]
	return db["default"]

static func list_tracks() -> Array:
	return _get_db().keys()

static func _get_db() -> Dictionary:
	return {
		"default": {
			"file": "res://assets/audio/bg_music.mp3",
			"loop": true,
			"bus": "Music"
		}
	}
