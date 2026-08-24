import bpy, sys

argv = sys.argv[sys.argv.index("--") + 1:]
in_path, out_glb_path, out_png_path, bake_size = argv[0], argv[1], argv[2], int(argv[3])

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.engine = 'CYCLES'
bpy.context.scene.cycles.device = 'GPU'

bpy.ops.import_scene.gltf(filepath=in_path)
mesh_obj = [o for o in bpy.data.objects if o.type == 'MESH'][0]
armature = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]

if not mesh_obj.data.uv_layers:
    raise RuntimeError("no UV layer on candidate mesh - expected one from the earlier smart_project pass")
uv_name = mesh_obj.data.uv_layers[0].name

# Three geometry-derived approaches (Cycles bake type=AO at two different
# distances, vertex_color_dirt, and a proper AmbientOcclusion shader node)
# all came back nearly flat white -- the actual root cause, confirmed by
# process of elimination: this mesh's geometry (AI-generated then heavily
# decimated) is just too smooth/rounded to have real creases for ANY
# curvature-based technique to find. No amount of bake tuning fixes that --
# the detail has to come from a deliberately-designed texture instead of
# being derived from geometry that doesn't have it.
#
# So: a real procedural coat pattern using Object-space coordinates (stable
# across the UV-seam-heavy decimated mesh, unlike UV-space noise which would
# show seams) -- fine high-frequency noise for a "short hair grain" look,
# plus a coarser noise for natural blotchy tonal variation, plus a
# Z-height-based gradient so the belly/lower legs read subtly darker than
# the topline (a real horse trait, and a controllable substitute for the
# per-joint AO darkening the geometry couldn't provide).
mesh_obj.data.materials.clear()
bake_img = bpy.data.images.new("horse_ao_bake", width=bake_size, height=bake_size)

bake_mat = bpy.data.materials.new("bake_temp")
bake_mat.use_nodes = True
nt = bake_mat.node_tree
for n in list(nt.nodes):
    nt.nodes.remove(n)

tex_coord = nt.nodes.new("ShaderNodeTexCoord")

# Scale=180 on a ~1-6 unit object turned out to alias into a near-uniform
# average (too fine to resolve at 1024px/32 samples) -- dropped to a
# frequency that actually resolves as visible grain at this bake resolution.
fine_noise = nt.nodes.new("ShaderNodeTexNoise")
fine_noise.inputs['Scale'].default_value = 35.0
fine_noise.inputs['Detail'].default_value = 2.0
fine_noise.inputs['Roughness'].default_value = 0.6
nt.links.new(tex_coord.outputs['Object'], fine_noise.inputs['Vector'])

coarse_noise = nt.nodes.new("ShaderNodeTexNoise")
coarse_noise.inputs['Scale'].default_value = 6.0
coarse_noise.inputs['Detail'].default_value = 3.0
coarse_noise.inputs['Roughness'].default_value = 0.55
nt.links.new(tex_coord.outputs['Object'], coarse_noise.inputs['Vector'])

# Wider remap bands than the first attempt (which read as nearly invisible
# even after a post-bake contrast stretch) -- favor a clearly visible
# painted-blotch coat pattern over understated realism at this point.
fine_map = nt.nodes.new("ShaderNodeMapRange")
fine_map.inputs['To Min'].default_value = 0.6
fine_map.inputs['To Max'].default_value = 1.0
nt.links.new(fine_noise.outputs['Fac'], fine_map.inputs['Value'])

coarse_map = nt.nodes.new("ShaderNodeMapRange")
coarse_map.inputs['To Min'].default_value = 0.45
coarse_map.inputs['To Max'].default_value = 1.0
nt.links.new(coarse_noise.outputs['Fac'], coarse_map.inputs['Value'])

mul1 = nt.nodes.new("ShaderNodeMath")
mul1.operation = 'MULTIPLY'
nt.links.new(fine_map.outputs['Result'], mul1.inputs[0])
nt.links.new(coarse_map.outputs['Result'], mul1.inputs[1])

