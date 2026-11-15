## Temporary asset inspector: dumps the node/material layout of a glTF scene so
## the runtime colour pass can target the right surfaces.  Not shipped gameplay.
extends SceneTree

const TARGET := "res://assets/models/satellite.glb"

func _init() -> void:
	var packed: PackedScene = load(TARGET)
	if packed == null:
		print("ASSET PROBE: could not load ", TARGET)
		quit(1)
		return
	var root: Node = packed.instantiate()
	_walk(root, 0)
	root.free()
	quit(0)

func _walk(node: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	print("%s%s [%s]" % [pad, node.name, node.get_class()])
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh:
			print("%s  mesh=%s surfaces=%d aabb=%s" % [pad, mesh.get_class(), mesh.get_surface_count(), mesh.get_aabb()])
			for i in mesh.get_surface_count():
				var mat: Material = (node as MeshInstance3D).get_surface_override_material(i)
				if mat == null:
					mat = mesh.surface_get_material(i)
				print("%s  surf %d -> %s" % [pad, i, _mat_info(mat)])
	for child in node.get_children():
		_walk(child, depth + 1)

func _mat_info(mat: Material) -> String:
	if mat == null:
		return "null"
	if mat is StandardMaterial3D:
		var sm := mat as StandardMaterial3D
		return "Standard albedo=%s metal=%.2f rough=%.2f emission=%s tex=%s" % [
			sm.albedo_color, sm.metallic, sm.roughness,
			sm.emission, sm.albedo_texture.resource_path if sm.albedo_texture else "none"]
	return mat.get_class() + " " + mat.resource_name
