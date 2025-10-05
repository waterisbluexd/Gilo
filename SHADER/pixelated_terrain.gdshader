shader_type spatial;

uniform sampler2D terrain_texture : source_color, filter_nearest;

void fragment() {
    // Sample texture with nearest-neighbor filtering for pixelated look
    vec4 tex_color = texture(terrain_texture, UV);
    
    ALBEDO = tex_color.rgb;
    ROUGHNESS = 0.8;
    METALLIC = 0.0;
}