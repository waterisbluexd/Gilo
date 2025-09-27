@tool
extends Area3D
class_name IdleZone

# --- ZONE SETTINGS ---
@export_group("Zone Settings")
@export var zone_radius: float = 8.0 : set = set_zone_radius
@export var max_idle_peasants: int = 8
@export var show_debug_zone: bool = true : set = set_debug_visibility

# --- SIGNALS ---
signal peasant_entered_zone(peasant: Peasant)
signal peasant_left_zone(peasant: Peasant)

# --- REFERENCES ---
var castle: Castle
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

# --- INTERNAL DATA ---
var peasants_in_zone: Array[Peasant] = []
var terrain_system: ChunkPixelTerrain

# --- DEBUG VISUALIZATION ---
var debug_mesh_instance: MeshInstance3D
var debug_material: StandardMaterial3D

# --- INITIALIZATION ---
func _ready():
	_setup_collision_shape()
	_setup_debug_visualization()
	# Find terrain system
	var root = get_tree().current_scene if get_tree().current_scene else get_parent()
	terrain_system = _find_terrain_system(root)

func _find_terrain_system(node: Node) -> ChunkPixelTerrain:
	if node is ChunkPixelTerrain:
		return node
	
	for child in node.get_children():
		var result = _find_terrain_system(child)
		if result:
			return result
	
	return null

func _setup_collision_shape():
	# Don't override existing collision shape - use what's already set up
	if not collision_shape:
		collision_shape = get_node_or_null("CollisionShape3D")
		if not collision_shape:
			push_warning("IdleZone: No CollisionShape3D found. Please add one to the scene.")
			return
	
	# Get the radius from existing shape if it's a cylinder
	if collision_shape.shape is CylinderShape3D:
		var shape = collision_shape.shape as CylinderShape3D
		zone_radius = shape.top_radius

func _setup_debug_visualization():
	if not show_debug_zone:
		return
	
	debug_mesh_instance = MeshInstance3D.new()
	add_child(debug_mesh_instance)
	
	# Create debug material
	debug_material = StandardMaterial3D.new()
	debug_material.albedo_color = Color.YELLOW
	debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debug_material.albedo_color.a = 0.2
	debug_material.no_depth_test = true
	debug_material.unshaded = true
	
	_update_debug_mesh()

func _update_debug_mesh():
	if not debug_mesh_instance:
		return
	
	var actual_radius = get_actual_zone_radius()
	
	var mesh = CylinderMesh.new()
	mesh.top_radius = actual_radius
	mesh.bottom_radius = actual_radius
	mesh.height = 0.2  # Thin disc on ground
	
	debug_mesh_instance.mesh = mesh
	debug_mesh_instance.material_override = debug_material
	debug_mesh_instance.position.y = 0.1  # Slightly above ground

# --- ZONE MANAGEMENT ---
func get_random_idle_position() -> Vector3:
	# Use actual collision shape size
	var actual_radius = get_actual_zone_radius()
	
	# Generate random position within the zone
	var angle = randf() * TAU
	var distance = randf() * actual_radius * 0.7  # Keep away from edge
	
	var offset = Vector3(
		cos(angle) * distance,
		0,
		sin(angle) * distance
	)
	
	var world_pos = global_position + offset
	
	# Snap to terrain height
	if terrain_system:
		world_pos.y = terrain_system.get_height_at_position(world_pos)
	
	return world_pos

func is_position_inside(pos: Vector3) -> bool:
	var actual_radius = get_actual_zone_radius()
	var distance = global_position.distance_to(pos)
	return distance <= actual_radius

func add_peasant_to_zone(peasant: Peasant):
	if peasant not in peasants_in_zone:
		peasants_in_zone.append(peasant)
		peasant_entered_zone.emit(peasant)

func remove_peasant_from_zone(peasant: Peasant):
	if peasant in peasants_in_zone:
		peasants_in_zone.erase(peasant)
		peasant_left_zone.emit(peasant)

func get_idle_peasants() -> Array[Peasant]:
	return peasants_in_zone.duplicate()

func get_peasant_count() -> int:
	return peasants_in_zone.size()

func is_zone_full() -> bool:
	return peasants_in_zone.size() >= max_idle_peasants

# --- SETTERS ---
func set_zone_radius(value: float):
	zone_radius = max(1.0, value)
	
	# Update existing collision shape
	if collision_shape and collision_shape.shape is CylinderShape3D:
		var shape = collision_shape.shape as CylinderShape3D
		shape.top_radius = zone_radius
		shape.bottom_radius = zone_radius
	
	_update_debug_mesh()

func get_actual_zone_radius() -> float:
	# Get radius from the actual collision shape
	if collision_shape and collision_shape.shape is CylinderShape3D:
		var shape = collision_shape.shape as CylinderShape3D
		return shape.top_radius
	return zone_radius

func set_debug_visibility(value: bool):
	show_debug_zone = value
	
	if debug_mesh_instance:
		debug_mesh_instance.visible = show_debug_zone
	elif show_debug_zone:
		_setup_debug_visualization()

# --- PUBLIC API ---
func find_nearest_free_position(preferred_pos: Vector3) -> Vector3:
	# Try the preferred position first
	if is_position_inside(preferred_pos):
		var too_close = false
		for peasant in peasants_in_zone:
			if peasant.global_position.distance_to(preferred_pos) < 2.0:
				too_close = true
				break
		
		if not too_close:
			return preferred_pos
	
	# Find alternative position
	for attempt in range(10):
		var pos = get_random_idle_position()
		var valid = true
		
		for peasant in peasants_in_zone:
			if peasant.global_position.distance_to(pos) < 2.0:
				valid = false
				break
		
		if valid:
			return pos
	
	# Fallback: just return any position
	return get_random_idle_position()

# --- DEBUG ---
func _get_configuration_warnings():
	var warnings = []
	
	if zone_radius <= 0:
		warnings.append("Zone radius must be greater than 0")
	
	return warnings
