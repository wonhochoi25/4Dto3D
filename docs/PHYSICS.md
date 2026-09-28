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
  force and impulses change linear velocity. Contact impulses can change angular velocity when inertia is configured;
  continuous torque integration is not implemented.

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
orientation in the existing fixed plane order. Rotation is about the configured center of mass. Without mass properties, the
legacy motion-frame origin is retained.

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

Continuous torque integration, friction and
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
Reports themselves are read-only. Session runs a separate position correction pass before final reports; set `session.overlap_correction_enabled = false` and invalidate to use detection only.

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

## Positional overlap correction

`physics/overlap_solver_4d.gd` is independent of GJK/EPA, scene hierarchy and UI.
It consumes only converged positive penetration estimates from the replaceable
backend. Missing/unconverged estimates are skipped; detection-only backends remain
usable. The solver requests penetration independently of report display options.

Session runs this pass after integration on new steps, before recording snapshots.
The authored initial frame stays untouched. Each pair is queried against fresh
world geometry, in ascending ID order. Only dynamic positions move: A moves opposite
the backend direction, B along it, split in proportion to inverse mass. Velocities,
orientation, force accumulators and initial settings remain unchanged. Static and
kinematic bodies receive no correction (ordinary parent inheritance still applies).

Defaults: eight sweeps, 0.0001 world-unit penetration slop. Configure
`session.overlap_options = {"iterations":8, "slop":0.0001}` then invalidate history.
`session.overlap_result` describes the most recent new-step solve, not a stored
per-frame diagnostic. `finished` means no further correction was applied, **not**
proof of separation: some backend estimates may be unavailable. `iteration_limit`
can leave residual overlap in crowded/constrained scenes. Final `contact_reports`
describe the corrected state. Replay restores corrected positions without solving.

Standalone hosts can call:

```gdscript
world.step(dt)
world.resolve_overlaps(build_current_colliders)
# build_current_colliders is a Callable returning {id: {geometry, world}}.
# It must derive fresh transforms from the current body states on every call.
```

By default body position is in world coordinates. A host with another coordinate
convention supplies the third argument, a Callable accepting a dictionary of
world-space displacements and applying the pair atomically. Session supplies this
adapter for its legacy local motion frames. Geometry and JSON loading remain host
responsibilities; the solver does not read files.

Position correction alone does not change velocity. The separate impulse pass below
adds stop/bounce response. Friction, contact manifolds and fast-motion
tunneling remain future work.
`tests/verify_overlap.gd` checks mass weighting, hidden W overlap, immovable bodies,
multiple contacts, failed penetration estimates, and exact reset/replay.


## Linear collision impulses

`physics/impulse_solver_4d.gd` is a separate backend-neutral module. Session runs
a deterministic iterative impulse solve on new steps **before** positional correction,
then stores both corrected position and velocity in the recording. Reset and replay
retain their existing behavior; the authored initial frame does not solve contacts.

Configure a body with `{"mass":2.0, "restitution":0.5}`. Restitution must be finite
in [0,1], defaults to zero, and the pair uses the maximum of the two values.
Zero removes closing normal velocity; one gives an elastic collision above the
bounce-speed threshold. The linear-only model preserves tangential linear velocity;
with angular response, only the applied impulse is purely normal (no friction).
For unit normal n pointing in B's separation direction:

```text
closing = dot(vB - vA, n)
j = -(1 + restitution) * closing / (inverse_mass_A + inverse_mass_B)
vA -= inverse_mass_A * j * n
vB += inverse_mass_B * j * n
```

For an isolated approaching pair, this gives the initial impulse. The iterative
solver below handles coupled contacts and near-touching separated pairs. Intersecting
pairs require converged touching/penetrating data with a valid normal; missing or
unconverged normals are skipped. Dynamic bodies have inverse mass 1/m; other types use zero
and retain their prescribed rates. With configured inertia and contact witnesses, angular velocities contribute to
contact speed and receive response as described below. Without inertia, dynamics
retain the linear-only model. Resting support uses the iterative constraints below.

Rate-driven kinematics supply their current linear velocity. Session derives
track-driven translation from successive transformed vertex centers; this is a
geometric center, not a computed center of mass. Parented static bodies likewise
use inherited center motion. When contact witnesses are available, Session evaluates velocity at the material
point instead, including prescribed rotation/deformation. Standalone World hosts may provide a velocity callback
for prescribed motion, and an atomic pair-impulse callback for another coordinate
convention. The default callbacks assume world-space body velocities.

```gdscript
world.step(dt)
var contacts = world.query_contacts(build_current_colliders())
world.resolve_impulses(contacts, Callable(), Callable(), {"dt":dt})
world.resolve_overlaps(build_current_colliders)
```

