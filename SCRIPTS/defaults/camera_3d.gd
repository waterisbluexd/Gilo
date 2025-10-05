# --- COMPLETE AND UPDATED SCRIPT ---
extends Camera3D

# --- User-tweakable ---
@export var snap : bool = true
@export var min_size: float = 80.0
@export var max_size: float = 200# Example of a larger value
@export var zoom_speed: float = 5.0
@export var tile_world_size: float = 1.0
@export var target_pixels_per_tile: int = 1
# Debugging
@export var show_debug_print: bool = true

# --- Raycasting settings ---
@export var raycast_length: float = 1000.0
@export var show_raycast_debug: bool = true
@export var show_visual_debug: bool = true
@export var ray_color: Color = Color.RED
@export var hit_point_color: Color = Color.GREEN
@export var hit_point_size: float = 0.5

# --- Mouse cursor world position settings ---
@export var show_cursor_indicator: bool = true
@export var cursor_indicator_color: Color = Color.CYAN
@export var cursor_indicator_size: float = 0.3
@export var cursor_ground_plane_y: float = 0.0
@export var continuous_raycast_update: bool = true

# internal
var zoom_level: float
var world_3d: World3D
var space_state: PhysicsDirectSpaceState3D

# Current mouse world position
var current_mouse_world_pos: Vector3
var current_hit_object: Node3D
var current_hit_normal: Vector3

# Visual debug components
var debug_ray_mesh: MeshInstance3D
var debug_hit_point_mesh: MeshInstance3D
var cursor_indicator_mesh: MeshInstance3D
var debug_ray_immediate_mesh: ImmediateMesh # For performant ray drawing
var ray_material: StandardMaterial3D
var hit_material: StandardMaterial3D
var cursor_material: StandardMaterial3D

# For getting the SubViewport properly
var sub_viewport: SubViewport
var sub_viewport_container: SubViewportContainer

# --- SIGNALS ---
signal mouse_world_position_changed(world_pos: Vector3, hit_normal: Vector3, hit_object: Node3D)
signal mouse_world_position_clicked(world_pos: Vector3, hit_object: Node3D)


func _ready():
	DebugManager.register_camera(self)
	
	# --- FIX: Initialize and clamp zoom level correctly on startup ---
	zoom_level = clamp(size, min_size, max_size)
	size = zoom_level
	# --- END FIX ---
	world_3d = get_world_3d()
	find_viewport_components()
	setup_visual_debug()
	
	# Debug viewport setup
	if show_debug_print:
		await get_tree().process_frame
		print_viewport_debug_info()

func find_viewport_components():
	var current_node = get_parent()
	while current_node:
		if current_node is SubViewport:
			sub_viewport = current_node
		elif current_node is SubViewportContainer:
			sub_viewport_container = current_node
		current_node = current_node.get_parent()
	
	if show_debug_print:
		ConsoleCapture.console_log("SubViewport found: " + str(sub_viewport != null))
		ConsoleCapture.console_log("SubViewportContainer found: " + str(sub_viewport_container != null))

func print_viewport_debug_info():
	if not show_debug_print:
		return
		
	ConsoleCapture.console_log("=== VIEWPORT DEBUG INFO ===")
	if sub_viewport:
		ConsoleCapture.console_log("SubViewport size: " + str(sub_viewport.size))
	if sub_viewport_container:
		ConsoleCapture.console_log("Container size: " + str(sub_viewport_container.size))
		ConsoleCapture.console_log("Container global rect: " + str(sub_viewport_container.get_global_rect()))
		ConsoleCapture.console_log("Container stretch: " + str(sub_viewport_container.stretch))
		ConsoleCapture.console_log("Container stretch_shrink: " + str(sub_viewport_container.stretch_shrink))
		
		var vp_aspect = float(sub_viewport.size.x) / float(sub_viewport.size.y)
		var cont_aspect = float(sub_viewport_container.size.x) / float(sub_viewport_container.size.y)
		ConsoleCapture.console_log("SubViewport aspect: %.3f" % vp_aspect)
		ConsoleCapture.console_log("Container aspect: %.3f" % cont_aspect)
		
	ConsoleCapture.console_log("Window size: " + str(get_window().size))
	ConsoleCapture.console_log("Root viewport size: " + str(get_tree().root.size))
	ConsoleCapture.console_log("===========================")

