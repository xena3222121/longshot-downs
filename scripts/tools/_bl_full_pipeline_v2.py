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

bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.0001)
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.mode_set(mode='OBJECT')

# --- 2. UV unwrap (before any glTF export splits corners) ---
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

# --- 4. import old rig, drop its mesh/helpers ---
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
old_size = old_max - old_min
bpy.data.objects.remove(old_mesh, do_unlink=True)

# rotate +90 about Z: new-mesh length runs along X, old rig runs along Y
new_mesh.data.transform(mathutils.Matrix.Rotation(math.radians(90), 4, 'Z'))
new_mesh.data.update()

verts_world = [new_mesh.matrix_world @ v.co for v in new_mesh.data.vertices]
vmin = mathutils.Vector((min(v[i] for v in verts_world) for i in range(3)))
vmax = mathutils.Vector((max(v[i] for v in verts_world) for i in range(3)))
new_size = vmax - vmin

# REAL FIX #1: non-uniform per-axis scale (matches old bbox on X/Y/Z
# independently) instead of one isotropic height-only scale. Root cause
# measured directly (2026-08-23): the raw AI-generated horse's body is
# proportionally SHORTER front-to-back and WIDER than the Quaternius rig's
# body, at the SAME height. A height-only isotropic scale left the whole
# skeleton below the hip floating outside the actual new-mesh geometry
# (confirmed by sampling: 0 mesh vertices within 0.15 units of
# BackUpperLeg/FrontUpperLeg/BackLowerLeg/FrontLowerLeg bone midpoints
# before this fix). This alone fixes the upper-leg segments (confirmed:
# 777/779 verts found nearby after switching to anisotropic scale).
sx, sy, sz = old_size.x / new_size.x, old_size.y / new_size.y, old_size.z / new_size.z
new_mesh.data.transform(mathutils.Matrix.Diagonal((sx, sy, sz, 1.0)))
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

# REAL FIX #2: even after the anisotropic fix above, the LOWER leg segment
# (hock/knee-to-hoof) is still proportionally shorter in the new mesh than
# in the old rig — a non-linear, within-limb difference no single affine
# transform can fix. This is what actually caused the reported "bowed
# camel leg": with BackLowerLeg's bone TAIL (the hoof end) sitting far from
# where the new mesh's real hoof geometry is, automatic weights bound that
# whole hoof/lower-leg region mostly onto BackUpperLeg instead (the nearer
# bone) — so the entire lower leg swung rigidly around the thigh's pivot
# during the Gallop animation instead of bending at its own hock, reading
# as a bowed/broken joint. Fix: measure the ACTUAL hoof cluster for each of
# the 4 legs directly from the now-aligned mesh (near-ground vertex
# clustering by X-sign/Y-sign), then move ONLY each LowerLeg bone's TAIL to
# that real position — HEAD stays put since the upper-leg segment already
# aligns correctly.
near_ground = [v for v in verts_world if -0.02 <= v.z < 0.15]
hoof_clusters = {}  # (is_back, is_left) -> Vector centroid
for x_positive in (True, False):
    side_pts = [v for v in near_ground if (v.x > 0) == x_positive]
    if not side_pts:
        continue
    ys = sorted(v.y for v in side_pts)
    clusters, cur = [], [ys[0]]
    for y in ys[1:]:
        if y - cur[-1] > 0.2:
            clusters.append(cur)
            cur = []
        cur.append(y)
    clusters.append(cur)
    for c in clusters:
        pts = [v for v in side_pts if min(c) <= v.y <= max(c)]
        centroid = mathutils.Vector((sum(v.x for v in pts) / len(pts), sum(v.y for v in pts) / len(pts), sum(v.z for v in pts) / len(pts)))
        is_back = centroid.y > 0
        is_left = centroid.x > 0  # matches old skeleton convention: BackUpperLeg.L head.x = +0.419
        hoof_clusters[(is_back, is_left)] = centroid
        print(f"measured hoof {'BACK' if is_back else 'FRONT'}_{'L' if is_left else 'R'}: {tuple(round(c,4) for c in centroid)} n={len(pts)}")

bpy.context.view_layer.objects.active = armature
bpy.ops.object.mode_set(mode='EDIT')
LEG_BONE_MAP = {
    (True, True): "BackLowerLeg.L", (True, False): "BackLowerLeg.R",
    (False, True): "FrontLowerLeg.L", (False, False): "FrontLowerLeg.R",
}
for key, bone_name in LEG_BONE_MAP.items():
    if key not in hoof_clusters:
        print(f"WARNING: no measured hoof cluster for {bone_name}, leaving as-is")
        continue
    bone = armature.data.edit_bones[bone_name]
    old_tail_world = armature.matrix_world @ bone.tail
    new_tail_world = hoof_clusters[key]
    bone.tail = armature.matrix_world.inverted() @ new_tail_world
    print(f"{bone_name}: tail moved {tuple(round(x,4) for x in old_tail_world)} -> {tuple(round(x,4) for x in new_tail_world)}")
bpy.ops.object.mode_set(mode='OBJECT')

# --- 5. parent to armature w/ automatic weights ---
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
print("DONE_FULL_PIPELINE_V2")
