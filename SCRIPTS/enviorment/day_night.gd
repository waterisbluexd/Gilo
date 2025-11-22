extends Node3D

var time: float
@export var day_length: float = 1440.0  # 24 minutes in seconds (24 * 60)
@export_range(0, 24, 0.5) var start_hour: float = 7.0  # Start at 7 AM
var time_rate : float
var is_paused: bool = false

@onready var sun: DirectionalLight3D = $Sun
@export var sun_color: Gradient
@export var sun_intensity: Curve

@onready var moon: DirectionalLight3D = $Moon
@export var moon_color: Gradient
@export var moon_intensity: Curve

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@export var sky_top_color: Gradient
@export var sky_bottom_color: Gradient
@export var ground_top_color: Gradient
@export var ground_bottom_color: Gradient
@export var world_environment_intensity: Curve

func _ready() -> void:
	time_rate = 1.0 / day_length
	time = start_hour / 24.0  # Convert hour to 0-1 range
	
	# Update global time immediately
	TimeManager.update_time(time)

func _process(delta: float) -> void:
	# Check for pause input
	if Input.is_key_pressed(KEY_P):
		is_paused = !is_paused
		TimeManager.is_paused = is_paused
	
	# Only update time if not paused
	if not is_paused:
		time += time_rate * delta
		
		if time >= 1.0:
			time = 0.0
		
		# Update global time
		TimeManager.update_time(time)
	
	# Always update visual elements (even when paused, so changes are visible)
	# Sun
	sun.rotation_degrees.x = time * 360 + 90
	sun.light_color = sun_color.sample(time)
	sun.light_energy = sun_intensity.sample(time)
	
	# Moon
	moon.rotation_degrees.x = time * 360 + 270
	moon.light_color = moon_color.sample(time)
	moon.light_energy = moon_intensity.sample(time)
	
	# Sky Color
	world_environment.environment.sky.sky_material.set("sky_top_color", sky_top_color.sample(time))
	world_environment.environment.sky.sky_material.set("sky_bottom_color", sky_bottom_color.sample(time))
	world_environment.environment.sky.sky_material.set("ground_top_color", ground_top_color.sample(time))
	world_environment.environment.sky.sky_material.set("ground_bottom_color", ground_bottom_color.sample(time))
	
	sun.visible = sun.light_energy > 0
	moon.visible = moon.light_energy > 0

# Helper function to get current hour (0-24)
func get_current_hour() -> float:
	return time * 24.0

# Helper function to set specific time
func set_time_of_day(hour: float) -> void:
	time = clamp(hour / 24.0, 0.0, 1.0)
	TimeManager.update_time(time)

# Helper function to check if paused
func is_time_paused() -> bool:
	return is_paused

# Helper function to toggle pause
func toggle_pause() -> void:
	is_paused = !is_paused
	TimeManager.is_paused = is_paused
