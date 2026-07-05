-- mart_map_routes: map-to-map next-hop shortest-path closure over int_map_connections.
--
-- One row per reachable (from_map, to_map): the immediate next map to head for
-- (next_hop), the shortest number of map transitions (hop_count), and how to make
-- that first transition (next_hop_instruction). Replaces the agent's Python
-- bfs_map_route / cached connection graph with a single filtered read:
--   SELECT next_hop, hop_count FROM marts.mart_map_routes
--   WHERE from_map = ? AND to_map = ?
-- and, for "nearest map matching a predicate", filter to_map and take MIN(hop_count).
--
-- ponytail: the recursive closure carries only (origin, dest, hop_count) and uses
-- UNION (dedup) + a hop cap so it terminates on the cyclic 220-node map graph.
-- Default cap 25 clears the current graph diameter (24); raise map_route_max_hops
-- if the modelled map ever grows past that.

{% set max_hops = var('map_route_max_hops', 25) %}

WITH RECURSIVE edges AS (
    SELECT DISTINCT from_map, to_map
    FROM {{ ref('int_map_connections') }}
    WHERE from_map IS NOT NULL
      AND to_map IS NOT NULL
      AND from_map <> to_map
),

-- All-pairs reachability with hop counts. UNION (not UNION ALL) dedups identical
-- (origin, dest, hop_count) rows, so the walk stays bounded and terminates at the cap.
reachable(origin, dest, hop_count) AS (
    SELECT from_map, to_map, 1
    FROM edges
    UNION
    SELECT r.origin, e.to_map, r.hop_count + 1
    FROM reachable r
    JOIN edges e ON e.from_map = r.dest
    WHERE r.hop_count < {{ max_hops }}
      AND e.to_map <> r.origin
),

-- Shortest hop count per ordered pair.
dist AS (
    SELECT origin, dest, MIN(hop_count) AS hop_count
    FROM reachable
    GROUP BY origin, dest
),

-- next_hop candidates: a neighbour of origin that lies on a shortest path to dest,
-- i.e. the destination itself (1 hop) or a neighbour that is one hop closer.
candidates AS (
    SELECT
        d.origin,
        d.dest,
        d.hop_count,
        e.to_map AS next_hop
    FROM dist d
    JOIN edges e ON e.from_map = d.origin
    LEFT JOIN dist nd ON nd.origin = e.to_map AND nd.dest = d.dest
    WHERE (e.to_map = d.dest)                -- direct neighbour is the destination
       OR (nd.hop_count + 1 = d.hop_count)   -- neighbour is one hop closer to dest
),

ranked AS (
    SELECT
        origin AS from_map,
        dest AS to_map,
        next_hop,
        hop_count,
        -- deterministic pick when several shortest paths leave origin differently
        ROW_NUMBER() OVER (PARTITION BY origin, dest ORDER BY next_hop) AS rn
    FROM candidates
),

-- One representative navigation instruction for the first hop. A pair of maps can be
-- joined by several warps; take the lowest-id warp for a stable single instruction.
first_hop_instruction AS (
    SELECT from_map, to_map, navigation_instruction
    FROM (
        SELECT
            from_map,
            to_map,
            navigation_instruction,
            ROW_NUMBER() OVER (PARTITION BY from_map, to_map ORDER BY id) AS rn
        FROM {{ ref('int_map_connections') }}
    )
    WHERE rn = 1
)

SELECT
    r.from_map || ' -> ' || r.to_map AS route_key,
    r.from_map,
    r.to_map,
    r.next_hop,
    r.hop_count,
    fhi.navigation_instruction AS next_hop_instruction
FROM ranked r
LEFT JOIN first_hop_instruction fhi
    ON fhi.from_map = r.from_map
   AND fhi.to_map = r.next_hop
WHERE r.rn = 1
ORDER BY r.from_map, r.hop_count, r.to_map
