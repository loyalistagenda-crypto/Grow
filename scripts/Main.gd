extends Node2D

const MusicDatabase = preload("res://scripts/MusicDatabase.gd")

var plant: Plant
var info_label: Label
var stats_label: Label
var sunlight_indicator: ProgressBar
var stats_container: VBoxContainer
var stat_rows: Dictionary = {}
var healthy_label: Label
var wilted_label: Label
var ground_height: float = 120.0
var sky_color: Color = Color(0.36, 0.48, 0.72)
var ground_color: Color = Color(0.12, 0.30, 0.14)
var action_buttons: Dictionary = {}
var ui_layer: CanvasLayer
var game_menu_layer: CanvasLayer
var drag_active: bool = false
var drag_button: int = -1
var pot_dragging: bool = false
var pot_drag_offset: float = 0.0

enum GameState { MENU, PLAYING }
var game_state: int = GameState.MENU
var menu_layer: CanvasLayer
var selected_flower_variant: String = "purple"
var current_flower_index: int = 0
var flower_options: Array = []

# Secret terminal
var tree_click_count: int = 0
var tree_click_timer: float = 0.0
var tree_click_window: float = 2.0
var terminal_open: bool = false
var terminal_layer: CanvasLayer

# Secret practice ivy - left trees 5 clicks in menu
var left_tree_click_count: int = 0
var left_tree_click_timer: float = 0.0
var left_tree_click_window: float = 2.0

# Secret space bar control for landscape/portrait toggle
var space_press_count: int = 0
var space_press_timer: float = 0.0
var space_press_window: float = 0.8

enum Action { WATER, FEED, PRUNE, SUN_DEC, SUN_INC, REPOT }
var current_action: int = Action.WATER
var drag_water_rate: float = 0.55
var drag_feed_rate: float = 0.35
var music_player: AudioStreamPlayer
var music_muted: bool = false
var music_volume_db: float = -5.0
var music_speed: float = 1.0
var music_track: String = "default"
var music_bass_db: float = 0.0
var music_bus_index: int = -1
var music_eq_effect: AudioEffectEQ6
var custom_cursors: Dictionary = {}

var interface_settings := {
	"growth_percent": true,
	"growth_bar": false,
	"moisture_percent": true,
	"moisture_bar": false,
	"nutrients_percent": true,
	"nutrients_bar": false,
	"sunlight_percent": true,
	"sunlight_bar": true,
	"show_healthy": true,
	"show_wilted": true,
}

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
	_create_custom_cursors()
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
	
	# Sunlight calculation removed - shed removed
	
	# Legacy stats tracking removed
	if plant and game_state == GameState.PLAYING:
		var s := plant.get_status()
		_update_stats_ui(s)
	if drag_active and plant and game_state == GameState.PLAYING:
		# Only apply draggable actions during drag
		if current_action == Action.WATER or current_action == Action.FEED:
			_apply_action_drag(delta)
	
	# Tree click timer decay
	if tree_click_timer > 0.0:
		tree_click_timer -= delta
		if tree_click_timer <= 0.0:
			tree_click_count = 0
	
	# Left tree click timer decay (for practice ivy)
	if left_tree_click_timer > 0.0:
		left_tree_click_timer -= delta
		if left_tree_click_timer <= 0.0:
			left_tree_click_count = 0
	
	# Space press timer decay
	if space_press_timer > 0.0:
		space_press_timer -= delta
		if space_press_timer <= 0.0:
			space_press_count = 0

	# Advance day/night cycle and update sky; global fast-forward via Engine.time_scale
	var accel: bool = Input.is_key_pressed(KEY_QUOTELEFT)
	Engine.time_scale = 50.0 if accel else 1.0
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
	# Menu state - handle left tree clicks for practice ivy
	if game_state == GameState.MENU:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var mouse_pos := get_viewport().get_mouse_position()
			var view := get_viewport_rect().size
			var tree1_x: float = view.x * 0.12
			var ground_y: float = view.y - ground_height
			var left_tree_area := Rect2(tree1_x - 50.0, ground_y - 80.0, 100.0, 80.0)
			
			if left_tree_area.has_point(mouse_pos):
				left_tree_click_count += 1
				left_tree_click_timer = left_tree_click_window
				if left_tree_click_count >= 5:
					# Secret: 5 left tree clicks starts practice ivy
					selected_flower_variant = "practice_ivy"
					_on_flower_selected("practice_ivy")
					left_tree_click_count = 0
				return
		return
	
	if game_state != GameState.PLAYING:
		return
	if plant == null:
		return
	
	# Check for tree click (secret terminal)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos := get_viewport().get_mouse_position()
		var view := get_viewport_rect().size
		var tree1_x: float = view.x * 0.12
		var ground_y: float = view.y - ground_height
		var tree_area := Rect2(tree1_x - 50.0, ground_y - 80.0, 100.0, 80.0)
		
		if tree_area.has_point(mouse_pos) and not terminal_open:
			tree_click_count += 1
			tree_click_timer = tree_click_window
			if tree_click_count >= 5:
				_open_terminal()
				tree_click_count = 0
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
		if event.keycode == KEY_ESCAPE and terminal_open:
			_close_terminal()
			return
		# Secret space bar control for landscape/portrait toggle
		if event.keycode == KEY_SPACE:
			space_press_count += 1
			space_press_timer = space_press_window
			if space_press_count >= 5:
				_toggle_orientation()
				space_press_count = 0
			return
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

func _open_terminal() -> void:
	terminal_open = true
	terminal_layer = CanvasLayer.new()
	add_child(terminal_layer)
	
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	terminal_layer.add_child(bg)
	
	var terminal_container := MarginContainer.new()
	terminal_container.set_anchors_preset(Control.PRESET_CENTER)
	terminal_container.offset_left = -300.0
	terminal_container.offset_top = -200.0
	terminal_container.offset_right = 300.0
	terminal_container.offset_bottom = 200.0
	terminal_layer.add_child(terminal_container)
	
	var terminal_panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.15, 0.12)
	panel_style.border_color = Color(0.30, 0.85, 0.35)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	terminal_panel.add_theme_stylebox_override("panel", panel_style)
	terminal_container.add_child(terminal_panel)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	terminal_panel.add_child(vbox)
	
	var title := Label.new()
	title.text = "SECRET TERMINAL"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.30, 0.85, 0.35))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var info := Label.new()
	info.text = "Garden Development Console"
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", Color(0.60, 0.70, 0.60))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)
	
	var button_grid := GridContainer.new()
	button_grid.columns = 2
	button_grid.add_theme_constant_override("h_separation", 10)
	button_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(button_grid)
	
	# Cheat buttons
	var btn_grow := Button.new()
	btn_grow.text = "Max Growth"
	btn_grow.custom_minimum_size = Vector2(140.0, 35.0)
	btn_grow.pressed.connect(_terminal_max_growth)
	button_grid.add_child(btn_grow)
	
	var btn_bloom := Button.new()
	btn_bloom.text = "Instant Bloom"
	btn_bloom.custom_minimum_size = Vector2(140.0, 35.0)
	btn_bloom.pressed.connect(_terminal_instant_bloom)
	button_grid.add_child(btn_bloom)
	
	var btn_water := Button.new()
	btn_water.text = "Full Water"
	btn_water.custom_minimum_size = Vector2(140.0, 35.0)
	btn_water.pressed.connect(_terminal_full_water)
	button_grid.add_child(btn_water)
	
	var btn_nutrients := Button.new()
	btn_nutrients.text = "Full Nutrients"
	btn_nutrients.custom_minimum_size = Vector2(140.0, 35.0)
	btn_nutrients.pressed.connect(_terminal_full_nutrients)
	button_grid.add_child(btn_nutrients)
	
	var btn_heal := Button.new()
	btn_heal.text = "Heal Plant"
	btn_heal.custom_minimum_size = Vector2(140.0, 35.0)
	btn_heal.pressed.connect(_terminal_heal_plant)
	button_grid.add_child(btn_heal)
	
	var btn_repot := Button.new()
	btn_repot.text = "Upgrade Pot"
	btn_repot.custom_minimum_size = Vector2(140.0, 35.0)
	btn_repot.pressed.connect(_terminal_upgrade_pot)
	button_grid.add_child(btn_repot)
	
	var close_btn := Button.new()
	close_btn.text = "Close Terminal [ESC]"
	close_btn.custom_minimum_size = Vector2(280.0, 40.0)
	close_btn.pressed.connect(_close_terminal)
	vbox.add_child(close_btn)

func _close_terminal() -> void:
	if terminal_layer:
		terminal_layer.queue_free()
		terminal_layer = null
	terminal_open = false

func _terminal_max_growth() -> void:
	if plant:
		plant.growth = 1.0

func _terminal_instant_bloom() -> void:
	if plant:
		plant.bloom_progress = 1.0

func _terminal_full_water() -> void:
	if plant:
		plant.moisture = 1.0

func _terminal_full_nutrients() -> void:
	if plant:
		plant.nutrients = 1.0

func _terminal_heal_plant() -> void:
	if plant:
		plant.wilted_leaves = 0
		plant.wilt_accum = 0.0

func _terminal_upgrade_pot() -> void:
	if plant:
		plant.repot()

