shader_type canvas_item;

uniform float tolerance : hint_range(0.0, 1.0) = 0.05;

uniform vec4 color_to_swap_1 : source_color = vec4(0.7137, 0.1020, 0.6824, 1.0);
uniform vec4 color_to_swap_2 : source_color = vec4(0.5961, 0.0588, 0.5804, 1.0);
uniform vec4 color_to_swap_3 : source_color = vec4(0.4275, 0.0000, 0.4471, 1.0);

uniform bool swap_1_enabled = true;
uniform vec4 new_color_1 : source_color = vec4(0.7137, 0.1020, 0.6824, 1.0);

uniform bool swap_2_enabled = true;
uniform vec4 new_color_2 : source_color = vec4(0.5961, 0.0588, 0.5804, 1.0);

uniform bool swap_3_enabled = true;
uniform vec4 new_color_3 : source_color = vec4(0.4275, 0.0000, 0.4471, 1.0);

void fragment() {
    vec4 original_color = texture(TEXTURE, UV);
    vec4 final_color = original_color;

    if (swap_3_enabled) {
        float distance_3 = distance(original_color.rgb, color_to_swap_3.rgb);
        if (distance_3 < tolerance) {
            final_color = vec4(new_color_3.rgb, original_color.a);
        }
    }

    if (swap_2_enabled && final_color == original_color) {
        float distance_2 = distance(original_color.rgb, color_to_swap_2.rgb);
        if (distance_2 < tolerance) {
            final_color = vec4(new_color_2.rgb, original_color.a);
        }
    }

    if (swap_1_enabled && final_color == original_color) {
        float distance_1 = distance(original_color.rgb, color_to_swap_1.rgb);
        if (distance_1 < tolerance) {
            final_color = vec4(new_color_1.rgb, original_color.a);
        }
    }

    COLOR = final_color;
}