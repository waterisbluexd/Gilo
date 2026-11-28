use std::{
    collections::{HashMap, HashSet, VecDeque, hash_map::DefaultHasher},
    hash::{Hash, Hasher},
    sync::Arc,
};

use godot::{
    classes::{Camera3D, Engine, Material, Mesh, MeshInstance3D, Node3D, Viewport},
    prelude::*,
};

use super::{
    generator::{self, TerrainSettings},
    mesh::{self, MeshData},
    workers::{ChunkCoord, GenerationJob, WorkerPool},
};

const CHUNK_SIZE: f32 = generator::CHUNK_SIZE as f32;
const DEFAULT_WORKERS: i64 = 2;
const DEFAULT_CACHE_CAPACITY: i64 = 64;

#[derive(Clone, Copy, Eq, Hash, PartialEq)]
struct ChunkKey {
    seed: u32,
    coord: ChunkCoordKey,
    settings: [u64; 6],
}

#[derive(Clone, Copy, Eq, Hash, PartialEq)]
struct ChunkCoordKey {
    x: i32,
    z: i32,
}

impl From<ChunkCoord> for ChunkCoordKey {
    fn from(coord: ChunkCoord) -> Self {
        Self {
            x: coord.x,
            z: coord.z,
        }
    }
}

#[derive(Clone)]
struct CachedMesh {
    mesh: Arc<MeshData>,
}

#[derive(Default)]
struct MeshCache {
    meshes: HashMap<ChunkKey, CachedMesh>,
    least_recent: VecDeque<ChunkKey>,
}

impl MeshCache {
    fn get(&mut self, key: ChunkKey) -> Option<Arc<MeshData>> {
        let mesh = self.meshes.get(&key)?.mesh.clone();
        self.least_recent.retain(|entry| *entry != key);
        self.least_recent.push_back(key);
        Some(mesh)
    }

    fn insert(&mut self, key: ChunkKey, mesh: Arc<MeshData>, capacity: usize) {
        self.meshes.insert(key, CachedMesh { mesh });
        self.least_recent.retain(|entry| *entry != key);
        self.least_recent.push_back(key);
        while self.meshes.len() > capacity {
            if let Some(oldest) = self.least_recent.pop_front() {
                self.meshes.remove(&oldest);
            } else {
                break;
            }
        }
    }
}

#[derive(GodotClass)]
#[class(base = Node3D)]
pub struct GiloChunkManager {
    base: Base<Node3D>,
    #[export]
    seed: i64,
    #[export]
    camera_path: NodePath,
    #[export]
    terrain_material: Option<Gd<Material>>,
    #[export]
    bootstrap_mesh: Option<Gd<Mesh>>,
    #[export]
    worker_count: i64,
    #[export]
    max_uploads_per_frame: i64,
    #[export]
    cache_capacity_chunks: i64,
    #[export]
    view_margin_chunks: i64,
    #[export]
    max_stream_radius_chunks: i64,
    #[export]
    biome_scale: f64,
    #[export]
    biome_blend_width: f64,
    #[export]
    biome_boundary_warp: f64,
    #[export]
    biome_coverage: f64,
    #[export]
    surface_bump_strength: f64,
    #[export]
    surface_bump_scale: f64,
    workers: Option<WorkerPool>,
    settings_signature: [u64; 6],
    generation_revision: u64,
    active_seed: u32,
    required: HashSet<ChunkKey>,
    generating: HashSet<ChunkKey>,
    pending_keys: HashSet<ChunkKey>,
    pending_uploads: VecDeque<(ChunkKey, Arc<MeshData>)>,
    loaded: HashMap<ChunkKey, Gd<MeshInstance3D>>,
    bootstrap_key: Option<ChunkKey>,
    cache: MeshCache,
    terrain_min_height: f32,
    terrain_max_height: f32,
}

impl GiloChunkManager {
    fn terrain_settings(&self) -> TerrainSettings {
        TerrainSettings {
            biome_scale: self.biome_scale.clamp(8.0, 4096.0),
            biome_blend_width: self.biome_blend_width.clamp(0.25, 64.0),
            biome_boundary_warp: self.biome_boundary_warp.clamp(0.0, 2.0),
            biome_coverage: self.biome_coverage.clamp(0.05, 0.95),
            surface_bump_strength: self.surface_bump_strength.clamp(0.0, 0.12),
            surface_bump_scale: self.surface_bump_scale.clamp(0.4, 8.0),
        }
    }

    fn current_signature(&self) -> [u64; 6] {
        let settings = self.terrain_settings();
        [
            settings.biome_scale.to_bits(),
            settings.biome_blend_width.to_bits(),
            settings.biome_boundary_warp.to_bits(),
            settings.biome_coverage.to_bits(),
            settings.surface_bump_strength.to_bits(),
            settings.surface_bump_scale.to_bits(),
        ]
    }