func _toggle_orientation() -> void:
	# Toggle orientation - works on mobile devices
	var current_orientation = DisplayServer.screen_get_orientation()
	if current_orientation == DisplayServer.SCREEN_PORTRAIT:
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
	elif current_orientation == DisplayServer.SCREEN_LANDSCAPE:
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
	else:
		# Default to portrait if unknown
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)

func _build_menu() -> void:
	menu_layer = CanvasLayer.new()
	add_child(menu_layer)
	
	# Title at top of screen with decorative styling
	var title_container := MarginContainer.new()
	title_container.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_container.add_theme_constant_override("margin_top", 20)
	title_container.add_theme_constant_override("margin_left", 20)
	title_container.add_theme_constant_override("margin_right", 20)
	menu_layer.add_child(title_container)
	
	var title_vbox := VBoxContainer.new()
	title_vbox.add_theme_constant_override("separation", 5)
	title_container.add_child(title_vbox)
	
	var title := Label.new()
	title.text = "Grow a Single Plant"
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.95, 0.90, 0.70))
	title.add_theme_color_override("font_outline_color", Color(0.25, 0.20, 0.15))
	title.add_theme_constant_override("outline_size", 8)
	title_vbox.add_child(title)
	
	# Center carousel container
	var center := MarginContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.offset_left = -300.0
	center.offset_top = -160.0
	center.offset_right = 300.0
	center.offset_bottom = 40.0
	menu_layer.add_child(center)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	center.add_child(vbox)
	
	# Flower selection label
	var flower_label := Label.new()
	flower_label.text = "Choose Your Plant:"
	flower_label.add_theme_font_size_override("font_size", 20)
	flower_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(flower_label)
	
	# Store flower options
	flower_options = [
		{"name": "Purple Flower", "variant": "purple", "color": Color(0.75, 0.55, 0.85)},
		{"name": "Yellow Flower", "variant": "yellow", "color": Color(0.95, 0.85, 0.40)},
		{"name": "Red Flower", "variant": "red", "color": Color(0.90, 0.35, 0.35)},
		{"name": "Rainbow Flower", "variant": "rainbow", "color": Color(1.0, 1.0, 1.0)},
		{"name": "Rose Bush", "variant": "rose_bush", "color": Color(0.95, 0.45, 0.55)},
		{"name": "Rainbow Rose Bush", "variant": "rainbow_rose_bush", "color": Color(1.0, 0.75, 0.85)}
	]
	
	# Horizontal carousel container
	var carousel_container := HBoxContainer.new()
	carousel_container.add_theme_constant_override("separation", 20)
	carousel_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(carousel_container)
	
	# Left arrow button
	var left_arrow := Button.new()
	left_arrow.text = "<"
	left_arrow.custom_minimum_size = Vector2(60.0, 140.0)
	left_arrow.add_theme_font_size_override("font_size", 32)
	left_arrow.pressed.connect(_on_flower_carousel_left)
	carousel_container.add_child(left_arrow)
	
	# Flower display area (clickable button)
	var select_area := Button.new()
	select_area.name = "SelectAreaButton"
	select_area.focus_mode = Control.FOCUS_NONE
	select_area.flat = true
	select_area.custom_minimum_size = Vector2(240.0, 260.0)
	select_area.mouse_filter = Control.MOUSE_FILTER_STOP
	select_area.pressed.connect(_on_select_area_pressed)
	carousel_container.add_child(select_area)
	
	# Plant preview as the main background
	var preview := Control.new()
	preview.name = "PlantPreview"
	preview.custom_minimum_size = Vector2(240.0, 260.0)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.draw.connect(_on_preview_draw.bind(preview))
	select_area.add_child(preview)
	
	# Name overlaid on top of preview
	var flower_name_label := Label.new()
	flower_name_label.name = "FlowerNameLabel"
	flower_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flower_name_label.add_theme_font_size_override("font_size", 24)
	flower_name_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	flower_name_label.offset_top = 3
	flower_name_label.offset_left = 0
	flower_name_label.offset_right = 0
	flower_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(flower_name_label)
	
	# Description overlaid below the name
	var flower_desc := Label.new()
	flower_desc.name = "FlowerDescLabel"
	flower_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flower_desc.add_theme_font_size_override("font_size", 14)
	flower_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	flower_desc.set_anchors_preset(Control.PRESET_TOP_WIDE)
	flower_desc.offset_top = 32
	flower_desc.offset_left = 4
	flower_desc.offset_right = -4
	flower_desc.modulate = Color(1.0, 1.0, 1.0, 0.95)
	flower_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(flower_desc)
	
	# Right arrow button
	var right_arrow := Button.new()
	right_arrow.text = ">"
	right_arrow.custom_minimum_size = Vector2(60.0, 140.0)
	right_arrow.add_theme_font_size_override("font_size", 32)
	right_arrow.pressed.connect(_on_flower_carousel_right)
	carousel_container.add_child(right_arrow)
	
	var collection_btn := Button.new()
	collection_btn.text = "View Collection"
	collection_btn.custom_minimum_size = Vector2(100.0, 40.0)
	collection_btn.pressed.connect(_on_view_collection)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 25)
	vbox.add_child(spacer)
	vbox.add_child(collection_btn)
	
	# Update display to show first flower
	_update_flower_display()

	# Confirmation dialog for planting
	var confirm := ConfirmationDialog.new()
	confirm.name = "SeedConfirmDialog"
	confirm.dialog_text = "Plant this seed?"
	confirm.ok_button_text = "Yes"
	confirm.cancel_button_text = "No"
	confirm.min_size = Vector2(360, 220)
	confirm.title = "Confirm Planting"
	confirm.confirmed.connect(_on_seed_confirmed)
	# Cozy theme tweaks
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.20, 0.16, 0.12, 0.95)
	panel.content_margin_left = 12
	panel.content_margin_right = 12
	panel.content_margin_top = 12
	panel.content_margin_bottom = 24
	panel.corner_radius_top_left = 10
	panel.corner_radius_top_right = 10
	panel.corner_radius_bottom_left = 10
	panel.corner_radius_bottom_right = 10
	panel.border_width_left = 2
	panel.border_width_top = 2
	panel.border_width_right = 2
	panel.border_width_bottom = 2
	panel.border_color = Color(0.55, 0.40, 0.30)
	confirm.add_theme_stylebox_override("panel", panel)
	confirm.add_theme_color_override("title_color", Color(0.95, 0.90, 0.80))
	confirm.add_theme_color_override("font_color", Color(0.95, 0.90, 0.80))
	confirm.add_theme_font_size_override("font_size", 32)
	confirm.add_theme_constant_override("title_outline_size", 3)
	confirm.add_theme_constant_override("outline_size", 3)
	# Style buttons
	var ok_btn := confirm.get_ok_button()
	var cancel_btn := confirm.get_cancel_button()
	ok_btn.custom_minimum_size = Vector2(180.0, 60.0)
	cancel_btn.custom_minimum_size = Vector2(180.0, 60.0)
	ok_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok_btn.add_theme_font_size_override("font_size", 26)
	cancel_btn.add_theme_font_size_override("font_size", 26)
	var ok_style := StyleBoxFlat.new()
	ok_style.bg_color = Color(0.08, 0.35, 0.18)
	ok_style.border_color = Color(0.05, 0.25, 0.12)
	ok_style.corner_radius_top_left = 8
	ok_style.corner_radius_top_right = 8
	ok_style.corner_radius_bottom_left = 8
	ok_style.corner_radius_bottom_right = 8
	ok_style.border_width_left = 2
	ok_style.border_width_top = 2
	ok_style.border_width_right = 2
	ok_style.border_width_bottom = 2
	ok_btn.add_theme_stylebox_override("normal", ok_style)
	ok_btn.add_theme_stylebox_override("hover", ok_style)
	ok_btn.add_theme_stylebox_override("pressed", ok_style)
	ok_btn.add_theme_color_override("font_color", Color(0.93, 0.96, 0.90))
	var cancel_style := StyleBoxFlat.new()
	cancel_style.bg_color = Color(0.55, 0.12, 0.18)
	cancel_style.border_color = Color(0.35, 0.08, 0.12)
	cancel_style.corner_radius_top_left = 8
	cancel_style.corner_radius_top_right = 8
	cancel_style.corner_radius_bottom_left = 8
	cancel_style.corner_radius_bottom_right = 8
	cancel_style.border_width_left = 2
	cancel_style.border_width_top = 2
	cancel_style.border_width_right = 2
	cancel_style.border_width_bottom = 2
	cancel_btn.add_theme_stylebox_override("normal", cancel_style)
	cancel_btn.add_theme_stylebox_override("hover", cancel_style)
	cancel_btn.add_theme_stylebox_override("pressed", cancel_style)
	cancel_btn.add_theme_color_override("font_color", Color(0.98, 0.92, 0.92))
	menu_layer.add_child(confirm)

func _on_flower_selected(variant: String) -> void:
	selected_flower_variant = variant
	game_state = GameState.PLAYING
	menu_layer.queue_free()
	_build_scene()
	_build_ui()

