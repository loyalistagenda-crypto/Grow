extends Node2D

var plant: Plant
var stats_label: Label
var info_label: Label
var action_hint: Label
var ground_height: float = 120.0
var sky_color: Color = Color(0.36, 0.48, 0.72)
var ground_color: Color = Color(0.12, 0.30, 0.14)
var sunlight_indicator: ProgressBar
var action_buttons: Dictionary = {}
var ui_layer: CanvasLayer
var drag_active: bool = false
var drag_button: int = -1
var pot_dragging: bool = false
var pot_drag_offset: float = 0.0

enum GameState { MENU, PLAYING }
var game_state: int = GameState.MENU
var menu_layer: CanvasLayer
var selected_flower_variant: String = "purple"

enum Action { WATER, FEED, PRUNE, SUN_DEC, SUN_INC, REPOT }
var current_action: int = Action.WATER
var drag_water_rate: float = 0.55
var drag_feed_rate: float = 0.35
var music_player: AudioStreamPlayer
var music_muted: bool = false

# Day/Night cycle
@export var cycle_seconds: float = 240.0
var cycle_time: float = 0.0
var stars: PackedVector2Array = PackedVector2Array()
var star_alpha: float = 0.0
var sky_day: Color = Color(0.55, 0.75, 0.95)
var sky_dawn: Color = Color(0.95, 0.65, 0.45)
var sky_dusk: Color = Color(0.85, 0.55, 0.45)
var sky_night: Color = Color(0.08, 0.08, 0.18)

# Ambient critters
var critters: Array = []
var bird_timer: float = 0.0
var squirrel_timer: float = 0.0
var butterfly_timer: float = 0.0

# Clouds
var clouds: Array = []

# Shooting stars
var shooting_stars: Array = []
var shooting_star_timer: float = 0.0

func _ready() -> void:
	RenderingServer.set_default_clear_color(sky_color)
	_build_menu()
	_setup_music()
	set_process(true)
	get_viewport().size_changed.connect(_on_size_changed)
	_generate_stars(90)
	_initialize_clouds()

func _process(delta: float) -> void:
	# Update clouds
	for cloud in clouds:
		cloud.x += cloud.speed * delta
		# Wrap around screen
		var view := get_viewport_rect().size
		if cloud.x > view.x + 100.0:
			cloud.x = -100.0
	
	# Handle pot dragging
	if pot_dragging and game_state == GameState.PLAYING:
		var mouse_pos := get_viewport().get_mouse_position()
		var new_x := mouse_pos.x - pot_drag_offset
		var view_width := get_viewport_rect().size.x
		plant.position.x = clampf(new_x, 100.0, view_width - 100.0)
	
	# Calculate sunlight based on position under awning
	if plant and game_state == GameState.PLAYING:
		var view_width := get_viewport_rect().size.x
		# Canopy coverage bounds (open shed: four posts + sloped roof)
		var shed_left: float = view_width - 300.0
		var shed_full_cover: float = view_width - 180.0
		var plant_x := plant.position.x
		
		if plant_x >= shed_full_cover:
			# Fully under shed - very low light
			plant.adjust_sunlight(0.10 - plant.sunlight_setting)
		elif plant_x >= shed_left:
			# Partially under awning - gradient from full sun to shade
			var under_amount := (plant_x - shed_left) / (shed_full_cover - shed_left)
			var target_sun: float = lerp(0.95, 0.10, under_amount)
			plant.adjust_sunlight(target_sun - plant.sunlight_setting)
		else:
			# Fully in sun
			plant.adjust_sunlight(0.95 - plant.sunlight_setting)
	
	if stats_label and plant and game_state == GameState.PLAYING:
		var s := plant.get_status()
		stats_label.text = "Stage: %s\nGrowth: %d%% (cap %d%%)\nBloom: %d%%\nMoisture: %d%%\nNutrients: %d%%\nSunlight: %d%% (ideal %d%%)\nWilted leaves: %d\nPot: %s" % [
			s.get("stage", ""),
			round(s.get("growth", 0.0) * 100.0),
			round(s.get("pot_cap", 0.0) * 100.0),
			round(s.get("bloom", 0.0) * 100.0),
			round(s.get("moisture", 0.0) * 100.0),
			round(s.get("nutrients", 0.0) * 100.0),
			round(s.get("sunlight", 0.0) * 100.0),
			round(plant.ideal_sunlight * 100.0),
			int(s.get("wilted", 0)),
			_pot_name(int(s.get("pot_level", 0))),
		]
		if sunlight_indicator:
			sunlight_indicator.value = s.get("sunlight", 0.0) * 100.0
	if drag_active and plant and game_state == GameState.PLAYING:
		# Only apply draggable actions during drag
		if current_action == Action.WATER or current_action == Action.FEED:
			_apply_action_drag(delta)

	# Advance day/night cycle and update sky; global fast-forward via Engine.time_scale
	var accel: bool = Input.is_key_pressed(KEY_QUOTELEFT)
	Engine.time_scale = 10.0 if accel else 1.0
	cycle_time += delta
	if cycle_time >= cycle_seconds:
		cycle_time -= cycle_seconds
	var p: float = cycle_time / cycle_seconds
	sky_color = _sky_color(p)
	star_alpha = _star_alpha(p)
	RenderingServer.set_default_clear_color(sky_color)
	
	# Spawn and update critters
	_update_critters(delta)
	
	# Update shooting stars
	_update_shooting_stars(delta, p)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if game_state != GameState.PLAYING:
		return
	if plant == null:
		return
	if event is InputEventMouseButton:
		if event.pressed:
			# Check if clicking on pot area
			var mouse_pos := get_viewport().get_mouse_position()
			var pot_area := Rect2(plant.position.x - 80.0, plant.position.y - 20.0, 160.0, 80.0)
			if pot_area.has_point(mouse_pos):
				pot_dragging = true
				pot_drag_offset = mouse_pos.x - plant.position.x
			else:
				drag_active = true
				drag_button = event.button_index
				_apply_action_press()
		else:
			pot_dragging = false
			drag_active = false
			drag_button = -1
	if event is InputEventScreenTouch:
		drag_active = event.pressed
		drag_button = 0 if event.pressed else -1
		if event.pressed:
			_apply_action_press()
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				ui_layer.visible = not ui_layer.visible
			KEY_M:
				_toggle_music()
			KEY_F:
				plant.feed_nutrients()
			KEY_P:
				plant.prune()
			KEY_R:
				plant.repot()

