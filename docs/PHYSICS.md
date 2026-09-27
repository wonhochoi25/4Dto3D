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
- Kinematic uses prescribed initial linear velocity on each step.
- Dynamic integrates its current simulated velocity.
- Orientation integration retains the previous implementation; Physics UI currently sets no angular velocity.
- No acceleration, forces, gravity, collision impulses, or contact response have been added.

`body_4d.gd` owns the packed layout (30 doubles); callers outside physics should use `matrices()` for poses and `snapshot/restore` for history. Public state dictionaries remain available for existing tests/low-level integrations, but must not be modified while using a cached recording. Snapshots contain state only; type/initial settings belong to configuration and are changed through lifecycle APIs. Collision geometry is passed to queries, not stored in body snapshots.

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
