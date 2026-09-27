# Core physics module

Physics is a separate module **inside the core engine**, independent of the sandbox. It can run without Session, scene graphs, expression tracks, playback, Godot nodes, IO or rendering. Current imports require the original `res://scripts/core/...` layout and Godot built-in types.

## Standalone use

```gdscript
const Physics = preload("res://scripts/core/physics/physics_world_4d.gd")
var physics = Physics.new()
physics.configure_body(1, "dynamic", Vector4(1, 0, 0, 2))
physics.step(1.0 / 60.0)
var matrices = physics.matrices()
var saved = physics.snapshot()
physics.step(1.0 / 60.0)
physics.restore(saved)
physics.reset()
physics.remove_body(1)
```

The caller owns body IDs and determines when to step. `configure_body` starts the body at zero displacement with the requested type/velocity. Its matrices are motion offsets. In the sandbox the scene adapter combines them with edited starting transforms. `add_body(id, position, velocity, type="dynamic")` is the lower-level/legacy API for absolute local initial positions. Reconfiguration requires invalidating any external recording; Session handles this automatically.

- Static restores its initial state on each step.
- Kinematic derives linear and angular rates from initial velocity plus constant acceleration × elapsed time.
- Dynamic integrates its current simulated linear and angular velocities using constant acceleration.
- The Physics UI exposes four-component linear velocity/acceleration and six-plane angular velocity/acceleration.
- Forces, torque, inertia, automatic gravity and collision response are not implemented.

`body_4d.gd` owns the packed layout (41 doubles); callers outside physics should use `matrices()` for poses and `snapshot/restore` for history. Public state dictionaries remain available for existing tests/low-level integrations, but must not be modified while using a cached recording. Snapshots contain state only; type/initial settings belong to configuration and are changed through lifecycle APIs. Collision geometry is passed to queries, not stored in body snapshots.

## Collision backend

`physics.query_collision(a, b, options)` delegates to `physics.collision_backend`. Inputs and outputs follow [COLLISION_BACKEND.md](COLLISION_BACKEND.md). The entry file is now `core/physics/collision/collision_backend.gd`; replacing it or assigning a compatible script changes detection without changing integration. Stepping never calls the backend in this version. The backend can be called directly without constructing PhysicsWorld4D.

## What stays outside physics

- `core/scene/physics_binding_4d.gd`: maps body matrices through parenting offsets and initial PRSA; validates scene-specific run constraints.
- `core/playback`: clock and an injected-runtime recorder. `Recording.new(physics)` uses only reset/step/snapshot/restore. It contains no body types, packed-state indexing, or physics import.
- `core/session_4d.gd`: coordinates scene mutations, physics lifecycle calls, history invalidation and render-facing state notifications.
- `sandbox/physics`: controls and input validation.
- `rendering`: projection and solid hull appearance.

## Verification

`tools/verify_physics_isolation.py GODOT_BINARY` copies only physics and math into a clean project and tests body lifecycle, motion, matrices, snapshots, and collision/EPA. A second clean project contains only playback, verifying recording with a non-physics counter runtime. This also checks import boundaries so future changes cannot silently couple physics back to the scene or recorder.

The existing motion/recording/scene/UI tests verify behavioral compatibility. `tools/verify_collision_backend_swap.py GODOT_BINARY` still verifies literal replacement of the collision entry with GJK/EPA files absent.

### Update and state ownership

Both sandbox modes advance through `Session4D.advance(delta)` once per display
frame. The timeline only edits/displays playback controls. Playback requests time;
the generic recorder advances its injected runtime in fixed steps. Only the physics
world invokes the body integrator. There is no second motion loop in the UI.

Physics owns mutable current body state. Recorded snapshots remain independent
copies, so scrubbing cannot mutate history. Consecutive forward steps use current
state directly; restore is needed when switching to a recorded frame, extending a
history tail after rewinding, or returning from a partial/failed seek. Trimming the
range also restores the clamped current frame. Do not mutate the runtime directly
while a recording is active; change configuration through the session and invalidate.

