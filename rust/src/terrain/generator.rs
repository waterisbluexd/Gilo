use std::{
    collections::HashMap,
    sync::{Mutex, OnceLock},
    time::Instant,
};

use super::noise::{fbm3, next_random, value_noise3};

pub const CHUNK_RESOLUTION: usize = 64;
pub const CHUNK_SIZE: f64 = 14.0;
pub const DEFAULT_BIOME_SCALE: f64 = 42.0;
pub const DEFAULT_BIOME_BLEND_WIDTH: f64 = 7.5;
pub const DEFAULT_BIOME_BOUNDARY_WARP: f64 = 0.38;
pub const DEFAULT_BIOME_COVERAGE: f64 = 0.4;
pub const DEFAULT_SURFACE_BUMP_STRENGTH: f64 = 0.025;
pub const DEFAULT_SURFACE_BUMP_SCALE: f64 = 1.6;

#[derive(Clone, Copy, Debug)]
pub struct TerrainSettings {
    pub biome_scale: f64,
    pub biome_blend_width: f64,
    pub biome_boundary_warp: f64,
    pub biome_coverage: f64,
    pub surface_bump_strength: f64,
    pub surface_bump_scale: f64,
}

impl Default for TerrainSettings {
    fn default() -> Self {
        Self {
            biome_scale: DEFAULT_BIOME_SCALE,
            biome_blend_width: DEFAULT_BIOME_BLEND_WIDTH,
            biome_boundary_warp: DEFAULT_BIOME_BOUNDARY_WARP,
            biome_coverage: DEFAULT_BIOME_COVERAGE,
            surface_bump_strength: DEFAULT_SURFACE_BUMP_STRENGTH,
            surface_bump_scale: DEFAULT_SURFACE_BUMP_SCALE,
        }
    }
}

impl TerrainSettings {
    fn sanitized(self) -> Self {
        Self {
            biome_scale: self.biome_scale.clamp(8.0, 4096.0),
            biome_blend_width: self.biome_blend_width.clamp(0.25, 64.0),
            biome_boundary_warp: self.biome_boundary_warp.clamp(0.0, 2.0),
            biome_coverage: self.biome_coverage.clamp(0.05, 0.95),
            surface_bump_strength: self.surface_bump_strength.clamp(0.0, 0.12),
            surface_bump_scale: self.surface_bump_scale.clamp(0.4, 8.0),
        }
    }

    fn cache_key(self, seed: u32) -> TerrainCacheKey {
        TerrainCacheKey {
            seed,
            settings: [
                self.biome_scale.to_bits(),
                self.biome_blend_width.to_bits(),
                self.biome_boundary_warp.to_bits(),
                self.biome_coverage.to_bits(),
                self.surface_bump_strength.to_bits(),
                self.surface_bump_scale.to_bits(),
            ],
        }
    }
}

#[derive(Clone, Copy, Eq, Hash, PartialEq)]
struct TerrainCacheKey {
    seed: u32,
    settings: [u64; 6],
}

struct CachedTerrainSample {
    height: f32,
    biome_weights: Option<[f32; 4]>,
}

#[derive(Default)]
struct SharedSampleCache {
    identity: Option<TerrainCacheKey>,
    samples: HashMap<(i64, i64), CachedTerrainSample>,
}

const MAX_SHARED_SAMPLES: usize = 16_384;
static SHARED_SAMPLE_CACHE: OnceLock<Mutex<SharedSampleCache>> = OnceLock::new();

fn shared_sample_cache() -> &'static Mutex<SharedSampleCache> {
    SHARED_SAMPLE_CACHE.get_or_init(|| Mutex::new(SharedSampleCache::default()))
}

fn is_shared_sample(grid_x: i64, grid_z: i64) -> bool {
    let edge_x = grid_x.rem_euclid(CHUNK_RESOLUTION as i64);
    let edge_z = grid_z.rem_euclid(CHUNK_RESOLUTION as i64);
    edge_x <= 1
        || edge_x >= CHUNK_RESOLUTION as i64 - 1
        || edge_z <= 1
        || edge_z >= CHUNK_RESOLUTION as i64 - 1
}

fn cached_boundary_height(
    identity: TerrainCacheKey,
    grid_x: i64,
    grid_z: i64,
    world_x: f64,
    world_z: f64,
    domain_offsets: [f64; 3],
    settings: TerrainSettings,
) -> f32 {
    let mut cache = shared_sample_cache()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if cache.identity != Some(identity) {
        cache.identity = Some(identity);
        cache.samples.clear();
    }
    if let Some(sample) = cache.samples.get(&(grid_x, grid_z)) {
        return sample.height;
    }
    if cache.samples.len() >= MAX_SHARED_SAMPLES {
        cache.samples.clear();
    }
    let height = sample_height(world_x, world_z, domain_offsets, settings) as f32;
    cache.samples.insert(
        (grid_x, grid_z),
        CachedTerrainSample {
            height,
            biome_weights: None,
        },
    );
    height
}

