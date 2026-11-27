use godot::classes::{
    ArrayMesh, StandardMaterial3D,
    base_material_3d::Flags,
    mesh::{ArrayType, PrimitiveType},
};
use godot::obj::EngineEnum;
use godot::prelude::*;

use super::generator::TerrainData;

fn color_from_rgb(rgb: [u8; 3]) -> Color {
    Color::from_rgba(
        rgb[0] as f32 / 255.0,
        rgb[1] as f32 / 255.0,
        rgb[2] as f32 / 255.0,
        1.0,
    )
}

fn vertex_color(height: f32, maximum: f32, normal: Vector3) -> Color {
    if normal.y < 0.75 || height > maximum * 0.76 {
        let shade = (0.55 + (1.0 - normal.y).clamp(0.0, 1.0) * 0.22).clamp(0.0, 1.0);
        return Color::from_rgba(0.58 * shade, 0.56 * shade, 0.53 * shade, 1.0);
    }

    if height < maximum * 0.34 {
        color_from_rgb(if normal.y > 0.96 {
            [115, 145, 57]
        } else {
            [154, 132, 66]
        })
    } else if height > maximum * 0.58 {
        color_from_rgb([177, 154, 108])
    } else {
        color_from_rgb([205, 176, 82])
    }
}

pub fn build_mesh(data: &TerrainData) -> Gd<ArrayMesh> {
    let resolution = data.resolution;
    let side = resolution + 1;
    let half_size = data.size * 0.5;
    let spacing = data.size / resolution as f32;
    let mut vertices = Vec::with_capacity(side * side + resolution * 16);
    let mut normals = Vec::with_capacity(side * side + resolution * 16);
    let mut colors = Vec::with_capacity(side * side + resolution * 16);
    let mut indices = Vec::with_capacity(resolution * resolution * 6 + resolution * 24);

    for row in 0..side {
        let z = row as f32 * spacing - half_size;
        for column in 0..side {
            let x = column as f32 * spacing - half_size;
            let index = row * side + column;
            let left = if column == 0 { index } else { index - 1 };
            let right = if column == resolution {
                index
            } else {
                index + 1
            };
            let up = if row == 0 { index } else { index - side };
            let down = if row == resolution {
                index
            } else {
                index + side
            };
            let dx_span = (right - left) as f32 * spacing;
            let dz_span = (down.abs_diff(up) / side) as f32 * spacing;
            let slope_x = (data.heights[right] - data.heights[left]) / dx_span.max(spacing);
            let slope_z = (data.heights[down] - data.heights[up]) / dz_span.max(spacing);
            let normal = Vector3::new(-slope_x, 1.0, -slope_z).normalized();
            let height = data.heights[index];

            vertices.push(Vector3::new(x, height, z));
            normals.push(normal);
            colors.push(vertex_color(height, data.max_height, normal));
        }
    }

    for row in 0..resolution {
        for column in 0..resolution {
            let a = (row * side + column) as i32;
            let b = a + 1;
            let d = a + side as i32;
            let c = d + 1;
            if (row + column) & 1 == 0 {
                indices.extend_from_slice(&[a, c, d, a, b, c]);
            } else {
                indices.extend_from_slice(&[a, b, d, b, c, d]);
            }
        }
    }

    append_skirt(data, &mut vertices, &mut normals, &mut colors, &mut indices);

    let packed_vertices = PackedVector3Array::from(vertices);
    let packed_normals = PackedVector3Array::from(normals);
    let packed_colors = PackedColorArray::from(colors);
    let packed_indices = PackedInt32Array::from(indices);
    let mut arrays = Array::<Variant>::new();
    arrays.resize(ArrayType::MAX.ord() as usize, &Variant::nil());
    arrays.set(
        ArrayType::VERTEX.ord() as usize,
        &packed_vertices.to_variant(),
    );
    arrays.set(
        ArrayType::NORMAL.ord() as usize,
        &packed_normals.to_variant(),
    );
    arrays.set(ArrayType::COLOR.ord() as usize, &packed_colors.to_variant());
    arrays.set(
        ArrayType::INDEX.ord() as usize,
        &packed_indices.to_variant(),
    );

    let mut mesh = ArrayMesh::new_gd();
    mesh.add_surface_from_arrays(PrimitiveType::TRIANGLES, &arrays);

    let mut material = StandardMaterial3D::new_gd();
    material.set_flag(Flags::ALBEDO_FROM_VERTEX_COLOR, true);
    material.set_roughness(1.0);
    mesh.surface_set_material(0, &material);
    mesh
}

fn append_skirt(
    data: &TerrainData,
    vertices: &mut Vec<Vector3>,
    normals: &mut Vec<Vector3>,
    colors: &mut Vec<Color>,
    indices: &mut Vec<i32>,
) {
    let resolution = data.resolution;
    let side = resolution + 1;
    let bottom = data.min_height - 1.35;
    let border_color = color_from_rgb([49, 47, 49]);

    for edge in 0..4 {
        for segment in 0..resolution {
            let (top_a, top_b, outward) = match edge {
                0 => (segment, segment + 1, Vector3::new(0.0, 0.0, -1.0)),
                1 => (
                    segment * side + resolution,
                    (segment + 1) * side + resolution,
                    Vector3::new(1.0, 0.0, 0.0),
                ),
                2 => (
                    resolution * side + resolution - segment,
                    resolution * side + resolution - segment - 1,
                    Vector3::new(0.0, 0.0, 1.0),
                ),
                _ => (
                    (resolution - segment) * side,
                    (resolution - segment - 1) * side,
                    Vector3::new(-1.0, 0.0, 0.0),
                ),
            };
            let top_a_position = vertices[top_a];
            let top_b_position = vertices[top_b];
            let first = vertices.len() as i32;
            vertices.extend_from_slice(&[
                top_a_position,
                top_b_position,
                Vector3::new(top_b_position.x, bottom, top_b_position.z),
                Vector3::new(top_a_position.x, bottom, top_a_position.z),
            ]);
            normals.extend_from_slice(&[outward; 4]);
            colors.extend_from_slice(&[border_color; 4]);
            indices.extend_from_slice(&[first, first + 1, first + 2, first, first + 2, first + 3]);
        }
    }
}
