extends Node2D
class_name Plant

@export var max_height: float = 345.0
@export var stem_width: float = 6.0
@export var base_growth_rate: float = 0.012  # Slightly slower to allow fuller progression
@export var water_bonus: float = 0.8
@export var nutrient_bonus: float = 0.9
@export var moisture_decay: float = 1.0 / 86400.0 # ~1 real-time day
@export var nutrient_decay: float = 1.0 / (86400.0 * 2.0) # ~2 real-time days
@export var ideal_sunlight: float = 0.55
@export var sunlight_tolerance: float = 0.25
@export var sunlight_step: float = 0.08
@export var seconds_per_day: float = 90.0
@export var growth_days: float = 4.0
@export var bloom_days: float = 2.0
@export var leaf_count: int = 6
@export var leaf_size: Vector2 = Vector2(34.0, 14.0)
@export var bud_radius: float = 12.0
@export var stem_color: Color = Color(0.16, 0.50, 0.25)
@export var leaf_color: Color = Color(0.25, 0.70, 0.35)

# Flower variant colors
var variant_name: String = "purple"
var flower_petal_color: Color = Color(0.75, 0.55, 0.85)  # Purple petals
var flower_bud_color: Color = Color(0.65, 0.45, 0.75)  # Purple bud
var flower_mid_color: Color = Color(0.55, 0.35, 0.65)  # Purple mid

@export var wilt_threshold: float = 0.22
@export var overwater_threshold: float = 0.86
@export var pot_caps: PackedFloat64Array = [0.35, 0.7, 1.0]

var growth: float = 0.0
var moisture: float = 0.0
var nutrients: float = 0.45
var sunlight_setting: float = 0.55
var time_accum: float = 0.0
var total_time: float = 0.0
var bloom_progress: float = 0.0
var wilted_leaves: int = 0
var pot_level: int = 0
var wilt_accum: float = 0.0
var splash_timer: float = 0.0

func _process(delta: float) -> void:
	time_accum += delta
	total_time += delta
	moisture = clampf(moisture - moisture_decay * delta, 0.0, 1.0)
	nutrients = clampf(nutrients - nutrient_decay * delta, 0.0, 1.0)
	if splash_timer > 0.0:
		splash_timer = maxf(0.0, splash_timer - delta)

	var pot_cap: float = float(pot_caps[min(pot_level, pot_caps.size() - 1)])
	var time_gate: float = clampf(total_time / (seconds_per_day * growth_days), 0.0, 1.0)
	var target_growth: float = minf(time_gate, pot_cap)
	var stress := _compute_stress(pot_cap, target_growth)
	_accumulate_wilt(stress, delta, pot_cap)

	var energy: float = base_growth_rate * (1.0 + moisture * water_bonus + nutrients * nutrient_bonus)
	energy *= maxf(0.25, 1.0 - stress)
	energy *= maxf(0.35, 1.0 - float(wilted_leaves) * 0.06)

	if growth < target_growth:
		growth = minf(target_growth, growth + energy * delta)
	elif growth > target_growth:
		growth = maxf(target_growth, growth - energy * 0.2 * delta)

	bloom_progress = clampf((total_time - seconds_per_day * growth_days) / (seconds_per_day * bloom_days), 0.0, 1.0)
	queue_redraw()

func water(amount: float = 0.35) -> void:
	moisture = clampf(moisture + amount, 0.0, 1.0)
	splash_timer = 0.6

func feed_nutrients(amount: float = 0.4) -> void:
	nutrients = clampf(nutrients + amount, 0.0, 1.0)

func prune() -> void:
	if wilted_leaves > 0:
		wilted_leaves -= 1
		wilt_accum = 0.0

func adjust_sunlight(delta: float) -> void:
	sunlight_setting = clampf(sunlight_setting + delta, 0.0, 1.0)