func _on_flower_carousel_left() -> void:
	current_flower_index -= 1
	if current_flower_index < 0:
		current_flower_index = flower_options.size() - 1
	_update_flower_display()

func _on_flower_carousel_right() -> void:
	current_flower_index += 1
	if current_flower_index >= flower_options.size():
		current_flower_index = 0
	_update_flower_display()

func _on_flower_select_current() -> void:
	var current_flower = flower_options[current_flower_index]
	_on_flower_selected(current_flower["variant"])

func _on_select_area_pressed() -> void:
	var dialog := menu_layer.find_child("SeedConfirmDialog", true, false)
	if dialog:
		var current_flower = flower_options[current_flower_index]
		dialog.dialog_text = "Plant %s Seed?" % current_flower["name"]
		dialog.popup_centered()

func _on_seed_confirmed() -> void:
	_on_flower_select_current()

func _update_flower_display() -> void:
	if not menu_layer:
		return
	var current_flower = flower_options[current_flower_index]
	var name_label = menu_layer.find_child("FlowerNameLabel", true, false)
	var desc_label = menu_layer.find_child("FlowerDescLabel", true, false)
	var preview = menu_layer.find_child("PlantPreview", true, false)
	if name_label:
		name_label.text = current_flower["name"]
		name_label.add_theme_color_override("font_color", current_flower["color"])
	if desc_label:
		var descriptions := {
			"purple": "Classic elegant blooms",
			"yellow": "Bright sunny flowers",
			"red": "Bold passionate petals",
			"rainbow": "Magical spectrum blooms",
			"rose_bush": "Natural branching roses",
			"rainbow_rose_bush": "Bushy rainbow blooms"
		}
		desc_label.text = descriptions.get(current_flower["variant"], "Beautiful plant")
	if preview:
		preview.queue_redraw()

func _on_preview_draw(preview_control: Control) -> void:
	var current_flower = flower_options[current_flower_index]
	var variant: String = current_flower["variant"]
	var size := preview_control.size
	var overlay_h := 48.0
	var scale := clampf(minf(size.x / 100.0, size.y / 80.0), 1.8, 3.0)
	var center := Vector2(size.x * 0.5, size.y - overlay_h * 0.5)
	
	# Background
	preview_control.draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0.20, 0.15))
	
	# Draw miniature pot
	var pot_w := 20.0 * scale
	var pot_h := 15.0 * scale
	var pot_pts := PackedVector2Array([
		center + Vector2(-pot_w * 0.5, -5.0 * scale),
		center + Vector2(pot_w * 0.5, -5.0 * scale),
		center + Vector2(pot_w * 0.4, -5.0 * scale + pot_h),
		center + Vector2(-pot_w * 0.4, -5.0 * scale + pot_h)
	])
	preview_control.draw_colored_polygon(pot_pts, Color(0.55, 0.35, 0.20))
	
	if variant == "rose_bush" or variant == "rainbow_rose_bush":
		# Mini rose bush with multiple stems from center
		var stem_col := Color(0.16, 0.50, 0.25)
		var pot_top := center + Vector2(0.0, -5.0 * scale)
		for i in range(5):
			var t: float = float(i) / 4.0
			var angle: float = lerp(-0.6, 0.6, t)
			var height: float = randf_range(35.0, 50.0) * scale
			var stem_tip := pot_top + Vector2(sin(angle) * height * 0.4, -height)
			preview_control.draw_line(pot_top, stem_tip, stem_col, 1.5)
			# Tiny bloom at tip
			if variant == "rainbow_rose_bush":
				for j in range(6):
					var petal_angle: float = (TAU / 6.0) * float(j)
					var col := Color.from_hsv(float(j) / 6.0, 0.9, 0.95)
					var petal_pos := stem_tip + Vector2(cos(petal_angle), sin(petal_angle)) * 2.0 * scale
					preview_control.draw_circle(petal_pos, 1.5 * scale, col)
				preview_control.draw_circle(stem_tip, 1.5 * scale, Color(1.0, 0.95, 0.70))
			else:
				preview_control.draw_circle(stem_tip, 2.5 * scale, Color(0.95, 0.45, 0.55))
				preview_control.draw_circle(stem_tip, 1.5 * scale, Color(0.85, 0.35, 0.45))
	else:
		# Single stem flower
		var stem_col := Color(0.16, 0.50, 0.25)
		var stem_base := center + Vector2(0.0, -5.0 * scale)
		var stem_tip := stem_base + Vector2(0.0, -60.0 * scale)
		preview_control.draw_line(stem_base, stem_tip, stem_col, 2.0 * scale)
		
		# Leaves
		for i in range(3):
			var y: float = lerp(-10.0, -50.0, float(i + 1) / 4.0) * scale
			var side: float = 1.0 if i % 2 == 0 else -1.0
			var leaf_base := stem_base + Vector2(0.0, y)
			var leaf_tip := leaf_base + Vector2(side * 8.0 * scale, -3.0 * scale)
			var leaf_pts := PackedVector2Array([
				leaf_base,
				leaf_base + Vector2(side * 4.0 * scale, 0.0),
				leaf_tip,
			])
			preview_control.draw_colored_polygon(leaf_pts, Color(0.25, 0.70, 0.35))
		
		# Flower at top
		if variant == "rainbow":
			# Mini rainbow flower
			for i in range(12):
				var angle: float = (TAU / 12.0) * float(i)
				var col := Color.from_hsv(float(i) / 12.0, 0.9, 0.95)
				var petal_tip := stem_tip + Vector2(cos(angle), sin(angle)) * 8.0 * scale
				var petal_pts := PackedVector2Array([
					stem_tip,
					stem_tip + Vector2(cos(angle - 0.3), sin(angle - 0.3)) * 4.0 * scale,
					petal_tip,
					stem_tip + Vector2(cos(angle + 0.3), sin(angle + 0.3)) * 4.0 * scale
				])
				preview_control.draw_colored_polygon(petal_pts, col)
			preview_control.draw_circle(stem_tip, 3.0 * scale, Color(1.0, 1.0, 1.0))
		else:
			# Regular flower
			var petal_col: Color = current_flower["color"]
			for i in range(8):
				var angle: float = (TAU / 8.0) * float(i)
				var petal_tip := stem_tip + Vector2(cos(angle), sin(angle)) * 7.0 * scale
				var petal_pts := PackedVector2Array([
					stem_tip,
					stem_tip + Vector2(cos(angle - 0.3), sin(angle - 0.3)) * 3.5 * scale,
					petal_tip,
					stem_tip + Vector2(cos(angle + 0.3), sin(angle + 0.3)) * 3.5 * scale
				])
				preview_control.draw_colored_polygon(petal_pts, petal_col)
			preview_control.draw_circle(stem_tip, 2.5 * scale, petal_col * 0.8)

func _on_view_collection() -> void:
	# TODO: Show collection of grown plants
	pass

func _build_scene() -> void:
	plant = Plant.new()
	plant.set_flower_variant(selected_flower_variant)
	var view := get_viewport_rect().size
	plant.position = Vector2(view.x * 0.5, view.y - ground_height + 6.0)
	add_child(plant)
	# Shed removed

