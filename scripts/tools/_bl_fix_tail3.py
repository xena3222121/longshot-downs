import bpy, sys, collections

argv = sys.argv[sys.argv.index("--") + 1:]
in_path, out_path = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=in_path)

armature = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
mesh = [o for o in bpy.data.objects if o.type == 'MESH'][0]
mw = mesh.matrix_world

print(f"before reweld: verts={len(mesh.data.vertices)}")

# The exported/re-imported glTF splits every vertex at UV seams (glTF's flat
# vertex-buffer format requires a unique vertex per unique attribute combo) -
# that's normal/expected for the FILE, but it means mesh.data.edges in this
# re-imported copy under-represents true 3D adjacency (a seam boundary looks
# "disconnected" in index-space even though both sides touch in real space).
# Re-weld by actual position (not just edge index) before doing any
# connectivity-based analysis, since weights were computed on the original
# well-connected mesh before export - seam-duplicate copies should carry
# identical weight data already, so this merge is safe.
bpy.context.view_layer.objects.active = mesh
mesh.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.001)
bpy.ops.object.mode_set(mode='OBJECT')
print(f"after reweld: verts={len(mesh.data.vertices)}")

bones = {}
for b in armature.data.bones:
    bones[b.name] = (armature.matrix_world @ b.head_local, armature.matrix_world @ b.tail_local)
tail_tip_pos = bones['Tail7'][1]

vg_by_index = {vg.index: vg.name for vg in mesh.vertex_groups}
name_to_vg = {vg.name: vg for vg in mesh.vertex_groups}

has_tail_weight = {}
for v in mesh.data.vertices:
    groups = {vg_by_index[g.group]: g.weight for g in v.groups}
    tw = sum(w for n, w in groups.items() if 'tail' in n.lower())
    has_tail_weight[v.index] = tw > 1e-6
print(f"has_tail_weight count={sum(has_tail_weight.values())}")

adjacency = collections.defaultdict(set)
for e in mesh.data.edges:
    a, b = e.vertices
    if has_tail_weight.get(a) and has_tail_weight.get(b):
        adjacency[a].add(b)
        adjacency[b].add(a)

candidates = [v for v in mesh.data.vertices if has_tail_weight.get(v.index)]
seed = min(candidates, key=lambda v: (mw @ v.co - tail_tip_pos).length)
print(f"seed vert={seed.index} dist_to_tip={(mw @ seed.co - tail_tip_pos).length:.4f}")

visited = {seed.index}
queue = collections.deque([seed.index])
while queue:
    cur = queue.popleft()
    for nxt in adjacency[cur]:
        if nxt not in visited:
            visited.add(nxt)
            queue.append(nxt)

print(f"true_tail_component_size={len(visited)} / total_has_any_tail_weight={sum(has_tail_weight.values())}")

reassigned = 0
for idx in visited:
    v = mesh.data.vertices[idx]
    groups = {vg_by_index[g.group]: g.weight for g in v.groups}
    tail_weights = {n: w for n, w in groups.items() if 'tail' in n.lower()}
    total = sum(tail_weights.values())
    if total <= 1e-6:
        continue
    for g in list(v.groups):
        name_to_vg[vg_by_index[g.group]].remove([v.index])
    for n, w in tail_weights.items():
        name_to_vg[n].add([v.index], w / total, 'REPLACE')
    reassigned += 1
print(f"reassigned={reassigned}")

bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    export_animations=True,
    export_force_sampling=True,
)
print("DONE_FIX_TAIL3")
