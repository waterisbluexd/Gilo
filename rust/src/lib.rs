use godot::classes::{IMeshInstance3D, MeshInstance3D};
use godot::prelude::*;
mod terrain;

struct GiloExtension;

#[gdextension]
unsafe impl ExtensionLibrary for GiloExtension {}

#[derive(GodotClass)]
#[class(base = MeshInstance3D)]
struct GiloTerrain {
    base: Base<MeshInstance3D>,
    #[export]
    seed: i64,
    #[export]
    resolution: i64,
    #[export]
    world_size: f64,
}

#[godot_api]
impl IMeshInstance3D for GiloTerrain {
    fn init(base: Base<MeshInstance3D>) -> Self {
        Self {
            base,
            seed: 42,
            resolution: terrain::generator::DEFAULT_RESOLUTION as i64,
            world_size: terrain::generator::DEFAULT_WORLD_SIZE as f64,
        }
    }

    fn ready(&mut self) {
        let resolution = self.resolution.clamp(64, 512) as usize;
        let world_size = self.world_size.clamp(1.0, 256.0) as f32;
        let data = terrain::generator::generate(self.seed as u32, resolution, world_size);
        let mesh_started = std::time::Instant::now();
        let generated_mesh = terrain::mesh::build_mesh(&data);
        let mesh_micros = mesh_started.elapsed().as_micros();
        self.base_mut().set_mesh(&generated_mesh);
        let half_size = data.size * 0.5;
        let bounds_in_view = self.base().get_viewport().and_then(|viewport| {
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
        godot_print!(
            "Terrain ready: seed={}, world size={}, resolution={}x{}, triangles={}, bounds in view={}, height generation={} ms, mesh build={} ms",
            self.seed,
            data.size,
            resolution + 1,
            resolution + 1,
            data.triangle_count,
            bounds_in_view,
            data.generation_micros as f64 / 1000.0,
            mesh_micros as f64 / 1000.0
        );
    }
}