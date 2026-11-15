shader_type canvas_item;

// Seamless lunar rotation for the title-screen moon.  The texture is the moon
// disc cropped from the plate with a soft circular alpha, so it melts back into
// the artwork; the shader spins it slowly around its centre and adds a tiny
// brightness breath so the surface never looks frozen.

uniform float spin_speed : hint_range(0.0, 0.1) = 0.016;
uniform float sway : hint_range(0.0, 0.03) = 0.006;
uniform float breathe_amount : hint_range(0.0, 0.15) = 0.04;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float t = TIME;
	// Slow libration sway: the surface drifts a few pixels, like a real tidally
	// locked body seen from Earth.
	uv += vec2(sin(t * 0.37), cos(t * 0.29)) * sway;
	float a = t * spin_speed;
	float ca = cos(a);
	float sa = sin(a);
	vec2 suv = vec2(ca * uv.x - sa * uv.y, sa * uv.x + ca * uv.y) + vec2(0.5);
	vec4 col = texture(TEXTURE, clamp(suv, vec2(0.0), vec2(1.0)));
	float breathe = 1.0 + breathe_amount * sin(t * 0.9);
	COLOR = vec4(col.rgb * breathe, col.a);
}
