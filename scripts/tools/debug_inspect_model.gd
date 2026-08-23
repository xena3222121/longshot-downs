extends SceneTree

const PATH: String = "res://assets/horse3d_candidate/horse-01.glb"

func _print_tree(node: Node, indent: String = "") -> void:
	var extra := ""
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		if mesh != null:
			extra = " surfaces=%d" % mesh.get_surface_count()
			for i in range(mesh.get_surface_count()):
				var mat: Material = node.get_active_material(i)
				var mat_info: String = "null"
				if mat != null:
					mat_info = mat.resource_name
					if mat is StandardMaterial3D:
						mat_info += " albedo_color=%s has_texture=%s" % [mat.albedo_color, mat.albedo_texture != null]
				extra += " [%d:%s]" % [i, mat_info]
	print("%s%s (%s)%s" % [indent, node.name, node.get_class(), extra])
	for child in node.get_children():
		_print_tree(child, indent + "  ")

func _init() -> void:
	var scene: PackedScene = load(PATH)
	var instance: Node = scene.instantiate()
	_print_tree(instance)

	var anim_player: AnimationPlayer = instance.find_child("AnimationPlayer", true, false)
	if anim_player != null:
		print("Animations: %s" % anim_player.get_animation_list())
	else:
		print("No AnimationPlayer found")

	var aabb_node: Node = instance
	quit()