func _build_menu() -> void:
	menu_layer = CanvasLayer.new()
	add_child(menu_layer)
	
	var center := MarginContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.offset_left = -200.0
	center.offset_top = -100.0
	center.offset_right = 200.0
	center.offset_bottom = 100.0
	menu_layer.add_child(center)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)
	
	var title := Label.new()
	title.text = "Grow a Single Plant"
	title.add_theme_font_size_override("font_size", 42)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# Flower selection label
	var flower_label := Label.new()
	flower_label.text = "Choose a Plant Type:"
	flower_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(flower_label)
	
	# Scrollable flower selection container
	var scroll_container := ScrollContainer.new()
	scroll_container.custom_minimum_size = Vector2(300.0, 240.0)
	vbox.add_child(scroll_container)
	
	var flower_grid := VBoxContainer.new()
	flower_grid.add_theme_constant_override("separation", 8)
	scroll_container.add_child(flower_grid)
	
	# Create 3 flower option buttons
	var flowers := [
		{"name": "Purple Flower", "variant": "purple", "color": Color(0.75, 0.55, 0.85)},
		{"name": "Yellow Flower", "variant": "yellow", "color": Color(0.95, 0.85, 0.40)},
		{"name": "Red Flower", "variant": "red", "color": Color(0.90, 0.35, 0.35)},
		{"name": "Rainbow Flower", "variant": "rainbow", "color": Color(1.0, 1.0, 1.0)},
		{"name": "Rose Bush", "variant": "rose_bush", "color": Color(0.95, 0.45, 0.55)}
	]
	
	for flower in flowers:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(260.0, 50.0)
		btn.text = flower["name"]
		btn.add_theme_color_override("font_color", flower["color"])
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(_on_flower_selected.bindv([flower["variant"]]))
		flower_grid.add_child(btn)
	
	var continue_btn := Button.new()
	continue_btn.text = "Continue Saved Flower"
	continue_btn.custom_minimum_size = Vector2(300.0, 50.0)
	continue_btn.pressed.connect(_on_continue_game)
	vbox.add_child(continue_btn)

func _on_flower_selected(variant: String) -> void:
	selected_flower_variant = variant
	game_state = GameState.PLAYING
	menu_layer.queue_free()
	_build_scene()
	_build_ui()

func _on_continue_game() -> void:
	# TODO: Load saved game data
	game_state = GameState.PLAYING
	menu_layer.queue_free()
	_build_scene()
	_build_ui()

