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
    #[var(set = set_chunk_coord)]
    chunk_coord: Vector2i,
    #[export]
    #[var(set = set_biome_scale)]
    biome_scale: f64,
    #[export]
    #[var(set = set_biome_blend_width)]
    biome_blend_width: f64,
    #[export]
    #[var(set = set_biome_boundary_warp)]
    biome_boundary_warp: f64,
    #[export]
    #[var(set = set_biome_coverage)]
    biome_coverage: f64,
    #[export]
    #[var(set = set_surface_bump_strength)]
    surface_bump_strength: f64,
    #[export]
    #[var(set = set_surface_bump_scale)]
    surface_bump_scale: f64,
    #[export]
    #[var(set = set_generate_in_editor)]
    generate_in_editor: bool,
    #[export]
    editor_only: bool,
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
        let settings = terrain::generator::TerrainSettings {
            biome_scale: self.biome_scale,
            biome_blend_width: self.biome_blend_width,
            biome_boundary_warp: self.biome_boundary_warp,
            biome_coverage: self.biome_coverage,
            surface_bump_strength: self.surface_bump_strength,
            surface_bump_scale: self.surface_bump_scale,
        };
        let data = terrain::generator::generate(
            self.seed as u32,
            self.chunk_coord.x,
            self.chunk_coord.y,
            settings,
        );
        let mesh_started = std::time::Instant::now();
        let mesh_data = terrain::mesh::build_mesh_data(&data);
        let generated_mesh = terrain::mesh::build_mesh(&mesh_data);
        let mesh_micros = mesh_started.elapsed().as_micros();
        let current_position = self.base().get_position();
        self.base_mut().set_position(Vector3::new(
            data.chunk_x as f32 * data.size,
            current_position.y,
            data.chunk_z as f32 * data.size,
        ));
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
    pub fn set_chunk_coord(&mut self, chunk_coord: Vector2i) {
        self.chunk_coord = chunk_coord;
        self.regenerate_if_editor_enabled();
    }

    #[func]
    pub fn set_biome_scale(&mut self, biome_scale: f64) {
        self.biome_scale = biome_scale.clamp(8.0, 4096.0);
        self.regenerate_if_editor_enabled();
    }

    #[func]
    pub fn set_biome_blend_width(&mut self, biome_blend_width: f64) {
        self.biome_blend_width = biome_blend_width.clamp(0.25, 64.0);
        self.regenerate_if_editor_enabled();
    }

    #[func]
    pub fn set_biome_boundary_warp(&mut self, biome_boundary_warp: f64) {
        self.biome_boundary_warp = biome_boundary_warp.clamp(0.0, 2.0);
        self.regenerate_if_editor_enabled();
    }

    #[func]
    pub fn set_biome_coverage(&mut self, biome_coverage: f64) {
        self.biome_coverage = biome_coverage.clamp(0.05, 0.95);
        self.regenerate_if_editor_enabled();
    }

    #[func]
    pub fn set_surface_bump_strength(&mut self, surface_bump_strength: f64) {
        self.surface_bump_strength = surface_bump_strength.clamp(0.0, 0.12);
        self.regenerate_if_editor_enabled();
    }

    #[func]
    pub fn set_surface_bump_scale(&mut self, surface_bump_scale: f64) {
        self.surface_bump_scale = surface_bump_scale.clamp(0.4, 8.0);
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
            chunk_coord: Vector2i::ZERO,
            biome_scale: terrain::generator::DEFAULT_BIOME_SCALE,
            biome_blend_width: terrain::generator::DEFAULT_BIOME_BLEND_WIDTH,
            biome_boundary_warp: terrain::generator::DEFAULT_BIOME_BOUNDARY_WARP,
            biome_coverage: terrain::generator::DEFAULT_BIOME_COVERAGE,
            surface_bump_strength: terrain::generator::DEFAULT_SURFACE_BUMP_STRENGTH,
            surface_bump_scale: terrain::generator::DEFAULT_SURFACE_BUMP_SCALE,
            generate_in_editor: false,
            editor_only: false,
        }
    }

    fn ready(&mut self) {
        let is_editor = Engine::singleton().is_editor_hint();
        if self.editor_only && !is_editor {
            self.base_mut().set_visible(false);
            return;
        }
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
                "Terrain chunk ready: seed={}, chunk=({}, {}), world size={}, subdivisions={}x{}, samples={}x{}, triangles={}, bounds in view={}, height generation={} ms, mesh build={} ms",
                self.seed,
                data.chunk_x,
                data.chunk_z,
                data.size,
                data.resolution,
                data.resolution,
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
