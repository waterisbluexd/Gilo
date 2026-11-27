pub fn hash3(i: i64, j: i64, k: i64) -> f64 {
    let mut value = (i as u32).wrapping_mul(73_856_093)
        ^ (j as u32).wrapping_mul(19_349_663)
        ^ (k as u32).wrapping_mul(83_492_791);
    for coordinate in [i, j, k] {
        if coordinate < i32::MIN as i64 || coordinate > i32::MAX as i64 {
            value ^= ((coordinate >> 31) as u32).wrapping_mul(2_654_435_761);
        }
    }
    value = (value ^ (value >> 15)).wrapping_mul(2_246_822_519);
    ((value ^ (value >> 13)) & 4095) as f64 / 4095.0
}

pub fn value_noise3(x: f64, y: f64, z: f64) -> f64 {
    let i = x.floor() as i64;
    let j = y.floor() as i64;
    let k = z.floor() as i64;
    let fx = x - i as f64;
    let fy = y - j as f64;
    let fz = z - k as f64;
    let u = fx * fx * (3.0 - 2.0 * fx);
    let v = fy * fy * (3.0 - 2.0 * fy);
    let w = fz * fz * (3.0 - 2.0 * fz);

    let a = hash3(i, j, k);
    let b = hash3(i + 1, j, k);
    let c = hash3(i, j + 1, k);
    let d = hash3(i + 1, j + 1, k);
    let e = hash3(i, j, k + 1);
    let f = hash3(i + 1, j, k + 1);
    let g = hash3(i, j + 1, k + 1);
    let h = hash3(i + 1, j + 1, k + 1);

    let x1 = a + (b - a) * u;
    let x2 = c + (d - c) * u;
    let x3 = e + (f - e) * u;
    let x4 = g + (h - g) * u;
    let y1 = x1 + (x2 - x1) * v;
    let y2 = x3 + (x4 - x3) * v;
    y1 + (y2 - y1) * w
}

pub fn fbm3(x: f64, y: f64, z: f64) -> f64 {
    value_noise3(x, y, z) * 0.65 + value_noise3(x * 2.1, y * 2.1, z * 2.1) * 0.35
}

pub fn next_random(state: &mut u32) -> f64 {
    *state = state.wrapping_add(0x6D2B_79F5);
    let mut value = *state;
    value = (value ^ (value >> 15)).wrapping_mul(value | 1);
    value ^= value.wrapping_add((value ^ (value >> 7)).wrapping_mul(value | 61));
    ((value ^ (value >> 14)) as u32) as f64 / 4_294_967_296.0
}

#[cfg(test)]
mod tests {
    use super::{fbm3, hash3, value_noise3};

    #[test]
    fn seeded_noise_is_deterministic_and_bounded() {
        let first = fbm3(-1.25, 0.75, 4.5);
        assert_eq!(first, fbm3(-1.25, 0.75, 4.5));
        assert!((0.0..=1.0).contains(&hash3(-2, 4, 9)));
        assert!((0.0..=1.0).contains(&value_noise3(-1.25, 0.75, 4.5)));
    }

    #[test]
    fn lattice_noise_supports_large_world_coordinates() {
        let first = value_noise3(3_000_000_000.25, 4.5, -6.75);
        let next_cell = value_noise3(3_000_000_001.25, 4.5, -6.75);
        assert_ne!(first, next_cell);
    }

    #[test]
    fn ordinary_coordinates_keep_the_original_hash_values() {
        fn original_hash3(i: i32, j: i32, k: i32) -> f64 {
            let mut value = (i as u32).wrapping_mul(73_856_093)
                ^ (j as u32).wrapping_mul(19_349_663)
                ^ (k as u32).wrapping_mul(83_492_791);
            value = (value ^ (value >> 15)).wrapping_mul(2_246_822_519);
            ((value ^ (value >> 13)) & 4095) as f64 / 4095.0
        }

        assert_eq!(hash3(-2, 4, 9), original_hash3(-2, 4, 9));
        assert_eq!(hash3(i32::MIN as i64, 0, 0), original_hash3(i32::MIN, 0, 0));
        assert_eq!(hash3(i32::MAX as i64, 0, 0), original_hash3(i32::MAX, 0, 0));
    }
}