func _build_scene() -> void:
	plant = Plant.new()
	plant.set_flower_variant(selected_flower_variant)
	var view := get_viewport_rect().size
	plant.position = Vector2(view.x * 0.5, view.y - ground_height + 6.0)
	add_child(plant)
	# Add shed as a separate foreground node so it renders above the plant
	var shed: Shed = Shed.new()
	shed.ground_height = ground_height
	shed.plant = plant
	shed.z_index = plant.z_index + 1
	add_child(shed)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	ui_layer = layer
	add_child(layer)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.offset_left = 16.0
	margin.offset_top = 16.0
	margin.offset_right = 320.0
	margin.offset_bottom = 200.0
	layer.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Grow a Single Plant"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)

	info_label = Label.new()
	info_label.text = "Choose an action below or use keys. Drag while watering/feeding to keep applying."
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(info_label)

	action_hint = Label.new()
	action_hint.text = "Current action: Water"
	action_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(action_hint)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	box.add_child(actions)

	_add_action_button(actions, "Water", Action.WATER)
	_add_action_button(actions, "Feed", Action.FEED)
	_add_action_button(actions, "Prune", Action.PRUNE)
	_add_action_button(actions, "Repot", Action.REPOT)
	_update_action_hint()

	# Music toggle button
	var music_btn := Button.new()
	music_btn.text = "Music: ON"
	music_btn.pressed.connect(_toggle_music)
	box.add_child(music_btn)
	action_buttons["music"] = music_btn

	# Return to menu button
	var menu_btn := Button.new()
	menu_btn.text = "Return to Menu"
	menu_btn.pressed.connect(_return_to_menu)
	box.add_child(menu_btn)

	stats_label = Label.new()
	stats_label.text = "Growth: 0%\nMoisture: 0%"
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(stats_label)

	sunlight_indicator = ProgressBar.new()
	sunlight_indicator.min_value = 0.0
	sunlight_indicator.max_value = 100.0
	sunlight_indicator.value = plant.sunlight_setting * 100.0
	sunlight_indicator.custom_minimum_size = Vector2(260.0, 10.0)
	sunlight_indicator.show_percentage = false
	box.add_child(sunlight_indicator)

func _draw() -> void:
	var view := get_viewport_rect().size
	# Sky
	draw_rect(Rect2(Vector2(-24.0, -24.0), Vector2(view.x + 48.0, view.y + 48.0)), sky_color)
	# Sun and moon
	var p: float = cycle_time / cycle_seconds
	var sun_pos := _sun_position(view, p)
	var moon_pos := _moon_position(view, p)
	var sun_col := Color(0.98, 0.90, 0.55)
	var moon_col := Color(0.85, 0.88, 0.95)
	var horizon: float = view.y - ground_height
	var sun_active: bool = p >= 0.00 and p <= 0.58
	var moon_active: bool = p >= 0.55 or p >= 0.95
	if sun_active and sun_pos.y < horizon + 30.0:
		draw_circle(sun_pos, 24.0, sun_col)
	if moon_active and moon_pos.y < horizon:
		draw_circle(moon_pos, 20.0, moon_col)
	# Stars (fade in at night)
	if star_alpha > 0.01:
		for v in stars:
			if v.y < view.y - ground_height - 6.0:
				draw_circle(v, 1.8, Color(1.0, 1.0, 1.0, star_alpha))
	
	# Shooting stars
	_draw_shooting_stars()
	
	# Scenery
	_draw_scenery(view)
	
	# Critters
	_draw_critters(view)
	
	# Ground
	draw_rect(Rect2(Vector2(-24.0, view.y - ground_height), Vector2(view.x + 48.0, ground_height + 32.0)), ground_color)


func _on_size_changed() -> void:
	if plant:
		var view := get_viewport_rect().size
		plant.position = Vector2(view.x * 0.5, view.y - ground_height + 6.0)
	_generate_stars(stars.size())

func _pot_name(level: int) -> String:
	match level:
		0:
			return "Starter"
		1:
			return "Medium"
		_:
			return "Large"

func _add_action_button(container: HBoxContainer, label: String, action: int) -> void:
	var b := Button.new()
	b.text = label
	b.toggle_mode = true
	b.button_pressed = action == current_action
	b.pressed.connect(Callable(self, "_on_action_button").bind(action))
	container.add_child(b)
	action_buttons[action] = b

func _set_action(action: int) -> void:
	current_action = action
	for key in action_buttons.keys():
		if key is int:  # Only process integer action keys
			action_buttons[key].button_pressed = key == current_action
	_update_action_hint()

func _on_action_button(action: int) -> void:
	_set_action(action)

func _draw_shed(view: Vector2) -> void:
	# Minimal cozy shed: four wooden posts with a sloped roof (open sides)
	var ground_y := view.y - ground_height
	var canopy_right := view.x - 60.0
	var canopy_left := canopy_right - 240.0
	var post_height := 160.0
	var roof_thickness := 10.0
	
	# Posts
	var post_color := Color(0.45, 0.34, 0.24)
	var post_w := 10.0
	# Front-right, back-right, front-left, back-left posts
	draw_rect(Rect2(canopy_right - post_w, ground_y - post_height, post_w, post_height), post_color)
	draw_rect(Rect2(canopy_right - 80.0 - post_w, ground_y - post_height + 4.0, post_w, post_height - 4.0), post_color)
	draw_rect(Rect2(canopy_left - post_w, ground_y - post_height + 8.0, post_w, post_height - 8.0), post_color)
	draw_rect(Rect2(canopy_left + 80.0 - post_w, ground_y - post_height + 12.0, post_w, post_height - 12.0), post_color)
	
	# Sloped roof (downward to the left)
	var roof_color := Color(0.58, 0.45, 0.32)
	var roof_y_right := ground_y - post_height - 6.0
	var roof_y_left := roof_y_right + 18.0
	var roof_pts := PackedVector2Array([
		Vector2(canopy_right, roof_y_right),
		Vector2(canopy_left, roof_y_left),
		Vector2(canopy_left, roof_y_left + roof_thickness),
		Vector2(canopy_right, roof_y_right + roof_thickness)
	])
	draw_colored_polygon(roof_pts, roof_color)
	
	# Ground shadow under canopy
	draw_rect(Rect2(canopy_left, ground_y - 10.0, canopy_right - canopy_left, 10.0), Color(0.0, 0.0, 0.0, 0.22))


