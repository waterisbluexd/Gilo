extends Resource
class_name BuildingData

# --- BASIC INFO ---
@export_group("Basic Info")
@export var name: String = "Building"
@export var size: Vector2 = Vector2(4, 4)
@export var color: Color = Color.WHITE
@export var prefab: PackedScene
@export var cost: int = 100
@export var build_time: float = 10.0
@export var ignore_collision_with_names: Array[String] = []

# --- BUILDING TYPE ---
@export_group("Building Type")
@export var building_type: BuildingType = BuildingType.HOUSE
enum BuildingType {
	HOUSE,
	FARM,
	CASTLE,
	QUARRY,
	BARRACKS,
	WALL,
	TOWER
}

# --- CASTLE ONLY PROPERTIES ---
@export_group("Castle Settings")
@export var owner: String = "Player"
@export var max_peasants: int = 20
@export var peasant_types: Array[NPCType] = [] 

# --- VALIDATION ---
func is_castle() -> bool:
	return building_type == BuildingType.CASTLE

func can_hold_more_peasants(current_peasant_count: int) -> bool:
	if not is_castle():
		return false
	return current_peasant_count < max_peasants

func can_spawn_peasant_type(peasant_type: NPCType) -> bool:
	if not is_castle():
		return false
	return peasant_types.has(peasant_type)

@export_group("Work Site")
@export var provides_jobs: Array[String] = []
@export var max_workers: int = 0
@export var work_positions: Array[Vector3] = []
@export var required_resources: Dictionary = {}
@export var produces_resources: Dictionary = {}

@export_group("Housing")
@export var provides_housing: bool = false
@export var max_residents: int = 0
@export var housing_comfort: int = 1

@export_group("Storage")
@export var storage_capacity: Dictionary = {}
func is_workplace() -> bool:
	return max_workers > 0

func is_housing() -> bool:
	return provides_housing and max_residents > 0

func can_employ_job_type(job_type: String) -> bool:
	return provides_jobs.has(job_type)

func is_wall() -> bool:
	return building_type == BuildingType.WALL

func can_ignore_collision_with(other_building_name: String) -> bool:
	return ignore_collision_with_names.has(other_building_name)
