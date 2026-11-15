shader_type canvas_item;

// Faint halo that breathes around the title-screen moon; drawn behind the
// spinning disc and faded out well before the rect edge.

uniform vec4 glow_color : source_color = vec4(0.55, 0.72, 0.95, 1.0);

void fragment() {
	vec2 c = UV - vec2(0.5);
	float d = length(c) * 2.0;
	float falloff = pow(max(0.0, 1.0 - d), 3.0);
	float pulse = 0.09 + 0.035 * sin(TIME * 0.8);
	COLOR = vec4(glow_color.rgb, falloff * pulse);
}