func _update_action_hint() -> void:
	var name := ""
	match current_action:
		Action.WATER:
			name = "Water"
		Action.FEED:
			name = "Feed nutrients"
		Action.PRUNE:
			name = "Prune wilted leaves"
		Action.REPOT:
			name = "Repot"
	action_hint.text = "Current action: %s" % name

func _apply_action_press() -> void:
	if plant == null:
		return
	# Non-draggable actions should not activate drag mode
	if current_action in [Action.PRUNE, Action.REPOT]:
		drag_active = false
		drag_button = -1
	match current_action:
		Action.WATER:
			plant.water()
		Action.FEED:
			plant.feed_nutrients()
		Action.PRUNE:
			plant.prune()
		Action.REPOT:
			plant.repot()

func _apply_action_drag(delta: float) -> void:
	if plant == null:
		return
	match current_action:
		Action.WATER:
			plant.water(delta * drag_water_rate)
		Action.FEED:
			plant.feed_nutrients(delta * drag_feed_rate)
		_:
			pass

func _sky_color(p: float) -> Color:
	# Phases: dawn 0.00-0.15, day 0.15-0.4167, dusk 0.4167-0.5167,
	# night deepen 0.5167-0.8583, pre-dawn 0.8583-1.00 (night -> dawn).
	if p < 0.15:
		var t: float = p / 0.15
		return sky_dawn.lerp(sky_day, t)
	elif p < 0.4167:
		return sky_day
	elif p < 0.5167:
		var t: float = (p - 0.4167) / 0.10
		return sky_day.lerp(sky_dusk, t)
	elif p < 0.8583:
		var t: float = (p - 0.5167) / 0.3416
		return sky_dusk.lerp(sky_night, t)
	else:
		var t: float = (p - 0.8583) / 0.1417
		return sky_night.lerp(sky_dawn, clampf(t, 0.0, 1.0))

func _star_alpha(p: float) -> float:
	# Stars fade in 0.5167-0.8583, fade out 0.8583-1.00 for smooth dawn.
	if p < 0.5167:
		return 0.0
	elif p < 0.8583:
		var t: float = (p - 0.5167) / 0.3416
		return clampf(t, 0.0, 1.0)
	else:
		var t: float = (1.0 - p) / 0.1417
		return clampf(t, 0.0, 1.0)

func _sun_position(view: Vector2, p: float) -> Vector2:
	# Sun arc during 0.00-0.58 of cycle (dawn through day). Use a semicircle above the horizon.
	var t: float = clampf(p / 0.58, 0.0, 1.0)
	var cx: float = view.x * 0.5
	var cy: float = view.y - ground_height
	var r: float = minf(view.x, view.y) * 0.48
	var theta: float = PI * (1.0 - t) # PI -> 0 (left horizon to right horizon)
	var x: float = cx + cos(theta) * r
	var y: float = cy - sin(theta) * r # minus to move upward for positive sin
	return Vector2(x, y)

func _moon_position(view: Vector2, p: float) -> Vector2:
	# Moon arc during 0.55-0.95 of cycle (dusk through night). Use a semicircle above the horizon.
	var t: float = clampf((p - 0.55) / 0.40, 0.0, 1.0)
	var cx: float = view.x * 0.5
	var cy: float = view.y - ground_height
	var r: float = minf(view.x, view.y) * 0.40
	var theta: float = PI * (1.0 - t)
	var x: float = cx + cos(theta) * r
	var y: float = cy - sin(theta) * r
	return Vector2(x, y)

func _generate_stars(count: int) -> void:
	var view := get_viewport_rect().size
	stars = PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(count):
		var x := rng.randf_range(16.0, view.x - 16.0)
		var y := rng.randf_range(16.0, view.y - ground_height - 24.0)
		stars.append(Vector2(x, y))
