"""int_map_components: weakly-connected components of each map's walkable graph.

Reads int_map_pathfinding edges and labels every walkable tile with a
`subregion_id` (0-based, stable per map) and the `component_size` of its region.
Tiles in different sub-regions cannot be reached from one another on foot -- this
is what lets consumers tell an intentional split map (e.g. ROUTE_2's north/south
halves, joined only via Viridian Forest) from a genuine data hole, and quiet the
"no path" warnings for the former.

Caveat: components are *undirected* (weakly connected). One-way ledge drops are
treated as ordinary connectivity, so a ledge-isolated tile is merged with the
tile that can drop onto it. Good enough as a "same physical region" proxy; the
warp-reachability test guards the cases that actually break navigation.
"""


def model(dbt, session):
    dbt.config(materialized="table")
    import pandas as pd

    edges = dbt.ref("int_map_pathfinding").df()

    out_rows = []
    for map_name, g in edges.groupby("map_name", sort=True):
        parent: dict[tuple[int, int], tuple[int, int]] = {}

        def find(n):
            root = n
            while parent[root] != root:
                root = parent[root]
            while parent[n] != root:  # path compression
                parent[n], n = root, parent[n]
            return root

        def union(a, b):
            parent.setdefault(a, a)
            parent.setdefault(b, b)
            ra, rb = find(a), find(b)
            if ra != rb:
                parent[ra] = rb

        for fx, fy, tx, ty in zip(g["from_x"], g["from_y"], g["to_x"], g["to_y"]):
            union((int(fx), int(fy)), (int(tx), int(ty)))

        members: dict[tuple[int, int], list] = {}
        for node in parent:
            members.setdefault(find(node), []).append(node)

        # stable ids: order components by their smallest tile
        for sub_id, nodes in enumerate(
            sorted(members.values(), key=min)
        ):
            size = len(nodes)
            for x, y in nodes:
                out_rows.append((map_name, x, y, sub_id, size))

    return pd.DataFrame(
        out_rows, columns=["map_name", "x", "y", "subregion_id", "component_size"]
    )