func _draw_tree(view: Vector2, cycle_progress: float, sun_active: bool) -> void:
	# Large decorative tree on right side, partially cut off at top
	var ground_y: float = view.y - ground_height
	var tree_x: float = view.x - 80.0
	var tree_base_y: float = ground_y
	
	# Calculate color adjustments based on time of day
	var trunk_color: Color = Color(0.45, 0.30, 0.15)
	var trunk_dark: Color = Color(0.35, 0.22, 0.10)
	if cycle_progress >= 0.4167 and cycle_progress < 0.5584:  # Dusk - warmer and less saturated
		var dusk_progress: float = (cycle_progress - 0.4167) / (0.5584 - 0.4167)
		trunk_color = _adjust_color_warm_desaturate(trunk_color, dusk_progress * 0.3, dusk_progress * 0.2)
		trunk_dark = _adjust_color_warm_desaturate(trunk_dark, dusk_progress * 0.3, dusk_progress * 0.2)
	elif cycle_progress >= 0.5584 and cycle_progress < 0.95:  # Night - cooler and less saturated
		trunk_color = _adjust_color_cool_desaturate(trunk_color, 0.3, 0.5)
		trunk_dark = _adjust_color_cool_desaturate(trunk_dark, 0.3, 0.5)
	elif cycle_progress >= 0.95 or cycle_progress < 0.02:  # Dawn transition back to normal
		if cycle_progress >= 0.95:
			var dawn_progress: float = (cycle_progress - 0.95) / (1.0 - 0.95)
			trunk_color = _adjust_color_cool_desaturate(trunk_color, 0.3 * (1.0 - dawn_progress), 0.5 * (1.0 - dawn_progress))
			trunk_dark = _adjust_color_cool_desaturate(trunk_dark, 0.3 * (1.0 - dawn_progress), 0.5 * (1.0 - dawn_progress))
		elif cycle_progress < 0.02:
			var early_dawn_progress: float = cycle_progress / 0.02
			trunk_color = _adjust_color_cool_desaturate(trunk_color, 0.3 * (1.0 - early_dawn_progress), 0.5 * (1.0 - early_dawn_progress))
			trunk_dark = _adjust_color_cool_desaturate(trunk_dark, 0.3 * (1.0 - early_dawn_progress), 0.5 * (1.0 - early_dawn_progress))
	
	# Trunk - thick and tapered upward
	var trunk_width_base: float = 60.0
	var trunk_width_mid: float = 45.0
	var trunk_width_top: float = 30.0
	var trunk_height: float = 500.0
	
	# Main trunk (tapered polygon)
	var trunk_pts := PackedVector2Array([
		Vector2(tree_x - trunk_width_base * 0.5, tree_base_y),
		Vector2(tree_x + trunk_width_base * 0.5, tree_base_y),
		Vector2(tree_x + trunk_width_top * 0.5, tree_base_y - trunk_height),
		Vector2(tree_x - trunk_width_top * 0.5, tree_base_y - trunk_height),
	])
	draw_colored_polygon(trunk_pts, trunk_color)
	
	# Trunk shading on left side
	var trunk_shade := PackedVector2Array([
		Vector2(tree_x - trunk_width_base * 0.5, tree_base_y),
		Vector2(tree_x - trunk_width_base * 0.5 + 15.0, tree_base_y),
		Vector2(tree_x - trunk_width_top * 0.5 + 8.0, tree_base_y - trunk_height),
		Vector2(tree_x - trunk_width_top * 0.5, tree_base_y - trunk_height),
	])
	draw_colored_polygon(trunk_shade, trunk_dark)
	
	# Main branches
	var branch_color: Color = Color(0.50, 0.32, 0.16)
	var branch_dark: Color = Color(0.38, 0.24, 0.12)
	
	# Apply color adjustments to branches based on time of day
	if cycle_progress >= 0.4167 and cycle_progress < 0.5584:  # Dusk - warmer and less saturated
		var dusk_progress: float = (cycle_progress - 0.4167) / (0.5584 - 0.4167)
		branch_color = _adjust_color_warm_desaturate(branch_color, dusk_progress * 0.3, dusk_progress * 0.2)
		branch_dark = _adjust_color_warm_desaturate(branch_dark, dusk_progress * 0.3, dusk_progress * 0.2)
	elif cycle_progress >= 0.5584 and cycle_progress < 0.95:  # Night - cooler and less saturated
		branch_color = _adjust_color_cool_desaturate(branch_color, 0.3, 0.5)
		branch_dark = _adjust_color_cool_desaturate(branch_dark, 0.3, 0.5)
	elif cycle_progress >= 0.95 or cycle_progress < 0.02:  # Dawn transition back to normal
		if cycle_progress >= 0.95:
			var dawn_progress: float = (cycle_progress - 0.95) / (1.0 - 0.95)
			branch_color = _adjust_color_cool_desaturate(branch_color, 0.3 * (1.0 - dawn_progress), 0.5 * (1.0 - dawn_progress))
			branch_dark = _adjust_color_cool_desaturate(branch_dark, 0.3 * (1.0 - dawn_progress), 0.5 * (1.0 - dawn_progress))
		elif cycle_progress < 0.02:
			var early_dawn_progress: float = cycle_progress / 0.02
			branch_color = _adjust_color_cool_desaturate(branch_color, 0.3 * (1.0 - early_dawn_progress), 0.5 * (1.0 - early_dawn_progress))
			branch_dark = _adjust_color_cool_desaturate(branch_dark, 0.3 * (1.0 - early_dawn_progress), 0.5 * (1.0 - early_dawn_progress))
	
	# Right branch (large)
	_draw_branch(
		Vector2(tree_x + 20.0, tree_base_y - 150.0),
		Vector2(tree_x + 200.0, tree_base_y - 280.0),
		12.0, 8.0, branch_color, branch_dark
	)
	
	# Right-upper branch
	_draw_branch(
		Vector2(tree_x + 10.0, tree_base_y - 280.0),
		Vector2(tree_x + 180.0, tree_base_y - 400.0),
		10.0, 6.0, branch_color, branch_dark
	)
	
	# Left branch (medium)
	_draw_branch(
		Vector2(tree_x - 20.0, tree_base_y - 200.0),
		Vector2(tree_x - 120.0, tree_base_y - 320.0),
		11.0, 7.0, branch_color, branch_dark
	)
	
	# Left-upper branch
	_draw_branch(
		Vector2(tree_x - 10.0, tree_base_y - 320.0),
		Vector2(tree_x - 140.0, tree_base_y - 420.0),
		9.0, 5.0, branch_color, branch_dark
	)
	
	# Upper right branch
	_draw_branch(
		Vector2(tree_x + 5.0, tree_base_y - 400.0),
		Vector2(tree_x + 150.0, tree_base_y - 520.0),
		8.0, 5.0, branch_color, branch_dark
	)
	
	# Foliage - large green leafy canopy with spherical shading
	var foliage_color: Color = Color(0.28, 0.55, 0.25)
	var foliage_dark: Color = Color(0.15, 0.32, 0.12)
	var foliage_bright: Color = Color(0.60, 0.85, 0.50)
	
	# Apply color adjustments to foliage based on time of day
	if cycle_progress >= 0.4167 and cycle_progress < 0.5584:  # Dusk - warmer and less saturated
		var dusk_progress: float = (cycle_progress - 0.4167) / (0.5584 - 0.4167)
		foliage_color = _adjust_color_warm_desaturate(foliage_color, dusk_progress * 0.3, dusk_progress * 0.2)
		foliage_dark = _adjust_color_warm_desaturate(foliage_dark, dusk_progress * 0.3, dusk_progress * 0.2)
		foliage_bright = _adjust_color_warm_desaturate(foliage_bright, dusk_progress * 0.3, dusk_progress * 0.2)
	elif cycle_progress >= 0.5584 and cycle_progress < 0.95:  # Night - cooler and less saturated
		foliage_color = _adjust_color_cool_desaturate(foliage_color, 0.3, 0.5)
		foliage_dark = _adjust_color_cool_desaturate(foliage_dark, 0.3, 0.5)
		foliage_bright = _adjust_color_cool_desaturate(foliage_bright, 0.3, 0.5)
	elif cycle_progress >= 0.95 or cycle_progress < 0.02:  # Dawn transition back to normal
		if cycle_progress >= 0.95:
			var dawn_progress: float = (cycle_progress - 0.95) / (1.0 - 0.95)
			foliage_color = _adjust_color_cool_desaturate(foliage_color, 0.3 * (1.0 - dawn_progress), 0.5 * (1.0 - dawn_progress))
			foliage_dark = _adjust_color_cool_desaturate(foliage_dark, 0.3 * (1.0 - dawn_progress), 0.5 * (1.0 - dawn_progress))
			foliage_bright = _adjust_color_cool_desaturate(foliage_bright, 0.3 * (1.0 - dawn_progress), 0.5 * (1.0 - dawn_progress))
		elif cycle_progress < 0.02:
			var early_dawn_progress: float = cycle_progress / 0.02
			foliage_color = _adjust_color_cool_desaturate(foliage_color, 0.3 * (1.0 - early_dawn_progress), 0.5 * (1.0 - early_dawn_progress))
			foliage_dark = _adjust_color_cool_desaturate(foliage_dark, 0.3 * (1.0 - early_dawn_progress), 0.5 * (1.0 - early_dawn_progress))
			foliage_bright = _adjust_color_cool_desaturate(foliage_bright, 0.3 * (1.0 - early_dawn_progress), 0.5 * (1.0 - early_dawn_progress))
	
	# Calculate medium circle alpha - complex fading behavior
	var medium_alpha: float = 1.0
	var fade_in_window: float = 40.0 / 240.0  # 40 seconds to fade in
	var fade_start: float = 5.0 / 240.0  # 5 seconds before cycle ends
	var night_start: float = 0.5584
	var night_one_third: float = 0.7056  # 1/3 through night (0.5584 + 0.4416/3)
	var night_three_quarters: float = 0.8896  # 3/4 through night (0.5584 + 0.4416*3/4)
	
	if cycle_progress >= 0.0 and cycle_progress < fade_in_window:  # Fade in at start of day
		medium_alpha = cycle_progress / fade_in_window
	elif cycle_progress >= fade_in_window and cycle_progress < night_start:  # Day - full opacity
		medium_alpha = 1.0
	elif cycle_progress >= night_start and cycle_progress < night_one_third:  # After night starts, fade to half
		medium_alpha = 1.0 - (cycle_progress - night_start) / (night_one_third - night_start) * 0.5
	elif cycle_progress >= night_one_third and cycle_progress < night_three_quarters:  # 1/3 to 3/4 night - fade to zero
		medium_alpha = 0.5 - (cycle_progress - night_one_third) / (night_three_quarters - night_one_third) * 0.5
	else:  # From 3/4 night through end of cycle - stay invisible
		medium_alpha = 0.0
	

	# Calculate highlight alpha based on cycle - fade during dusk/dawn, disappear at night
	var highlight_alpha: float = 0.0
	if cycle_progress >= 0.00417 and cycle_progress < 0.32077:  # Early morning fade-in (20x longer, ~76 seconds after sunrise)
		var early_start := 0.00417
		var early_end := 0.32077
		highlight_alpha = (cycle_progress - early_start) / (early_end - early_start)
	elif cycle_progress >= 0.32077 and cycle_progress < 0.4167:  # Day time - full highlight
		highlight_alpha = 1.0
	elif cycle_progress >= 0.4167 and cycle_progress <= 0.6584:  # Dusk to night window
		var dusk_start := 0.4167
		if cycle_progress < night_start:
			# Fading during dusk (0.4167 to 0.5584)
			highlight_alpha = 1.0 - (cycle_progress - dusk_start) / (night_start - dusk_start)
		else:
			# Night time - no highlight
			highlight_alpha = 0.0
	# No highlight during night (0.6584 to 0.00417 of next cycle)
	
	# Main canopy - large circle on right
	_draw_foliage_sphere(Vector2(tree_x + 100.0, tree_base_y - 350.0), 140.0, foliage_color, foliage_dark, foliage_bright, cycle_progress, sun_active, highlight_alpha, medium_alpha)
	
	# Left side canopy
	_draw_foliage_sphere(Vector2(tree_x - 90.0, tree_base_y - 320.0), 120.0, foliage_color, foliage_dark, foliage_bright, cycle_progress, sun_active, highlight_alpha, medium_alpha)
	
	# Upper canopy
	_draw_foliage_sphere(Vector2(tree_x + 60.0, tree_base_y - 480.0), 100.0, foliage_color, foliage_dark, foliage_bright, cycle_progress, sun_active, highlight_alpha, medium_alpha)