func setup_visual_debug():
	ray_material = StandardMaterial3D.new()
	ray_material.flags_unshaded = true
	ray_material.vertex_color_use_as_albedo = true
	ray_material.flags_transparent = true
	ray_material.albedo_color = ray_color
	ray_material.albedo_color.a = 0.8
	
	hit_material = StandardMaterial3D.new()
	hit_material.flags_unshaded = true
	hit_material.albedo_color = hit_point_color
	hit_material.emission_enabled = true
	hit_material.emission = hit_point_color * 0.5
	
	cursor_material = StandardMaterial3D.new()
	cursor_material.flags_unshaded = true
	cursor_material.albedo_color = cursor_indicator_color
	cursor_material.emission_enabled = true
	cursor_material.emission = cursor_indicator_color * 0.7
	cursor_material.flags_transparent = true
	cursor_material.albedo_color.a = 0.8
	
	if show_visual_debug:
		debug_ray_mesh = MeshInstance3D.new()
		debug_ray_mesh.material_override = ray_material
		
		# --- PERFORMANCE: Create a reusable ImmediateMesh for the ray ---
		debug_ray_immediate_mesh = ImmediateMesh.new()
		debug_ray_mesh.mesh = debug_ray_immediate_mesh
		add_child(debug_ray_mesh)
		
		debug_hit_point_mesh = MeshInstance3D.new()
		debug_hit_point_mesh.material_override = hit_material
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = hit_point_size
		sphere_mesh.radial_segments = 8
		sphere_mesh.rings = 6
		debug_hit_point_mesh.mesh = sphere_mesh
		add_child(debug_hit_point_mesh)
		
		debug_ray_mesh.visible = false
		debug_hit_point_mesh.visible = false
	
	if show_cursor_indicator:
		cursor_indicator_mesh = MeshInstance3D.new()
		cursor_indicator_mesh.material_override = cursor_material
		var cursor_sphere = SphereMesh.new()
		cursor_sphere.radius = cursor_indicator_size
		cursor_sphere.radial_segments = 12
		cursor_sphere.rings = 8
		cursor_indicator_mesh.mesh = cursor_sphere
		add_child(cursor_indicator_mesh)
		cursor_indicator_mesh.visible = false

func _physics_process(_delta):
	if continuous_raycast_update:
		var screen_mouse_pos = get_tree().root.get_mouse_position()
		var viewport_direct = get_viewport().get_mouse_position()
		
		if show_debug_print:
			var debug_counter = Engine.get_frames_drawn()
			#if debug_counter % 120 == 0: # Every 2 seconds
				#ConsoleCapture.console_log("🖱️ MOUSE SOURCE:")
				#ConsoleCapture.console_log("  Root mouse: %s" % screen_mouse_pos)
				#ConsoleCapture.console_log("  Viewport mouse: %s" % viewport_direct)
				#ConsoleCapture.console_log("  Window mode: %s" % DisplayServer.window_get_mode())
		
		update_mouse_world_position(screen_mouse_pos)

func _input(event):
	if event is InputEventMouseButton:
		var zoom_changed = false

		if event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
			if current_mouse_world_pos:
				emit_signal("mouse_world_position_clicked", current_mouse_world_pos, current_hit_object)

		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.is_pressed():
			zoom_level -= zoom_speed
			zoom_changed = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.is_pressed():
			zoom_level += zoom_speed
			zoom_changed = true

		if zoom_changed:
			zoom_level = clamp(zoom_level, min_size, max_size)
			size = zoom_level
			# --- ADDED: Print statement for current zoom level ---
			print("Camera Zoom Level: ", size)