fn cached_boundary_biome_weights(
    identity: TerrainCacheKey,
    grid_x: i64,
    grid_z: i64,
    world_x: f64,
    world_z: f64,
    height: f32,
    domain_offsets: [f64; 3],
    settings: TerrainSettings,
) -> [f32; 4] {
    let mut cache = shared_sample_cache()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if cache.identity != Some(identity) {
        cache.identity = Some(identity);
        cache.samples.clear();
    }
    if let Some(weights) = cache
        .samples
        .get(&(grid_x, grid_z))
        .and_then(|sample| sample.biome_weights)
    {
        return weights;
    }
    if cache.samples.len() >= MAX_SHARED_SAMPLES {
        cache.samples.clear();
    }
    let weights = sample_biome_weights(world_x, world_z, height as f64, domain_offsets, settings);
    cache.samples.insert(
        (grid_x, grid_z),
        CachedTerrainSample {
            height,
            biome_weights: Some(weights),
        },
    );
    weights
}

pub struct TerrainData {
    pub resolution: usize,
    pub size: f32,
    pub chunk_x: i32,
    pub chunk_z: i32,
    pub heights: Vec<f32>,
    pub normals: Vec<[f32; 3]>,
    pub biome_weights: Vec<[f32; 4]>,
    pub min_height: f32,
    pub max_height: f32,
    pub triangle_count: usize,
    pub generation_micros: u128,
}

pub fn generate(seed: u32, chunk_x: i32, chunk_z: i32, settings: TerrainSettings) -> TerrainData {
    let started = Instant::now();
    let settings = settings.sanitized();
    let resolution = CHUNK_RESOLUTION;
    let side = resolution + 1;
    let padded_side = side + 2;
    let spacing = CHUNK_SIZE / resolution as f64;
    let mut random_state = if seed == 0 { 42 } else { seed };
    let domain_offsets = [
        next_random(&mut random_state) * 80.0,
        next_random(&mut random_state) * 80.0,
        next_random(&mut random_state) * 80.0,
    ];

    let cache_identity = settings.cache_key(seed);
    let mut padded_heights = vec![0.0_f32; padded_side * padded_side];
    for row in 0..padded_side {
        let grid_z = chunk_z as i64 * resolution as i64 + row as i64 - 1;
        let world_z = -CHUNK_SIZE * 0.5 + grid_z as f64 * spacing;
        for column in 0..padded_side {
            let grid_x = chunk_x as i64 * resolution as i64 + column as i64 - 1;
            let world_x = -CHUNK_SIZE * 0.5 + grid_x as f64 * spacing;
            padded_heights[row * padded_side + column] = if is_shared_sample(grid_x, grid_z) {
                cached_boundary_height(
                    cache_identity,
                    grid_x,
                    grid_z,
                    world_x,
                    world_z,
                    domain_offsets,
                    settings,
                )
            } else {
                sample_height(world_x, world_z, domain_offsets, settings) as f32
            };
        }
    }

    let mut heights = Vec::with_capacity(side * side);
    let mut normals = Vec::with_capacity(side * side);
    let mut biome_weights = Vec::with_capacity(side * side);
    let mut min_height = f32::INFINITY;
    let mut max_height = f32::NEG_INFINITY;
    for row in 0..side {
        let grid_z = chunk_z as i64 * resolution as i64 + row as i64;
        let world_z = -CHUNK_SIZE * 0.5 + grid_z as f64 * spacing;
        for column in 0..side {
            let grid_x = chunk_x as i64 * resolution as i64 + column as i64;
            let world_x = -CHUNK_SIZE * 0.5 + grid_x as f64 * spacing;
            let index = (row + 1) * padded_side + column + 1;
            let height = padded_heights[index];
            let slope_x =
                (padded_heights[index + 1] - padded_heights[index - 1]) / (2.0 * spacing as f32);
            let slope_z = (padded_heights[index + padded_side]
                - padded_heights[index - padded_side])
                / (2.0 * spacing as f32);
            let inverse_length = (slope_x * slope_x + 1.0 + slope_z * slope_z).sqrt().recip();

            min_height = min_height.min(height);
            max_height = max_height.max(height);
            heights.push(height);
            normals.push([
                -slope_x * inverse_length,
                inverse_length,
                -slope_z * inverse_length,
            ]);
            biome_weights.push(if is_shared_sample(grid_x, grid_z) {
                cached_boundary_biome_weights(
                    cache_identity,
                    grid_x,
                    grid_z,
                    world_x,
                    world_z,
                    height,
                    domain_offsets,
                    settings,
                )
            } else {
                sample_biome_weights(world_x, world_z, height as f64, domain_offsets, settings)
            });
        }
    }

    TerrainData {
        resolution,
        size: CHUNK_SIZE as f32,
        chunk_x,
        chunk_z,
        heights,
        normals,
        biome_weights,
        min_height,
        max_height,
        triangle_count: resolution * resolution * 2,
        generation_micros: started.elapsed().as_micros(),
    }
}