func set_flower_variant(variant: String) -> void:
	variant_name = variant.to_lower()
	match variant_name:
		"yellow":
			flower_petal_color = Color(0.95, 0.85, 0.40)
			flower_bud_color = Color(0.85, 0.75, 0.30)
			flower_mid_color = Color(0.75, 0.65, 0.20)
		"red":
			flower_petal_color = Color(0.90, 0.35, 0.35)
			flower_bud_color = Color(0.80, 0.25, 0.25)
			flower_mid_color = Color(0.70, 0.15, 0.15)
		_:
			# Default to purple
			variant_name = "purple"
			flower_petal_color = Color(0.75, 0.55, 0.85)
			flower_bud_color = Color(0.65, 0.45, 0.75)
			flower_mid_color = Color(0.55, 0.35, 0.65)

func repot() -> void:
	if pot_level < pot_caps.size() - 1 and growth >= pot_caps[pot_level] - 0.05:
		pot_level += 1

func get_status() -> Dictionary:
	return {
		"growth": growth,
		"bloom": bloom_progress,
		"moisture": moisture,
		"nutrients": nutrients,
		"sunlight": sunlight_setting,
		"wilted": wilted_leaves,
		"pot_level": pot_level,
		"pot_cap": pot_caps[min(pot_level, pot_caps.size() - 1)],
		"stage": get_stage(),
		"time_gate": clampf(total_time / (seconds_per_day * growth_days), 0.0, 1.0),
	}

func get_stage() -> String:
	if bloom_progress >= 1.0:
		return "Blooming"
	if total_time >= seconds_per_day * growth_days:
		return "Mature"
	return "Seedling"

func _compute_stress(pot_cap: float, target_growth: float) -> float:
	var stress: float = 0.0
	if moisture < wilt_threshold:
		stress += (wilt_threshold - moisture) * 0.9
	if moisture > overwater_threshold:
		stress += (moisture - overwater_threshold) * 0.7
	if nutrients < 0.35:
		stress += (0.35 - nutrients) * 0.7
	var light_diff: float = absf(sunlight_setting - ideal_sunlight)
	if light_diff > sunlight_tolerance:
		stress += (light_diff - sunlight_tolerance) * 0.9
	if growth >= pot_cap - 0.02 and growth > target_growth:
		stress += 0.3
	return minf(stress, 2.0)

func _accumulate_wilt(stress: float, delta: float, pot_cap: float) -> void:
	var stress_factor: float = maxf(0.0, stress)
	if moisture < wilt_threshold or moisture > overwater_threshold:
		stress_factor += 0.3
	if growth >= pot_cap - 0.02:
		stress_factor += 0.4
	wilt_accum += stress_factor * delta * 0.35
	if wilt_accum > 1.0:
		wilted_leaves += 1
		wilt_accum = 0.0

func _draw() -> void:
	var stem_height := _ease_out(growth) * max_height
	var sway := sin(time_accum * 1.3) * 6.0 * growth
	var base := Vector2.ZERO
	var tip := base + Vector2(sway, -stem_height)
	var stem_col := stem_color.darkened(minf(0.4, float(wilted_leaves) * 0.05))
	_draw_pot(base)
	# Draw main stem
	draw_line(base, tip, stem_col, stem_width, true)
	
	# Branches gated by repotting: first branch after repot 1, second after repot 2
	var branch_len: float = stem_height * 0.55
	var branch_width: float = stem_width * 0.7
	if branch_len > 20.0:
		var branch1_progress: float = 0.0
		var branch2_progress: float = 0.0
		if pot_level >= 1:
			branch1_progress = clampf((growth - pot_caps[0]) / 0.35, 0.0, 1.0)
		if pot_level >= 2 and pot_caps.size() > 1:
			branch2_progress = clampf((growth - pot_caps[1]) / 0.30, 0.0, 1.0)
		if branch1_progress > 0.0:
			var branch1_attach := base + Vector2(sway * 0.18, -stem_height * 0.32 + 70.0)
			var branch1_tip := branch1_attach + Vector2(-branch_len * 0.45 * branch1_progress, -branch_len * 0.80 * branch1_progress)
			draw_line(branch1_attach, branch1_tip, stem_col, branch_width, true)
			if branch1_progress > 0.65:
				_draw_flower(branch1_tip)
		if branch2_progress > 0.0:
			var branch2_attach := base + Vector2(sway * -0.15, -stem_height * 0.48 + 70.0)
			var branch2_tip := branch2_attach + Vector2(branch_len * 0.50 * branch2_progress, -branch_len * 0.85 * branch2_progress)
			draw_line(branch2_attach, branch2_tip, stem_col, branch_width, true)
			if branch2_progress > 0.65:
				_draw_flower(branch2_tip)

	_draw_leaves(base, tip, stem_height)
	# Primary flower at main tip
	_draw_flower(tip)
	_draw_splash(base)

