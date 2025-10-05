shader_type spatial;

// Chunk world position (set from GDScript)
uniform vec2 chunk_world_offset = vec2(0.0, 0.0);
uniform float chunk_size = 32.0;
uniform float pixel_size = 4.0;

// Noise parameters (must match your FastNoiseLite settings)
uniform float primary_frequency = 0.02;
uniform float primary_octaves = 2.0;
uniform float primary_gain = 0.3;
uniform float primary_lacunarity = 1.8;
uniform int primary_seed = 0;

uniform float secondary_frequency = 0.05;
uniform int secondary_seed = 1000;

// Noise mixing
uniform float primary_weight = 0.85;
uniform float secondary_weight = 0.15;
uniform float noise_contrast = 0.8;

// Biome colors (8 biomes)
uniform vec4 color_1 : source_color = vec4(0.169, 0.239, 0.075, 1.0);
uniform vec4 color_2 : source_color = vec4(0.196, 0.341, 0.133, 1.0);
uniform vec4 color_3 : source_color = vec4(0.38, 0.408, 0.133, 1.0);
uniform vec4 color_4 : source_color = vec4(0.447, 0.569, 0.267, 1.0);
uniform vec4 color_5 : source_color = vec4(0.78, 0.69, 0.282, 1.0);
uniform vec4 color_6 : source_color = vec4(0.482, 0.624, 0.2, 1.0);
uniform vec4 color_7 : source_color = vec4(0.545, 0.702, 0.22, 1.0);
uniform vec4 color_8 : source_color = vec4(0.647, 0.753, 0.208, 1.0);

// Thresholds
uniform float threshold_1 = -0.6;
uniform float threshold_2 = -0.3;
uniform float threshold_3 = -0.1;
uniform float threshold_4 = 0.1;
uniform float threshold_5 = 0.3;
uniform float threshold_6 = 0.5;
uniform float threshold_7 = 0.7;

// Height settings
uniform bool enable_height_variation = false;
uniform float height_frequency = 0.08;
uniform float terrain_height_variation = 0.5;
uniform float height_influence = 1.0;
uniform int height_seed = 2000;

// ===== NOISE FUNCTIONS =====
// Simple hash for random
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Perlin-style gradient noise
vec2 random_gradient(vec2 p, int seed) {
    float angle = hash(p + vec2(float(seed))) * 6.283185307;
    return vec2(cos(angle), sin(angle));
}

float perlin_noise(vec2 p, int seed) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    
    // Smooth interpolation
    vec2 u = f * f * (3.0 - 2.0 * f);
    
    // Grid corners
    vec2 g00 = random_gradient(i + vec2(0.0, 0.0), seed);
    vec2 g10 = random_gradient(i + vec2(1.0, 0.0), seed);
    vec2 g01 = random_gradient(i + vec2(0.0, 1.0), seed);
    vec2 g11 = random_gradient(i + vec2(1.0, 1.0), seed);
    
    // Dot products
    float v00 = dot(g00, f - vec2(0.0, 0.0));
    float v10 = dot(g10, f - vec2(1.0, 0.0));
    float v01 = dot(g01, f - vec2(0.0, 1.0));
    float v11 = dot(g11, f - vec2(1.0, 1.0));
    
    // Bilinear interpolation
    float v0 = mix(v00, v10, u.x);
    float v1 = mix(v01, v11, u.x);
    return mix(v0, v1, u.y);
}

// Fractal Brownian Motion (multi-octave noise)
float fbm(vec2 p, float frequency, float octaves, float gain, float lacunarity, int seed) {
    float value = 0.0;
    float amplitude = 1.0;
    float max_value = 0.0;
    
    p *= frequency;
    
    for (float i = 0.0; i < octaves; i += 1.0) {
        value += perlin_noise(p, seed) * amplitude;
        max_value += amplitude;
        amplitude *= gain;
        p *= lacunarity;
    }
    
    return value / max_value;
}

// ===== BIOME COLOR SELECTION =====
vec4 get_biome_color(float noise_value) {
    if (noise_value < threshold_1) return color_1;
    if (noise_value < threshold_2) return color_2;
    if (noise_value < threshold_3) return color_3;
    if (noise_value < threshold_4) return color_4;
    if (noise_value < threshold_5) return color_5;
    if (noise_value < threshold_6) return color_6;
    if (noise_value < threshold_7) return color_7;
    return color_8;
}

void fragment() {
    // Calculate world position from UV
    vec2 local_pos = UV * chunk_size * pixel_size;
    vec2 world_pos = chunk_world_offset + local_pos;
    
    // Generate primary noise (matching your FastNoiseLite)
    float primary_noise = fbm(
        world_pos, 
        primary_frequency, 
        primary_octaves, 
        primary_gain, 
        primary_lacunarity, 
        primary_seed
    );
    
    // Generate secondary noise
    float secondary_noise = fbm(
        world_pos,
        secondary_frequency,
        1.0, // 1 octave
        0.5,
        2.0,
        secondary_seed
    );
    
    // Combine noises
    float combined = (primary_noise * primary_weight + secondary_noise * secondary_weight) * noise_contrast;
    combined = clamp(combined, -1.0, 1.0);
    
    // Get biome color
    vec4 terrain_color = get_biome_color(combined);
    
    ALBEDO = terrain_color.rgb;
    ROUGHNESS = 0.8;
    METALLIC = 0.0;
    
    // Optional: Height displacement (requires vertex shader)
    if (enable_height_variation) {
        float height_noise = fbm(world_pos, height_frequency, 2.0, 0.5, 2.0, height_seed);
        // This would need to be in vertex() to actually displace geometry
    }
}

void vertex() {
    // Optional: Apply height displacement
    if (enable_height_variation) {
        vec2 world_pos = chunk_world_offset + (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
        float height_noise = fbm(world_pos, height_frequency, 2.0, 0.5, 2.0, height_seed);
        VERTEX.y += height_noise * terrain_height_variation * height_influence;
    }
}