func _update_shooting_stars(delta: float, cycle_p: float) -> void:
	# Only spawn during night (when stars are visible)
	if star_alpha > 0.3:
		shooting_star_timer -= delta
		if shooting_star_timer <= 0.0:
			shooting_star_timer = randf_range(8.0, 20.0)
			var view := get_viewport_rect().size
			var start_x: float = randf_range(view.x * 0.2, view.x * 0.8)
			var start_y: float = randf_range(40.0, view.y * 0.4)
			var angle: float = randf_range(0.087, 0.785)  # 5 to 45 degrees (downward-right)
			var speed: float = randf_range(400.0, 700.0)
			var length: float = randf_range(60.0, 120.0)
			shooting_stars.append({
				"x": start_x,
				"y": start_y,
				"angle": angle,
				"speed": speed,
				"length": length,
				"life": 0.0,
				"max_life": randf_range(1.2, 2.0)
			})
	
	# Update existing shooting stars
	var i: int = 0
	while i < shooting_stars.size():
		var star: Dictionary = shooting_stars[i]
		star.life += delta
		star.x += cos(star.angle) * star.speed * delta
		star.y += sin(star.angle) * star.speed * delta
		
		# Remove if off screen or life expired
		var view := get_viewport_rect().size
		if star.life > star.max_life or star.x < -100.0 or star.x > view.x + 100.0 or star.y > view.y:
			shooting_stars.remove_at(i)
		else:
			i += 1

func _draw_shooting_stars() -> void:
	for star in shooting_stars:
		# Fade in and out based on life progress
		var life_progress: float = star.life / star.max_life
		var alpha: float = 0.0
		if life_progress < 0.2:
			alpha = life_progress / 0.2
		elif life_progress > 0.8:
			alpha = (1.0 - life_progress) / 0.2
		else:
			alpha = 1.0
		
		var head_pos := Vector2(star.x, star.y)
		var star_length: float = star.length
		var star_angle: float = star.angle
		var tail_offset := Vector2(cos(star_angle + PI), sin(star_angle + PI)) * star_length
		var tail_pos := head_pos + tail_offset
		
		# Draw streak with gradient (bright head to faded tail)
		draw_line(head_pos, tail_pos, Color(1.0, 1.0, 1.0, alpha * star_alpha * 0.9), 2.5, true)
		draw_circle(head_pos, 2.0, Color(1.0, 1.0, 0.95, alpha * star_alpha))
func _initialize_clouds() -> void:
	var view := get_viewport_rect().size
	# Create 4 clouds with varying sizes and speeds
	for i in range(4):
		var size_scale := randf_range(0.5, 1.5)
		var speed := randf_range(15.0, 40.0)
		var x_pos := randf_range(0.0, view.x)
		var y_pos := randf_range(view.y * 0.1, view.y * 0.3)
		clouds.append({
			"x": x_pos,
			"y": y_pos,
			"size_scale": size_scale,
			"speed": speed
		})

func _update_critters(delta: float) -> void:
	var view := get_viewport_rect().size
	
	# Spawn birds
	bird_timer -= delta
	if bird_timer <= 0.0:
		bird_timer = randf_range(16.0, 36.0)
		var y: float = randf_range(40.0, view.y - ground_height - 100.0)
		critters.append({"type": "bird", "x": -30.0, "y": y, "speed": randf_range(60.0, 120.0), "flap": 0.0})
	
	# Spawn squirrels
	squirrel_timer -= delta
	if squirrel_timer <= 0.0:
		squirrel_timer = randf_range(24.0, 50.0)
		var dir: int = 1 if randf() > 0.5 else -1
		var x: float = -30.0 if dir > 0 else view.x + 30.0
		critters.append({"type": "squirrel", "x": x, "y": view.y - ground_height, "speed": randf_range(80.0, 140.0) * float(dir), "hop": 0.0})
	
	# Spawn butterflies
	butterfly_timer -= delta
	if butterfly_timer <= 0.0:
		butterfly_timer = randf_range(12.0, 30.0)
		var y: float = randf_range(80.0, view.y - ground_height - 60.0)
		critters.append({"type": "butterfly", "x": -20.0, "y": y, "speed": randf_range(30.0, 60.0), "flutter": 0.0, "wave": randf_range(0.0, TAU)})
	
	# Update and remove off-screen critters
	var i: int = 0
	while i < critters.size():
		var c: Dictionary = critters[i]
		c.x += c.speed * delta
		if c.type == "bird":
			c.flap += delta * 12.0
		elif c.type == "squirrel":
			c.hop += delta * 8.0
		elif c.type == "butterfly":
			c.flutter += delta * 15.0
			c.wave += delta * 2.0
			c.y += sin(c.wave) * 25.0 * delta
		
		if c.x < -50.0 or c.x > view.x + 50.0:
			critters.remove_at(i)
		else:
			i += 1

