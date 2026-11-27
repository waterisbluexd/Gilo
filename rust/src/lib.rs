use godot::classes::{Engine, IMeshInstance3D, MeshInstance3D};
use godot::prelude::*;
mod terrain;

struct GiloExtension;

#[gdextension]
unsafe impl ExtensionLibrary for GiloExtension {}

#[derive(GodotClass)]
#[class(tool, base = MeshInstance3D)]
struct GiloTerrain {
    base: Base<MeshInstance3D>,
    #[export]
    #[var(set = set_seed)]
    seed: i64,
    #[export]
    #[var(set = set_resolution)]
    resolution: i64,
    #[export]
    #[var(set = set_world_size)]
    world_size: f64,
    #[export]
    #[var(set = set_generate_in_editor)]
    generate_in_editor: bool,
}

impl GiloTerrain {
    fn regenerate_if_editor_enabled(&mut self) {
        if self.generate_in_editor
            && self.base().is_inside_tree()
            && Engine::singleton().is_editor_hint()
        {
            self.regenerate_mesh();
        }
    }

    fn regenerate_mesh(&mut self) -> (terrain::generator::TerrainData, u128) {
        let resolution = self.resolution.clamp(64, 512) as usize;
        let world_size = self.world_size.clamp(1.0, 256.0) as f32;
        let data = terrain::generator::generate(self.seed as u32, resolution, world_size);
        let mesh_started = std::time::Instant::now();
        let generated_mesh = terrain::mesh::build_mesh(&data);
        let mesh_micros = mesh_started.elapsed().as_micros();
        self.base_mut().set_mesh(&generated_mesh);
        (data, mesh_micros)
    }
}

#[godot_api]
impl GiloTerrain {
    #[func]
    pub fn set_seed(&mut self, seed: i64) {
        self.seed = seed;
        self.regenerate_if_editor_enabled();
    }

    #[func]
    pub fn set_resolution(&mut self, resolution: i64) {
        self.resolution = resolution;
        self.regenerate_if_editor_enabled();
    }

    #[func]
    pub fn set_world_size(&mut self, world_size: f64) {
        self.world_size = world_size;
        self.regenerate_if_editor_enabled();
    }

    #[func]
    pub fn set_generate_in_editor(&mut self, enabled: bool) {
        self.generate_in_editor = enabled;
        self.regenerate_if_editor_enabled();
    }
}

#[godot_api]
impl IMeshInstance3D for GiloTerrain {
    fn init(base: Base<MeshInstance3D>) -> Self {
        Self {
            base,
            seed: 42,
            resolution: terrain::generator::DEFAULT_RESOLUTION as i64,
            world_size: terrain::generator::DEFAULT_WORLD_SIZE as f64,
            generate_in_editor: false,
        }
    }

    fn ready(&mut self) {
        let is_editor = Engine::singleton().is_editor_hint();
        if is_editor && !self.generate_in_editor {
            return;
        }

        let (data, mesh_micros) = self.regenerate_mesh();
        let half_size = data.size * 0.5;
        let bounds_in_view = (!is_editor)
            .then(|| self.base().get_viewport())
            .flatten()
            .and_then(|viewport| {
                viewport.get_camera_3d().map(|camera| {
                    let visible = viewport.get_visible_rect();
                    let mut minimum = Vector2::new(f32::INFINITY, f32::INFINITY);
                    let mut maximum = Vector2::new(f32::NEG_INFINITY, f32::NEG_INFINITY);
                    let mut all_in_front = true;
                    for x in [-half_size, half_size] {
                        for z in [-half_size, half_size] {
                            for y in [data.min_height - 1.35, data.max_height] {
                                let point = self.base().to_global(Vector3::new(x, y, z));
                                all_in_front &= !camera.is_position_behind(point);
                                let projected = camera.unproject_position(point);
                                minimum.x = minimum.x.min(projected.x);
                                minimum.y = minimum.y.min(projected.y);
                                maximum.x = maximum.x.max(projected.x);
                                maximum.y = maximum.y.max(projected.y);
                            }
                        }
                    }
                    let fits = all_in_front
                        && minimum.x >= visible.position.x
                        && minimum.y >= visible.position.y
                        && maximum.x <= visible.position.x + visible.size.x
                        && maximum.y <= visible.position.y + visible.size.y;
                    (fits, all_in_front, minimum, maximum, visible)
                })
            });
        let bounds_in_view = bounds_in_view.map(|result| result.0).unwrap_or(false);
        if !is_editor {
            godot_print!(
                "Terrain ready: seed={}, world size={}, resolution={}x{}, triangles={}, bounds in view={}, height generation={} ms, mesh build={} ms",
                self.seed,
                data.size,
                data.resolution + 1,
                data.resolution + 1,
                data.triangle_count,
                bounds_in_view,
                data.generation_micros as f64 / 1000.0,
                mesh_micros as f64 / 1000.0
            );
        }
    }
}