func _draw_branch(from: Vector2, to: Vector2, width_from: float, width_to: float, color: Color, shadow_color: Color) -> void:
	# Draw a tapered branch with shading
	var dir: Vector2 = (to - from).normalized()
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	
	# Main branch (tapered)
	var branch_pts: PackedVector2Array = PackedVector2Array([
		from + perp * width_from * 0.5,
		from - perp * width_from * 0.5,
		to - perp * width_to * 0.5,
		to + perp * width_to * 0.5,
	])
	draw_colored_polygon(branch_pts, color)
	
	# Branch shadow on one side
	var shadow_pts: PackedVector2Array = PackedVector2Array([
		from - perp * width_from * 0.5,
		from - perp * width_from * 0.5 + perp * 3.0,
		to - perp * width_to * 0.5 + perp * 2.0,
		to - perp * width_to * 0.5,
	])
	draw_colored_polygon(shadow_pts, shadow_color)

func _draw_foliage_sphere(center: Vector2, radius: float, mid_color: Color, dark_color: Color, bright_color: Color, cycle_progress: float, sun_active: bool, highlight_alpha: float, medium_alpha: float) -> void:
	# Draw spherical foliage with highlights that follow the day/night arc
	# Highlight moves around sphere following sun/moon arc (0 = left, 0.5 = top, 1 = right)
	
	# Map cycle progress to arc angle around the sphere
	# Day cycle goes from 0.0 (sunrise at left) through 0.5 (noon at top) to 1.0 (sunset at right)
	# Highlight follows the sun arc across the sky
	var arc_angle: float = cycle_progress * PI - PI  # Maps 0->-PI/PI (left) to 0.5->-PI/2 (top) to 1->0 (right)
	var light_direction: Vector2 = Vector2(cos(arc_angle), sin(arc_angle))
	
	# Dark outer shadow - stationary at center
	var dark_radius: float = radius * 1.15
	draw_circle(center, dark_radius, dark_color)
	
	# Medium tone main sphere - positioned on edge of dark circle along arc
	var dark_offset: Vector2 = light_direction * (dark_radius - radius)
	var mid_center: Vector2 = center + dark_offset
	var mid_col: Color = mid_color
	mid_col.a = medium_alpha
	draw_circle(mid_center, radius, mid_col)
	
	# Bright highlight near top, positioned on edge of medium circle along arc
	# Only show if highlight_alpha > 0
	if highlight_alpha > 0.01:
		var highlight_radius: float = radius * 0.35
		var highlight_offset: Vector2 = light_direction * (radius - highlight_radius)
		var highlight_col: Color = bright_color
		highlight_col.a = highlight_alpha
		draw_circle(mid_center + highlight_offset, highlight_radius, highlight_col)

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

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	box.add_child(actions)

	_add_action_button(actions, "Water", Action.WATER)
	_add_action_button(actions, "Feed", Action.FEED)
	_add_action_button(actions, "Prune", Action.PRUNE)
	_add_action_button(actions, "Repot", Action.REPOT)

	# Music toggle button
	var music_btn := Button.new()
	music_btn.text = "Music: ON"
	music_btn.pressed.connect(_toggle_music)
	box.add_child(music_btn)

	# Menu button opens in-game menu overlay
	var menu_btn := Button.new()
	menu_btn.text = "Menu"
	menu_btn.pressed.connect(_open_game_menu)
	box.add_child(menu_btn)

	_build_stats_ui(box)

func _build_stats_ui(parent: VBoxContainer) -> void:
	stats_container = VBoxContainer.new()
	stats_container.add_theme_constant_override("separation", 6)
	parent.add_child(stats_container)

	var header := Label.new()
	header.text = "Plant Status"
	header.add_theme_font_size_override("font_size", 18)
	stats_container.add_child(header)

	_create_stat_row("growth", "Growth")
	_create_stat_row("moisture", "Moisture")
	_create_stat_row("nutrients", "Nutrients")
	_create_stat_row("sunlight", "Sunlight")

	healthy_label = Label.new()
	healthy_label.text = "Healthy leaves: 0"
	stats_container.add_child(healthy_label)

	wilted_label = Label.new()
	wilted_label.text = "Wilted leaves: 0"
	stats_container.add_child(wilted_label)

	_refresh_interface_visibility()

func _create_stat_row(key: String, title: String) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	stats_container.add_child(row)

	var percent := Label.new()
	percent.text = "%s: 0%%" % title
	row.add_child(percent)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 0.0
	bar.custom_minimum_size = Vector2(260.0, 10.0)
	bar.show_percentage = false
	row.add_child(bar)

	stat_rows[key] = {
		"percent_label": percent,
		"bar": bar,
		"title": title,
	}
	if key == "sunlight":
		sunlight_indicator = bar

func _update_stats_ui(status: Dictionary) -> void:
	_set_stat_value("growth", status.get("growth", 0.0), status.get("pot_cap", 1.0), plant.ideal_sunlight)
	_set_stat_value("moisture", status.get("moisture", 0.0))
	_set_stat_value("nutrients", status.get("nutrients", 0.0))
	_set_stat_value("sunlight", status.get("sunlight", 0.0), status.get("pot_cap", 1.0), plant.ideal_sunlight)
	if healthy_label:
		healthy_label.text = "Healthy leaves: %d" % plant.healthy_leaves
	if wilted_label:
		wilted_label.text = "Wilted leaves: %d" % plant.wilted_leaves
	_refresh_interface_visibility()

func _set_stat_value(key: String, value: float, cap: float = -1.0, ideal: float = -1.0) -> void:
	var entry: Dictionary = stat_rows.get(key, {})
	if entry.is_empty():
		return
	var pct := int(round(value * 100.0))
	var label_text := "%s: %d%%" % [entry.get("title", "Stat"), pct]
	if key == "growth":
		var cap_pct := int(round(cap * 100.0))
		label_text = "Growth: %d%% (cap %d%%)" % [pct, cap_pct]
	elif key == "sunlight":
		var ideal_pct := int(round(ideal * 100.0))
		label_text = "Sunlight: %d%% (ideal %d%%)" % [pct, ideal_pct]

	var percent_label: Label = entry.get("percent_label")
	if percent_label:
		percent_label.text = label_text
		percent_label.visible = interface_settings.get("%s_percent" % key, true)

	var bar: ProgressBar = entry.get("bar")
	if bar:
		bar.value = pct
		bar.visible = interface_settings.get("%s_bar" % key, false)

func _refresh_interface_visibility() -> void:
	for key in ["growth", "moisture", "nutrients", "sunlight"]:
		var entry: Dictionary = stat_rows.get(key, {})
		if entry.is_empty():
			continue
		var percent_label: Label = entry.get("percent_label")
		if percent_label:
			percent_label.visible = interface_settings.get("%s_percent" % key, true)
		var bar: ProgressBar = entry.get("bar")
		if bar:
			bar.visible = interface_settings.get("%s_bar" % key, false)
	if healthy_label:
		healthy_label.visible = interface_settings.get("show_healthy", true)
	if wilted_label:
		wilted_label.visible = interface_settings.get("show_wilted", true)

