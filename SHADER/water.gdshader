shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Water appearance
uniform vec4 water_color : source_color = vec4(0.1, 0.3, 0.6, 0.85);
uniform vec4 deep_water_color : source_color = vec4(0.0, 0.1, 0.3, 0.95);
uniform vec4 foam_color : source_color = vec4(0.9, 0.95, 1.0, 1.0);

// Wave settings
uniform float wave_speed : hint_range(0.0, 5.0) = 1.0;
uniform float wave_amplitude : hint_range(0.0, 2.0) = 0.15;
uniform float wave_frequency : hint_range(0.1, 10.0) = 2.0;
uniform float wave_sharpness : hint_range(0.1, 5.0) = 1.5;

// Foam/Edge settings
uniform float foam_distance : hint_range(0.0, 5.0) = 1.5;
uniform float foam_cutoff : hint_range(0.0, 1.0) = 0.5;
uniform float foam_smoothness : hint_range(0.001, 0.5) = 0.1;
uniform float edge_wave_speed : hint_range(0.0, 3.0) = 1.5;
uniform float edge_wave_scale : hint_range(0.1, 5.0) = 2.0;

// Visual properties
uniform float roughness : hint_range(0.0, 1.0) = 0.1;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform float refraction : hint_range(-1.0, 1.0) = 0.05;

// Simple noise function
float noise(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Smoother noise with interpolation
float smooth_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = noise(i);
    float b = noise(i + vec2(1.0, 0.0));
    float c = noise(i + vec2(0.0, 1.0));
    float d = noise(i + vec2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal noise for more organic patterns
float fractal_noise(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    for (int i = 0; i < 4; i++) {
        value += amplitude * smooth_noise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    
    return value;
}

void vertex() {
    // Animate water surface with multiple wave layers
    float time = TIME * wave_speed;
    vec2 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
    
    // Primary wave
    float wave1 = sin(world_pos.x * wave_frequency + time) * 
                  cos(world_pos.y * wave_frequency * 0.8 + time * 0.7);
    
    // Secondary wave (different direction)
    float wave2 = sin(world_pos.y * wave_frequency * 1.3 - time * 0.9) * 
                  cos(world_pos.x * wave_frequency * 0.9 - time * 0.6);
    
    // Combine waves with sharpness
    float wave = pow((wave1 + wave2) * 0.5 + 0.5, wave_sharpness) * 2.0 - 1.0;
    
    // Apply wave displacement
    VERTEX.y += wave * wave_amplitude;
    
    // Calculate normal for lighting (approximate)
    float offset = 0.1;
    float h_x = sin((world_pos.x + offset) * wave_frequency + time) * 
                cos((world_pos.y) * wave_frequency * 0.8 + time * 0.7);
    float h_z = sin((world_pos.x) * wave_frequency + time) * 
                cos((world_pos.y + offset) * wave_frequency * 0.8 + time * 0.7);
    
    vec3 tangent_x = vec3(offset, (h_x - wave) * wave_amplitude, 0.0);
    vec3 tangent_z = vec3(0.0, (h_z - wave) * wave_amplitude, offset);
    NORMAL = normalize(cross(tangent_z, tangent_x));
}

void fragment() {
    vec2 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
    float time = TIME * edge_wave_speed;
    
    // Calculate distance-based foam (edges near land/shallow water)
    // This will show foam where water meets land
    float depth = COLOR.a; // Using alpha channel to pass depth info
    
    // Animated foam pattern using fractal noise
    float foam_noise = fractal_noise(world_pos * edge_wave_scale + vec2(time * 0.3, time * 0.2));
    foam_noise += smooth_noise(world_pos * edge_wave_scale * 2.0 - vec2(time * 0.5, time * 0.4)) * 0.5;
    
    // Create foam at edges with animated threshold
    float foam_threshold = foam_cutoff + sin(time * 2.0) * 0.1;
    float foam = smoothstep(foam_threshold - foam_smoothness, 
                           foam_threshold + foam_smoothness, 
                           foam_noise);
    
    // Distance-based foam intensity (stronger at edges)
    float edge_factor = 1.0 - smoothstep(0.0, foam_distance, depth);
    foam *= edge_factor;
    
    // Animate foam movement
    float foam_wave = sin(world_pos.x * 3.0 + time * 2.0) * 
                     cos(world_pos.y * 3.0 - time * 1.5) * 0.5 + 0.5;
    foam *= foam_wave * 0.5 + 0.5;
    
    // Color mixing based on depth
    vec3 water_col = mix(water_color.rgb, deep_water_color.rgb, 
                         smoothstep(0.0, 2.0, depth));
    
    // Add foam color
    vec3 final_color = mix(water_col, foam_color.rgb, foam);
    
    // Apply subtle color variation
    float color_variation = smooth_noise(world_pos * 0.5 + vec2(time * 0.1)) * 0.1;
    final_color += color_variation;
    
    ALBEDO = final_color;
    ROUGHNESS = roughness - foam * 0.3; // Foam is rougher
    METALLIC = metallic;
    SPECULAR = specular + foam * 0.2; // Foam is more specular
    
    // Add transparency (less transparent with foam)
    ALPHA = mix(water_color.a, 1.0, foam * 0.5);
    
    // Refraction effect
    NORMAL_MAP_DEPTH = refraction;
}