func update_mouse_world_position(screen_mouse_pos: Vector2):
	if not world_3d:
		return
		
	space_state = world_3d.direct_space_state
	if not space_state:
		return
	
	var viewport_mouse_pos = get_viewport_mouse_position(screen_mouse_pos)
	
	if viewport_mouse_pos == Vector2(-1, -1):
		if show_visual_debug:
			if debug_ray_mesh: debug_ray_mesh.visible = false
			if debug_hit_point_mesh: debug_hit_point_mesh.visible = false
		if show_cursor_indicator and cursor_indicator_mesh:
			cursor_indicator_mesh.visible = false
		return
	
	var ray_origin = project_ray_origin(viewport_mouse_pos)
	var ray_direction = project_ray_normal(viewport_mouse_pos)
	var ray_end = ray_origin + ray_direction * raycast_length
	
	if show_debug_print:
		var debug_counter = Engine.get_frames_drawn()
		#if debug_counter % 60 == 0:
			#ConsoleCapture.console_log("🎯 RAYCAST:")
			#ConsoleCapture.console_log("  Viewport Mouse: %s" % viewport_mouse_pos)
			#ConsoleCapture.console_log("  Ray Origin: %s" % ray_origin)
			#ConsoleCapture.console_log("  Ray Direction: %s" % ray_direction)
	
	if show_visual_debug:
		update_visual_ray(ray_origin, ray_end)
	
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	var result = space_state.intersect_ray(query)
	
	var world_position: Vector3
	var hit_normal: Vector3 = Vector3.UP
	var hit_object: Node3D = null
	
	if result:
		world_position = result.position
		hit_normal = result.normal
		hit_object = result.collider as Node3D
		
		if show_visual_debug:
			update_visual_hit_point(world_position, true)
	else:
		world_position = raycast_to_ground_plane(ray_origin, ray_direction, cursor_ground_plane_y)
		if world_position == Vector3.ZERO:
			if show_visual_debug and debug_hit_point_mesh:
				debug_hit_point_mesh.visible = false
			if show_cursor_indicator and cursor_indicator_mesh:
				cursor_indicator_mesh.visible = false
			return
		
		hit_normal = Vector3.UP
		if show_visual_debug:
			update_visual_hit_point(world_position, false)

	if show_cursor_indicator and cursor_indicator_mesh:
		cursor_indicator_mesh.global_position = world_position
		cursor_indicator_mesh.visible = true
		
		#if show_debug_print:
			#var debug_counter = Engine.get_frames_drawn()
			#if debug_counter % 60 == 0:
				#ConsoleCapture.console_log("🌍 FINAL RESULT:")
				#ConsoleCapture.console_log("  World Position: %s" % world_position)
	
	current_mouse_world_pos = world_position
	current_hit_object = hit_object
	current_hit_normal = hit_normal
	
	emit_signal("mouse_world_position_changed", world_position, hit_normal, hit_object)

func get_viewport_mouse_position(screen_mouse_pos: Vector2) -> Vector2:
	if not sub_viewport_container or not sub_viewport:
		return get_viewport().get_mouse_position()
	
	var viewport_mouse = sub_viewport.get_mouse_position()
	
	#if show_debug_print:
		#var debug_counter = Engine.get_frames_drawn()
		#if debug_counter % 60 == 0:
			#ConsoleCapture.console_log("📍 DIRECT METHOD:")
			#ConsoleCapture.console_log("  SubViewport.get_mouse_position(): %s" % viewport_mouse)
			#ConsoleCapture.console_log("  SubViewport size: %s" % sub_viewport.size)
			#ConsoleCapture.console_log("  Container size: %s" % sub_viewport_container.size)
	
	return viewport_mouse

func raycast_to_ground_plane(ray_origin: Vector3, ray_direction: Vector3, ground_y: float = 0.0) -> Vector3:
	if abs(ray_direction.y) < 0.001:
		return Vector3.ZERO
	var t = (ground_y - ray_origin.y) / ray_direction.y
	if t < 0:
		return Vector3.ZERO
	return ray_origin + ray_direction * t

func update_visual_ray(ray_origin: Vector3, ray_end: Vector3):
	if not show_visual_debug or not debug_ray_immediate_mesh:
		return
	# --- PERFORMANCE: Update existing mesh instead of creating a new one ---
	debug_ray_immediate_mesh.clear_surfaces()
	debug_ray_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, ray_material)
	debug_ray_immediate_mesh.surface_add_vertex(ray_origin)
	debug_ray_immediate_mesh.surface_add_vertex(ray_end)
	debug_ray_immediate_mesh.surface_end()
	debug_ray_mesh.visible = true

func update_visual_hit_point(hit_pos: Vector3, is_object_hit: bool):
	if not show_visual_debug or not debug_hit_point_mesh:
		return
	debug_hit_point_mesh.global_position = hit_pos
	debug_hit_point_mesh.visible = true
	var color = hit_point_color if is_object_hit else Color.YELLOW
	hit_material.albedo_color = color
	hit_material.emission = color * 0.5