func _open_game_menu() -> void:
	if game_menu_layer:
		return
	if game_state != GameState.PLAYING:
		return
	game_menu_layer = CanvasLayer.new()
	add_child(game_menu_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	game_menu_layer.add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -320.0
	panel.offset_right = 320.0
	panel.offset_top = -260.0
	panel.offset_bottom = 260.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.10, 0.08, 0.92)
	panel_style.border_color = Color(0.35, 0.28, 0.20)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel", panel_style)
	game_menu_layer.add_child(panel)

	var padding := MarginContainer.new()
	padding.add_theme_constant_override("margin_left", 18)
	padding.add_theme_constant_override("margin_right", 18)
	padding.add_theme_constant_override("margin_top", 18)
	padding.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(padding)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	padding.add_child(root)

	var title := Label.new()
	title.text = "Game Menu"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var start_btn := Button.new()
	start_btn.text = "Start Screen"
	start_btn.custom_minimum_size = Vector2(0.0, 44.0)
	start_btn.pressed.connect(_on_start_screen_pressed)
	root.add_child(start_btn)

	root.add_child(HSeparator.new())

	var audio_header := Label.new()
	audio_header.text = "Audio Settings"
	audio_header.add_theme_font_size_override("font_size", 20)
	root.add_child(audio_header)

	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 8)
	root.add_child(volume_row)

	var volume_label := Label.new()
	volume_label.text = "Volume"
	volume_row.add_child(volume_label)

	var volume_slider := HSlider.new()
	volume_slider.min_value = -30.0
	volume_slider.max_value = 6.0
	volume_slider.step = 0.5
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.value = music_volume_db
	volume_row.add_child(volume_slider)

	var volume_value := Label.new()
	volume_value.text = _format_db(music_volume_db)
	volume_row.add_child(volume_value)
	volume_slider.value_changed.connect(Callable(self, "_on_volume_changed").bind(volume_value))

	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 8)
	root.add_child(speed_row)

	var speed_label := Label.new()
	speed_label.text = "Speed"
	speed_row.add_child(speed_label)

	var speed_slider := HSlider.new()
	speed_slider.min_value = 0.5
	speed_slider.max_value = 1.5
	speed_slider.step = 0.05
	speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_slider.value = music_speed
	speed_row.add_child(speed_slider)

	var speed_value := Label.new()
	speed_value.text = _format_speed(music_speed)
	speed_row.add_child(speed_value)
	speed_slider.value_changed.connect(Callable(self, "_on_speed_changed").bind(speed_value))

	var bass_row := HBoxContainer.new()
	bass_row.add_theme_constant_override("separation", 8)
	root.add_child(bass_row)

	var bass_label := Label.new()
	bass_label.text = "Bass"
	bass_row.add_child(bass_label)

	var bass_slider := HSlider.new()
	bass_slider.min_value = -12.0
	bass_slider.max_value = 12.0
	bass_slider.step = 0.5
	bass_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bass_slider.value = music_bass_db
	bass_row.add_child(bass_slider)

	var bass_value := Label.new()
	bass_value.text = _format_db(music_bass_db)
	bass_row.add_child(bass_value)
	bass_slider.value_changed.connect(Callable(self, "_on_bass_changed").bind(bass_value))

	var track_row := HBoxContainer.new()
	track_row.add_theme_constant_override("separation", 8)
	root.add_child(track_row)

	var track_label := Label.new()
	track_label.text = "Track"
	track_row.add_child(track_label)

	var track_select := OptionButton.new()
	track_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tracks := MusicDatabase.list_tracks()
	if tracks.is_empty():
		tracks = [music_track]
	for i in range(tracks.size()):
		var track_name: String = String(tracks[i])
		track_select.add_item(track_name.capitalize(), i)
		track_select.set_item_metadata(i, track_name)
		if track_name == music_track:
			track_select.select(i)
	track_row.add_child(track_select)
	track_select.item_selected.connect(Callable(self, "_on_track_selected").bind(track_select))

	root.add_child(HSeparator.new())

	var interface_header := Label.new()
	interface_header.text = "Interface Settings"
	interface_header.add_theme_font_size_override("font_size", 20)
	root.add_child(interface_header)

	var interface_grid := GridContainer.new()
	interface_grid.columns = 2
	interface_grid.add_theme_constant_override("h_separation", 10)
	interface_grid.add_theme_constant_override("v_separation", 6)
	root.add_child(interface_grid)

	_add_interface_toggle(interface_grid, "Growth: show percent", "growth_percent")
	_add_interface_toggle(interface_grid, "Growth: show bar", "growth_bar")
	_add_interface_toggle(interface_grid, "Moisture: show percent", "moisture_percent")
	_add_interface_toggle(interface_grid, "Moisture: show bar", "moisture_bar")
	_add_interface_toggle(interface_grid, "Nutrients: show percent", "nutrients_percent")
	_add_interface_toggle(interface_grid, "Nutrients: show bar", "nutrients_bar")
	_add_interface_toggle(interface_grid, "Sunlight: show percent", "sunlight_percent")
	_add_interface_toggle(interface_grid, "Sunlight: show bar", "sunlight_bar")
	_add_interface_toggle(interface_grid, "Display healthy leaves", "show_healthy")
	_add_interface_toggle(interface_grid, "Display wilted leaves", "show_wilted")

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0.0, 40.0)
	close_btn.pressed.connect(_close_game_menu)
	root.add_child(close_btn)

func _close_game_menu() -> void:
	if game_menu_layer:
		game_menu_layer.queue_free()
		game_menu_layer = null

func _on_start_screen_pressed() -> void:
	_close_game_menu()
	_return_to_menu()

func _on_volume_changed(value: float, value_label: Label) -> void:
	music_volume_db = value
	value_label.text = _format_db(value)
	_apply_audio_settings()

func _on_speed_changed(value: float, value_label: Label) -> void:
	music_speed = value
	value_label.text = _format_speed(value)
	_apply_audio_settings()

func _on_bass_changed(value: float, value_label: Label) -> void:
	music_bass_db = value
	value_label.text = _format_db(value)
	_apply_audio_settings()

func _on_track_selected(index: int, dropdown: OptionButton) -> void:
	var meta = dropdown.get_item_metadata(index)
	var selected_name := String(meta if meta != null else dropdown.get_item_text(index).to_lower())
	_load_track(selected_name)

func _add_interface_toggle(container: Container, label: String, key: String) -> void:
	var box := CheckBox.new()
	box.text = label
	box.button_pressed = interface_settings.get(key, true)
	box.toggled.connect(Callable(self, "_on_interface_toggle").bind(key))
	container.add_child(box)

func _on_interface_toggle(pressed: bool, key: String) -> void:
	interface_settings[key] = pressed
	_refresh_interface_visibility()
	if plant and game_state == GameState.PLAYING:
		_update_stats_ui(plant.get_status())

func _format_db(value: float) -> String:
	return "%0.1f dB" % value

func _format_speed(value: float) -> String:
	return "%0.2fx" % value

func _draw() -> void:
	var view: Vector2 = get_viewport_rect().size
	# Sky
	draw_rect(Rect2(Vector2(-24.0, -24.0), Vector2(view.x + 48.0, view.y + 48.0)), sky_color)
	# Sun and moon
	var p: float = cycle_time / cycle_seconds
	var sun_pos: Vector2 = _sun_position(view, p)
	var moon_pos: Vector2 = _moon_position(view, p)
	var sun_col: Color = Color(0.98, 0.90, 0.55)
	var moon_col: Color = Color(0.85, 0.88, 0.95)
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
	_draw_scenery(view, p)
	
	# Calculate color adjustments for ground and trees based on time of day
	var adjusted_ground_color: Color = ground_color
	if p >= 0.4167 and p < 0.5584:  # Dusk - 30% warmer, 20% less saturated
		var dusk_progress: float = (p - 0.4167) / (0.5584 - 0.4167)
		adjusted_ground_color = _adjust_color_warm_desaturate(ground_color, dusk_progress * 0.3, dusk_progress * 0.2)
	elif p >= 0.5584 and p < 0.95:  # Night - 30% less saturated, 50% cooler (bluer)
		adjusted_ground_color = _adjust_color_cool_desaturate(ground_color, 0.3, 0.5)
	elif p >= 0.95 or p < 0.02:  # Dawn/night transition
		if p >= 0.95:
			var dawn_progress: float = (p - 0.95) / (1.0 - 0.95)
			adjusted_ground_color = _adjust_color_cool_desaturate(ground_color, 0.3 * (1.0 - dawn_progress), 0.5 * (1.0 - dawn_progress))
		elif p < 0.02:
			var early_dawn_progress: float = p / 0.02
			adjusted_ground_color = _adjust_color_cool_desaturate(ground_color, 0.3 * (1.0 - early_dawn_progress), 0.5 * (1.0 - early_dawn_progress))
	
	# Decorative tree - pass cycle progress for arc-based lighting
	_draw_tree(view, p, sun_active)
	
	# Critters
	_draw_critters(view)
	
	# Ground
	draw_rect(Rect2(Vector2(-24.0, view.y - ground_height), Vector2(view.x + 48.0, ground_height + 32.0)), adjusted_ground_color)


func _adjust_color_warm_desaturate(color: Color, warmth_amount: float, desaturate_amount: float) -> Color:
	# Make color warmer (more red/orange) and less saturated
	var result: Color = color
	# Add warmth by increasing red slightly and reducing blue
	result.r = minf(1.0, result.r + warmth_amount * 0.2)
	result.b = maxf(0.0, result.b - warmth_amount * 0.15)
	# Desaturate by blending towards gray
	var gray: float = (result.r + result.g + result.b) / 3.0
	result.r = lerpf(result.r, gray, desaturate_amount)
	result.g = lerpf(result.g, gray, desaturate_amount)
	result.b = lerpf(result.b, gray, desaturate_amount)
	return result

