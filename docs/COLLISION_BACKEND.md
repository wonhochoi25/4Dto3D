# Replaceable collision backend contract

Collision detection is behind a general backend. **You can exchange the default backend for other collision checks that implement the input and output structure below, without changing the session, inspector, transforms, playback, or rendering.** GJK and EPA are the default implementation, not a requirement of the interface.

## Replace the backend

Replace `scripts/core/physics/collision/collision_backend.gd` with a GDScript exposing:

```gdscript
extends RefCounted

static func query(a: Dictionary, b: Dictionary, options: Dictionary = {}) -> Dictionary:
    # Perform your collision check here.
    return {"status": "indeterminate", "reason": "Unsupported geometry"}
```

Keep that entry path and signature. Replacement implementations can bring their own helper files; they do not need GJK, EPA, a support map, or a simplex. Reload/restart the Godot project after replacing scripts. Alternatively, assign a compatible script to `session.collision_backend` at runtime (per session). There is no global backend registry or UI selector.

The backend must be read-only, deterministic for the same inputs, and bounded in execution. It must not access UI, rendering, IO, or mutate geometry/matrices. Unsupported geometry or numerical failure returns `indeterminate`, not a guessed negative or positive. The interface does not make every algorithm support every shape: an oriented-box backend must explicitly reject geometry it cannot handle. No physics response is performed by a query.

## Input

Both `a` and `b` contain:

| Key | Type | Meaning |
| --- | --- | --- |
| `geometry` | core Geometry4D object | Local `vertices: Array[Vector4]`, `edges: Array[Vector2i]`, `faces: Array`, and other geometry metadata. Topology may be empty. |
| `world` | `PackedFloat64Array` of length 25 | Row-major homogeneous 5×5 local-to-world matrix, already including parent/group and geometry transforms. Translation is at indices 4, 9, 14, 19. |

The session lends these references read-only. Copy before modifying. There is no display projection in the collision input. A backend can transform vertices, inspect topology, or construct its own collider. The default uses convex hulls of transformed vertices, ignoring edges/faces.

`options.include_penetration: bool` defaults to false. It requests an optional penetration estimate; detection-only backends may ignore it. Ignore unknown options to allow future additions.

## Required output

Return a `Dictionary` with:

| Key | Type | Meaning |
| --- | --- | --- |
| `status` | String | Exactly `separated`, `intersecting`, or `indeterminate`. Intersecting includes contact within the backend's tolerance. |
| `reason` | String | Human-readable explanation, including failure/unsupported reasons. |

A dictionary with only these two fields is valid. **Omit unavailable optional fields; do not fill them with zero, empty placeholders, or null.** Callers must check for their presence. All reported numerical values must be finite. Result dictionaries and values must not alias mutable backend scratch state across queries.

## Optional separation measurements

| Key | Type | Meaning |
| --- | --- | --- |
| `distance` | float ≥ 0 | Upper estimate of shortest Euclidean 4D distance. |
| `distance_lower` | float ≥ 0 | Lower bound; include only with `distance`, and ≤ distance. |
| `direction` | `PackedFloat64Array`, 4 values | Unit separating axis oriented so B's interval follows A's. |
| `intervals` | Array of two Vector2 values | A and B min/max scalar coordinates on `direction`; requires `direction` and `interval_origin`. |
| `interval_origin` | `PackedFloat64Array`, 4 values | Reference point: scalar coordinate is `(world_point − interval_origin) dot direction`. |
| `gap` | float | `intervals[1].x − intervals[0].y`; requires intervals. |
| `point_a`, `point_b` | `PackedFloat64Array`, 4 values each | World-space witness points, supplied together. |
| `tolerance` | float ≥ 0 | World-space numerical/contact tolerance used by this query. |

Distance, intervals, and penetration are independently optional. The inspector hides unavailable measurements. Witness points/tolerance may also be supplied for an intersecting result.

## Optional penetration result

On an `intersecting` result, `penetration` may contain:

- Required `status`: `penetrating`, `touching`, `indeterminate`, or `unavailable`.
- Required `reason`: explanatory String.
- Optional `converged: bool` (defaults false for consumers).
- Optional `depth: float ≥ 0`: estimated minimum translation magnitude to contact.
- Optional `depth_lower` and `depth_upper`: ordered nonnegative bounds, supplied together.
- Optional `direction`: unit 4D `PackedFloat64Array`, pointing in the direction B should translate with A fixed.
- Optional `translation_b`: 4D `PackedFloat64Array`, `direction * depth`; requires direction/depth.
- Optional `point_a`, `point_b`: world-space witnesses supplied together. For a converged estimate their difference approximately equals `translation_b` when it is supplied.
- Optional `tolerance`: nonnegative world-space tolerance.

Only report usable penetration measurements when `converged` is true. Unresolved results retain the outer detection status. An omitted penetration result means no estimate is available, even if requested. Zero depth is actual touching within tolerance, never an unavailable estimate. Translation is a geometric estimate, not an impulse or velocity, and the optional core overlap solver applies it only to dynamic positions. Minimum directions can be nonunique.

## Optional diagnostics

`diagnostics: Dictionary` is informational. Recognized UI fields are `backend: String`, `detection_iterations: int`, and `penetration_iterations: int`. The UI tolerates their absence. Algorithms may add other diagnostic keys; callers must not require them for collision behavior. GJK simplex internals are intentionally excluded from the public contract.

## Default implementation and verification

The default entry adapts GJK + optional EPA to this contract. It uses `convex_vertices_4d.gd`, `gjk_4d.gd`, `simplex_4d.gd`, and `epa_4d.gd` internally. These can be removed if a replacement no longer imports them. Tests dedicated to GJK/EPA naturally still need those algorithms; production session and inspector do not.

Run `tests/verify_collision_backend.gd` for minimal-result, optional-field, read-only, and backend-injection coverage. Run:

```sh
python3 tools/verify_collision_backend_swap.py /Applications/Godot.app/Contents/MacOS/Godot
```

This copies the project to a temporary directory, replaces only the backend entry with a detection-result test double, removes the GJK/EPA/support/simplex files from that copy, and exercises the session and inspector. The double checks plumbing, not physical collision correctness. A new real backend needs its own mathematical correctness tests in addition to this contract integration test.


Angular response consumes finite world-space `point_a`/`point_b` witnesses when
available, using their midpoint as a shared contact location. Missing or invalid
witnesses fall back to linear response; backends remain valid without them. No
algorithm-specific simplex or EPA internals are consumed by the response solver.
