import bpy, sys, math, mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
raw_path, old_rig_path, tex_path, out_path, target_tris = argv[0], argv[1], argv[2], argv[3], int(argv[4])

bpy.ops.wm.read_factory_settings(use_empty=True)

# --- 1. import + clean + decimate raw candidate mesh ---
bpy.ops.import_scene.gltf(filepath=raw_path)
new_mesh = [o for o in bpy.data.objects if o.type == 'MESH'][0]
bpy.context.view_layer.objects.active = new_mesh
new_mesh.select_set(True)

bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.0001)
bpy.ops.mesh.fill_holes(sides=0)
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.mode_set(mode='OBJECT')

cur_tris = len(new_mesh.data.polygons)
ratio = min(1.0, target_tris / cur_tris)
mod = new_mesh.modifiers.new(name="Decimate", type='DECIMATE')
mod.decimate_type = 'COLLAPSE'
mod.ratio = ratio
bpy.ops.object.modifier_apply(modifier=mod.name)
print(f"decimated: tris={len(new_mesh.data.polygons)} verts={len(new_mesh.data.vertices)}")

# manifold cleanup pass AFTER decimate too — collapse decimation can itself
# introduce new non-manifold edges/degenerate faces
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.0001)
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.mode_set(mode='OBJECT')

# --- 2. UV unwrap (kept in-memory — connectivity for weighting happens
#         BEFORE any glTF export splits corners, so this is safe here) ---
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=66.0, island_margin=0.01)
bpy.ops.object.mode_set(mode='OBJECT')

# --- 3. texture material ---
mat = bpy.data.materials.new("coat")
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes.get("Principled BSDF")
img = bpy.data.images.load(tex_path)
img.colorspace_settings.name = 'sRGB'
tex_node = nt.nodes.new("ShaderNodeTexImage")
tex_node.image = img
tex_node.extension = 'REPEAT'
mapping = nt.nodes.new("ShaderNodeMapping")
mapping.inputs['Scale'].default_value = (6.0, 6.0, 1.0)
uv_node = nt.nodes.new("ShaderNodeUVMap")
uv_node.uv_map = new_mesh.data.uv_layers[0].name
nt.links.new(uv_node.outputs['UV'], mapping.inputs['Vector'])
nt.links.new(mapping.outputs['Vector'], tex_node.inputs['Vector'])
nt.links.new(tex_node.outputs['Color'], bsdf.inputs['Base Color'])
bsdf.inputs['Roughness'].default_value = 0.75
new_mesh.data.materials.clear()
new_mesh.data.materials.append(mat)

# --- 4. import old rig, drop its mesh/helpers, align new mesh into its frame ---
bpy.ops.import_scene.gltf(filepath=old_rig_path)
armature = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
old_mesh = None
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o is not new_mesh:
        if o.name == 'Horse':
            old_mesh = o
        else:
            bpy.data.objects.remove(o, do_unlink=True)

old_verts_world = [old_mesh.matrix_world @ v.co for v in old_mesh.data.vertices]
old_min = mathutils.Vector((min(v[i] for v in old_verts_world) for i in range(3)))
old_max = mathutils.Vector((max(v[i] for v in old_verts_world) for i in range(3)))
old_center = (old_min + old_max) / 2
old_height = old_max.z - old_min.z
bpy.data.objects.remove(old_mesh, do_unlink=True)

# rotate +90 about Z: new-mesh length runs along its X (head -X/tail +X,
# measured separately), old rig length runs along Y (head -Y/tail +Y)
rot_matrix = mathutils.Matrix.Rotation(math.radians(90), 4, 'Z')
new_mesh.data.transform(rot_matrix)
new_mesh.data.update()

verts_world = [new_mesh.matrix_world @ v.co for v in new_mesh.data.vertices]
vmin = mathutils.Vector((min(v[i] for v in verts_world) for i in range(3)))
vmax = mathutils.Vector((max(v[i] for v in verts_world) for i in range(3)))
new_height = vmax.z - vmin.z
scale = old_height / new_height
scale_matrix = mathutils.Matrix.Scale(scale, 4)
new_mesh.data.transform(scale_matrix)
new_mesh.data.update()

verts_world = [new_mesh.matrix_world @ v.co for v in new_mesh.data.vertices]
vmin = mathutils.Vector((min(v[i] for v in verts_world) for i in range(3)))
vmax = mathutils.Vector((max(v[i] for v in verts_world) for i in range(3)))
new_center = (vmin + vmax) / 2
translate = mathutils.Vector((old_center.x - new_center.x, old_center.y - new_center.y, old_min.z - vmin.z))
new_mesh.data.transform(mathutils.Matrix.Translation(translate))
new_mesh.data.update()

verts_world = [new_mesh.matrix_world @ v.co for v in new_mesh.data.vertices]
vmin = mathutils.Vector((min(v[i] for v in verts_world) for i in range(3)))
vmax = mathutils.Vector((max(v[i] for v in verts_world) for i in range(3)))
print(f"aligned new mesh bbox min={vmin} max={vmax}  (old was min={old_min} max={old_max})")

# --- 5. parent to armature w/ automatic weights, still fully connected ---
bpy.ops.object.select_all(action='DESELECT')
new_mesh.select_set(True)
armature.select_set(True)
bpy.context.view_layer.objects.active = armature
bpy.ops.object.parent_set(type='ARMATURE_AUTO')

total_weighted = sum(1 for v in new_mesh.data.vertices if len(v.groups) > 0)
print(f"verts with weight: {total_weighted} / {len(new_mesh.data.vertices)}")

bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    export_animations=True,
    export_force_sampling=True,
)
print("DONE_FULL_PIPELINE")