fn sample_height(
    world_x: f64,
    world_z: f64,
    domain_offsets: [f64; 3],
    settings: TerrainSettings,
) -> f64 {
    let ux = world_x / CHUNK_SIZE;
    let vz = world_z / CHUNK_SIZE;
    let warped_x = ux
        + (fbm3(
            ux * 1.4 + domain_offsets[0],
            vz * 1.4 + domain_offsets[1],
            1.7,
        ) - 0.5)
            * 0.24;
    let warped_z = vz
        + (fbm3(
            ux * 1.4 + domain_offsets[2],
            vz * 1.4 + domain_offsets[0],
            4.3,
        ) - 0.5)
            * 0.24;

    let mut ridge = 0.0;
    let mut amplitude = 0.55;
    let mut frequency = 2.1;
    for octave in 0..4 {
        let noise = 1.0
            - (2.0
                * value_noise3(
                    warped_x * frequency + domain_offsets[0],
                    warped_z * frequency + domain_offsets[1],
                    octave as f64 * 6.7 + domain_offsets[2],
                )
                - 1.0)
                .abs();
        ridge += noise * noise * amplitude;
        amplitude *= 0.48;
        frequency *= 2.08;
    }

    let back_massif = (-ux * 0.72 - vz * 0.78 + 0.32).max(0.0);
    let right_peak = (-((ux - 0.26).powi(2) * 14.0 + (vz + 0.16).powi(2) * 14.0)).exp() * 0.55;
    let front_meadow = (vz * 0.95 + 0.25).max(0.0);
    let base_height = (ridge * 1.65 * (0.35 + 0.55 * 1.15)
        + back_massif.powf(1.25) * 1.85 * (0.4 + 0.55)
        + right_peak * (0.4 + 0.55)
        + (fbm3(
            warped_x * 3.2 + domain_offsets[1],
            warped_z * 3.2 + domain_offsets[2],
            8.1,
        ) - 0.5)
            * 0.55
            * 0.65)
        * (1.0 - front_meadow * 0.42 * 0.65);

    let terrace_bands = 4.0;
    let scaled_height = base_height * terrace_bands;
    let lower_band = scaled_height.floor();
    let fraction = scaled_height - lower_band;
    let smooth_fraction = fraction * fraction * (3.0 - 2.0 * fraction);
    let stepped_height = (lower_band + smooth_fraction) / terrace_bands;
    let terrace_mask = ((value_noise3(
        ux * 1.7 + domain_offsets[0],
        warped_z * 1.7 + domain_offsets[2],
        13.0,
    ) - 0.35)
        / 0.35)
        .clamp(0.0, 1.0)
        * 0.45;
    let terrain_height =
        (base_height * (1.0 - terrace_mask) + stepped_height * terrace_mask).max(0.02);

    let bump_noise = fbm3(
        world_x / settings.surface_bump_scale + domain_offsets[0],
        31.7 + domain_offsets[1],
        world_z / settings.surface_bump_scale + domain_offsets[2],
    );
    (terrain_height + (bump_noise - 0.5) * 2.0 * settings.surface_bump_strength).max(0.02)
}

fn sample_biome_weights(
    world_x: f64,
    world_z: f64,
    height: f64,
    domain_offsets: [f64; 3],
    settings: TerrainSettings,
) -> [f32; 4] {
    let biome_x = world_x / settings.biome_scale;
    let biome_z = world_z / settings.biome_scale;
    let warp_x = (fbm3(
        biome_x * 0.7 + domain_offsets[0],
        57.3 + domain_offsets[1],
        biome_z * 0.7 + domain_offsets[2],
    ) - 0.5)
        * 2.0
        * settings.biome_boundary_warp;
    let warp_z = (fbm3(
        biome_x * 0.7 + domain_offsets[2],
        83.1 + domain_offsets[0],
        biome_z * 0.7 + domain_offsets[1],
    ) - 0.5)
        * 2.0
        * settings.biome_boundary_warp;
    let biome_signal = fbm3(
        biome_x + warp_x + domain_offsets[1] * 0.03,
        103.7 + domain_offsets[2],
        biome_z + warp_z + domain_offsets[0] * 0.03,
    );
    let blend_width = (settings.biome_blend_width / settings.biome_scale).clamp(0.01, 0.8);
    let half_width = blend_width * 0.5;
    let mut green_weight = smoothstep(
        settings.biome_coverage - half_width,
        settings.biome_coverage + half_width,
        biome_signal,
    );
    let elevation_modifier = smoothstep(0.8, 2.8, height) * 0.12;
    green_weight *= 1.0 - elevation_modifier;
    let total = (1.0 - green_weight) + green_weight;
    let green_weight = green_weight / total;
    let golden_weight = (1.0 - green_weight) / total;
    [golden_weight as f32, green_weight as f32, 0.0, 0.0]
}

