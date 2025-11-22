extends Node3D

# Wind trail scene to instance
@export var trail_scene: PackedScene 
@export var trail_count: int = 20 

@export_group("Wind Direction & Distance")
@export var wind_direction: Vector3 = Vector3(1, 0, 1) 
@export var travel_distance: float = 50.0 

@export_group("Spawn Area (Around Camera)")
@export var spawn_radius_xz: float = 20.0
@export var spawn_height_variation: float = 10.0

@export_group("Height Constraints (Global)")
@export var use_global_y_limits: bool = true
@export var global_min_y: float = 2.0
@export var global_max_y: float = 15.0

@export_group("Wind Behavior")
@export var wind_speed: float = 8.0 
@export var wind_turbulence: float = 0.5 
@export var wave_frequency: float = 2.0 
@export var wave_amplitude: float = 1.0 

@export_group("Trail Settings")
# CRITICAL: Set this to match the 'Lifetime' or 'Length' of your GPUTrail3D node!
# If your trail lasts 2 seconds, set this to 2.0 (or slightly more).
@export var trail_fade_duration: float = 2.0 

# Active trails data
var active_trails: Array = []

func _ready() -> void:
	for i in range(trail_count):
		spawn_new_trail(true)

func _process(delta: float) -> void:
	# Only spawn new ones if we have fewer TOTAL trails than allowed
	if active_trails.size() < trail_count:
		spawn_new_trail()

	# Iterate backwards to allow safe removal
	for i in range(active_trails.size() - 1, -1, -1):
		var trail_data = active_trails[i]
		
		# This function now returns TRUE if the trail is fully dead and ready to delete
		if update_trail(trail_data, delta):
			if is_instance_valid(trail_data.node):
				trail_data.node.queue_free()
			active_trails.remove_at(i)

func spawn_new_trail(prewarm: bool = false) -> void:
	if not trail_scene: return
	
	var camera = get_viewport().get_camera_3d()
	if not camera: return

	var cam_pos = camera.global_position
	
	# 1. Spawn Calculations
	var offset_x = randf_range(-spawn_radius_xz, spawn_radius_xz)
	var offset_z = randf_range(-spawn_radius_xz, spawn_radius_xz)
	var upwind_bias = -wind_direction.normalized() * (spawn_radius_xz * 0.5)
	
	var start_x = cam_pos.x + offset_x + upwind_bias.x
	var start_z = cam_pos.z + offset_z + upwind_bias.z
	var start_y = cam_pos.y + randf_range(-spawn_height_variation, spawn_height_variation)
	
	if use_global_y_limits:
		start_y = clamp(start_y, global_min_y, global_max_y)
	
	var start_pos = Vector3(start_x, start_y, start_z)
	var norm_dir = wind_direction.normalized()
	var end_pos = start_pos + (norm_dir * travel_distance)
	
	# 2. Instance
	var trail_instance = trail_scene.instantiate()
	add_child(trail_instance)
	trail_instance.set_as_top_level(true) 
	trail_instance.global_position = start_pos
	
	var start_progress = randf() if prewarm else 0.0
	
	# 3. Store Data (Added 'is_fading' and 'fade_timer')
	var trail_data = {
		"node": trail_instance,
		"start_pos": start_pos,
		"end_pos": end_pos,
		"progress": start_progress,
		"wave_offset": randf() * TAU,
		"speed_multiplier": randf_range(0.8, 1.2),
		"right_vec": norm_dir.cross(Vector3.UP).normalized(),
		"up_vec": norm_dir.cross(norm_dir.cross(Vector3.UP)).normalized(),
		"is_fading": false,
		"fade_timer": 0.0
	}
	
	set_trail_emitting(trail_instance, true)
	active_trails.append(trail_data)

# Helper to toggle emission on different trail types
func set_trail_emitting(node: Node, is_emitting: bool) -> void:
	if node is GPUTrail3D:
		node.emitting = is_emitting
	elif node.has_node("GPUTrail3D"):
		node.get_node("GPUTrail3D").emitting = is_emitting
	# If using standard Godot particles or trails
	elif node is GPUParticles3D:
		node.emitting = is_emitting

func update_trail(trail_data: Dictionary, delta: float) -> bool:
	# --- PHASE 1: FADING OUT ---
	# If the wind has finished moving, we wait for the tail to disappear
	if trail_data.is_fading:
		trail_data.fade_timer += delta
		
		# If time is up, return TRUE (signal to delete this trail)
		if trail_data.fade_timer >= trail_fade_duration:
			return true
		return false # Still fading, don't delete yet

	# --- PHASE 2: MOVING ---
	trail_data.progress += delta * (wind_speed / travel_distance) * trail_data.speed_multiplier
	
	# Check if we reached the end
	if trail_data.progress >= 1.0:
		# Start the fade out process
		trail_data.is_fading = true
		set_trail_emitting(trail_data.node, false) # Stop drawing new lines
		return false # Don't delete yet!

	# Calculate Movement (Only if not fading)
	var t = trail_data.progress
	var base_pos = trail_data.start_pos.lerp(trail_data.end_pos, t)
	
	var wave_time = t * TAU * wave_frequency + trail_data.wave_offset
	var wave_offset_x = sin(wave_time) * wave_amplitude
	var wave_offset_y = cos(wave_time * 0.5) * (wave_amplitude * 0.5)
	var wave_motion = (trail_data.right_vec * wave_offset_x) + (trail_data.up_vec * wave_offset_y)
	
	var time_now = Time.get_ticks_msec() * 0.001
	var turbulence = Vector3(
		sin(time_now + trail_data.wave_offset) * wind_turbulence,
		cos(time_now * 1.5 + trail_data.wave_offset) * wind_turbulence,
		sin(time_now * 0.7) * wind_turbulence * 0.5
	) * min(t * 4.0, 1.0)
	
	trail_data.node.global_position = base_pos + wave_motion + turbulence
	
	return false # Not ready to delete
