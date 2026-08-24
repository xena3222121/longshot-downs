import bpy, sys, collections

argv = sys.argv[sys.argv.index("--") + 1:]
in_path = argv[0]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=in_path)

mesh = [o for o in bpy.data.objects if o.type == 'MESH'][0]
vg_by_index = {vg.index: vg.name for vg in mesh.vertex_groups}

has_tail_weight = set()
for v in mesh.data.vertices:
    groups = {vg_by_index[g.group]: g.weight for g in v.groups}
    tw = sum(w for n, w in groups.items() if 'tail' in n.lower())
    if tw > 1e-6:
        has_tail_weight.add(v.index)

# full mesh adjacency (all edges)
adjacency = collections.defaultdict(set)
for e in mesh.data.edges:
    a, b = e.vertices
    adjacency[a].add(b)
    adjacency[b].add(a)

# connected components WITHIN has_tail_weight, using ONLY edges where both ends are in the set
remaining = set(has_tail_weight)
components = []
while remaining:
    seed = next(iter(remaining))
    comp = {seed}
    queue = collections.deque([seed])
    remaining.discard(seed)
    while queue:
        cur = queue.popleft()
        for nxt in adjacency[cur]:
            if nxt in remaining:
                remaining.discard(nxt)
                comp.add(nxt)
                queue.append(nxt)
    components.append(comp)

components.sort(key=len, reverse=True)
print(f"num_components={len(components)} sizes_top10={[len(c) for c in components[:10]]} total={sum(len(c) for c in components)}")

# is the mesh globally connected at all (ignoring the tail-weight mask)? check largest overall component size vs total vert count
remaining2 = set(range(len(mesh.data.vertices)))
seed2 = next(iter(remaining2))
comp2 = {seed2}
queue2 = collections.deque([seed2])
remaining2.discard(seed2)
while queue2:
    cur = queue2.popleft()
    for nxt in adjacency[cur]:
        if nxt in remaining2:
            remaining2.discard(nxt)
            comp2.add(nxt)
            queue2.append(nxt)
print(f"whole_mesh_main_component_size={len(comp2)} / total_verts={len(mesh.data.vertices)}")
print("DONE_DIAG_TAIL3")