func _draw_scenery(view: Vector2) -> void:
	# Draw moving clouds
	var cloud_col := Color(1.0, 1.0, 1.0, 0.7)
	for cloud in clouds:
		var scale: float = cloud.size_scale
		var base_x: float = cloud.x
		var base_y: float = cloud.y
		# Three overlapping semi-circles for fluffy cloud effect
		var r1 := 16.0 * scale
		var r2 := 20.0 * scale
		var r3 := 14.0 * scale
		draw_arc(Vector2(base_x - 12.0 * scale, base_y), r1, PI, TAU, 32, cloud_col, r1 * 0.9, true)
		draw_arc(Vector2(base_x + 3.0 * scale, base_y - 4.0 * scale), r2, PI, TAU, 32, cloud_col, r2 * 0.9, true)
		draw_arc(Vector2(base_x + 18.0 * scale, base_y), r3, PI, TAU, 32, cloud_col, r3 * 0.9, true)
	
	# Tree clusters
	var ground_y: float = view.y - ground_height
	
	# Left tree cluster
	var tree1_x: float = view.x * 0.12
	# Trunks
	var trunk_col := Color(0.35, 0.25, 0.18)
	draw_rect(Rect2(tree1_x - 6.0, ground_y - 45.0, 12.0, 45.0), trunk_col)
	draw_rect(Rect2(tree1_x + 25.0, ground_y - 38.0, 10.0, 38.0), trunk_col)
	draw_rect(Rect2(tree1_x - 28.0, ground_y - 40.0, 11.0, 40.0), trunk_col)
	# Foliage layers
	var foliage_dark := Color(0.15, 0.40, 0.18)
	var foliage_mid := Color(0.20, 0.50, 0.22)
	var foliage_light := Color(0.25, 0.58, 0.28)
	draw_circle(Vector2(tree1_x, ground_y - 48.0), 28.0, foliage_dark)
	draw_circle(Vector2(tree1_x - 8.0, ground_y - 52.0), 24.0, foliage_mid)
	draw_circle(Vector2(tree1_x + 10.0, ground_y - 54.0), 22.0, foliage_light)
	draw_circle(Vector2(tree1_x + 25.0, ground_y - 42.0), 24.0, foliage_dark)
	draw_circle(Vector2(tree1_x + 18.0, ground_y - 46.0), 20.0, foliage_mid)
	draw_circle(Vector2(tree1_x - 28.0, ground_y - 44.0), 26.0, foliage_dark)
	draw_circle(Vector2(tree1_x - 24.0, ground_y - 48.0), 22.0, foliage_light)
	
	# Right tree cluster
	var tree2_x: float = view.x * 0.88
	draw_rect(Rect2(tree2_x - 5.0, ground_y - 42.0, 10.0, 42.0), trunk_col)
	draw_rect(Rect2(tree2_x + 20.0, ground_y - 36.0, 9.0, 36.0), trunk_col)
	draw_circle(Vector2(tree2_x, ground_y - 45.0), 26.0, foliage_dark)
	draw_circle(Vector2(tree2_x - 6.0, ground_y - 49.0), 22.0, foliage_mid)
	draw_circle(Vector2(tree2_x + 8.0, ground_y - 51.0), 20.0, foliage_light)
	draw_circle(Vector2(tree2_x + 20.0, ground_y - 40.0), 22.0, foliage_dark)
	draw_circle(Vector2(tree2_x + 16.0, ground_y - 44.0), 18.0, foliage_mid)
	
	# Rocks
	var rock_col := Color(0.48, 0.48, 0.52)
	var rock_shadow := Color(0.35, 0.35, 0.38)
	var rock_pts := PackedVector2Array([
		Vector2(view.x * 0.06, ground_y + 12.0),
		Vector2(view.x * 0.06 + 14.0, ground_y + 2.0),
		Vector2(view.x * 0.06 + 26.0, ground_y + 6.0),
		Vector2(view.x * 0.06 + 22.0, ground_y + 14.0),
	])
	draw_colored_polygon(rock_pts, rock_col)
	var rock2_pts := PackedVector2Array([
		Vector2(view.x * 0.06 + 8.0, ground_y + 8.0),
		Vector2(view.x * 0.06 + 12.0, ground_y + 4.0),
		Vector2(view.x * 0.06 + 18.0, ground_y + 10.0),
	])
	draw_colored_polygon(rock2_pts, rock_shadow)

