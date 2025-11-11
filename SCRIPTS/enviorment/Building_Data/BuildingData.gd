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
# --- This is the new property ---
@export var ignore_collision_with: Array[BuildingData] = []

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
@export var owner: String = "Player"  # Who owns this castle
@export var max_peasants: int = 20  # Maximum peasants this castle can hold at one time
@export var peasant_types: Array[NPCType] = []  # What types of peasants this castle can spawn

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
@export var provides_jobs: Array[String] = []  # Job types this building provides
@export var max_workers: int = 0  # 0 = no jobs, >0 = workplace
@export var work_positions: Array[Vector3] = []  # Where NPCs work (relative to building)
@export var required_resources: Dictionary = {}  # What resources needed to function
@export var produces_resources: Dictionary = {}  # What this building produces

@export_group("Housing")
@export var provides_housing: bool = false
@export var max_residents: int = 0
@export var housing_comfort: int = 1  # 1-5 quality rating

@export_group("Storage")
@export var storage_capacity: Dictionary = {}  # {"wood": 100, "food": 50}

# Helper functions for your existing system
func is_workplace() -> bool:
	return max_workers > 0

func is_housing() -> bool:
	return provides_housing and max_residents > 0

func can_employ_job_type(job_type: String) -> bool:
	return provides_jobs.has(job_type)

func is_wall() -> bool:
	return building_type == BuildingType.WALL