    fn key(&self, x: i32, z: i32) -> ChunkKey {
        ChunkKey {
            seed: self.seed as u32,
            coord: ChunkCoordKey { x, z },
            settings: self.settings_signature,
        }
    }

    fn current_revision(&self) -> u64 {
        let mut hasher = DefaultHasher::new();
        (self.seed as u32).hash(&mut hasher);
        self.settings_signature.hash(&mut hasher);
        hasher.finish()
    }

    fn camera(&self) -> Option<Gd<Camera3D>> {
        self.base()
            .get_node_or_null(&self.camera_path)?
            .try_cast::<Camera3D>()
            .ok()
    }

    fn required_chunks(&self, camera: &Gd<Camera3D>) -> HashSet<ChunkKey> {
        let bounds = camera_ground_bounds(camera, self.terrain_min_height, self.terrain_max_height);
        let to_chunk = |world: f32| ((world + CHUNK_SIZE * 0.5) / CHUNK_SIZE).floor() as i32;
        let margin = self.view_margin_chunks.clamp(0, 8) as i32;
        let max_radius = self.max_stream_radius_chunks.clamp(1, 64) as i32;
        let center_x = to_chunk(bounds.center.x);
        let center_z = to_chunk(bounds.center.y);
        let min_x = (to_chunk(bounds.min.x) - margin).max(center_x - max_radius);
        let max_x = (to_chunk(bounds.max.x) + margin).min(center_x + max_radius);
        let min_z = (to_chunk(bounds.min.y) - margin).max(center_z - max_radius);
        let max_z = (to_chunk(bounds.max.y) + margin).min(center_z + max_radius);
        let mut required = HashSet::new();
        for z in min_z..=max_z {
            for x in min_x..=max_x {
                required.insert(self.key(x, z));
            }
        }
        required
    }

    fn update_stream(&mut self, camera: &Gd<Camera3D>) {
        self.required = self.required_chunks(camera);
        let required_coords: HashSet<_> = self
            .required
            .iter()
            .map(|key| (key.coord.x, key.coord.z))
            .collect();
        if let Some(workers) = &self.workers {
            let discarded = workers.retain_queued(self.generation_revision, &required_coords);
            for job in discarded {
                self.generating.remove(&self.key(job.coord.x, job.coord.z));
            }
        }

        let obsolete: Vec<_> = self
            .loaded
            .keys()
            .filter(|key| !self.required.contains(key))
            .copied()
            .collect();
        for key in obsolete {
            if let Some(mut chunk) = self.loaded.remove(&key) {
                chunk.queue_free();
            }
        }

        self.pending_uploads
            .retain(|(key, _)| self.required.contains(key));
        self.pending_keys.retain(|key| self.required.contains(key));

        let revision = self.generation_revision;
        let mut received = Vec::new();
        if let Some(workers) = &self.workers {
            received.extend(workers.drain_results());
        }
        for result in received {
            if result.revision != revision {
                continue;
            }
            let key = ChunkKey {
                seed: result.seed,
                coord: result.coord.into(),
                settings: self.settings_signature,
            };
            self.generating.remove(&key);
            self.observe_height_bounds(result.mesh.min_height, result.mesh.max_height);
            if !self.required.contains(&key) {
                continue;
            }
            let capacity = self.cache_capacity_chunks.clamp(1, 512) as usize;
            self.cache.insert(key, result.mesh.clone(), capacity);
            self.pending_keys.insert(key);
            self.pending_uploads.push_back((key, result.mesh));
        }

        let mut needed: Vec<_> = self
            .required
            .iter()
            .copied()
            .filter(|key| {
                (!self.loaded.contains_key(key) || self.bootstrap_key == Some(*key))
                    && !self.pending_keys.contains(key)
                    && !self.generating.contains(key)
            })
            .collect();
        needed.sort_unstable_by_key(|key| {
            let (camera_x, camera_z) = center_chunk(camera);
            let dx = key.coord.x as i64 - camera_x as i64;
            let dz = key.coord.z as i64 - camera_z as i64;
            dx * dx + dz * dz
        });

        for key in needed {
            if let Some(mesh_data) = self.cache.get(key) {
                self.observe_height_bounds(mesh_data.min_height, mesh_data.max_height);
                self.pending_keys.insert(key);
                self.pending_uploads.push_back((key, mesh_data));
                continue;
            }
            let (camera_x, camera_z) = center_chunk(camera);
            let dx = key.coord.x as i64 - camera_x as i64;
            let dz = key.coord.z as i64 - camera_z as i64;
            let job = GenerationJob {
                seed: key.seed,
                coord: ChunkCoord {
                    x: key.coord.x,
                    z: key.coord.z,
                },
                settings: self.terrain_settings(),
                revision,
                priority: (dx * dx + dz * dz) as u64,
            };
            if self
                .workers
                .as_ref()
                .is_some_and(|workers| workers.try_submit(job))
            {
                self.generating.insert(key);
            } else {
                break;
            }
        }

        let upload_budget = self.max_uploads_per_frame.clamp(1, 16) as usize;
        for _ in 0..upload_budget {
            let Some((key, mesh_data)) = self.pending_uploads.pop_front() else {
                break;
            };
            self.pending_keys.remove(&key);
            if !self.required.contains(&key) {
                continue;
            }
            self.attach_chunk(key, &mesh_data);
        }
    }

