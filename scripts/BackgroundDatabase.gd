extends Node
class_name BackgroundDatabase

static func get_background(name: String) -> Dictionary:
	var db := _get_db()
	if db.has(name):
		return db[name]
	return db["earth"]

static func list_backgrounds() -> Array:
	return _get_db().keys()

static func _get_db() -> Dictionary:
	return {
		"earth": {
			"sky_day": Color(0.55, 0.75, 0.95),
			"sky_dawn": Color(0.95, 0.65, 0.45),
			"sky_dusk": Color(0.85, 0.55, 0.45),
			"sky_night": Color(0.08, 0.08, 0.18),
			"ground": Color(0.12, 0.30, 0.14),
			"trunk": Color(0.45, 0.30, 0.15),
			"trunk_dark": Color(0.35, 0.22, 0.10),
			"branch": Color(0.50, 0.32, 0.16),
			"branch_dark": Color(0.38, 0.24, 0.12),
			"foliage": Color(0.28, 0.55, 0.25),
			"foliage_dark": Color(0.15, 0.32, 0.12),
			"foliage_bright": Color(0.60, 0.85, 0.50),
			"scenery_trunk": Color(0.35, 0.25, 0.18),
			"scenery_foliage_dark": Color(0.15, 0.40, 0.18),
			"scenery_foliage_mid": Color(0.20, 0.50, 0.22),
			"scenery_foliage_light": Color(0.25, 0.58, 0.28)
		}
	}
