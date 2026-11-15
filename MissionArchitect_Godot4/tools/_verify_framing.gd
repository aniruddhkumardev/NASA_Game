extends SceneTree

# Geometry probe: reproduce the deploy camera composition headlessly and report
# how much of the vertical frame is Earth (below the limb) vs black space, for
# the whole 20s separation. Earth radius 340, craft altitude 46, cam fov 70 (vert).

const R: float = 340.0
const ALT: float = 46.0
const FOV_V: float = 70.0

func _init() -> void:
	var center := Vector3.ZERO
	var craft_r: float = R + ALT
	# Worst case: sample the shot across the release, with a growing gap.
	var t: float = 0.0
	while t <= 20.0:
		var raw: float = clampf(t / 13.0, 0.0, 1.0)
		var c := raw - 0.5
		var release: float = clampf((raw + (0.5 + 4.0 * c * c * c)) * 0.5, 0.0, 1.0)
		# Build an orthonormal frame at the craft: radial = +Y, prograde = -Z, side = +X.
		var radial := Vector3.UP
		var prograde := Vector3(0.0, 0.0, -1.0)
		var side := Vector3.RIGHT
		# Stage drifts back/down, payload rises out and ahead.
		var stage_pos := center + radial * craft_r + prograde * (-release * 30.0) + radial * (-release * 3.0)
		var mouth := stage_pos + radial * 4.4
		var pay_pos := mouth + radial * (release * 5.0) + prograde * (release * 22.0)
		var focus := (stage_pos + pay_pos) * 0.5
		var gap := stage_pos.distance_to(pay_pos)
		var rhat := (focus - center).normalized()
		var dist := 12.0 + gap * 0.9
		var cam_pos := focus + side * dist + rhat * (dist * 0.12)
		var aim := focus + rhat * 0.5
		# Optical axis and its angle from nadir (toward center).
		var axis := (aim - cam_pos).normalized()
		var nadir := (center - cam_pos).normalized()
		var axis_from_nadir: float = rad_to_deg(acos(clampf(axis.dot(nadir), -1.0, 1.0)))
		# Earth angular radius from the camera.
		var cam_alt: float = cam_pos.distance_to(center)
		var earth_half_angle: float = rad_to_deg(asin(clampf(R / cam_alt, -1.0, 1.0)))
		var half_fov: float = FOV_V * 0.5
		var frame_lo: float = axis_from_nadir - half_fov  # bottom edge (toward nadir)
		var frame_hi: float = axis_from_nadir + half_fov  # top edge (toward space)
		# Earth occupies frame from nadir(0) up to earth_half_angle.
		var earth_span: float = clampf(minf(frame_hi, earth_half_angle) - maxf(frame_lo, 0.0), 0.0, FOV_V)
		var earth_pct: float = earth_span / FOV_V * 100.0
		print("t=%5.1f gap=%5.1f axisFromNadir=%5.1f earthAA=%5.1f earth%%=%4.1f space%%=%4.1f" % [t, gap, axis_from_nadir, earth_half_angle, earth_pct, 100.0 - earth_pct])
		t += 2.5
	print("PROBE-DONE")
	quit()