    fn attach_chunk(&mut self, key: ChunkKey, mesh_data: &MeshData) {
        let mesh: Gd<Mesh> = mesh::build_mesh(mesh_data).upcast();
        self.attach_mesh(key, &mesh);
    }

    fn attach_mesh(&mut self, key: ChunkKey, mesh: &Gd<Mesh>) {
        if let Some(mut old_chunk) = self.loaded.remove(&key) {
            old_chunk.queue_free();
        }
        let mut instance = MeshInstance3D::new_alloc();
        instance.set_name(format!("Chunk_{}_{}", key.coord.x, key.coord.z).as_str());
        instance.set_mesh(mesh);
        if let Some(material) = &self.terrain_material {
            instance.set_material_override(material);
        }
        instance.set_position(Vector3::new(
            key.coord.x as f32 * CHUNK_SIZE,
            0.0,
            key.coord.z as f32 * CHUNK_SIZE,
        ));
        self.base_mut().add_child(&instance);
        self.loaded.insert(key, instance);
        if self.bootstrap_key == Some(key) {
            self.bootstrap_key = None;
        }
    }

    fn attach_bootstrap_mesh(&mut self) {
        if self.current_signature() != self.default_signature() {
            return;
        }
        let Some(mesh) = self.bootstrap_mesh.clone() else {
            return;
        };
        let bounds = mesh.get_aabb();
        self.observe_height_bounds(bounds.position.y, bounds.position.y + bounds.size.y);
        let key = self.key(0, 0);
        self.attach_mesh(key, &mesh);
        self.bootstrap_key = Some(key);
    }

    fn default_signature(&self) -> [u64; 6] {
        let defaults = TerrainSettings::default();
        [
            defaults.biome_scale.to_bits(),
            defaults.biome_blend_width.to_bits(),
            defaults.biome_boundary_warp.to_bits(),
            defaults.biome_coverage.to_bits(),
            defaults.surface_bump_strength.to_bits(),
            defaults.surface_bump_scale.to_bits(),
        ]
    }

    fn observe_height_bounds(&mut self, minimum: f32, maximum: f32) {
        self.terrain_min_height = self.terrain_min_height.min(minimum);
        self.terrain_max_height = self.terrain_max_height.max(maximum);
    }

    fn reset_height_bounds(&mut self) {
        self.terrain_min_height = 0.02;
        self.terrain_max_height = 3.0;
        if let Some(mesh) = &self.bootstrap_mesh {
            let bounds = mesh.get_aabb();
            self.observe_height_bounds(bounds.position.y, bounds.position.y + bounds.size.y);
        }
    }
}

#[derive(Clone, Copy)]
struct GroundBounds {
    center: Vector2,
    min: Vector2,
    max: Vector2,
}