# This function is no longer needed due to the performance improvement
# func create_line_mesh(start: Vector3, end: Vector3) -> ImmediateMesh:

# --- Public utility functions ---
func get_mouse_world_position() -> Vector3:
	return current_mouse_world_pos

func get_mouse_hit_object() -> Node3D:
	return current_hit_object

func get_mouse_hit_normal() -> Vector3:
	return current_hit_normal

func get_mouse_tile_position() -> Vector2i:
	return world_to_tile(current_mouse_world_pos)

func world_to_tile(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / tile_world_size)),
		int(floor(world_pos.z / tile_world_size))
	)

func tile_to_world(tile_pos: Vector2i) -> Vector3:
	return Vector3(
		tile_pos.x * tile_world_size + tile_world_size * 0.5,
		0.0,
		tile_pos.y * tile_world_size + tile_world_size * 0.5
	)

func pixels_per_tile() -> float:
	var vp_h = float(get_viewport().size.y)
	var visible_world_height = size * 2.0
	if visible_world_height == 0.0:
		return 0.0
	return (vp_h / visible_world_height) * tile_world_size

func camera_size_for_target(desired_px: float) -> float:
	var vp_h = float(get_viewport().size.y)
	return (vp_h * tile_world_size) / (2.0 * desired_px)

func zoom_to_next_pixel_level(zoom_in: bool):
	var current_px_int = int(round(pixels_per_tile()))
	var target_px = current_px_int + 1 if zoom_in else max(1, current_px_int - 1)
	size = clamp(camera_size_for_target(float(target_px)), min_size, max_size)
	zoom_level = size

func snap_to_pixel_size():
	var best_px = max(1, int(round(pixels_per_tile())))
	size = clamp(camera_size_for_target(float(best_px)), min_size, max_size)
	zoom_level = size

func fit_to_target_pixels():
	var desired = float(target_pixels_per_tile)
	if snap:
		desired = float(max(1, int(round(pixels_per_tile()))))
	size = clamp(camera_size_for_target(desired), min_size, max_size)
	zoom_level = size

# ========================================
# DEBUG INTERFACE
# ========================================

func toggle_visual_debug():
	show_visual_debug = !show_visual_debug
	if debug_ray_mesh: debug_ray_mesh.visible = false
	if debug_hit_point_mesh: debug_hit_point_mesh.visible = false

func toggle_cursor_indicator():
	show_cursor_indicator = !show_cursor_indicator
	if cursor_indicator_mesh:
		cursor_indicator_mesh.visible = show_cursor_indicator

func toggle_snap():
	snap = !snap
	if snap: snap_to_pixel_size()

func toggle_continuous_raycast():
	continuous_raycast_update = !continuous_raycast_update

func set_zoom_level_debug(value: float):
	zoom_level = clamp(value, min_size, max_size)
	size = zoom_level

func set_zoom_speed_debug(value: float):
	zoom_speed = value

func set_raycast_length_debug(value: float):
	raycast_length = value

func set_hit_point_size_debug(value: float):
	hit_point_size = value
	if debug_hit_point_mesh and debug_hit_point_mesh.mesh:
		var sphere = debug_hit_point_mesh.mesh as SphereMesh
		sphere.radius = value

func set_cursor_size_debug(value: float):
	cursor_indicator_size = value
	if cursor_indicator_mesh and cursor_indicator_mesh.mesh:
		var sphere = cursor_indicator_mesh.mesh as SphereMesh
		sphere.radius = value

func teleport_to(pos: Vector3):
	global_position = pos

func reset_camera_position():
	global_position = Vector3.ZERO
	global_rotation = Vector3.ZERO

func get_debug_info() -> Dictionary:
	return {
		"position": global_position,
		"rotation": global_rotation,
		"zoom_level": zoom_level,
		"size": size,
		"pixels_per_tile": pixels_per_tile(),
		"mouse_world_pos": current_mouse_world_pos,
		"mouse_hit_object": current_hit_object.name if current_hit_object else "None",
		"mouse_tile_pos": get_mouse_tile_position(),
		"fov": fov,
		"snap_enabled": snap,
		"visual_debug": show_visual_debug,
		"cursor_indicator": show_cursor_indicator,
		"continuous_raycast": continuous_raycast_update
	}
