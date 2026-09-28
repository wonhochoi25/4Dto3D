# Core 4D physics

Physics runs without Nodes, UI, files, rendering or a scene tree. Godot is the
runtime. `core/physics/physics_world_4d.gd` coordinates body state, integration and
collision-backend dispatch. `body_4d.gd` owns packed state; `integrator_4d.gd` owns
fixed-step motion. Collision algorithms live under `physics/collision/` behind the
replaceable backend documented in COLLISION_BACKEND.md.

## Motion ownership

- Static: physics does not integrate motion. In a Session, the starting local
  geometry/group transforms are frozen, but ordinary parent transforms still apply.
- Kinematic: the host prescribes velocity or a transform trajectory. Forces and
  impulses cannot move these bodies. `set_kinematic_velocity` may be called before
  each step, for example with a velocity calculated from time.
- Dynamic: initial velocities seed mutable simulated state. Gravity, accumulated
  force and impulses change linear velocity. Angular velocity remains constant
  until changed by future torque/contact code; torque and inertia are not implemented.

Acceleration is derived, not configured. Nonzero legacy `acceleration` or
`angular_acceleration` settings are rejected. Zero values are accepted for older
clients. The unused packed slots remain reserved to preserve existing pose offsets.

## Standalone use

```gdscript
const World = preload("res://scripts/core/physics/physics_world_4d.gd")
var world = World.new()
world.set_gravity(Vector4(0, -9.81, 0, 0))
world.configure_body(1, "dynamic", Vector4(1, 0, 0, 0), {
    "mass": 2.0,
    "angular_velocity": PackedFloat64Array([0, 0, 30, 0, 0, 0])
})
world.apply_impulse(1, Vector4(4, 0, 0, 0)) # Adds 2 units/s in X immediately.
world.apply_force(1, Vector4(0, 0, 0, 10)) # Applied for the next step only.
world.step(1.0 / 60.0)
var motion_matrices = world.matrices()
```

Body IDs belong to the host. `configure_body` starts at zero motion displacement;
`add_body(id, position, velocity, type)` is the lower-level legacy initializer,
with mass 1 by default. Configuration requires finite positive mass (default 1).
Gravity defaults to zero and is a world-space Vector4 acceleration. Angular plane
order is XY, XZ, XW, YZ, YW, ZW, in degrees/s.

`apply_force` accumulates central world-space forces until the next step, then the
accumulator is cleared. Call every step for sustained force. `apply_impulse` changes
velocity immediately by J/m and is independent of timestep. Neither method applies
torque. Unknown IDs, wrong body types and nonfinite inputs are rejected with `false`
and an `error` string. Positive finite step duration is required.

The semi-implicit Euler step is:

```text
a = gravity + accumulated_force / mass
v = v + a * dt
p = p + v * dt
```

Gravity therefore affects all dynamic masses equally. Prescribed kinematic velocity
is used directly without gravity/force integration. Angular increments left-multiply
orientation in the existing fixed plane order. Rotation is about the motion frame,
not an implemented center-of-mass model.

## Session and scene integration

Session exposes `configure_body`, `set_gravity`, `apply_force`, `apply_impulse`, and
`set_kinematic_velocity`. The scene-side physics binding composes motion offsets
with starting transforms. Static/dynamic geometry is frozen at run start.
`configure_kinematic(id)` instead uses existing geometry/group tracks; the physics
world does not also integrate that external pose driver. Authoritative world geometry
for collision queries is supplied by Session, not the standalone motion matrices.
Track-driven kinematic bodies may be parented; dynamic/rate bodies require World.

`configure_dynamic_initial(id, expressions)` remains an optional core authoring API
for initial velocity and angular velocity only, sampled at the range start. It
preserves configured mass. Acceleration-expression keys are rejected. Numeric game
callers do not need this API, or any animation module when using World directly.

Projection has no effect on physics. Core projection tracks may independently animate
the display. JSON loading, procedural authoring and visual controls remain adapters.

## Update and state ownership

