extends Camera3D

# --- User-tweakable ---
@export var snap : bool = true
@export var min_size: float = 40.97
@export var max_size: float = 100.0
@export var zoom_speed: float = 0.4
# How big a world tile is (your pixel_size)
@export var tile_world_size: float = 1.0
# Desired pixel-art density you'd like to target (px per tile)
@export var target_pixels_per_tile: int = 4
# Debugging
@export var show_debug_print: bool = true

# internal
var zoom_level: float

func _ready():
	zoom_level = size

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F:
			fit_to_target_pixels()
		return
	
	if event is InputEventMouseButton:
		var zoom_changed = false
		
		# Mouse wheel events don't have a 'pressed' state, so remove the check.
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if snap:
				zoom_to_next_pixel_level(true)  # zoom in
			else:
				zoom_level -= zoom_speed
				size = zoom_level
			zoom_changed = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if snap:
				zoom_to_next_pixel_level(false)  # zoom out
			else:
				zoom_level += zoom_speed
				size = zoom_level
			zoom_changed = true
		
		if zoom_changed and not snap:
			# Clamp zoom level within defined limits (only for non-snap mode)
			zoom_level = clamp(zoom_level, min_size, max_size)
			size = zoom_level

# --- Core helpers ---
# Compute how many screen pixels correspond to ONE world tile given the camera & viewport
func pixels_per_tile() -> float:
	var vp := get_viewport()
	if not vp:
		return 0.0
	# Use the viewport's internal resolution (height)
	var vp_size: Vector2i = vp.size
	# Cast to float to avoid integer division issues
	var vp_h: float = float(vp_size.y)
	var visible_world_height: float = size * 2.0
	if visible_world_height == 0.0:
		return 0.0
	var px_per_world: float = vp_h / visible_world_height
	return px_per_world * tile_world_size

# Calculate camera.size required to make pixels_per_tile == desired_px
func camera_size_for_target(desired_px: float) -> float:
	var vp := get_viewport()
	if not vp:
		return size
	var vp_size: Vector2i = vp.size
	var vp_h: float = float(vp_size.y)
	# camera.size = (vp_h * tile_world_size) / (2 * desired_px)
	return (vp_h * tile_world_size) / (2.0 * desired_px)

# ---- Step to next/previous pixel-perfect zoom level ----
func zoom_to_next_pixel_level(zoom_in: bool):
	var current_px: float = pixels_per_tile()
	var current_px_int: int = int(round(current_px))
	var target_px: int
	
	if zoom_in:
		# Zoom in = more pixels per tile (smaller camera size)
		target_px = current_px_int + 1
	else:
		# Zoom out = fewer pixels per tile (larger camera size)
		target_px = max(1, current_px_int - 1)  # Don't go below 1 pixel per tile
	
	var new_size = camera_size_for_target(float(target_px))
	
	# Enforce bounds on the new size
	new_size = clamp(new_size, min_size, max_size)
	
	# Only update if we're actually changing something
	if abs(new_size - size) > 0.001:
		size = new_size
		zoom_level = new_size
		
		if show_debug_print:
			print("Stepped to: ", target_px, " pixels per tile, camera size: ", new_size)

# ---- Snap to the nearest integer pixels-per-tile ----
func snap_to_pixel_size():
	var current_px: float = pixels_per_tile()
	var best_px: int = int(round(current_px))
	
	# Ensure the pixel count is at least 1
	if best_px < 1:
		best_px = 1
		
	var new_size = camera_size_for_target(float(best_px))
	
	# Enforce bounds on the new snapped size
	new_size = clamp(new_size, min_size, max_size)
	size = new_size
	zoom_level = new_size # Keep the zoom_level variable in sync
	
	if show_debug_print:
		print("Snapped to: ", best_px, " pixels per tile, camera size: ", new_size)

# Set camera to match target_pixels_per_tile, optionally snapping to integer px
func fit_to_target_pixels():
	var desired: float = float(target_pixels_per_tile)
	if snap:
		var current_px: float = pixels_per_tile()
		# choose the nearest reasonable integer pixel-per-tile to current
		var best_px: int = int(round(current_px))
		if best_px < 1:
			best_px = max(1, int(desired))
		desired = float(best_px)
	var new_size := camera_size_for_target(desired)
	# enforce bounds
	new_size = clamp(new_size, min_size, max_size)
	size = new_size
	zoom_level = size
	
	if show_debug_print:
		print("Fit to target: ", desired, " pixels per tile, camera size: ", new_size)
