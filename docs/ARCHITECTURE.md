# 4D runtime and sandbox architecture

The runtime is `scripts/core/`. It requires Godot types, but no scene tree, controls, files, catalog, camera, renderer, or sandbox. The sandbox and a future game are separate clients of this API.

## Dependency direction

```text
Sandbox UI / game logic → Session4D (composition + history invalidation)
                         ├─ Scene4D → tracks / geometry / math
                         ├─ PhysicsWorld4D → body state / integrator / collision backend
                         ├─ Recording(runtime=physics) → reset/step/snapshot/restore
                         └─ Playback clock

Scene-side PhysicsBinding4D maps physics matrices into scene-local overrides.
Physics imports no scene, session, animation, playback, IO, UI or rendering code.
Recording imports no physics code; its runtime is injected.
IO → in-memory geometry/settings → Session
Session world state → projection/rendering adapter → Godot meshes
```

Only `core/` may be imported by core scripts. IO and rendering can import core; they cannot import sandbox. Sandbox composes all three layers. Compatibility scripts at older paths forward to the canonical implementations; they contain no second implementation and are not required by core.

## Canonical directories

| Directory | Responsibilities |
| --- | --- |
| `core/math` | 5×5 homogeneous matrices, PRSA, 3×4 projection utility |
| `core/geometry` | Vertex/edge/face data and procedural generators |
| `core/animation` | Restricted scalar expressions and transform tracks |
| `core/scene` | Stable IDs, implicit group/geometry pairs, transforms, parenting, physics-to-scene adapter |
| `core/physics` | Physics world API, body lifecycle/state layout, integration, replaceable collision backend |
| `core/simulation` | Legacy import alias only; no implementation |
| `core/playback` | Fixed-step recording, restoration, seeking, playback clock |
| `core/session_4d.gd` | Public mutation/evaluation API and history invalidation |
| `io` | JSON loading, folder discovery, built-in face asset loading |
| `rendering` | Presentation projection expressions and Godot mesh renderers |
| `sandbox` | App tabs, Playground, inspector drafts, tree controls, timeline widget, camera input |

## Minimal use without UI, files, or renderer

```gdscript
const Session = preload("res://scripts/core/session_4d.gd")
const Geometry = preload("res://scripts/core/geometry/geometry_4d.gd")

var runtime = Session.new()
var geometry = Geometry.new()
geometry.vertices = [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0)]
geometry.edges = [Vector2i(0, 1)]

var parent = runtime.add_geometry(geometry)
var child = runtime.add_geometry(geometry)
runtime.reparent(child, parent, true)

var expressions = runtime.scene.objects[parent].group.sources.duplicate()
expressions["angles.2"] = "30*t" # XW; degrees
runtime.set_group_expressions(parent, expressions)
runtime.seek(2.0)
var vertices_4d = runtime.world_vertices(child)
```

`add_geometry` copies geometry, so instances do not share mutable vertex arrays. Its optional initial geometry/group dictionaries use the same component structure accepted by custom assets, but require no JSON parsing. Position and anchor initialize literally. Objects own a group track and geometry track; geometry tracks affect only their own leaf.

Object IDs returned by `add_geometry` identify groups. Leaf IDs in `scene.objects[id].leaf_id` are implementation details used by adapters. Inspect `scene.objects`, `scene.entries`, and tracks as read-only data; change them through Session methods so recording invalidation is respected. Direct low-level graph operations are available for testing and advanced use, but bypass that policy.

## Runtime API

- `add_geometry(geometry, geometry_settings={}, group_settings={}) -> int`: returns 0 on invalid settings.
- `set_geometry_expressions(id, expressions, keep_anchor=true)` and `set_group_expressions(...)`: commit atomically, compensating edited anchors when requested. Expression dictionaries use track keys such as `position.0`, `scale.3`, and `angles.2`. Missing keys retain their values; unrelated keys are ignored.
- `reparent(id, parent_id, keep_world=true)`: World is ID 0. Prevents cycles and invalid parents; keep-world uses a constant matrix offset.
- `remove_object(id)`: removes its pair and promotes child objects, retaining their current 4D world pose.
- `replace_geometry(id, geometry)`: replaces an object's geometry and invalidates history. Caller supplies the replacement data.
- `make_dynamic(id, position, velocity)` / `make_procedural(id)`: change group motion source. Dynamic matrices replace the group's procedural local transform in its parent frame. Geometry tracks still apply afterward.
- `seek(time)`: synchronous snap-to-step evaluation/restoration; returns false on invalid state.
- `request_seek(time)` / `advance_seek(budget=120)`: bounded seeking for interactive hosts.
- `play(direction=1)`, `pause()`, `advance(delta)`: UI-independent playback. A game calls `advance` from its update loop.
- `set_range(start,end)`: validates range, resets on Start changes, trims or extends on End changes.
- `cancel_seek()`: stops pending work and restores the displayed simulation state.
- `world_vertices(id)`: obtains 4D vertices from the last evaluated world state.

