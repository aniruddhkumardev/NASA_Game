shader_type canvas_item;

// Renders an equirectangular planetary map as a lit spherical disc with a
// soft atmosphere rim, so a flat NASA map reads as a real globe in the menu.
uniform sampler2D planet_tex : filter_linear_mipmap;
uniform vec3  tint            = vec3(1.0, 1.0, 1.0);
uniform vec2  light_dir       = vec2(-0.55, -0.35);
uniform float atmosphere      = 0.35;
uniform float night_floor     = 0.16;

void fragment() {
	vec2 uv = UV;
	vec2 c  = uv * 2.0 - 1.0;          // map to -1..1 across the disc
	float r = length(c);
	// Outside the disc we must emit transparent black.  Godot forbids early
	// `return` inside fragment(), so the lit body is guarded by a branch.
	if (r <= 1.0) {
		vec3 col = texture(planet_tex, uv).rgb * tint;

		// Approximate sphere surface normal from the disc position.
		float z = sqrt(max(0.0, 1.0 - r * r));
		vec3 normal = normalize(vec3(c.x, -c.y, z));
		vec3 L      = normalize(vec3(light_dir, 0.7));
		float diff  = clamp(dot(normal, L), 0.0, 1.0);
		float shade = night_floor + (1.0 - night_floor) * diff;
		col *= shade;

		// Atmosphere glow concentrated on the lit limb.
		float rim = smoothstep(0.55, 1.0, r) * diff;
		col += tint * rim * atmosphere;

		float alpha = 1.0 - smoothstep(0.97, 1.0, r);
		COLOR = vec4(col, alpha);
	} else {
		COLOR = vec4(0.0);
	}
}