func _draw_leaves(base: Vector2, tip: Vector2, stem_height: float) -> void:
	if leaf_count <= 0:
		return
	var steps: int = max(1, leaf_count)
	var wilt_dark := minf(0.6, float(wilted_leaves) * 0.07)
	var leaf_col := leaf_color.darkened(wilt_dark)
	for i in range(steps):
		var t := float(i + 1) / float(steps + 1)
		if growth < t * 0.8:
			continue
		var y := -stem_height * t
		var side := 1.0 if i % 2 == 0 else -1.0
		var attach := Vector2(0.0, y)
		var sway := sin(time_accum * 1.8 + float(i)) * 4.0 * growth
		var dir := Vector2(side * leaf_size.x, -leaf_size.y * 0.35).rotated(deg_to_rad(8.0 * side) + sway * 0.02)
		var tip_point := attach + dir
		var mid := attach + dir * 0.5 + Vector2(0.0, -leaf_size.y * 0.35)
		var spread := Vector2(dir.x * 0.25, leaf_size.y * 0.8 * side)
		var pts := PackedVector2Array([
			attach,
			mid + spread * -1.0,
			tip_point,
			mid + spread,
		])
		draw_colored_polygon(pts, leaf_col)

func _draw_pot(base: Vector2) -> void:
	# Pot sizes scale with pot level
	var pot_width := 60.0 + float(pot_level) * 30.0
	var pot_height := 50.0 + float(pot_level) * 18.0
	var pot_rim_y := 6.0
	var pot_color := Color(0.55, 0.35, 0.20)
	var pot_shadow := Color(0.35, 0.22, 0.12)
	
	# Shadow beneath pot
	var shadow_pts := PackedVector2Array([
		base + Vector2(-pot_width * 0.5 - 4.0, pot_rim_y),
		base + Vector2(pot_width * 0.5 + 4.0, pot_rim_y),
		base + Vector2(pot_width * 0.45, pot_rim_y + 3.0),
		base + Vector2(-pot_width * 0.45, pot_rim_y + 3.0)
	])
	draw_colored_polygon(shadow_pts, pot_shadow)
	
	# Pot body (trapezoid shape - wider at top)
	var pot_pts := PackedVector2Array([
		base + Vector2(-pot_width * 0.5, pot_rim_y),
		base + Vector2(pot_width * 0.5, pot_rim_y),
		base + Vector2(pot_width * 0.4, pot_rim_y + pot_height),
		base + Vector2(-pot_width * 0.4, pot_rim_y + pot_height)
	])
	draw_colored_polygon(pot_pts, pot_color)
	
	# Pot rim
	draw_line(
		base + Vector2(-pot_width * 0.5, pot_rim_y),
		base + Vector2(pot_width * 0.5, pot_rim_y),
		pot_color.lightened(0.2),
		3.0,
		true
	)