`state_changed(time)` notifies adapters of a valid new state. `scene_changed` notifies clients of structural changes. `error` describes failures. `state` contains world matrices, never meshes or projected positions.

## Evaluation and recording

1. Sample local procedural tracks or obtain local dynamic-body matrices.
2. Compose parent world × parenting offset × local matrix in 4D.
3. Record only dynamic body state at fixed 1/60-second steps.
4. Restore a recorded step when scrubbing/reversing; extend from the latest recorded step when needed.
5. Transform vertices only on demand. Presentation adapters project these positions and create meshes.

Simulation validation does not project geometry and cannot be invalidated by a rendering expression. Projection failures are presentation errors: the sandbox pauses and retains the last rendered geometry. Projection settings and appearance never enter recorded physics state.

The packed dynamic state contains position (4), velocity (4), orientation matrix (16), and angular velocity (6, degrees/sec). Dynamic groups are now wired into scene evaluation. Physics body controls and read-only collision queries are available; there are no forces, gravity, or collision response yet. Snapshot dictionaries are adequate for this sandbox; this is not a production physics engine.

## Sandbox adapters

`procedural_scene.gd` creates controls, translates UI actions to Session operations, owns selection and renderer instances, and presents errors. Its `pairs` dictionary maps existing runtime IDs to editor widgets; it does not own the actual runtime pairs. Deleting a widget is not a runtime deletion.

`object_view_model.gd` binds a core track/geometry to appearance and a presentation projection track. Draft strings stay in `object_card.gd`. `timeline.gd` displays fields and forwards actions; playback arithmetic is in `core/playback/playback_4d.gd`.

Playground remains a separate manual editor using the same core math and geometry generators. Undo/redo and vertex selection are editor responsibilities under `sandbox/playground`.

## Packaging and checks

Copy `scripts/core/` into another Godot project at the same path to use the runtime. It has no dependency on `data/`, `scenes/`, or any other scripts. Relocating it to an addon path currently requires updating its `res://scripts/core/...` imports; addon manifests and editor registration are not part of this refactor.

- `tests/verify_core.gd`: in-memory creation, expression scopes, parenting, simulation-to-scene mapping, replay and deletion.
- `tools/verify_core_isolation.py GODOT_BINARY`: checks dependency boundaries, copies only core and its test into a temporary minimal Godot project, and runs it there.
- Existing Playground, transform, hierarchy, custom-shape, recording, resolution, and procedural suites cover sandbox regressions.

## Convex collision queries

`core/physics/collision/convex_vertices_4d.gd` transforms a vertex cloud into a query-local convex support map. Its convex hull is the collider: edges, faces, projection, and render visibility do not affect collision. Concave geometry requires convex decomposition before this query can describe its actual occupied region.

`core/physics/collision/simplex_4d.gd` finds the closest point on a simplex of up to five vertices by examining its features and solving affine closest points with QR. `core/physics/collision/gjk_4d.gd` uses that solver for distance GJK in R4. Intermediate support points and arithmetic use packed doubles.

Call `session.query_collision(a_id, b_id)` with two public object IDs to query their current world geometry transforms, including parenting. This is read-only and does not change playback or recording. The standalone GJK API also accepts support providers exposing `valid`, `center`, `radius`, and `support(direction)`. It needs no UI, renderer, or IO.

