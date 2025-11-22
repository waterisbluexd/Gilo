# TimeManager.gd
# Autoload this script as "TimeManager"
extends Node

# Signals
signal time_changed(current_hour)
signal hour_passed(hour)
signal day_changed(day_count)

# Time variables
var current_time: float = 0.0  # 0-1 range (0 = midnight, 0.5 = noon)
var current_hour: float = 0.0  # 0-24 range
var current_minute: float = 0.0  # 0-60 range
var day_count: int = 0
var is_paused: bool = false

# Previous hour tracking for hour_passed signal
var previous_hour: int = 0

# Update time from the day/night cycle
func update_time(time: float):
	var old_time = current_time
	current_time = time
	current_hour = time * 24.0
	current_minute = (current_hour - floor(current_hour)) * 60.0
	
	# Emit time changed signal
	emit_signal("time_changed", current_hour)
	
	# Check if hour has passed
	var current_hour_int = int(floor(current_hour))
	if current_hour_int != previous_hour:
		emit_signal("hour_passed", current_hour_int)
		previous_hour = current_hour_int
	
	# Check if day wrapped around
	if old_time > time:
		day_count += 1
		emit_signal("day_changed", day_count)

# Get current hour (0-24)
func get_hour() -> float:
	return current_hour

# Get current hour as integer (0-23)
func get_hour_int() -> int:
	return int(floor(current_hour))

# Get current minute (0-60)
func get_minute() -> int:
	return int(floor(current_minute))

# Get time in 0-1 range
func get_time() -> float:
	return current_time

# Get formatted time string (e.g., "14:30" or "2:30 PM")
func get_time_string(use_24_hour: bool = true) -> String:
	var hour = get_hour_int()
	var minute = get_minute()
	
	if use_24_hour:
		return "%02d:%02d" % [hour, minute]
	else:
		var period = "AM" if hour < 12 else "PM"
		var display_hour = hour % 12
		if display_hour == 0:
			display_hour = 12
		return "%d:%02d %s" % [display_hour, minute, period]

# Check if current time is after a specific hour
func is_after_hour(hour: float) -> bool:
	return current_hour >= hour

# Check if current time is before a specific hour
func is_before_hour(hour: float) -> bool:
	return current_hour < hour

# Check if current time is between two hours
func is_between_hours(start_hour: float, end_hour: float) -> bool:
	if start_hour < end_hour:
		# Normal range (e.g., 6:00 to 18:00)
		return current_hour >= start_hour and current_hour < end_hour
	else:
		# Overnight range (e.g., 22:00 to 6:00)
		return current_hour >= start_hour or current_hour < end_hour

# Check if it's day time (default: 6 AM to 6 PM)
func is_daytime(dawn: float = 6.0, dusk: float = 18.0) -> bool:
	return is_between_hours(dawn, dusk)

# Check if it's night time
func is_nighttime(dawn: float = 6.0, dusk: float = 18.0) -> bool:
	return not is_daytime(dawn, dusk)

# Get day count
func get_day_count() -> int:
	return day_count

# Get time period as string
func get_period() -> String:
	var hour = get_hour_int()
	if hour >= 5 and hour < 12:
		return "Morning"
	elif hour >= 12 and hour < 17:
		return "Afternoon"
	elif hour >= 17 and hour < 21:
		return "Evening"
	else:
		return "Night"