func _adjust_color_cool_desaturate(color: Color, desaturate_amount: float, cool_amount: float) -> Color:
	# Make color cooler (more blue) and less saturated
	var result: Color = color
	# Add coolness by increasing blue and reducing red
	result.b = minf(1.0, result.b + cool_amount * 0.3)
	result.r = maxf(0.0, result.r - cool_amount * 0.2)
	# Desaturate by blending towards gray
	var gray: float = (result.r + result.g + result.b) / 3.0
	result.r = lerpf(result.r, gray, desaturate_amount)
	result.g = lerpf(result.g, gray, desaturate_amount)
	result.b = lerpf(result.b, gray, desaturate_amount)
	return result

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
	
	# Set custom cursor based on action
	if action in custom_cursors:
		Input.set_custom_mouse_cursor(custom_cursors[action], Input.CURSOR_ARROW, Vector2(8, 8))
	else:
		Input.set_custom_mouse_cursor(null)

func _on_action_button(action: int) -> void:
	_set_action(action)




func _apply_action_press() -> void:
	if plant == null:
		return
	# Non-draggable actions should not activate drag mode
	if current_action in [Action.PRUNE, Action.REPOT]:
		drag_active = false
		drag_button = -1
	
	# Special handling for PRUNE - try to click on individual leaf
	if current_action == Action.PRUNE:
		var mouse_pos := get_viewport().get_mouse_position()
		var plant_local_pos := mouse_pos - plant.position
		if plant.try_prune_leaf(plant_local_pos):
			return  # Successfully pruned a leaf
	
	match current_action:
		Action.WATER:
			plant.water()
		Action.FEED:
			plant.feed_nutrients()
		Action.PRUNE:
			plant.prune()  # Fallback to old prune if didn't click a leaf
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
	# Phases: dawn 0.00-0.15, day 0.15-0.4167, dusk 0.4167-0.5584,
	# dusk->night 0.5584-0.6584, steady night 0.6584-0.9000, dawn 0.9000-1.00.
	if p < 0.15:
		var t: float = p / 0.15
		return sky_dawn.lerp(sky_day, t)
	elif p < 0.4167:
		return sky_day
	elif p < 0.5584:
		var t: float = (p - 0.4167) / 0.1417
		return sky_day.lerp(sky_dusk, t)
	elif p < 0.6584:
		var t: float = (p - 0.5584) / 0.10
		return sky_dusk.lerp(sky_night, t)
	elif p < 0.9000:
		return sky_night
	else:
		var t: float = (p - 0.9000) / 0.10
		return sky_night.lerp(sky_dawn, clampf(t, 0.0, 1.0))

func _star_alpha(p: float) -> float:
	# Stars fade in during dusk->night 0.5584-0.6584, stay on through 0.9000, then fade out to dawn.
	if p < 0.5584:
		return 0.0
	elif p < 0.6584:
		var t: float = (p - 0.5584) / 0.10
		return clampf(t, 0.0, 1.0)
	elif p < 0.9000:
		return 1.0
	else:
		var t: float = (1.0 - p) / 0.10
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

func _draw_scenery(view: Vector2, cycle_progress: float) -> void:
	# Draw moving clouds
	var cloud_col: Color = Color(1.0, 1.0, 1.0, 0.7)
	for cloud in clouds:
		var scale: float = cloud.size_scale
		var base_x: float = cloud.x
		var base_y: float = cloud.y
		# Three overlapping semi-circles for fluffy cloud effect
		var r1: float = 16.0 * scale
		var r2: float = 20.0 * scale
		var r3: float = 14.0 * scale
		draw_arc(Vector2(base_x - 12.0 * scale, base_y), r1, PI, TAU, 32, cloud_col, r1 * 0.9, true)
		draw_arc(Vector2(base_x + 3.0 * scale, base_y - 4.0 * scale), r2, PI, TAU, 32, cloud_col, r2 * 0.9, true)
		draw_arc(Vector2(base_x + 18.0 * scale, base_y), r3, PI, TAU, 32, cloud_col, r3 * 0.9, true)
	
	# Tree clusters
	var ground_y: float = view.y - ground_height
	
	# Calculate color adjustments for scenery trees based on time of day
	var trunk_col: Color = Color(0.35, 0.25, 0.18)
	var foliage_dark: Color = Color(0.15, 0.40, 0.18)
	var foliage_mid: Color = Color(0.20, 0.50, 0.22)
	var foliage_light: Color = Color(0.25, 0.58, 0.28)
	
	if cycle_progress >= 0.4167 and cycle_progress < 0.5584:  # Dusk - warmer and less saturated
		var dusk_progress: float = (cycle_progress - 0.4167) / (0.5584 - 0.4167)
		trunk_col = _adjust_color_warm_desaturate(trunk_col, dusk_progress * 0.3, dusk_progress * 0.2)
		foliage_dark = _adjust_color_warm_desaturate(foliage_dark, dusk_progress * 0.3, dusk_progress * 0.2)
		foliage_mid = _adjust_color_warm_desaturate(foliage_mid, dusk_progress * 0.3, dusk_progress * 0.2)
		foliage_light = _adjust_color_warm_desaturate(foliage_light, dusk_progress * 0.3, dusk_progress * 0.2)
	elif cycle_progress >= 0.5584 and cycle_progress < 0.95:  # Night - cooler and less saturated
		trunk_col = _adjust_color_cool_desaturate(trunk_col, 0.3, 0.5)
		foliage_dark = _adjust_color_cool_desaturate(foliage_dark, 0.3, 0.5)
		foliage_mid = _adjust_color_cool_desaturate(foliage_mid, 0.3, 0.5)
		foliage_light = _adjust_color_cool_desaturate(foliage_light, 0.3, 0.5)
	elif cycle_progress >= 0.95 or cycle_progress < 0.02:  # Dawn transition back to normal
		if cycle_progress >= 0.95:
			var dawn_progress: float = (cycle_progress - 0.95) / (1.0 - 0.95)
			trunk_col = _adjust_color_cool_desaturate(trunk_col, 0.3 * (1.0 - dawn_progress), 0.5 * (1.0 - dawn_progress))
			foliage_dark = _adjust_color_cool_desaturate(foliage_dark, 0.3 * (1.0 - dawn_progress), 0.5 * (1.0 - dawn_progress))
			foliage_mid = _adjust_color_cool_desaturate(foliage_mid, 0.3 * (1.0 - dawn_progress), 0.5 * (1.0 - dawn_progress))
			foliage_light = _adjust_color_cool_desaturate(foliage_light, 0.3 * (1.0 - dawn_progress), 0.5 * (1.0 - dawn_progress))
		elif cycle_progress < 0.02:
			var early_dawn_progress: float = cycle_progress / 0.02
			trunk_col = _adjust_color_cool_desaturate(trunk_col, 0.3 * (1.0 - early_dawn_progress), 0.5 * (1.0 - early_dawn_progress))
			foliage_dark = _adjust_color_cool_desaturate(foliage_dark, 0.3 * (1.0 - early_dawn_progress), 0.5 * (1.0 - early_dawn_progress))
			foliage_mid = _adjust_color_cool_desaturate(foliage_mid, 0.3 * (1.0 - early_dawn_progress), 0.5 * (1.0 - early_dawn_progress))
			foliage_light = _adjust_color_cool_desaturate(foliage_light, 0.3 * (1.0 - early_dawn_progress), 0.5 * (1.0 - early_dawn_progress))
	
	# Left tree cluster
	var tree1_x: float = view.x * 0.12
	# Trunks
	draw_rect(Rect2(tree1_x - 6.0, ground_y - 45.0, 12.0, 45.0), trunk_col)
	draw_rect(Rect2(tree1_x + 25.0, ground_y - 38.0, 10.0, 38.0), trunk_col)
	draw_rect(Rect2(tree1_x - 28.0, ground_y - 40.0, 11.0, 40.0), trunk_col)
	# Foliage layers
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
	_load_track(music_track)

func _load_track(name: String) -> void:
	if music_player == null:
		return
	music_track = name
	var data := MusicDatabase.get_track(name)
	var music_path: String = String(data.get("file", "res://assets/audio/bg_music.mp3"))
	if ResourceLoader.exists(music_path):
		var stream := load(music_path)
		if stream:
			music_player.stream = stream
			var bus_name: String = String(data.get("bus", "Master"))
			music_bus_index = _ensure_bus_exists(bus_name)
			music_player.bus = bus_name
			if not music_player.finished.is_connected(_on_music_finished):
				music_player.finished.connect(_on_music_finished)
			_apply_audio_settings()
			var should_loop: bool = bool(data.get("loop", true))
			if stream.has_method("set_loop"):
				stream.set_loop(should_loop)
			elif stream.has_method("set_looping"):
				stream.call("set_looping", should_loop)
			elif stream.has_method("set_loop_mode"):
				stream.call("set_loop_mode", should_loop)
			if not music_muted:
				music_player.play()
	else:
		push_warning("Music file not found at: " + music_path + ". Add your music file to assets/audio/")

func _apply_audio_settings() -> void:
	if music_player == null:
		return
	music_player.volume_db = music_volume_db
	music_player.pitch_scale = music_speed
	_apply_bass_boost()

