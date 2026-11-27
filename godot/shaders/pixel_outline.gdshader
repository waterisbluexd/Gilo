// pixel_outline.gdshader (Godot 4.3+, Forward+/Mobile)
// Put on a MeshInstance3D with a QuadMesh (size 2x2, Flip Faces ON), child of the Camera3D, extra_cull_margin = max.
// Depth-based 2nd-difference ink outline (same test as the web demo's POST_FS).
shader_type spatial;
render_mode unshaded, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform float edge_threshold = 0.12;   // view-space depth step (world units) that counts as an edge
uniform float ink_strength = 0.55;
uniform vec3 ink_color = vec3(0.227, 0.208, 0.192);
uniform bool ink_background_edge = true; // also ink the pixel just outside the silhouette

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// custom functions cannot see built-ins, so the matrix is passed in
float lin_depth(vec2 uv, mat4 inv_proj, out bool bg) {
	float d = texture(depth_tex, uv).x;
	bg = d <= 0.00001;                    // reversed-Z: 0 = far plane / nothing drawn
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0); // for Compatibility renderer use: vec4(vec3(uv, d) * 2.0 - 1.0, 1.0)
	v.xyz /= v.w;
	return -v.z;
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	bool bg0;
	float d0 = lin_depth(SCREEN_UV, INV_PROJECTION_MATRIX, bg0);
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;

	vec2 offs[4] = vec2[4](vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0));
	bool outline = false;
	for (int k = 0; k < 4; k++) {
		bool bgn, bgm;
		float dn = lin_depth(SCREEN_UV + offs[k] * px, INV_PROJECTION_MATRIX, bgn);
		float dm = lin_depth(SCREEN_UV - offs[k] * px, INV_PROJECTION_MATRIX, bgm);
		if (bg0) {
			if (!bgn && ink_background_edge) outline = true;
		} else if (!bgn && (d0 - dn) - (!bgm ? dm - d0 : 0.0) > edge_threshold) {
			outline = true;
		}
	}
	ALBEDO = mix(c, ink_color, outline ? ink_strength : 0.0);
}
