# FlowerDatabase.gd - Centralized flower configuration and properties
# Each flower variant has complete behavior definitions

class_name FlowerDatabase

static func get_flower_data(variant: String) -> Dictionary:
	"""Returns complete flower data for a given variant"""
	var database = _get_database()
	if database.has(variant):
		return database[variant]
	else:
		push_error("Unknown flower variant: %s" % variant)
		return database["purple"]  # Fallback to default

static func get_all_flowers() -> Array:
	"""Returns list of all available flower variants"""
	return _get_database().keys()

static func _get_database() -> Dictionary:
	"""Master flower database with all properties"""
	return {
		"purple": {
			"name": "Purple Flower",
			"display_name": "Purple Flower",
			"color": Color(0.75, 0.55, 0.85),
			
			# Growth
			"growth_rate": 1.0,  # Multiplier on growth speed
			"max_height": 300.0,
			"bloom_threshold": 0.9,  # Growth % when flower blooms
			
			# Leaves
			"leaf_size": Vector2(34.0, 14.0),
			"leaf_color": Color(0.20, 0.50, 0.25),
			"leaf_wilted_color": Color(0.40, 0.30, 0.20),
			"leaf_brown_color": Color(0.35, 0.25, 0.15),
			"leaf_spawn_interval": 10.0,
			"leaf_max_count": 18,
			"leaf_sag_strength": 0.3,
			
			# Branches
			"branch_enabled": true,
			"branch_density": 2,  # Branches per plant
			"branch_angle_range": 45.0,
			"branch_leaf_count": 5,
			
			# Flower/Bloom
			"flower_petal_color": Color(0.85, 0.55, 0.75),
			"flower_petal_count": 6,
			"flower_size": 18.0,
			"bud_radius": 12.0,
			"bud_color": Color(0.40, 0.70, 0.45),
			
			# Sunlight preference
			"ideal_sunlight": 0.70,
			"sunlight_tolerance": 0.25,
			
			# Water/nutrient consumption
			"water_consumption": 0.05,
			"nutrient_consumption": 0.03,
		},
		
		"yellow": {
			"name": "Yellow Flower",
			"display_name": "Yellow Flower",
			"color": Color(0.95, 0.85, 0.40),
			
			"growth_rate": 1.1,  # Grows slightly faster
			"max_height": 280.0,
			"bloom_threshold": 0.85,
			
			"leaf_size": Vector2(32.0, 13.0),
			"leaf_color": Color(0.25, 0.55, 0.20),
			"leaf_wilted_color": Color(0.45, 0.35, 0.15),
			"leaf_brown_color": Color(0.40, 0.28, 0.12),
			"leaf_spawn_interval": 8.0,
			"leaf_max_count": 20,
			"leaf_sag_strength": 0.25,
			
			"branch_enabled": true,
			"branch_density": 2,
			"branch_angle_range": 50.0,
			"branch_leaf_count": 5,
			
			"flower_petal_color": Color(1.0, 0.90, 0.30),
			"flower_petal_count": 8,
			"flower_size": 20.0,
			"bud_radius": 11.0,
			"bud_color": Color(0.50, 0.75, 0.35),
			
			"ideal_sunlight": 0.85,
			"sunlight_tolerance": 0.20,
			
			"water_consumption": 0.06,
			"nutrient_consumption": 0.04,
		},
		
		"red": {
			"name": "Red Flower",
			"display_name": "Red Flower",
			"color": Color(0.90, 0.35, 0.35),
			
			"growth_rate": 0.95,  # Grows slightly slower
			"max_height": 320.0,
			"bloom_threshold": 0.88,
			
			"leaf_size": Vector2(36.0, 15.0),
			"leaf_color": Color(0.18, 0.48, 0.22),
			"leaf_wilted_color": Color(0.38, 0.28, 0.18),
			"leaf_brown_color": Color(0.32, 0.22, 0.12),
			"leaf_spawn_interval": 12.0,
			"leaf_max_count": 16,
			"leaf_sag_strength": 0.35,
			
			"branch_enabled": true,
			"branch_density": 2,
			"branch_angle_range": 40.0,
			"branch_leaf_count": 4,
			
			"flower_petal_color": Color(0.95, 0.40, 0.35),
			"flower_petal_count": 5,
			"flower_size": 22.0,
			"bud_radius": 13.0,
			"bud_color": Color(0.45, 0.70, 0.40),
			
			"ideal_sunlight": 0.75,
			"sunlight_tolerance": 0.30,
			
			"water_consumption": 0.04,
			"nutrient_consumption": 0.02,
		},
		
		"rainbow": {
			"name": "Rainbow Flower",
			"display_name": "Rainbow Flower",
			"color": Color(1.0, 1.0, 1.0),
			
			"growth_rate": 1.05,
			"max_height": 310.0,
			"bloom_threshold": 0.92,
			
			"leaf_size": Vector2(34.0, 14.0),
			"leaf_color": Color(0.22, 0.52, 0.24),
			"leaf_wilted_color": Color(0.42, 0.32, 0.19),
			"leaf_brown_color": Color(0.37, 0.26, 0.14),
			"leaf_spawn_interval": 9.0,
			"leaf_max_count": 19,
			"leaf_sag_strength": 0.28,
			
			"branch_enabled": true,
			"branch_density": 2,
			"branch_angle_range": 45.0,
			"branch_leaf_count": 5,
			
			"flower_petal_color": Color(1.0, 1.0, 1.0),  # Will be rainbow in code
			"flower_petal_count": 12,
			"flower_size": 24.0,
			"bud_radius": 12.0,
			"bud_color": Color(0.48, 0.72, 0.42),
			
			"ideal_sunlight": 0.70,
			"sunlight_tolerance": 0.25,
			
			"water_consumption": 0.05,
			"nutrient_consumption": 0.03,
		},
		
		"rose_bush": {
			"name": "Rose Bush",
			"display_name": "Rose Bush",
			"color": Color(0.95, 0.45, 0.55),
			
			"growth_rate": 0.90,
			"max_height": 250.0,
			"bloom_threshold": 0.87,
			
			"leaf_size": Vector2(30.0, 12.0),
			"leaf_color": Color(0.20, 0.50, 0.25),
			"leaf_wilted_color": Color(0.40, 0.30, 0.20),
			"leaf_brown_color": Color(0.35, 0.25, 0.15),
			"leaf_spawn_interval": 11.0,
			"leaf_max_count": 15,
			"leaf_sag_strength": 0.20,
			
			"branch_enabled": true,
			"branch_density": 4,  # More branches
			"branch_angle_range": 55.0,
			"branch_leaf_count": 4,
			
			"flower_petal_color": Color(0.95, 0.45, 0.55),
			"flower_petal_count": 8,
			"flower_size": 20.0,
			"bud_radius": 11.0,
			"bud_color": Color(0.40, 0.70, 0.45),
			
			"ideal_sunlight": 0.65,
			"sunlight_tolerance": 0.28,
			
			"water_consumption": 0.07,
			"nutrient_consumption": 0.05,
		},
		
		"rainbow_rose_bush": {
			"name": "Rainbow Rose Bush",
			"display_name": "Rainbow Rose Bush",
			"color": Color(1.0, 0.75, 0.85),
			
			"growth_rate": 0.92,
			"max_height": 255.0,
			"bloom_threshold": 0.90,
			
			"leaf_size": Vector2(31.0, 12.5),
			"leaf_color": Color(0.21, 0.51, 0.26),
			"leaf_wilted_color": Color(0.41, 0.31, 0.21),
			"leaf_brown_color": Color(0.36, 0.26, 0.16),
			"leaf_spawn_interval": 10.0,
			"leaf_max_count": 16,
			"leaf_sag_strength": 0.22,
			
			"branch_enabled": true,
			"branch_density": 4,
			"branch_angle_range": 55.0,
			"branch_leaf_count": 4,
			
			"flower_petal_color": Color(1.0, 1.0, 1.0),  # Will be rainbow
			"flower_petal_count": 10,
			"flower_size": 21.0,
			"bud_radius": 11.5,
			"bud_color": Color(0.42, 0.71, 0.46),
			
			"ideal_sunlight": 0.68,
			"sunlight_tolerance": 0.26,
			
			"water_consumption": 0.07,
			"nutrient_consumption": 0.05,
		},
		
		"practice_ivy": {
			"name": "Practice Ivy",
			"display_name": "Practice Ivy",
			"color": Color(0.60, 0.85, 0.50),
			
			# Very fast growth - ideal for testing
			"growth_rate": 2.0,
			"max_height": 280.0,
			"bloom_threshold": 0.80,  # Blooms earlier
			
			# Lots of small delicate leaves
			"leaf_size": Vector2(20.0, 8.0),
			"leaf_color": Color(0.30, 0.60, 0.20),
			"leaf_wilted_color": Color(0.50, 0.40, 0.25),
			"leaf_brown_color": Color(0.45, 0.35, 0.20),
			"leaf_spawn_interval": 3.0,  # Spawns very frequently
			"leaf_max_count": 35,  # Lots of leaves
			"leaf_sag_strength": 0.15,  # Minimal sag - stays perky
			
			# Many winding branches
			"branch_enabled": true,
			"branch_density": 6,  # More branches than others
			"branch_angle_range": 60.0,  # More variation
			"branch_leaf_count": 3,
			
			# Delicate flower
			"flower_petal_color": Color(0.70, 0.90, 0.55),
			"flower_petal_count": 4,
			"flower_size": 14.0,
			"bud_radius": 8.0,
			"bud_color": Color(0.50, 0.75, 0.40),
			
			# Ivy prefers shade
			"ideal_sunlight": 0.40,
			"sunlight_tolerance": 0.35,
			
			# Moderate water/nutrient needs
			"water_consumption": 0.04,
			"nutrient_consumption": 0.02,
		},
	}