Session performs this coordination automatically. To isolate detection, disable
both `collision_impulses_enabled` and `overlap_correction_enabled`, then invalidate.
`impulse_result` reports applied/skipped contacts from the most recent new-step
solve; it is not recorded as per-frame history. No UI is required.

`tests/verify_impulses.gd` checks analytic unequal-mass solutions, momentum/energy,
tangential preservation, oblique 4D normals, separating contacts, failed estimates,
kinematic pushing, W-axis wall stop/bounce, and reset/replay. The isolated physics
module test also exercises impulses without Session, scene, UI or playback.


## Resting contact constraints

The linear impulse solver builds one normal constraint per valid reported pair and
performs up to 32 sequential sweeps. Impulses accumulate **within this step** and
are clamped to nonnegative totals. A later sweep can undo an earlier excess impulse
without making the total attractive. Restitution targets are calculated once from
pre-solve velocities; repeating sweeps does not repeatedly apply bounce.

For intersecting bodies the target separating normal velocity is zero, except for
impacts approaching at least 1 world unit/s, where material restitution applies.
This suppresses gravity-driven micro-bounces. For a separated pair within 0.005
world units, a valid backend normal and its certified interval gap give the target
`-gap / dt`: closing the gap is allowed, crossing it on the following step is not.
No restitution is applied before contact. Missing near-contact measurements simply
omit that constraint; the backend remains replaceable.

The solver measures all constraint residuals after each complete sweep. It stops
at velocity error <= 0.000001, or reports `iteration_limit`. The limits are bounded,
so large stacks/extreme mass ratios may need more iterations. Positional correction
remains a separate pass with its existing penetration slop, keeping penetration
removal out of the velocity/energy calculation.

Session exposes `impulse_options` (edits require `invalidate()`):

```gdscript
session.impulse_options = {
    "iterations":32,            # 1..256
    "contact_margin":0.005,     # world distance
    "bounce_threshold":1.0,     # world speed; 0 restores all-speed restitution
    "velocity_tolerance":0.000001
}
session.invalidate()
```

Session always supplies its fixed dt. Standalone callers using a different step
must pass their dt in the fourth argument to `resolve_impulses`. Other defaults
match Session. Diagnostics include constraint count, sweeps, velocity_error and
finished/iteration_limit status. `impulses` counts pairs changed, not solver sweeps.

There is no inter-step impulse cache, so no extra recorded state or invalidation
rules are needed. Rewind restores snapshots and reset recomputes deterministically.
This supports simple frictionless, translation-only resting bodies/stacks. It does
not provide friction, rotational support, contact manifolds, sleeping or continuous
collision detection. The near-contact margin is not a general tunneling solution.

`tests/verify_resting_contacts.gd` exercises near-gap closure, separating bodies,
low/high-speed bounce, iterative stack support, settling under Y/W gravity,
unequal-mass stacks, and exact reset/replay with the real collision backend.


## Center of mass and 4D inertia

`physics/mass_properties_4d.gd` supplies explicit mass properties and exact uniform
hyperrectangle/tesseract properties. No geometry-name guessing, convex-hull volume
integration, or vertex-average mass approximation is used. This is opt-in; existing
bodies without mass properties keep their old origin pivot and have no assigned
inertia. Configured inertia enables angular collision response when contact witnesses are available.

```gdscript
const Mass = preload("res://scripts/core/physics/mass_properties_4d.gd")
var properties = Mass.uniform_box(2.0, Vector4(2,2,2,2))
session.configure_body(shape_id, "dynamic", Vector4.ZERO, {
    "mass":2.0,
    "mass_properties":properties,
    "angular_velocity":PackedFloat64Array([0,0,30,0,0,0])
})
```

The same motion dictionary works with `World.configure_body`. Frame conventions:

- World input is in its unrotated physics reference frame.
- Session input is shape-local. The scene adapter applies the starting geometry,
  group, and parenting-offset matrices to both the center and distribution. It
  refreshes them when starting transforms are edited/reset. Explicit properties in
  Session currently require a rate-driven body directly under World.
- Changing scale keeps total mass fixed and changes inertia; density is not inferred.
- For custom/edited geometry, the caller supplies updated properties. Uniform-box
  formulas are valid only if that box really describes the mass distribution.

Explicit input is `{mass, center_of_mass: Vector4, second_moment: PackedFloat64Array}`.
The row-major 4x4 second moment is **mass weighted and centered at the COM**:
`C = integral(r r^T dm)`. For a uniform box of full side lengths L,
`C_ii = mass * L_i^2 / 12` and off-diagonals are zero. Its plane inertia is
`I_(ij),(ij) = mass * (L_i^2 + L_j^2) / 12`.