fn camera_ground_bounds(camera: &Gd<Camera3D>, min_height: f32, max_height: f32) -> GroundBounds {
    let position = camera.get_global_position();
    let basis = camera.get_global_basis();
    let axes = basis.transposed();
    let right = axes.rows[0];
    let up = axes.rows[1];
    let forward = -axes.rows[2];
    let viewport = camera.get_viewport();
    let (half_width, half_height) = viewport
        .map(|viewport| viewport_dimensions(&viewport, camera.get_size()))
        .unwrap_or((camera.get_size() * 8.0 / 9.0, camera.get_size() * 0.5));
    let mut min = Vector2::new(f32::INFINITY, f32::INFINITY);
    let mut max = Vector2::new(f32::NEG_INFINITY, f32::NEG_INFINITY);
    let near = camera.get_near();
    let far = camera.get_far();
    let corners = [
        Vector2::new(-1.0, -1.0),
        Vector2::new(1.0, -1.0),
        Vector2::new(1.0, 1.0),
        Vector2::new(-1.0, 1.0),
    ];
    for terrain_height in [min_height, max_height] {
        let mut polygon = corners.to_vec();
        let mut clipped = Vec::with_capacity(8);
        for index in 0..polygon.len() {
            let current = polygon[index];
            let previous = polygon[(index + polygon.len() - 1) % polygon.len()];
            let current_y = position.y
                + forward.y * near
                + right.y * half_width * current.x
                + up.y * half_height * current.y;
            let previous_y = position.y
                + forward.y * near
                + right.y * half_width * previous.x
                + up.y * half_height * previous.y;
            let current_inside = current_y >= terrain_height;
            let previous_inside = previous_y >= terrain_height;
            if current_inside != previous_inside {
                let t = (terrain_height - previous_y) / (current_y - previous_y);
                clipped.push(previous + (current - previous) * t);
            }
            if current_inside {
                clipped.push(current);
            }
        }
        polygon.clear();
        polygon.extend(clipped);
        for screen_point in polygon {
            let corner = position
                + forward * near
                + right * (half_width * screen_point.x)
                + up * (half_height * screen_point.y);
            let distance = (terrain_height - corner.y) / forward.y;
            if distance < 0.0 || distance + near > far {
                continue;
            }
            let ground = corner + forward * distance;
            min.x = min.x.min(ground.x);
            min.y = min.y.min(ground.z);
            max.x = max.x.max(ground.x);
            max.y = max.y.max(ground.z);
        }
    }
    if !min.x.is_finite() {
        min = Vector2::new(position.x, position.z);
        max = min;
    }
    GroundBounds {
        center: (min + max) * 0.5,
        min,
        max,
    }
}

fn viewport_dimensions(viewport: &Viewport, size: f32) -> (f32, f32) {
    let visible = viewport.get_visible_rect();
    let aspect = if visible.size.y > 0.0 {
        visible.size.x / visible.size.y
    } else {
        16.0 / 9.0
    };
    (size * aspect * 0.5, size * 0.5)
}

fn center_chunk(camera: &Gd<Camera3D>) -> (i32, i32) {
    let bounds = camera_ground_bounds(camera, 0.02, 3.0);
    (
        ((bounds.center.x + CHUNK_SIZE * 0.5) / CHUNK_SIZE).floor() as i32,
        ((bounds.center.y + CHUNK_SIZE * 0.5) / CHUNK_SIZE).floor() as i32,
    )
}

#[godot_api]
impl INode3D for GiloChunkManager {
    fn init(base: Base<Node3D>) -> Self {
        Self {
            base,
            seed: 42,
            camera_path: NodePath::default(),
            terrain_material: None,
            bootstrap_mesh: None,
            worker_count: DEFAULT_WORKERS,
            max_uploads_per_frame: 2,
            cache_capacity_chunks: DEFAULT_CACHE_CAPACITY,
            view_margin_chunks: 1,
            max_stream_radius_chunks: 48,
            biome_scale: generator::DEFAULT_BIOME_SCALE,
            biome_blend_width: generator::DEFAULT_BIOME_BLEND_WIDTH,
            biome_boundary_warp: generator::DEFAULT_BIOME_BOUNDARY_WARP,
            biome_coverage: generator::DEFAULT_BIOME_COVERAGE,
            surface_bump_strength: generator::DEFAULT_SURFACE_BUMP_STRENGTH,
            surface_bump_scale: generator::DEFAULT_SURFACE_BUMP_SCALE,
            workers: None,
            settings_signature: [0; 6],
            generation_revision: 0,
            active_seed: 42,
            required: HashSet::new(),
            generating: HashSet::new(),
            pending_keys: HashSet::new(),
            pending_uploads: VecDeque::new(),
            loaded: HashMap::new(),
            bootstrap_key: None,
            cache: MeshCache::default(),
            terrain_min_height: 0.02,
            terrain_max_height: 3.0,
        }
    }

    fn ready(&mut self) {
        if Engine::singleton().is_editor_hint() {
            return;
        }
        self.settings_signature = self.current_signature();
        self.generation_revision = self.current_revision();
        self.active_seed = self.seed as u32;
        self.reset_height_bounds();
        self.workers = Some(WorkerPool::new(self.worker_count.clamp(1, 4) as usize));
        self.attach_bootstrap_mesh();
    }

    fn process(&mut self, _delta: f64) {
        if Engine::singleton().is_editor_hint() {
            return;
        }
        let signature = self.current_signature();
        if signature != self.settings_signature || self.seed as u32 != self.active_seed {
            self.settings_signature = signature;
            self.generation_revision = self.current_revision();
            self.active_seed = self.seed as u32;
            self.required.clear();
            self.generating.clear();
            self.pending_uploads.clear();
            self.pending_keys.clear();
            self.bootstrap_key = None;
            self.reset_height_bounds();
            for (_, mut chunk) in self.loaded.drain() {
                chunk.queue_free();
            }
        }
        if let Some(camera) = self.camera() {
            self.update_stream(&camera);
        }
    }
}