func _draw_critters(view: Vector2) -> void:
	for c in critters:
		if c.type == "bird":
			# Detailed bird with body, head, beak, wings, tail
			var body_col := Color(0.25, 0.22, 0.28)
			var wing_col := Color(0.20, 0.18, 0.24)
			var wing_up: bool = int(c.flap) % 2 == 0
			var wing_angle: float = -0.3 if wing_up else 0.4
			
			# Body (oval)
			var body_pts := PackedVector2Array([
				Vector2(c.x - 6.0, c.y),
				Vector2(c.x - 4.0, c.y - 3.5),
				Vector2(c.x + 2.0, c.y - 4.0),
				Vector2(c.x + 6.0, c.y - 2.0),
				Vector2(c.x + 4.0, c.y + 2.0),
				Vector2(c.x - 2.0, c.y + 3.0),
			])
			draw_colored_polygon(body_pts, body_col)
			
			# Head
			draw_circle(Vector2(c.x + 6.0, c.y - 2.0), 3.0, body_col)
			
			# Beak
			var beak_pts := PackedVector2Array([
				Vector2(c.x + 8.0, c.y - 2.0),
				Vector2(c.x + 11.0, c.y - 1.5),
				Vector2(c.x + 8.0, c.y - 1.0),
			])
			draw_colored_polygon(beak_pts, Color(0.85, 0.65, 0.35))
			
			# Wings
			var left_wing := PackedVector2Array([
				Vector2(c.x - 2.0, c.y - 1.0),
				Vector2(c.x - 12.0, c.y + wing_angle * 15.0),
				Vector2(c.x - 10.0, c.y + wing_angle * 10.0 + 3.0),
				Vector2(c.x - 4.0, c.y + 2.0),
			])
			var right_wing := PackedVector2Array([
				Vector2(c.x + 1.0, c.y - 1.0),
				Vector2(c.x + 11.0, c.y + wing_angle * 15.0),
				Vector2(c.x + 9.0, c.y + wing_angle * 10.0 + 3.0),
				Vector2(c.x + 2.0, c.y + 2.0),
			])
			draw_colored_polygon(left_wing, wing_col)
			draw_colored_polygon(right_wing, wing_col)
			
			# Tail
			var tail_pts := PackedVector2Array([
				Vector2(c.x - 6.0, c.y),
				Vector2(c.x - 10.0, c.y - 2.0),
				Vector2(c.x - 10.0, c.y + 2.0),
			])
			draw_colored_polygon(tail_pts, wing_col)
			
		elif c.type == "squirrel":
			# Detailed squirrel with body, head, ears, legs, bushy tail
			var sq_body := Color(0.58, 0.38, 0.22)
			var sq_dark := Color(0.48, 0.28, 0.15)
			var hop_offset: float = abs(sin(c.hop)) * 5.0
			var body_y: float = c.y - 10.0 - hop_offset
			var facing: float = 1.0 if c.speed > 0.0 else -1.0
			
			# Bushy tail (layered circles)
			var tail_x: float = c.x - 8.0 * facing
			draw_circle(Vector2(tail_x, body_y - 8.0), 7.0, sq_dark)
			draw_circle(Vector2(tail_x - 3.0 * facing, body_y - 12.0), 6.5, sq_body)
			draw_circle(Vector2(tail_x - 6.0 * facing, body_y - 15.0), 6.0, sq_dark)
			draw_circle(Vector2(tail_x - 8.0 * facing, body_y - 17.0), 5.0, sq_body)
			
			# Body (oval)
			var body_pts := PackedVector2Array([
				Vector2(c.x - 6.0, body_y),
				Vector2(c.x - 5.0, body_y - 6.0),
				Vector2(c.x + 2.0, body_y - 7.0),
				Vector2(c.x + 6.0, body_y - 4.0),
				Vector2(c.x + 5.0, body_y + 2.0),
				Vector2(c.x - 3.0, body_y + 3.0),
			])
			draw_colored_polygon(body_pts, sq_body)
			
			# Head
			var head_x: float = c.x + 4.0 * facing
			draw_circle(Vector2(head_x, body_y - 6.0), 4.5, sq_body)
			
			# Ears
			var ear1_pts := PackedVector2Array([
				Vector2(head_x - 2.0, body_y - 9.0),
				Vector2(head_x - 1.0, body_y - 12.0),
				Vector2(head_x, body_y - 9.5),
			])
			var ear2_pts := PackedVector2Array([
				Vector2(head_x + 2.0, body_y - 9.0),
				Vector2(head_x + 3.0, body_y - 12.0),
				Vector2(head_x + 4.0, body_y - 9.5),
			])
			draw_colored_polygon(ear1_pts, sq_dark)
			draw_colored_polygon(ear2_pts, sq_dark)
			
			# Eye
			draw_circle(Vector2(head_x + 2.0 * facing, body_y - 6.5), 1.2, Color(0.1, 0.1, 0.1))
			
			# Legs (animated with hop)
			var leg_forward: float = sin(c.hop) * 3.0
			draw_line(Vector2(c.x - 2.0, body_y + 3.0), Vector2(c.x - 2.0 + leg_forward, c.y), sq_dark, 2.0)
			draw_line(Vector2(c.x + 2.0, body_y + 3.0), Vector2(c.x + 2.0 - leg_forward, c.y), sq_dark, 2.0)
			
		elif c.type == "butterfly":
			# Detailed butterfly with shaped wings and patterns
			var wing_base := Color(0.92, 0.55, 0.75)
			var wing_accent := Color(0.98, 0.75, 0.85)
			var wing_pattern := Color(0.45, 0.25, 0.55)
			var wing_open: float = abs(sin(c.flutter))
			var offset_x: float = 3.0 + wing_open * 3.0
			var offset_y: float = wing_open * 1.5
			
			# Upper wings (larger, teardrop shaped)
			var upper_left := PackedVector2Array([
				Vector2(c.x - 1.0, c.y - 2.0),
				Vector2(c.x - offset_x - 2.0, c.y - 6.0 - offset_y),
				Vector2(c.x - offset_x - 3.0, c.y - 3.0),
				Vector2(c.x - offset_x, c.y - 1.0 + offset_y),
			])
			var upper_right := PackedVector2Array([
				Vector2(c.x + 1.0, c.y - 2.0),
				Vector2(c.x + offset_x + 2.0, c.y - 6.0 - offset_y),
				Vector2(c.x + offset_x + 3.0, c.y - 3.0),
				Vector2(c.x + offset_x, c.y - 1.0 + offset_y),
			])
			draw_colored_polygon(upper_left, wing_base)
			draw_colored_polygon(upper_right, wing_base)
			
			# Lower wings (smaller, rounded)
			var lower_left := PackedVector2Array([
				Vector2(c.x - 1.0, c.y + 2.0),
				Vector2(c.x - offset_x, c.y + 1.0 - offset_y),
				Vector2(c.x - offset_x - 2.0, c.y + 4.0),
				Vector2(c.x - offset_x, c.y + 5.0 + offset_y),
			])
			var lower_right := PackedVector2Array([
				Vector2(c.x + 1.0, c.y + 2.0),
				Vector2(c.x + offset_x, c.y + 1.0 - offset_y),
				Vector2(c.x + offset_x + 2.0, c.y + 4.0),
				Vector2(c.x + offset_x, c.y + 5.0 + offset_y),
			])
			draw_colored_polygon(lower_left, wing_accent)
			draw_colored_polygon(lower_right, wing_accent)
			
			# Wing patterns (spots)
			draw_circle(Vector2(c.x - offset_x - 1.5, c.y - 4.0), 1.5, wing_pattern)
			draw_circle(Vector2(c.x + offset_x + 1.5, c.y - 4.0), 1.5, wing_pattern)
			draw_circle(Vector2(c.x - offset_x - 1.0, c.y + 3.0), 1.2, wing_pattern)
			draw_circle(Vector2(c.x + offset_x + 1.0, c.y + 3.0), 1.2, wing_pattern)
			
			# Body (thin, segmented)
			draw_line(Vector2(c.x, c.y - 3.0), Vector2(c.x, c.y + 5.0), Color(0.15, 0.15, 0.15), 2.5)
			draw_circle(Vector2(c.x, c.y - 3.5), 1.5, Color(0.1, 0.1, 0.1))  # Head
			
			# Antennae
			draw_line(Vector2(c.x, c.y - 3.5), Vector2(c.x - 1.5, c.y - 6.0), Color(0.1, 0.1, 0.1), 0.8)
			draw_line(Vector2(c.x, c.y - 3.5), Vector2(c.x + 1.5, c.y - 6.0), Color(0.1, 0.1, 0.1), 0.8)
			draw_circle(Vector2(c.x - 1.5, c.y - 6.0), 0.8, Color(0.1, 0.1, 0.1))
			draw_circle(Vector2(c.x + 1.5, c.y - 6.0), 0.8, Color(0.1, 0.1, 0.1))