Results are `separated`, `intersecting` (including contact within tolerance), or `indeterminate`. Separated results contain distance bounds, witness points, a separating direction, and intervals on that direction. A certified gap can establish separation even if the distance iteration stalls. `converged` describes distance convergence, not whether a separating certificate exists. Simplex difference points are normalized by the returned `simplex_scale`; their original support witnesses are retained. These are internal GJK results consumed by the default collision adapter and EPA; session queries expose only the standardized backend contract.

Tolerance is `1e-7 + 1e-6 * max(radius_a + radius_b, 1e-12)`. Near contact is deliberately approximate. Empty/nonfinite input, exhausted iterations without a certificate, or numerical failure can return indeterminate. This implementation provides no broad phase, continuous collision detection, penetration depth, contact manifold, or response.

The sandbox's collapsible collision inspector chooses two objects, displays the result and separating intervals, and applies a temporary edge highlight. Tests cover analytic box/sphere distances, W-only separation, containment, degeneracy, symmetry, common rotations, scale, and inspector integration.

### EPA penetration query

`core/physics/collision/epa_4d.gd` estimates penetration after a GJK `intersecting` result. Call `session.query_collision(a_id, b_id, true)` to add a `penetration` dictionary to that result. The default query remains GJK-only. GJK status is preserved when EPA cannot resolve penetration.

EPA reuses GJK witnesses, samples additional supports to seed a full-dimensional hull, and expands tetrahedral boundary facets through triangular horizons. Facet orientation uses a fixed interior point; expansion is transactional and verifies that each ridge belongs to two facets. The nearest boundary plane and its support plane bound depth. Coplanar tetrahedra are searched for barycentric witness recovery. Arithmetic is normalized by collider radii and uses packed doubles.

Successful results contain `status` (`penetrating` or `touching` within tolerance), depth bounds, unit `direction`, `translation_b`, world-space witnesses `point_a`/`point_b`, tolerance and iteration count. Direction points outward from A−B: adding `translation_b = direction * depth` to B estimates contact with A fixed. It is not a velocity, impulse, force, or contact manifold. At convergence, `point_a - point_b` approximately equals this translation. Nonunique minimum directions can differ between equivalent queries.

Lower-dimensional differences, hull degeneracy, duplicate support without convergence, or iteration/facet budgets return explicit `indeterminate` with no usable translation. The query is bounded at 192 expansion iterations / 4096 facets; smooth or difficult shapes can remain unresolved. Initialization work is additional to the displayed EPA iteration count. This remains experimental floating-point geometry, not a guarantee for every convex input.

The sandbox exposes an opt-in **Estimate penetration** checkbox. It reports results without modifying simulation state or applying response. Validation includes analytic box depths, containment, contact, common 4D rotations, independent XW rotations against SAT, witness consistency, swapped order, scale, and translating past the estimated contact depth.

### Replaceable backend boundary

Production callers now depend only on `core/physics/collision/collision_backend.gd`, not GJK or EPA. The entry receives local geometry plus evaluated world matrices and returns a standardized result. The session's `query_collision` API is unchanged; `session.collision_backend` optionally selects a different compatible script. The inspector checks optional measurements before displaying them and supports detection-only backends. Algorithm details remain inside the default adapter and optional diagnostics.

**The general collision backend can be exchanged for other collision checks that fit the specified output structure.** See [COLLISION_BACKEND.md](COLLISION_BACKEND.md) for the complete input/output contract, field types, unavailable-result conventions, direction semantics, and literal file-replacement instructions. Existing descriptions above of GJK/EPA internals apply to the default implementation only; their raw result dictionaries are no longer exposed by the session. In particular, simplex internals stay private and iteration counts live under `diagnostics`.

### Custom-shape export

`io/shape_json_exporter.gd` serializes supplied in-memory geometry plus committed geometry/group/projection source dictionaries into the existing `hi_4d.json` schema, then writes JSON. It has no sandbox dependencies and does not bake world transforms. The procedural controller owns the save dialog, checks for unapplied editor fields, and snapshots the selected shape before opening the dialog. Existing discovery and loading require no changes. `tests/verify_shape_export.gd` verifies edited geometry/topology and every transform/projection expression through the real loader; the procedural suite verifies both default tabs and subsequent tab closing/creation.

### Physics solid-view workspace