Both sandbox modes call `Session.advance(delta)` once per frame. Playback requests
time, the generic recorder advances its injected runtime in fixed steps, and only
the world invokes the integrator. The recorder has no physics dependency.

Physics snapshots own independent copies of position, velocity, orientation, angular
velocity, elapsed time, mass and pending force. Configuration (body type, gravity,
initial settings) is separate. Reset restores initial state and clears runtime forces
and impulses while retaining configuration. Direct configuration edits require a
recording reset; Session setters handle this.

Session runtime inputs are committed at the displayed frame and truncate future
history. This permits applying an impulse after rewind without replaying stale
future states. A pending seek must finish or be canceled before inputs are accepted.
Recorded forward/backward playback restores snapshots; forces are not applied twice.
Reset discards runtime inputs. Inputs are not a persistent command/event log: after
reset, a host that wants the same commands must submit them again.

When using a Session, use its input methods rather than mutating `session.physics`
directly, so recording remains consistent. For a headless game without recording,
call World methods before each step. Constant force must be submitted each step;
calling Session.apply_force once before a long seek affects only its next step.

The binding caches initial transforms until Session invalidation. Continuous forward
recording avoids per-step restores; the final validated scene sample supplies display
state. Replay still evaluates the restored scene. Zero angular velocity avoids
unnecessary rotation matrices.

## Sandbox scope

There is currently no Physics sandbox UI. Playground and Procedural remain available.
The physics core, optional animation APIs and reusable rendering utilities remain;
headless tests drive physics development until a later UI is built.

## Verification and remaining work

`verify_forces.gd` checks mass scaling, gravity, force accumulation/consumption,
impulses, ownership, snapshots, reset and recording branches. The physics isolation
test copies only physics/math into a fresh project and exercises forces there.
Existing core, scene, procedural, playback and motion suites remain applicable.

Collision response, center of mass, inertia, torque, friction and
continuous collision detection are not implemented. Contact queries run automatically through Session and remain read-only and replaceable;
the integrator does not depend on GJK/EPA.

## Automatic contact reports

Session queries registered physics bodies after every valid fixed-step scene sample,
including the initial state. `session.contact_reports` contains reports for the
currently displayed/accepted frame. Each entry is:

```text
{ body_a: integer ID, body_b: integer ID, result: backend result dictionary }
```

The pair pass is deterministic (ascending IDs, one unordered pair each) and includes
pairs with at least one dynamic body. Static-static, static-kinematic, and
kinematic-kinematic pairs are skipped. Objects not registered as physics bodies do
not participate. No broad phase is used yet: this is O(n²) pair enumeration.

All queried pairs are reported, including separated and indeterminate results.
`result.status == "intersecting"` means touching or overlap under the backend's
contract, not necessarily positive penetration depth. Penetration is requested by
default; optional/failed penetration results must be inspected before use. Set
`session.contact_options = {"include_penetration":false}` for detection only.
Reports never apply correction, impulses or other response.

`contacts_evaluated(time, reports)` exposes every evaluated sample, including intermediate
steps in a long seek and replayed destination samples. It is not an enter/exit event
stream. Observers should be read-only; reports are copied for them. Partial/failed
seeks retain `contact_reports` for the previous displayed state. Replaying a frame
recomputes queries from its restored geometry, rather than serializing backend reports
into body snapshots. Replacing the backend takes effect on the next evaluation.

The scene binding supplies local geometry and evaluated world matrices, including
hierarchy and geometry transforms; projection never enters the query. Pair selection
lives in `core/physics/contact_queries_4d.gd`, outside the replaceable collision backend
folder. It calls only the backend's public query contract. Missing collider descriptors
produce indeterminate reports rather than silently claiming separation.

Standalone World clients continue calling `step(dt)` for motion, evaluate their own
world transforms, then call `world.query_contacts(colliders)`, where colliders maps
body IDs to `{geometry, world}` descriptors. Session performs that coordination
without UI. The integrator remains independently usable without collision queries.
`tests/verify_contact_queries.gd` covers the automatic integration and backend contract.