func _setup_music() -> void:
	music_player = AudioStreamPlayer.new()
	add_child(music_player)
	music_player.bus = "Master"
	
	# Try to load music from assets/audio folder
	var music_path := "res://assets/audio/bg_music.mp3"
	if ResourceLoader.exists(music_path):
		music_player.stream = load(music_path)
		if music_player.stream:
			music_player.volume_db = -5.0  # Slightly quieter than full volume
			# Connect finished signal to restart music for looping
			music_player.finished.connect(_on_music_finished)
			music_player.play()
			music_muted = false
	else:
		push_warning("Music file not found at: " + music_path + ". Add your music file to assets/audio/")

func _on_music_finished() -> void:
	if not music_muted and music_player.stream:
		music_player.play()

func _toggle_music() -> void:
	music_muted = not music_muted
	if music_muted:
		music_player.stop()
		if "music" in action_buttons:
			action_buttons["music"].text = "Music: OFF"
	elif music_player.stream:
		music_player.play()
		if "music" in action_buttons:
			action_buttons["music"].text = "Music: ON"

func _return_to_menu() -> void:
	game_state = GameState.MENU
	# Clean up current game
	if plant:
		plant.queue_free()
		plant = null
	# Remove shed (it's a child of Main)
	for child in get_children():
		if child.get_script() and child.get_script().resource_path.contains("Shed.gd"):
			child.queue_free()
	if ui_layer:
		ui_layer.queue_free()
		ui_layer = null
	action_buttons.clear()
	# Rebuild menu
	_build_menu()
