shader_type canvas_item;

// ─────────────────────────────────────────────────────────────────────────────
// MISSIONFORGE — title-plate white-ink pass
//
// The first page is one pre-rendered concept plate: dark space, a painted Earth
// limb, thin rules and the menu lettering.  The regular monochrome pass turns
// the lettering mid-grey, which is why the page reads as "black on black".
//
// This shader keeps the photographic darks and pushes the bright, saturated
// ink (lettering, icons, frame lines) to pure white, giving the approved
// white-on-black first page without redrawing the plate.  It only ever runs on
// the MainMenu background TextureRect, never on the 3D simulation.
// ─────────────────────────────────────────────────────────────────────────────

uniform float ink_level : hint_range(0.0, 1.0) = 0.40;
uniform float ink_softness : hint_range(0.01, 0.5) = 0.15;
uniform float chroma_boost : hint_range(0.0, 1.0) = 0.45;
uniform float shadow_floor : hint_range(0.0, 1.0) = 0.72;

void fragment() {
	vec3 source = COLOR.rgb;
	float luma = dot(source, vec3(0.2126, 0.7152, 0.0722));
	float chroma = max(source.r, max(source.g, source.b))
		- min(source.r, min(source.g, source.b));

	// Bright or coloured pixels are ink; quiet dark pixels stay as dark space.
	float ink = smoothstep(
		ink_level - ink_softness,
		ink_level + ink_softness,
		luma + chroma * chroma_boost);

	vec3 quiet = vec3(luma * shadow_floor);
	COLOR.rgb = mix(quiet, vec3(1.0), ink);
}