# Belly/lower-leg darkening via object-space Z (mesh is Z-up, feet near
# Z=0). separate_xyz -> map_range -> multiply into the noise result.
sep_xyz = nt.nodes.new("ShaderNodeSeparateXYZ")
nt.links.new(tex_coord.outputs['Object'], sep_xyz.inputs['Vector'])
z_map = nt.nodes.new("ShaderNodeMapRange")
z_map.inputs['From Min'].default_value = -0.3
z_map.inputs['From Max'].default_value = 2.0
z_map.inputs['To Min'].default_value = 0.78
z_map.inputs['To Max'].default_value = 1.0
z_map.clamp = True
nt.links.new(sep_xyz.outputs['Z'], z_map.inputs['Value'])

mul2 = nt.nodes.new("ShaderNodeMath")
mul2.operation = 'MULTIPLY'
nt.links.new(mul1.outputs['Value'], mul2.inputs[0])
nt.links.new(z_map.outputs['Result'], mul2.inputs[1])

shade_to_color = nt.nodes.new("ShaderNodeCombineXYZ")
nt.links.new(mul2.outputs['Value'], shade_to_color.inputs['X'])
nt.links.new(mul2.outputs['Value'], shade_to_color.inputs['Y'])
nt.links.new(mul2.outputs['Value'], shade_to_color.inputs['Z'])

emit_node = nt.nodes.new("ShaderNodeEmission")
out_node = nt.nodes.new("ShaderNodeOutputMaterial")
nt.links.new(shade_to_color.outputs['Vector'], emit_node.inputs['Color'])
nt.links.new(emit_node.outputs['Emission'], out_node.inputs['Surface'])

img_node = nt.nodes.new("ShaderNodeTexImage")
img_node.image = bake_img
for n in nt.nodes:
    n.select = False
img_node.select = True
nt.nodes.active = img_node

mesh_obj.data.materials.append(bake_mat)

bpy.ops.object.select_all(action='DESELECT')
mesh_obj.select_set(True)
bpy.context.view_layer.objects.active = mesh_obj

bpy.context.scene.cycles.samples = 32
bpy.ops.object.bake(type='EMIT', margin=8)

# Real variation is present but subtle (measured: mean~0.82, std~0.09 on a
# 0-1 scale) -- too subtle to read as a coat pattern rather than a flat
# tone at a glance. Percentile-based contrast stretch (not a flat linear
# formula) so the real spread present in the data actually pops, without
# guessing at absolute min/max that may not match this bake's real range.
import numpy as np
px = np.array(bake_img.pixels[:]).reshape(-1, 4)
rgb = px[:, :3]
baked_mask = px[:, 3] > 0.0  # alpha=0 is the unbaked outside-UV margin, exclude from percentile calc
sample = rgb[baked_mask][:, 0]
lo, hi = np.percentile(sample, 3), np.percentile(sample, 97)
rgb_stretched = np.clip((rgb - lo) / max(hi - lo, 1e-4), 0.0, 1.0)
# Re-bias so the stretched result centers around a believable mid-light
# coat tone (0.55) instead of 0-1 full range, then re-apply only where the
# original bake actually had data.
rgb_final = 0.15 + rgb_stretched * 0.7
rgb = np.where(baked_mask[:, None], rgb_final, rgb)
px[:, :3] = rgb
bake_img.pixels.foreach_set(px.flatten().tolist())
bake_img.update()

bake_img.filepath_raw = out_png_path
bake_img.file_format = 'PNG'
bake_img.save()
print(f"BAKED_DIRT_TEXTURE: {out_png_path}")

final_mat = bpy.data.materials.new("coat")
final_mat.use_nodes = True
nt2 = final_mat.node_tree
bsdf = nt2.nodes.get("Principled BSDF")
tex_node = nt2.nodes.new("ShaderNodeTexImage")
tex_node.image = bake_img
uv_node = nt2.nodes.new("ShaderNodeUVMap")
uv_node.uv_map = uv_name
nt2.links.new(uv_node.outputs['UV'], tex_node.inputs['Vector'])
nt2.links.new(tex_node.outputs['Color'], bsdf.inputs['Base Color'])
bsdf.inputs['Roughness'].default_value = 0.75

mesh_obj.data.materials.clear()
mesh_obj.data.materials.append(final_mat)

bpy.ops.export_scene.gltf(
    filepath=out_glb_path,
    export_format='GLB',
    export_animations=True,
    export_force_sampling=True,
)
print("DONE_BAKE_AO_TEXTURE")
