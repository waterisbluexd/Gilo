@tool
extends Node3D
class_name Castle

# --- CASTLE SETTINGS ---
@export_group("Castle Settings")
@export var max_population: int = 10
@export var spawn_interval: float = 5.0
@export var peasant_scene: PackedScene

# --- REFERENCES ---
@onready var entrance_marker: Marker3D = $CastleMesh/EntranceMarker
@onready var idle_zone: IdleZone = $CastleMesh/IdleZone
@onready var castle_mesh: MeshInstance3D = $CastleMesh
@onready var collision_shape_3d: CollisionShape3D = $CastleMesh/StaticBody3D/CollisionShape3D
@onready var collision_shape_3d_2: CollisionShape3D = $CastleMesh/StaticBody3D/CollisionShape3D2
#group name is "Avoid_Building"

# --- INTERNAL DATA ---
var peasants: Array[Peasant] = []
var current_population: int = 0
var spawn_timer: float = 0.0
var terrain_system: ChunkPixelTerrain

# --- INITIALIZATION ---
func _ready():
	if not peasant_scene:
		peasant_scene = preload("res://SCENES/Assets/human_type_ceviliean.tscn")
	
	# Add castle collision shapes to avoidance group
	if collision_shape_3d:
		collision_shape_3d.add_to_group("Avoid_Building")
	if collision_shape_3d_2:
		collision_shape_3d_2.add_to_group("Avoid_Building")
	
	# Find terrain system
	terrain_system = get_parent().get_node("ChunkPixelTerrain")
	if not terrain_system:
		push_warning("Castle: No ChunkPixelTerrain found in parent!")
	
	# Auto-spawn some peasants for testing
	if not Engine.is_editor_hint():
		spawn_initial_peasants()

func _process(delta):
	if Engine.is_editor_hint():
		return
	
	# Auto-spawn peasants over time
	spawn_timer += delta
	if spawn_timer >= spawn_interval and current_population < max_population:
		spawn_peasant()
		spawn_timer = 0.0

# --- PEASANT SPAWNING ---
func spawn_peasant():
	if current_population >= max_population or not peasant_scene:
		return
	
	var peasant = peasant_scene.instantiate()
	if not peasant:
		push_error("Failed to instantiate peasant scene")
		return
	
	# Add to scene tree FIRST before accessing global_position
	get_tree().current_scene.add_child(peasant)
	
	# Then find valid spawn position and set it
	var spawn_pos = find_valid_spawn_position()
	
	peasant.global_position = spawn_pos
	peasant.target_castle = self
	peasant.terrain_system = terrain_system
	
	peasants.append(peasant)
	current_population += 1
	
	print("Castle: Spawned peasant #", current_population)

func find_valid_spawn_position() -> Vector3:
	var base_pos = entrance_marker.global_position
	
	# Try multiple positions around the entrance
	for attempt in range(10):
		var spawn_pos: Vector3
		
		if attempt == 0:
			# First try: exact entrance position
			spawn_pos = base_pos
		else:
			# Try positions in a circle around entrance
			var angle = (attempt / 9.0) * TAU
			var distance = 2.0 + (attempt * 0.5)  # Gradually increase distance
			spawn_pos = base_pos + Vector3(cos(angle) * distance, 0, sin(angle) * distance)
		
		# Snap to terrain height
		spawn_pos.y = get_terrain_height_at_position(spawn_pos)
		
		# Check if position is valid (not colliding with buildings)
		if is_position_valid_for_spawn(spawn_pos):
			return spawn_pos
	
	# Fallback: return entrance position even if not ideal
	var fallback_pos = base_pos
	fallback_pos.y = get_terrain_height_at_position(fallback_pos)
	return fallback_pos

func is_position_valid_for_spawn(pos: Vector3) -> bool:
	# Check distance from all building collision shapes
	var building_obstacles = get_tree().get_nodes_in_group("Avoid_Building")
	
	for obstacle in building_obstacles:
		if obstacle is CollisionShape3D:
			var collision_shape = obstacle as CollisionShape3D
			
			# Calculate distance to the collision shape
			var shape_pos = collision_shape.global_position
			var distance = pos.distance_to(shape_pos)
			
			# Get approximate size of the collision shape
			var min_distance = get_collision_shape_radius(collision_shape) + 1.5  # +1.5 for peasant size
			
			if distance < min_distance:
				return false  # Too close to building
	
	# Also make sure not spawning inside idle zone (peasants should walk into it)
	if idle_zone and idle_zone.is_position_inside(pos):
		return false  # Don't spawn inside idle zone
	
	return true  # Position is valid

func get_collision_shape_radius(collision_shape: CollisionShape3D) -> float:
	var shape = collision_shape.shape
	
	if shape is BoxShape3D:
		var box = shape as BoxShape3D
		# Use largest dimension as radius
		return max(box.size.x, max(box.size.y, box.size.z)) * 0.5
	
	elif shape is CylinderShape3D:
		var cylinder = shape as CylinderShape3D
		return max(cylinder.top_radius, cylinder.bottom_radius)
	
	elif shape is SphereShape3D:
		var sphere = shape as SphereShape3D
		return sphere.radius
	
	else:
		# Default fallback radius
		return 2.0

func spawn_initial_peasants():
	# Spawn a few peasants at start for testing
	var initial_count = min(3, max_population)
	for i in range(initial_count):
		await get_tree().create_timer(0.5).timeout  # Small delay between spawns
		spawn_peasant()

# --- PEASANT MANAGEMENT ---
func remove_peasant(peasant: Peasant):
	if peasant in peasants:
		peasants.erase(peasant)
		current_population -= 1

func get_idle_position() -> Vector3:
	if idle_zone:
		return idle_zone.get_random_idle_position()
	else:
		# Fallback: spawn in front of castle
		var pos = entrance_marker.global_position + Vector3(0, 0, 5)
		pos.y = get_terrain_height_at_position(pos)
		return pos

# --- TERRAIN INTEGRATION ---
func get_terrain_height_at_position(world_pos: Vector3) -> float:
	if terrain_system:
		return terrain_system.get_height_at_position(world_pos)
	return 0.0
# --- PUBLIC API ---
func get_peasant_count() -> int:
	return current_population

func get_idle_peasants() -> Array[Peasant]:
	return idle_zone.get_idle_peasants() if idle_zone else []

func can_spawn_peasant() -> bool:
	return current_population < max_population
