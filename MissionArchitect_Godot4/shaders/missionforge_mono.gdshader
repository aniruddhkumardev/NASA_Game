shader_type canvas_item;

// ─────────────────────────────────────────────────────────────────────────────
// MISSIONFORGE — monochrome UI pass
//
// This shader is only ever attached to 2D CanvasItems (Controls, labels,
// panels, HUD sprites) by MissionForgeTheme.gd.  It desaturates whatever the
// item draws — font glyphs, StyleBox fills, textures, icons — into pure
// luminance, so the entire interface is black / white / grey.
//
// It is never attached to a Node3D, StandardMaterial3D, MeshInstance3D or the
// WorldEnvironment, so the live simulation keeps its natural colours: blue
// oceans, white clouds, orange plume, gold foil, blue rain, natural ice.
//
// The luminance weights are Rec.709 so mid-greys keep the same perceived
// brightness the original accent colour had.  Alpha is untouched, which keeps
// every translucent panel, glow and fade behaving exactly as designed.
// ─────────────────────────────────────────────────────────────────────────────

uniform float strength : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec3 source = COLOR.rgb;
	float luma = dot(source, vec3(0.2126, 0.7152, 0.0722));
	COLOR.rgb = mix(source, vec3(luma), strength);
}