func _ensure_bus_exists(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
	return idx

func _ensure_music_eq() -> void:
	if music_bus_index < 0:
		return
	for i in range(AudioServer.get_bus_effect_count(music_bus_index)):
		var eff := AudioServer.get_bus_effect(music_bus_index, i)
		if eff is AudioEffectEQ6:
			music_eq_effect = eff
			return
	# Add a new EQ6 if none present
	var eq := AudioEffectEQ6.new()
	AudioServer.add_bus_effect(music_bus_index, eq)
	music_eq_effect = eq

func _apply_bass_boost() -> void:
	if music_bus_index < 0:
		return
	_ensure_music_eq()
	if music_eq_effect:
		# Boost first two bands for low end
		music_eq_effect.set_band_gain_db(0, music_bass_db)
		music_eq_effect.set_band_gain_db(1, music_bass_db * 0.75)

func _on_music_finished() -> void:
	if not music_muted and music_player.stream:
		music_player.play()

func _toggle_music() -> void:
	if music_player == null:
		return
	music_muted = not music_muted
	if music_muted:
		music_player.stop()
		if "music" in action_buttons:
			action_buttons["music"].text = "Music: OFF"
	elif music_player.stream:
		_apply_audio_settings()
		music_player.play()
		if "music" in action_buttons:
			action_buttons["music"].text = "Music: ON"

func _return_to_menu() -> void:
	_close_game_menu()
	game_state = GameState.MENU
	# Clean up current game
	if plant:
		plant.queue_free()
		plant = null
	if ui_layer:
		ui_layer.queue_free()
		ui_layer = null
	action_buttons.clear()
	# Reset cursor to default
	Input.set_custom_mouse_cursor(null)
	# Rebuild menu
	_build_menu()

func _create_custom_cursors() -> void:
	# Create custom cursor icons for each tool
	custom_cursors[Action.WATER] = _create_watering_can_cursor()
	custom_cursors[Action.FEED] = _create_fertilizer_cursor()
	custom_cursors[Action.PRUNE] = _create_pruner_cursor()
	custom_cursors[Action.REPOT] = _create_pot_cursor()

func _create_watering_can_cursor() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	
	# Draw a watering can with white border
	var can_color := Color(0.5, 0.6, 0.7)
	var border_color := Color(1.0, 1.0, 1.0)
	
	# White border - can body
	for y in range(4, 26):
		for x in range(0, 18):
			if x < 3 or x >= 15 or y < 7 or y >= 23:
				if x >= 0 and y >= 4:
					img.set_pixel(x, y, border_color)
	
	# Can body
	for y in range(7, 23):
		for x in range(3, 15):
			img.set_pixel(x, y, can_color)
	
	# White border - spout
	for x in range(15, 30):
		for y in range(10, 18):
			if x < 18 or x >= 27 or y < 13 or y >= 15:
				img.set_pixel(x, y, border_color)
	
	# Spout
	for x in range(18, 27):
		for y in range(13, 15):
			img.set_pixel(x, y, can_color)
	
	# Handle with border
	var handle_color := Color(0.4, 0.5, 0.6)
	for y in range(8, 22):
		for x in range(0, 5):
			if x == 0 or y == 8 or y == 21:
				img.set_pixel(x, y, border_color)
			elif x >= 1 and x < 4 and y > 8 and y < 21:
				img.set_pixel(x, y, handle_color)
	
	# Water drops with white border
	var drop_color := Color(0.4, 0.6, 0.9, 0.9)
	for drop in [[27, 18], [28, 23], [29, 28]]:
		var dx = drop[0]
		var dy = drop[1]
		if dy < 32:
			# Border
			for by in range(-1, 3):
				for bx in range(-1, 3):
					if dx+bx >= 0 and dx+bx < 32 and dy+by >= 0 and dy+by < 32:
						if bx == -1 or bx == 2 or by == -1 or by == 2:
							img.set_pixel(dx+bx, dy+by, border_color)
			# Drop
			for by in range(0, 2):
				for bx in range(0, 2):
					if dx+bx < 32 and dy+by < 32:
						img.set_pixel(dx+bx, dy+by, drop_color)
	
	return ImageTexture.create_from_image(img)

func _create_fertilizer_cursor() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	
	# Draw a fertilizer bag with white border
	var bag_color := Color(0.8, 0.6, 0.4)
	var dark_bag := Color(0.7, 0.5, 0.3)
	var border_color := Color(1.0, 1.0, 1.0)
	
	# White border around entire bag
	for y in range(0, 30):
		for x in range(3, 29):
			if x < 6 or x >= 26 or y < 3 or y >= 27:
				if y >= 0:
					img.set_pixel(x, y, border_color)
	
	# Bag shape (main body)
	for y in range(6, 27):
		for x in range(6, 26):
			img.set_pixel(x, y, bag_color)
	
	# Bag top (folded area)
	for x in range(6, 26):
		for y in range(3, 9):
			if y >= 3:
				img.set_pixel(x, y, dark_bag)
	
	# Label stripe (green)
	var label_color := Color(0.3, 0.6, 0.3)
	for y in range(13, 21):
		for x in range(8, 24):
			img.set_pixel(x, y, label_color)
	
	# Label text suggestion (darker green lines)
	var text_color := Color(0.2, 0.4, 0.2)
	for x in range(10, 22):
		img.set_pixel(x, 15, text_color)
		img.set_pixel(x, 18, text_color)
	
	return ImageTexture.create_from_image(img)

func _create_pruner_cursor() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	
	# Draw scissors with white border
	var blade_color := Color(0.7, 0.7, 0.75)
	var handle_color := Color(0.6, 0.2, 0.2)
	var border_color := Color(1.0, 1.0, 1.0)
	
	# Left blade - larger pointed blade going up-left
	for i in range(14):
		var blade_width = 4 if i < 10 else 3
		for thick in range(blade_width):
			var px = 4 + i - thick
			var py = 1 + i
			if px >= 0 and px < 32 and py < 32:
				if thick == 0 or thick == blade_width - 1:
					img.set_pixel(px, py, border_color)
				else:
					img.set_pixel(px, py, blade_color)
	
	# Right blade - larger pointed blade going up-right
	for i in range(14):
		var blade_width = 4 if i < 10 else 3
		for thick in range(blade_width):
			var px = 28 - i + thick
			var py = 1 + i
			if px >= 0 and px < 32 and py < 32:
				if thick == 0 or thick == blade_width - 1:
					img.set_pixel(px, py, border_color)
				else:
					img.set_pixel(px, py, blade_color)
	
	# Left handle loop with border
	var loop_left_center_x = 8
	var loop_left_center_y = 24
	for y in range(18, 30):
		for x in range(2, 14):
			var dx = x - loop_left_center_x
			var dy = y - loop_left_center_y
			var dist = sqrt(dx * dx + dy * dy)
			if dist < 6.5 and dist > 3.5:
				if dist < 4.5 or dist > 5.5:
					img.set_pixel(x, y, border_color)
				else:
					img.set_pixel(x, y, handle_color)
	
	# Right handle loop with border
	var loop_right_center_x = 24
	var loop_right_center_y = 24
	for y in range(18, 30):
		for x in range(18, 30):
			var dx = x - loop_right_center_x
			var dy = y - loop_right_center_y
			var dist = sqrt(dx * dx + dy * dy)
			if dist < 6.5 and dist > 3.5:
				if dist < 4.5 or dist > 5.5:
					img.set_pixel(x, y, border_color)
				else:
					img.set_pixel(x, y, handle_color)
	
	# Pivot point with border (center where blades cross)
	for y in range(13, 19):
		for x in range(13, 19):
			if x == 13 or x == 18 or y == 13 or y == 18:
				img.set_pixel(x, y, border_color)
			else:
				img.set_pixel(x, y, Color(0.3, 0.3, 0.3))
	
	return ImageTexture.create_from_image(img)

func _create_pot_cursor() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	
	# Draw a pot with white border
	var pot_color := Color(0.7, 0.4, 0.3)
	var rim_color := Color(0.8, 0.5, 0.4)
	var border_color := Color(1.0, 1.0, 1.0)
	
	# White border - rim
	for x in range(0, 32):
		for y in range(3, 9):
			if x < 3 or x >= 29 or y < 6:
				img.set_pixel(x, y, border_color)
	
	# Pot rim
	for x in range(3, 29):
		for y in range(6, 9):
			img.set_pixel(x, y, rim_color)
	
	# Pot body with border (tapered)
	for y in range(9, 29):
		var width := 22.0 + (y - 9) * 0.4
		var start_x := 16.0 - width / 2.0
		var end_x := 16.0 + width / 2.0
		for x in range(32):
			if x >= start_x - 3 and x < end_x + 3:
				if x < start_x or x >= end_x:
					# Border
					img.set_pixel(x, y, border_color)
				else:
					# Pot body
					img.set_pixel(x, y, pot_color)
	
	# Bottom with border
	for x in range(4, 28):
		for y in range(29, 32):
			if y == 29:
				img.set_pixel(x, y, border_color)
			else:
				img.set_pixel(x, y, Color(0.6, 0.3, 0.2))
	
	return ImageTexture.create_from_image(img)