fn smoothstep(edge0: f64, edge1: f64, value: f64) -> f64 {
    let t = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

#[cfg(test)]
mod tests {
    use super::{CHUNK_RESOLUTION, CHUNK_SIZE, TerrainSettings, generate};

    #[test]
    fn chunks_have_fixed_dimensions_and_normalized_biome_weights() {
        let terrain = generate(42, 0, 0, TerrainSettings::default());
        let expected_samples = (CHUNK_RESOLUTION + 1) * (CHUNK_RESOLUTION + 1);
        assert_eq!(terrain.resolution, 64);
        assert_eq!(terrain.size, 14.0);
        assert_eq!(terrain.heights.len(), expected_samples);
        assert_eq!(terrain.normals.len(), expected_samples);
        assert_eq!(terrain.biome_weights.len(), expected_samples);
        assert!(terrain.biome_weights.iter().all(|weights| {
            weights.iter().all(|weight| (0.0..=1.0).contains(weight))
                && (weights.iter().sum::<f32>() - 1.0).abs() < 1.0e-6
        }));
        assert!(
            terrain
                .biome_weights
                .iter()
                .any(|weights| weights[0] > 0.75)
        );
        assert!(
            terrain
                .biome_weights
                .iter()
                .any(|weights| weights[1] > 0.75)
        );
    }

    #[test]
    fn biome_weights_blend_smoothly_between_samples() {
        let terrain = generate(42, 0, 0, TerrainSettings::default());
        let side = CHUNK_RESOLUTION + 1;
        for row in 0..side {
            for column in 0..side {
                let index = row * side + column;
                if column < CHUNK_RESOLUTION {
                    let difference = (terrain.biome_weights[index][1]
                        - terrain.biome_weights[index + 1][1])
                        .abs();
                    assert!(difference < 0.15);
                }
                if row < CHUNK_RESOLUTION {
                    let difference = (terrain.biome_weights[index][1]
                        - terrain.biome_weights[index + side][1])
                        .abs();
                    assert!(difference < 0.15);
                }
            }
        }
    }

    #[test]
    fn adjacent_chunks_share_identical_edges() {
        let settings = TerrainSettings::default();
        let center = generate(42, 0, 0, settings);
        let east = generate(42, 1, 0, settings);
        let north = generate(42, 0, -1, settings);
        let side = CHUNK_RESOLUTION + 1;
        for row in 0..side {
            let center_index = row * side + CHUNK_RESOLUTION;
            let east_index = row * side;
            assert_eq!(center.heights[center_index], east.heights[east_index]);
            assert_eq!(center.normals[center_index], east.normals[east_index]);
            assert_eq!(
                center.biome_weights[center_index],
                east.biome_weights[east_index]
            );
        }
        for column in 0..side {
            let center_index = column;
            let north_index = CHUNK_RESOLUTION * side + column;
            assert_eq!(center.heights[center_index], north.heights[north_index]);
            assert_eq!(center.normals[center_index], north.normals[north_index]);
            assert_eq!(
                center.biome_weights[center_index],
                north.biome_weights[north_index]
            );
        }
        assert_eq!(center.size, CHUNK_SIZE as f32);
    }

    #[test]
    fn surface_bumps_are_bounded_and_do_not_replace_major_relief() {
        let settings = TerrainSettings::default();
        let bumped = generate(42, 0, 0, settings);
        let flat = generate(
            42,
            0,
            0,
            TerrainSettings {
                surface_bump_strength: 0.0,
                ..settings
            },
        );
        let differences: Vec<f32> = bumped
            .heights
            .iter()
            .zip(&flat.heights)
            .map(|(bump, base)| bump - base)
            .collect();
        assert!(
            differences
                .iter()
                .all(|difference| difference.abs() <= 0.0251)
        );
        assert!(differences.iter().any(|difference| *difference < -0.001));
        assert!(differences.iter().any(|difference| *difference > 0.001));
        assert!((bumped.max_height - flat.max_height).abs() <= 0.0251);
        let side = CHUNK_RESOLUTION + 1;
        for row in 0..side {
            for column in 0..side {
                let index = row * side + column;
                if column < CHUNK_RESOLUTION {
                    assert!((differences[index] - differences[index + 1]).abs() < 0.01);
                }
                if row < CHUNK_RESOLUTION {
                    assert!((differences[index] - differences[index + side]).abs() < 0.01);
                }
            }
        }
    }
}