The scene-side physics binding caches inverse parenting offsets and starting group
poses. `session.invalidate()` clears this cache along with history after edits.
Low-level callers that edit scene tracks, offsets, body modes or start time directly
must invalidate before continuing. Physics itself knows nothing about this cache.
The adapter fills its existing matrix dictionary without an intermediate dictionary.
The session reuses the final validated scene sample for display on newly simulated
steps; replay still samples the restored scene. Zero angular velocity skips rotation
matrix construction, while nonzero angular velocity retains the existing integrator.

`tests/verify_motion_pipeline.gd` checks continuous stepping, rewind/extension,
partial seeks, failed-step recovery, trimming and scene-sample counts.
`tools/benchmark_motion.gd` measures three runs of 24 translating tesseracts over
600 fixed steps, excluding setup. It is a comparison tool, not a timing assertion.

Cleanup benchmark (2026-09-27, Godot 4.7, headless, same machine): median of
three runs was 3762 ms before and 1741 ms after for that workload (about 54% less
elapsed time). This measures simulation plus scene evaluation, not rendering FPS.


### Constant acceleration and angular motion

`configure_body(id, type, velocity, motion={})` accepts optional `acceleration`
(Vector4), `angular_velocity` and `angular_acceleration` (six finite numbers each).
Omitted fields are zero; existing three-argument calls remain valid. Plane order is
XY, XZ, XW, YZ, YW, ZW. Angular units are degrees/second and degrees/second²;
linear units are world units/second and world units/second².

At each fixed step, semi-implicit Euler updates velocity before applying displacement.
Kinematic rates are recomputed from initial rates and recorded elapsed time; dynamic
rates accumulate acceleration on their current values. This is a discrete integrator,
so accelerated displacement approximates the continuous-time formula. Static bodies
ignore all rates. Reset restores the initial pose and rates. Apply while paused resets
history; uncommitted fields prevent Run.

Angular increments left-multiply orientation in fixed world planes (sandbox motion
requires World-parented bodies). Multiple plane increments retain the ordered plane
composition used by the existing integrator, a finite-step approximation to simultaneous
angular motion. Rotation is about the motion frame origin; a center-of-mass model is
not implemented. The underlying scene adapter still combines this motion with the
starting group pose. Geometry/group transform editors remain separate.

Body state adds acceleration at 30–33, angular acceleration at 34–39, and elapsed time
at 40. These are included in snapshots for deterministic replay. Configuration arrays
are copied on input. The UI performs no motion math; it validates numeric text and
passes settings through Session to the physics module.

Verification: `tests/verify_acceleration.gd` checks all planes, accelerated rates,
static/kinematic/dynamic behavior, snapshot independence, invalid input, world-plane
composition, reset/replay, and UI field application/draft checks.

### Procedural kinematic integration

The UI-independent Session API now provides `configure_kinematic(id)`. It selects
`configure_body(id, "kinematic", Vector4.ZERO, {"source":"tracks"})`: both geometry
and group tracks are sampled at each fixed simulation time through the ordinary
scene graph. Parenting, scale, anchor compensation and rotation expressions use the
same evaluator as a procedural scene. There is no second integrator for this mode.
The standalone physics world treats these as externally driven bodies; the scene
adapter supplies their authoritative world geometry. Use Session's evaluated state,
`world_vertices` and `query_collision` for these bodies, not the world's motion-offset
matrices. Surface velocity/contact response for animated kinematic bodies is future work.

Existing `configure_body` calls retain `source: "rates"` by default. This supports the
previous prescribed velocity/acceleration mode without silently changing game callers.
Dynamic bodies use rates; static bodies hold their starting local pose and inherit
parent transforms, including animated parents. Both freeze their geometry track at the run's starting time.
Expressions are preserved in the tracks so changing back to kinematic restores them.
Track-driven kinematic bodies may be parented. Dynamic and rate-driven bodies still
require World as parent when advancing; this is enforced in core seek as well as Run.

