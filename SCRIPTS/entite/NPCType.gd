extends Resource
class_name NPCType

# --- BASIC INFO ---
@export_group("Basic Info")
@export var npc_name: String = "Peasant"
@export var description: String = "Basic worker unit that can be assigned jobs"
@export var visual_scene: PackedScene  # The actual NPC mesh/model
@export var icon: Texture2D  # For UI

# --- SPAWNING RULES ---
@export_group("Spawning")
@export var spawn_cost: int = 0  # Cost to spawn (food, gold, etc.)
@export var spawn_time: float = 5.0  # How long to spawn

# --- BASIC STATS ---
@export_group("Stats")
@export var health: float = 50.0
@export var move_speed: float = 2.0
@export var work_efficiency: float = 1.0  # Base productivity

# --- DAILY SCHEDULE ---
@export_group("Schedule")
@export var work_start_hour: int = 6  # 6 AM
@export var work_end_hour: int = 18   # 6 PM
@export var sleeps_at_night: bool = true

# --- HOUSING ---
@export_group("Housing")
@export var needs_housing: bool = true
@export var housing_priority: int = 1  # 1=low priority

# --- AI BEHAVIOR ---
@export_group("AI Settings")
@export var wander_when_idle: bool = true
@export var flee_from_combat: bool = true
@export var follow_roads: bool = true

# --- HELPER FUNCTIONS ---
func get_work_schedule() -> Dictionary:
	return {
		"work_hours": range(work_start_hour, work_end_hour),
		"sleep_hours": range(20, 24) + range(0, 6) if sleeps_at_night else [],
		"free_hours": range(work_end_hour, 20) if sleeps_at_night else []
	}

func is_peasant() -> bool:
	return true  # This resource is only for peasants

# --- STATIC FACTORY ---
static func create_basic_peasant() -> NPCType:
	var peasant = NPCType.new()
	peasant.npc_name = "Peasant"
	peasant.description = "Basic worker that can be assigned to various jobs"
	peasant.spawn_cost = 0
	peasant.spawn_time = 5.0
	peasant.health = 50.0
	peasant.move_speed = 2.0
	peasant.work_efficiency = 1.0
	peasant.needs_housing = true
	peasant.housing_priority = 1
	peasant.wander_when_idle = true
	peasant.flee_from_combat = true
	peasant.follow_roads = true
	return peasant

@export_group("Job System")
@export var can_work_jobs: Array[String] = ["laborer"]  # Jobs this NPC can do
@export var preferred_jobs: Array[String] = []  # Jobs they prefer (higher satisfaction)
@export var job_efficiency: Dictionary = {}  # {"farming": 1.2, "mining": 0.8}

# --- RESOURCE NEEDS ---
@export_group("Needs")
@export var daily_food_need: int = 2
@export var daily_rest_need: float = 8.0  # Hours of sleep needed

# Helper functions
func can_do_job(job_type: String) -> bool:
	return can_work_jobs.has(job_type)

func get_job_efficiency(job_type: String) -> float:
	return job_efficiency.get(job_type, work_efficiency)

func prefers_job(job_type: String) -> bool:
	return preferred_jobs.has(job_type)
