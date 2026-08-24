import bpy, sys, math, mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
in_path, out_prefix = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=in_path)

meshes = [o for o in bpy.data.objects if o.type == 'MESH']
obj = meshes[0]

# simple clay material if none present, so shape reads even without texture
if not obj.data.materials:
    mat = bpy.data.materials.new("clay")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (0.85, 0.85, 0.83, 1.0)
    obj.data.materials.append(mat)

bpy.context.scene.render.engine = 'BLENDER_EEVEE'
bpy.context.scene.render.resolution_x = 640
bpy.context.scene.render.resolution_y = 640
bpy.context.scene.render.film_transparent = False
bpy.context.scene.world = bpy.data.worlds.new("W")
bpy.context.scene.world.use_nodes = True
bg = bpy.context.scene.world.node_tree.nodes.get("Background")
if bg:
    bg.inputs[0].default_value = (0.55, 0.55, 0.55, 1.0)

sun = bpy.data.lights.new("sun", type='SUN')
sun.energy = 3.0
sun_obj = bpy.data.objects.new("sun", sun)
bpy.context.collection.objects.link(sun_obj)
sun_obj.rotation_euler = (math.radians(55), 0, math.radians(35))

dims = obj.dimensions
center = mathutils.Vector((0, 0, dims.z / 2.0))
radius = max(dims.x, dims.y, dims.z) * 3.0

cam_data = bpy.data.cameras.new("cam")
cam_data.lens = 35
cam_obj = bpy.data.objects.new("cam", cam_data)
bpy.context.collection.objects.link(cam_obj)
bpy.context.scene.camera = cam_obj

angles = {"side": 90, "front": 0, "three_quarter": 45, "back": 180}
for name, deg in angles.items():
    rad = math.radians(deg)
    cam_obj.location = center + mathutils.Vector((radius * math.sin(rad), -radius * math.cos(rad), radius * 0.15))
    direction = center - cam_obj.location
    cam_obj.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.render.filepath = f"{out_prefix}_{name}.png"
    bpy.ops.render.render(write_still=True)
    print(f"rendered {name}")

print("DONE_PREVIEW")
