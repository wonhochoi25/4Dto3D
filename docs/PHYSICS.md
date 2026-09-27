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