`physics/physics_scene.gd` specializes the existing sandbox controller with numeric mode, preserving shared selection/hierarchy/export behavior. Numeric input is checked before committing, imported defaults and compensated anchor expressions are frozen at t=0, and the procedural timeline is disabled. Procedural mode remains expression-based. Physics has its own translation-only Run/Pause/Reset controls, described below.

`rendering/projected_hull_3d.gd` computes an incremental 3D convex hull after scale normalization/deduplication, with planar monotone-chain and line/point fallbacks. `solid_hull_renderer.gd` caches unchanged projected vertices, renders only exterior triangles with flat normals and opaque material, and removes coplanar triangulation diagonals from edge overlays. Physics picking uses this hull rather than source wire faces. These display operations never alter the source 4D vertices, collider, or transform state. Hull tolerances approximate nearly degenerate projections; a fallback label reports lower dimension.

`verify_physics.gd` checks cube volume, closed hulls and vertex containment for built-in shapes, dimensional fallbacks, opaque material, numeric validation, custom animation freezing and numeric anchor compensation. The shared tab tests include the new persistent Physics tab.

### Body types and translation-only motion

`PhysicsWorld4D.body_types` chooses static (restore initial state), kinematic (prescribed initial velocity each step), or dynamic (integrate current simulated velocity). Configuration is separate from packed recorded state; changing configuration invalidates history. Existing `make_dynamic` API semantics are preserved.

`Session.configure_body(id, type, initial_velocity)` stores validated settings and registers a zero-displacement body. The scene-side `PhysicsBinding4D` composes that displacement with the initial group PRSA, compensating the fixed parenting offset so velocity is in world axes for root bodies. Geometry PRSA remains intact. `start_body_motion` refuses parented Physics bodies; queries still work while paused. Removal and `make_procedural` clean up body metadata. Legacy procedural sessions do not assign body types automatically.

Physics UI owns controls only; `session.advance(delta)` drives the existing bounded fixed-step recording system. Numeric starting edits invalidate/reset motion; run-time pose and velocity live in recorded simulation state. The UI blocks edit commits during playback and checks pending drafts before starting. No collision backend is invoked by integration. Reset and backward/forward seeking reproduce recorded poses. Initial angular velocity is zero, so this UI stage has no angular dynamics.

`verify_body_motion.gd` covers immovable static bodies, constant motion in all four axes, initial geometry/group transform preservation, prescribed vs simulated velocity ownership, deterministic replay/reset, root-only run validation, metadata removal, fractional velocity input, and Physics Run/Pause/Reset integration.

## Physics module boundary

The canonical implementation is now:

```text
core/physics/
  physics_world_4d.gd       body lifecycle, reset/step/snapshot/restore, matrices, backend dispatch
  body_4d.gd                body types, packed state layout, initial state and matrix conversion
  integrator_4d.gd          one body's motion law for one timestep
  collision/
    collision_backend.gd   replaceable query entry (same output contract)
    convex_vertices_4d.gd
    gjk_4d.gd
    simplex_4d.gd
    epa_4d.gd
```

No contact solver file exists yet: there is no collision response or acceleration in this refactor. The integrator does not call detection. Collision queries can also be used independently of a physics world.

`Session.physics` owns the runtime instance. Session's existing body APIs delegate to it and handle recording invalidation; its `motion_settings` and `collision_backend` properties forward to physics for compatibility. The session does not index packed body state or implement integration. The scene adapter owns only hierarchy/PRSA conversion and the current World-only run restriction; those concepts do not leak into physics.

`core/playback/simulation_recording.gd` now takes a runtime in its constructor: `Recording.new(physics)`. Any compatible runtime can supply `reset()`, `step(dt)`, `snapshot() -> Dictionary`, and `restore(snapshot)`. Snapshots must own their mutable state; body configuration changes require recording reset. The recorder treats payload dictionaries as opaque. The old `scripts/procedural/simulation_recording.gd` keeps its legacy no-argument default via a thin compatibility wrapper. The old core simulation path also forwards to PhysicsWorld4D; it contains no physics logic.

See [PHYSICS.md](PHYSICS.md) for standalone usage. `tools/verify_physics_isolation.py GODOT_BINARY` enforces allowed imports and runs physics with only physics/math installed, then runs the recorder with only playback installed and a non-physics test runtime. The complete core isolation test and the literal collision-backend replacement test remain in place.
