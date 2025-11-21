@tool
extends Node3D

var time: float
@export var day_length: float = 24 * 60  # 24 minutes in seconds
@export_range(1, 24, 1) var start_hour: int = 7  # Start at 7 AM
@export_range(0.0, 100.0, 1.0) var time_speed: float = 100.0
@export var paused: bool = false

# Sun
@onready var sun: DirectionalLight3D = $Sun
@export var sun_color: Gradient
@export var sun_intensity: Curve

# Moon
@onready var moon: DirectionalLight3D = $Moon
@export var moon_color: Gradient
@export var moon_intensity: Curve

# World Environment
@onready var environment: WorldEnvironment = $WorldEnvironment
@export var sky_color: Gradient
@export var environment_intensity: Curve

# Time constants
const SUNRISE = 0.25
const NOON = 0.5
const SUNSET = 0.75
const MIDNIGHT = 0.0

func _ready():
	time = hour_to_normalized_time(start_hour)
	
	if not sun_color:
		sun_color = create_default_sun_gradient()
	if not moon_color:
		moon_color = create_default_moon_gradient()
	if not sky_color:
		sky_color = create_default_sky_gradient()
	
	if not sun_intensity:
		sun_intensity = create_default_sun_curve()
	if not moon_intensity:
		moon_intensity = create_default_moon_curve()
	if not environment_intensity:
		environment_intensity = create_default_env_curve()
	
	update_lighting()

func _process(delta):
	if paused:
		return
	
	# Progress time
	time += (delta / day_length) * time_speed
	if time >= 1.0:
		time -= 1.0
	
	update_celestial_bodies()
	update_lighting()

func hour_to_normalized_time(hour: int) -> float:
	if hour == 24:
		return 0.0
	return float(hour) / 24.0

func get_current_hour() -> int:
	var hour = int(time * 24.0)
	if hour == 0:
		return 24
	return hour

func get_current_time_string() -> String:
	# Returns time as "HH:MM" format
	var total_minutes = int(time * 24.0 * 60.0)
	var hours = total_minutes / 60
	var minutes = total_minutes % 60
	if hours == 0:
		hours = 24
	return "%02d:%02d" % [hours, minutes]

func update_celestial_bodies():
	var sun_angle = time * -180.0
	if sun:
		sun.rotation_degrees.x = sun_angle

	if moon:
		moon.rotation_degrees.x = sun_angle - 90.0

func update_lighting():
	# Update sun
	if sun and sun_color and sun_intensity:
		sun.light_color = sun_color.sample(time)
		sun.light_energy = sun_intensity.sample(time)
	
	# Update moon
	if moon and moon_color and moon_intensity:
		moon.light_color = moon_color.sample(time)
		moon.light_energy = moon_intensity.sample(time)
	
	# Update environment
	if environment and environment.environment:
		if sky_color:
			environment.environment.ambient_light_color = sky_color.sample(time)
		if environment_intensity:
			environment.environment.ambient_light_energy = environment_intensity.sample(time)

# Default gradient and curve creators
func create_default_sun_gradient() -> Gradient:
	var grad = Gradient.new()
	grad.set_color(0, Color(0.1, 0.1, 0.2))  # Midnight - dark blue
	grad.set_color(1, Color(0.1, 0.1, 0.2))  # Midnight - dark blue
	grad.add_point(0.23, Color(1.0, 0.4, 0.2))  # Sunrise - orange
	grad.add_point(0.3, Color(1.0, 0.95, 0.9))  # Morning - warm white
	grad.add_point(0.5, Color(1.0, 1.0, 1.0))  # Noon - pure white
	grad.add_point(0.7, Color(1.0, 0.95, 0.9))  # Evening - warm white
	grad.add_point(0.77, Color(1.0, 0.3, 0.1))  # Sunset - deep orange
	return grad

func create_default_moon_gradient() -> Gradient:
	var grad = Gradient.new()
	grad.set_color(0, Color(0.6, 0.7, 1.0))  # Midnight - pale blue
	grad.set_color(1, Color(0.6, 0.7, 1.0))  # Midnight - pale blue
	return grad

func create_default_sky_gradient() -> Gradient:
	var grad = Gradient.new()
	grad.set_color(0, Color(0.05, 0.05, 0.1))  # Midnight - very dark
	grad.set_color(1, Color(0.05, 0.05, 0.1))  # Midnight - very dark
	grad.add_point(0.25, Color(0.3, 0.2, 0.4))  # Sunrise - purple
	grad.add_point(0.5, Color(0.5, 0.6, 0.8))  # Noon - bright sky
	grad.add_point(0.75, Color(0.3, 0.2, 0.4))  # Sunset - purple
	return grad

func create_default_sun_curve() -> Curve:
	var curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.0))  # Midnight - off
	curve.add_point(Vector2(0.2, 0.0))  # Pre-sunrise - off
	curve.add_point(Vector2(0.25, 0.3))  # Sunrise - dim
	curve.add_point(Vector2(0.5, 1.0))  # Noon - full brightness
	curve.add_point(Vector2(0.75, 0.3))  # Sunset - dim
	curve.add_point(Vector2(0.8, 0.0))  # Post-sunset - off
	curve.add_point(Vector2(1.0, 0.0))  # Midnight - off
	return curve

func create_default_moon_curve() -> Curve:
	var curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.3)) 
	curve.add_point(Vector2(0.2, 0.3)) 
	curve.add_point(Vector2(0.25, 0.1)) 
	curve.add_point(Vector2(0.3, 0.0))  
	curve.add_point(Vector2(0.7, 0.0)) 
	curve.add_point(Vector2(0.75, 0.1)) 
	curve.add_point(Vector2(0.8, 0.3))  
	curve.add_point(Vector2(1.0, 0.3))  
	return curve

func create_default_env_curve() -> Curve:
	var curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.1))
	curve.add_point(Vector2(0.25, 0.3)) 
	curve.add_point(Vector2(0.5, 0.8))  
	curve.add_point(Vector2(0.75, 0.3)) 
	curve.add_point(Vector2(1.0, 0.1)) 
	return curve
