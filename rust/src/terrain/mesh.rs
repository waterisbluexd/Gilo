use godot::classes::{
    ArrayMesh, StandardMaterial3D,
    base_material_3d::Flags,
    mesh::{ArrayType, PrimitiveType},
};
use godot::obj::EngineEnum;
use godot::prelude::*;

use super::generator::TerrainData;

#[derive(Clone)]
pub struct MeshData {
    pub vertices: Vec<[f32; 3]>,
    pub normals: Vec<[f32; 3]>,
    pub colors: Vec<[f32; 4]>,
    pub indices: Vec<i32>,
    pub min_height: f32,
    pub max_height: f32,
}

pub fn build_mesh_data(data: &TerrainData) -> MeshData {
    let resolution = data.resolution;
    let side = resolution + 1;
    let half_size = data.size * 0.5;
    let spacing = data.size / resolution as f32;
    let mut vertices = Vec::with_capacity(side * side);
    let mut normals = Vec::with_capacity(side * side);
    let mut colors = Vec::with_capacity(side * side);
    let mut indices = Vec::with_capacity(resolution * resolution * 6);

    for row in 0..side {
        let z = row as f32 * spacing - half_size;
        for column in 0..side {
            let x = column as f32 * spacing - half_size;
            let index = row * side + column;
            let normal = data.normals[index];
            let weights = data.biome_weights[index];

            vertices.push([x, data.heights[index], z]);
            normals.push(normal);
            colors.push([weights[0], weights[1], weights[2], weights[3]]);
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

    MeshData {
        vertices,
        normals,
        colors,
        indices,
        min_height: data.min_height,
        max_height: data.max_height,
    }
}

pub fn build_mesh(data: &MeshData) -> Gd<ArrayMesh> {
    let packed_vertices = PackedVector3Array::from(
        data.vertices
            .iter()
            .map(|vertex| Vector3::new(vertex[0], vertex[1], vertex[2]))
            .collect::<Vec<_>>(),
    );
    let packed_normals = PackedVector3Array::from(
        data.normals
            .iter()
            .map(|normal| Vector3::new(normal[0], normal[1], normal[2]))
            .collect::<Vec<_>>(),
    );
    let packed_colors = PackedColorArray::from(
        data.colors
            .iter()
            .map(|color| Color::from_rgba(color[0], color[1], color[2], color[3]))
            .collect::<Vec<_>>(),
    );
    let packed_indices = PackedInt32Array::from(data.indices.clone());
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