func _draw_flower(tip: Vector2) -> void:
	var open_amount: float = clampf(bloom_progress, 0.0, 1.0)
	var bloom_radius: float = bud_radius + open_amount * 18.0
	
	if open_amount < 0.3:
		# Bud stage - simple circles
		draw_circle(tip, bloom_radius, flower_bud_color)
		draw_circle(tip + Vector2(0.0, 3.0), bloom_radius * 0.55, flower_mid_color)
	elif open_amount < 1.0:
		# Blooming stage - size increases every 10%
		var growth_stage: float = floor((open_amount - 0.3) / 0.1) / 7.0  # 0-7 stages mapped to 0.0-1.0
		var stage_scale: float = 1.0 + growth_stage * 0.8  # grows from 1.0 to 1.8
		var petal_count: int = 6
		var petal_length: float = bloom_radius * 1.4 * stage_scale
		var petal_width: float = bloom_radius * 0.7 * stage_scale
		var rotation_offset: float = time_accum * 0.15
		
		for i in range(petal_count):
			var angle: float = (TAU / float(petal_count)) * float(i) + rotation_offset
			var petal_tip: Vector2 = tip + Vector2(cos(angle), sin(angle)) * petal_length
			var petal_mid1: Vector2 = tip + Vector2(cos(angle - 0.35), sin(angle - 0.35)) * petal_width
			var petal_mid2: Vector2 = tip + Vector2(cos(angle + 0.35), sin(angle + 0.35)) * petal_width
			
			var petal_pts := PackedVector2Array([tip, petal_mid1, petal_tip, petal_mid2])
			draw_colored_polygon(petal_pts, flower_petal_color)
		
		# Flower center layers
		draw_circle(tip, bloom_radius * 0.7 * stage_scale, flower_bud_color)
		draw_circle(tip, bloom_radius * 0.45 * stage_scale, flower_mid_color)
		draw_circle(tip, bloom_radius * 0.25 * stage_scale, flower_mid_color * 0.8)
	else:
		# Full bloom (100%) - complex multi-layer petals
		var rotation_offset: float = time_accum * 0.12
		
		# Large outer petals (8 petals)
		var outer_count: int = 8
		var outer_length: float = bloom_radius * 2.2
		var outer_width: float = bloom_radius * 0.95
		for i in range(outer_count):
			var angle: float = (TAU / float(outer_count)) * float(i) + rotation_offset
			var petal_tip: Vector2 = tip + Vector2(cos(angle), sin(angle)) * outer_length
			var petal_mid1: Vector2 = tip + Vector2(cos(angle - 0.3), sin(angle - 0.3)) * outer_width
			var petal_mid2: Vector2 = tip + Vector2(cos(angle + 0.3), sin(angle + 0.3)) * outer_width
			
			var petal_pts := PackedVector2Array([tip, petal_mid1, petal_tip, petal_mid2])
			draw_colored_polygon(petal_pts, flower_petal_color * 0.95)  # Slightly lighter outer petals
		
		# Medium inner petals (8 petals offset)
		var mid_count: int = 8
		var mid_length: float = bloom_radius * 1.5
		var mid_width: float = bloom_radius * 0.65
		for i in range(mid_count):
			var angle: float = (TAU / float(mid_count)) * float(i) + rotation_offset + (TAU / 16.0)
			var petal_tip: Vector2 = tip + Vector2(cos(angle), sin(angle)) * mid_length
			var petal_mid1: Vector2 = tip + Vector2(cos(angle - 0.4), sin(angle - 0.4)) * mid_width
			var petal_mid2: Vector2 = tip + Vector2(cos(angle + 0.4), sin(angle + 0.4)) * mid_width
			
			var petal_pts := PackedVector2Array([tip, petal_mid1, petal_tip, petal_mid2])
			draw_colored_polygon(petal_pts, flower_petal_color)
		
		# Flower center layers
		draw_circle(tip, bloom_radius * 0.85, flower_petal_color * 1.1)
		draw_circle(tip, bloom_radius * 0.60, flower_bud_color)
		draw_circle(tip, bloom_radius * 0.35, flower_mid_color)

func _draw_splash(base: Vector2) -> void:
	if splash_timer <= 0.0:
		return
	var t: float = 1.0 - splash_timer / 0.6
	var radius: float = lerp(12.0, 34.0, t)
	var alpha: float = lerp(0.55, 0.0, t)
	draw_circle(base, radius, Color(0.55, 0.75, 0.95, alpha))
	draw_circle(base, radius * 0.55, Color(0.35, 0.55, 0.85, alpha * 0.8))

func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 2)
