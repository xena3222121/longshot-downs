import bpy, sys, math, mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
in_path, out_prefix = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=in_path)

meshes = [o for o in bpy.data.objects if o.type == 'MESH']
armatures = [o for o in bpy.data.objects if o.type == 'ARMATURE']
obj = meshes[0]
arm = armatures[0] if armatures else None

if arm is not None:
    gallop_action = None
    for a in bpy.data.actions:
        if 'Gallop' in a.name and 'Jump' not in a.name:
            gallop_action = a
            break
    if gallop_action:
        arm.animation_data_create()
        arm.animation_data.action = gallop_action
        print(f"using action {gallop_action.name} frames {gallop_action.frame_range}")

bpy.context.scene.render.engine = 'BLENDER_EEVEE'
bpy.context.scene.render.resolution_x = 640
bpy.context.scene.render.resolution_y = 640
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
verts_world = [obj.matrix_world @ v.co for v in obj.data.vertices]
zmax = max(v.z for v in verts_world)
center = mathutils.Vector((0, 0, zmax / 2.0))
radius = zmax * 2.2

cam_data = bpy.data.cameras.new("cam")
cam_data.lens = 35
cam_obj = bpy.data.objects.new("cam", cam_data)
bpy.context.collection.objects.link(cam_obj)
bpy.context.scene.camera = cam_obj
rad = math.radians(60)
cam_obj.location = center + mathutils.Vector((radius * math.sin(rad), -radius * math.cos(rad), radius * 0.2))
direction = center - cam_obj.location
cam_obj.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()

frames = [0, 4, 8, 12] if arm is not None else [0]
for f in frames:
    bpy.context.scene.frame_set(f)
    bpy.context.view_layer.update()
    bpy.context.scene.render.filepath = f"{out_prefix}_f{f}.png"
    bpy.ops.render.render(write_still=True)
    print(f"rendered frame {f}")

print("DONE_PREVIEW_ANIM")