Recording stores integrated state as before; procedural targets are reconstructed
purely from time and unchanged tracks on replay. Track/configuration edits invalidate
history. Invalid targets stop seeking and restore the prior displayed frame.

`core/animation/projection_track_4d.gd` evaluates animated projections independently
of all body types. It has no UI/rendering dependencies. The old rendering path is a
compatibility wrapper. Projection never affects collision geometry or body motion.

The Physics sandbox uses numeric starting transforms and numeric motion settings.
New shapes default to kinematic rates. It exposes the shared timeline; projection
expressions remain active for every body type. Opaque hull
rendering remains a separate display choice, so it can differ visually from the
Procedural tab's transparent faces even when projected vertices match exactly.

`tests/verify_kinematic_tracks.gd` loads teleport data into core types and checks exact
4D/projected agreement with a procedural reference, mixed dynamic motion, hierarchy,
static/dynamic pose ownership, replay, and invalid-expression recovery.


### Dynamic initial expressions and static inheritance

`Session.configure_dynamic_initial(id, expressions)` accepts flat expression keys:
`velocity.0`–`.3`, `acceleration.0`–`.3`, `angular_velocity.0`–`.5`, and
`angular_acceleration.0`–`.5`. Missing fields default to zero. For example:

```gdscript
session.configure_dynamic_initial(id, {
    "velocity.3": "5*cos(t)",
    "acceleration.3": "-5*sin(t)",
    "angular_velocity.2": "30"
})
```

`t` is the playback range's start time. The core's `initial_motion_4d.gd` compiles
and evaluates these expressions, and Session passes numeric initial conditions to
physics. Geometry/group expressions already supply the starting pose. No automatic
derivatives of transform expressions are taken. Angular order remains XY, XZ, XW,
YZ, YW, ZW in degrees/s (or degrees/s² for acceleration).

During stepping, velocities and stored accelerations are mutable physics state;
the initializer is not sampled again. This permits future collision/force code to
change state without a procedural trajectory overwriting it. Acceleration expressions
are initial stored values, not ongoing forcing functions. Reset re-evaluates initial
conditions; changing the start time re-evaluates them at that time. Invalid expression
edits and invalid start-time changes are rejected before changing body configuration.
Switching body modes or removing a body removes its initial-expression driver.
Recorded replay restores snapshots and does not reinitialize bodies.

Static bodies freeze their own group/geometry tracks locally but use normal parent
composition. Parent translation, rotation and scale affect their world geometry.
Static means no physics integration, not a world-space transform lock. The temporary
world-override implementation has been removed. Collision response/surface velocity
for parent-driven static motion is not added by this change; use kinematic bodies
for intentionally prescribed moving obstacles.

Initial-expression APIs remain available to engine callers and are not exposed by
the numeric Physics sandbox. Run detects uncommitted numeric motion edits. `verify_initial_conditions.gd` covers initialization
at nonzero times, reset/replay, simulated-state mutations, invalid input, parent
translation/rotation/scale, unparenting and UI application.


### Compact numeric Physics editor

Physics presents position/scale as four-component rows and rotation as a six-plane
row (degrees). Group scale stays uniform. Initial linear/angular velocities and
stored accelerations are compact numeric rows. Only the collapsible 3×4 projection
matrix accepts expressions in t. Anchor controls and kinematic source selection are
removed from this sandbox. The Procedural editor and core animation APIs are intact.

At import, geometry/group PRSA expressions are sampled at the playback range start.
Each anchor is removed by replacing position with the sampled matrix's translation:
`p_new = p - R*S*a`. This preserves the starting local matrix, including nonuniform
scale, without carrying transform animation into Physics. Projection expressions
remain unchanged. Imported JSON files themselves are never modified. These controls
are starting settings; Apply resets the run. Motion thereafter comes from rates and
stored acceleration (and future interactions), with normal parent inheritance.
