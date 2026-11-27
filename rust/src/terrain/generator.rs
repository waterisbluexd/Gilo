use std::time::Instant;

use super::noise::{fbm3, next_random, value_noise3};

pub const DEFAULT_RESOLUTION: usize = 256*256;
pub const DEFAULT_WORLD_SIZE: f32 = 14.0*2.0;

pub struct TerrainData {
    pub resolution: usize,
    pub size: f32,
    pub heights: Vec<f32>,
    pub min_height: f32,
    pub max_height: f32,
    pub triangle_count: usize,
    pub generation_micros: u128,
}

pub fn generate(seed: u32, resolution: usize, world_size: f32) -> TerrainData {
    let started = Instant::now();
    let resolution = resolution.clamp(64, 1024);
    let side = resolution + 1;
    let mut random_state = if seed == 0 { 42 } else { seed };

    let _noise_offsets = [
        next_random(&mut random_state) * 60.0,
        next_random(&mut random_state) * 60.0,
        next_random(&mut random_state) * 60.0,
    ];
    let domain_offsets = [
        next_random(&mut random_state) * 80.0,
        next_random(&mut random_state) * 80.0,
        next_random(&mut random_state) * 80.0,
    ];

    let mut heights = vec![0.0_f32; side * side];
    for row in 0..side {
        let vz = row as f64 / resolution as f64 - 0.5;
        for column in 0..side {
            let ux = column as f64 / resolution as f64 - 0.5;
            let index = row * side + column;

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
            let right_peak =
                (-((ux - 0.26).powi(2) * 14.0 + (vz + 0.16).powi(2) * 14.0)).exp() * 0.55;
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

            heights[index] = (base_height * (1.0 - terrace_mask) + stepped_height * terrace_mask)
                .max(0.02) as f32;
        }
    }

    // Match the reference's two forward in-place relaxation passes.
    for _ in 0..2 {
        for row in 1..resolution {
            let row_start = row * side;
            for column in 1..resolution {
                let index = row_start + column;
                let average = (heights[index - 1] as f64
                    + heights[index + 1] as f64
                    + heights[index - side] as f64
                    + heights[index + side] as f64)
                    * 0.25;
                heights[index] = (heights[index] as f64 * 0.72 + average * 0.28) as f32;
            }
        }
    }

    let (min_height, max_height) = heights.iter().fold(
        (f32::INFINITY, f32::NEG_INFINITY),
        |(minimum, maximum), &height| (minimum.min(height), maximum.max(height)),
    );
    let generation_micros = started.elapsed().as_micros();
    TerrainData {
        resolution,
        size: world_size,
        heights,
        min_height,
        max_height,
        triangle_count: resolution * resolution * 2 + resolution * 8,
        generation_micros,
    }
}

#[cfg(test)]
mod tests {
    use super::{DEFAULT_WORLD_SIZE, generate};

    #[test]
    fn terrain_is_seeded_and_has_finite_relief() {
        let first = generate(42, 64, DEFAULT_WORLD_SIZE);
        let second = generate(42, 64, DEFAULT_WORLD_SIZE);
        assert_eq!(first.heights, second.heights);
        assert!(first.min_height >= 0.02);
        assert!(first.max_height > first.min_height);
        assert!(first.heights.iter().all(|height| height.is_finite()));
    }

    #[test]
    fn world_size_does_not_change_requested_resolution() {
        let terrain = generate(42, 256, 48.0);
        assert_eq!(terrain.size, 48.0);
        assert_eq!(terrain.resolution, 256);
        assert_eq!(terrain.heights.len(), 257 * 257);
    }
}