General distributions produce a full symmetric 6x6 inertia matrix in plane order
XY,XZ,XW,YZ,YW,ZW. This module derives that matrix and its inverse from C. It uses
radians/s for the physical relation `energy = 0.5 * omega^T I omega`; public motion
angular velocities remain degrees/s and must be converted when used in that relation.
Providing C rather than arbitrary six-plane numbers keeps the inertia consistent
with a mass distribution. Validation requires finite positive mass, a finite center,
and a symmetric positive-definite C; singular/lower-dimensional distributions and
numerically ill-conditioned tensors are rejected for now.

For affine linear part L: `C_new = L C L^T`. Translation changes only the center.
This supports nonuniform scale, rotation, reflection, and nonsingular shear at fixed
mass. `world.mass_properties(id)` returns an owned reference-frame copy.
`world.world_mass_properties(id)` rotates it into current world planes and returns
world COM plus inertia/inverse. `world.inverse_inertia_world(id)` returns a zero
matrix for static/kinematic bodies and an empty array for an unconfigured dynamic
inertia. No default inertia is silently invented.

Body position slots remain displacement offsets for compatibility. Reference COM
occupies formerly reserved packed slots 30..33. Pose translation is now
`displacement + center - rotation * center`, so orientation changes leave the moving
COM fixed. `world.center_of_mass(id)` returns `displacement + reference_center`.
Snapshots include that center; immutable mass-property configuration remains separate.
The existing angular integrator still prescribes angular rates: torque-free angular
momentum evolution for asymmetric bodies is not part of this step.

Mass properties themselves do not apply forces or impulses. Central
forces/impulses remain central; point-contact impulses are described below. Tests cover analytic box moments, coupled rotated
inertia, rotational energy, inverse matrices, scaled/translated shapes, COM rotation,
invalid configurations, scene edits, isolated runtime use, and replay.


## Angular contact response

`physics/angular_response_4d.gd` implements world-plane moment, inertia multiplication,
and rotational surface velocity. The existing iterative normal solver now includes
angular response for dynamic bodies with explicit mass properties. A body without
inertia retains linear-only response. Static and kinematic rates are never changed
by collision response.

For a world contact point p and COM c, let r = p-c. Point velocity is
`v + Omega*r`. Angular velocity storage is still degrees/s; the angular algebra
converts to radians/s and converts updates back to degrees/s. For an impulse J:

```text
moment_ij = r_i * J_j - r_j * J_i
angular_delta = inverse_inertia_world * moment
linear_delta = J / mass
```

For contact normal n, define k = moment(r,n). Effective inverse mass now includes
`k_A^T I_A^-1 k_A + k_B^T I_B^-1 k_B`, in addition to both linear inverse masses.
That same effective mass is used throughout the iterative resting-contact solve.
Both linear and angular rate changes are applied atomically.

The backend's optional `point_a`/`point_b` witnesses must be finite world-space 4D
points. Their midpoint is used as one shared contact location, so equal/opposite
impulses preserve total angular momentum about a common origin. Intersections use
penetration witnesses; speculative separated contacts use distance witnesses. If
witnesses are absent/invalid, the solver falls back to central linear impulses.
Normals must still satisfy the existing convergence/validity requirements.

Rate-driven kinematic surface velocities include prescribed rotation. For tracks
and inherited static motion, Session maps the current contact point into local
coordinates and evaluates that same point in the previous frame, giving a backward
difference velocity. Singular transforms fall back to center motion. No UI is involved.
Standalone hosts can override point-velocity/pair-impulse callbacks on
`World.resolve_impulses`; legacy linear callbacks remain available for missing-point
contacts. Custom coordinate adapters should supply both kinds of callback.

`World.apply_point_impulses({id: {"impulse":Vector4(...), "point":Vector4(...)}})`
is also available to headless hosts. When using Session recording, runtime mutations
must be committed/reset as with other direct World edits; this is currently an
internal collision path rather than a Session user-input wrapper.

Limitations: one contact location per pair, no friction or contact manifold yet.
A broad face-face contact's single witness can generate artificial tipping; the
previous translation-only stack tests do not establish rotational stacking stability.
There is no continuous torque integrator or torque-free angular momentum evolution
for asymmetric rotating bodies yet. Collision impulses conserve instantaneous
linear/angular momentum and elastic impact energy within solver tolerance, but this
is not a claim of exact energy conservation over subsequent integration steps.

`verify_angular_contacts.gd` checks all six plane signs, unit conversion, zero torque
for impulses through COM, contact-point stopping, two-body momentum and elastic
energy, rotating kinematics, actual backend witnesses, and recorded reset/replay.
