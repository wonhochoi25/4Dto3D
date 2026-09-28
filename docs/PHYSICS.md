# Core 4D physics

The Godot-dependent core needs no Nodes, UI, renderer or file loader. `Session`
coordinates shape transforms, physics, collision response, and recorded playback.
`PhysicsWorld` can also be used alone with host-owned geometry/transforms.
Projection is display-only and never affects collision or simulation.

## Modules and step order

| Module under `scripts/core/physics` | Responsibility |
|---|---|
| `body_4d.gd` | Packed body state and COM-centered pose |
| `physics_world_4d.gd` | Body lifecycle, inputs, snapshots, response APIs, sleep/wake |
| `integrator_4d.gd` | Linear integration; prescribed angular motion |
| `angular_integrator_4d.gd` | Torque and momentum-based dynamic rotation |
| `mass_properties_4d.gd` | Central second moments, full six-plane inertia |
| `angular_response_4d.gd` | Moments and rotational contact velocity |
| `contact_queries_4d.gd` | Deterministic candidate-pair queries |
| `broad_phase_4d.gd` | Four-dimensional AABB sweep-and-prune |
| `contact_manifold_4d.gd` | Contact-plane intersection for affine boxes |
| `impulse_solver_4d.gd` | Iterative normal/angular contact constraints |
| `friction_4d.gd` | Coulomb impulses in the 3D tangent space |
| `overlap_solver_4d.gd` | Position-only penetration removal |
| `motion_substeps_4d.gd` | Travel-based bounded substep budget |
| `collision/` | Replaceable backend: box SAT, otherwise GJK/EPA |

Session records macro frames at 1/60 second. On new frames it:

1. Predicts motion and chooses bounded substeps when necessary.
2. Integrates dynamic velocity/pose; samples prescribed motion.
3. Broad-phase filters candidate pairs in R4 and queries the collision backend.
4. Builds box manifolds when possible, otherwise uses backend witness contacts.
5. Iteratively solves normal/angular impulses and tangential friction.
6. Removes residual overlap without adding velocity.
7. Updates sleeping state and records the accepted macro frame.

Initial authored poses are preserved; response starts at the first simulated step.
Rewind restores snapshots. It does not apply inverse physics or solve contacts twice.
Only accepted macro frames emit final contact/state reports, not every substep.

## Body ownership and configuration

- **Static:** not integrated, no inverse-mass/inertia response. Session permits
  ordinary inherited parent motion; it samples that motion for contacts.
- **Kinematic:** host-prescribed rates or Session transform tracks. Contact response
  never modifies its motion; its moving surface can push dynamic bodies.
- **Dynamic:** initial rates become mutable state, changed by forces, torque and
  contacts. Configured rate-driven bodies must be directly under World in Session.

```gdscript
const Session = preload("res://scripts/core/session_4d.gd")
const Box = preload("res://scripts/core/geometry/generators/tesseract.gd")
const Mass = preload("res://scripts/core/physics/mass_properties_4d.gd")
var simulation = Session.new()
var id = simulation.add_geometry(Box.new(), {"position":{"Y":4}})
simulation.configure_body(id, "dynamic", Vector4.ZERO, {
    "mass":2.0,
    "restitution":0.1,
    "friction":0.6,
    "mass_properties":Mass.uniform_box(2.0, Vector4(2,2,2,2))
})
simulation.set_gravity(Vector4(0,-9.81,0,0))
simulation.seek(1.0)
var points = simulation.world_vertices(id)
```

Mass is finite and positive (default 1). Restitution is in [0,1] (default 0);
a pair uses the maximum. Friction is finite/nonnegative (default 0); a pair uses
`sqrt(mu_A * mu_B)`, so set it on both the floor and moving object. This is one
isotropic Coulomb coefficient, not separate static/dynamic material coefficients.

Nonzero legacy acceleration/angular-acceleration inputs are rejected. Dynamics use
forces/torque; kinematic velocity may be changed before each step. The optional
`configure_dynamic_initial` API samples initial velocity/angular-velocity expressions
once at run start, preserving mass, restitution, friction and mass properties.

## Forces, torque, and units

World and Session expose `apply_force`, `apply_impulse`, `apply_torque`, and
`apply_force_at_point`. Session wrappers branch recorded history after rewind and
reject inputs during pending seeks. Configuration changes require `invalidate()`.
Inputs are not an event log: reset restores launch state, so the host must resubmit
runtime commands for a new run.

- `apply_force(id, Vector4)`: central world force, accumulated for the next macro
  step only. Submit every step for sustained force.
- `apply_impulse(id, Vector4)`: instantaneous central impulse, `delta_v = J / mass`.
- `apply_torque(id, PackedFloat64Array[6])`: world-plane torque, consumed next step.
  Requires dynamic inertia. Physical algebra uses radians, not degrees.
- `apply_force_at_point(id, force, world_point)`: central force plus its moment,
  committed atomically. Requires inertia.
- `set_kinematic_velocity(id, velocity, angular_velocity)`: prescribed rate update.
- `World.apply_point_impulses({id:{impulse,point}})`: atomic linear/angular contact
  response. Standalone hosts may also use it for impacts; direct World edits under
  a Session must commit/reset recording appropriately.

Plane order is XY, XZ, XW, YZ, YW, ZW. Public angular velocity is degrees/second;
inertia, moments, torque and angular momentum use radians-based physical units.
Linear integration is semi-implicit Euler:

```text
v += (gravity + accumulated_force / mass) * dt
position += v * dt
```

Force and torque are applied over the entire macro interval when it is subdivided,
not just the first substep. Gravity acts equally on different masses.

## Mass properties and angular integration

Mass properties are opt-in. Bodies without them retain their original origin pivot,
prescribed angular rates, and linear-only collision response; no inertia is guessed.
`Mass.uniform_box(mass, full_side_lengths, center)` exactly describes a uniform
4D rectangular solid, including a tesseract. Custom geometry requires explicit
properties; vertex averaging is not used to infer mass distribution.

Input: `{mass, center_of_mass:Vector4, second_moment:PackedFloat64Array[16]}`.
The row-major central moment is `C = integral(r r^T dm)`, measured from COM.
For a uniform box, `C_ii = mass * L_i^2 / 12`. The module derives the full symmetric
6x6 plane inertia and inverse; diagonal box inertia is
`I_(ij),(ij) = mass * (L_i^2 + L_j^2) / 12`.

Validation requires finite, symmetric positive-definite C. Singular/lower-dimensional
or ill-conditioned distributions are currently rejected. Shape scale changes the
distribution at fixed total mass; density is not inferred. Affine transforms use
`C_new = A C A^T`. Translation changes only COM.

World input uses its unrotated reference frame. Session input is shape-local and
is transformed through the authored starting geometry/group/offset; edits refresh
it on reset. Explicit properties in Session currently require a rate-driven root
body. Geometry edits that change the distribution require updated input properties.

`world.mass_properties(id)` returns an owned reference copy;
`world.world_mass_properties(id)` returns rotated world properties;
`world.inverse_inertia_world(id)` is zero for static/kinematic bodies and empty for
unconfigured dynamic inertia. Inverse tensors are cached only until pose/config
changes. `world.center_of_mass(id)` gives the current center.

Body position slots are displacement offsets. Pose translation is
`displacement + reference_center - rotation * reference_center`, so spin fixes COM.
For dynamics with inertia, each step computes world momentum `L = I_world * omega`,
adds `torque * dt`, estimates midpoint angular velocity, advances orientation with
a matrix exponential, then recovers final omega from final inertia and momentum.
Torque-free world angular momentum is conserved to numerical precision; omega can
change for asymmetric bodies. Energy is approximately conserved with timestep error,
not guaranteed exact for arbitrarily large dt. Kinematics retain prescribed rates.

## Contact generation and manifolds

The backend interface remains replaceable (see COLLISION_BACKEND.md). The default
backend recognizes 16-corner local boxes under nonsingular affine world transforms
and uses 4D SAT: candidate normals are orthogonal to triples of the eight combined
edge generators. Other convex hulls use GJK/EPA. This avoids the observed EPA
penetration failures on wide box floors. SAT separation returns interval gaps and
distance bounds; its upper bound need not be an exact closest distance.

Manifold generation is outside the backend. For a verified box pair it intersects
the shared contact plane with both boxes' halfspaces, yielding contact-region
vertices (eight points for an aligned full facet). A 0.005 normal contact skin
allows nearly flat configurations to retain multiple supports. It does not thicken
rendered geometry. Singular/non-box cases retain the single-witness fallback.

No contact is fabricated from an indeterminate collision. Converged intersection
normals or valid near-separation certificates are required. Missing witnesses
fall back to central linear response. Backend witnesses are world-space Vector4s
or four-element arrays; paired witnesses use a shared midpoint for impulse moments.

## Constraint solving and friction

At each contact, `v_point = v_COM + Omega * (point - COM)`. For impulse J, the
six-plane moment is `r_i*J_j - r_j*J_i`. Angular velocity changes by
`I_world^-1 * moment`, converted back to stored degrees/second.

Normal constraints include both linear inverse masses and both rotational effective
masses. Impulses accumulate within the current step and are clamped nonnegative.
Restitution targets are frozen before sweeps. Speeds below 1 unit/second suppress
bounce; near-separated contacts target `-gap/dt` so the remaining gap may close.
Tangential friction solves a coupled 3x3 effective-mass system and clamps the total
3D tangential impulse to a ball of radius `mu * normal_impulse`.

Defaults in `session.impulse_options`: 32 sweeps, contact margin 0.005,
bounce threshold 1, velocity tolerance 1e-6. More difficult stacks may require
more sweeps (maximum 256). Diagnostic `iteration_limit` means residuals remain.
Position correction stays separate: eight sweeps, 0.0001 penetration slop, dynamic
positions only. It does not inject velocity or bounce energy.

Track-driven contact velocity follows the same material point between substeps,
including prescribed rotation/scale; singular transforms fall back to center motion.
Projection never enters these calculations.

## Broad phase, sleeping, and fast motion

Session response/final candidate reports use 4D AABB sweep-and-prune. Explicit
`Session.query_collision` is always a direct pair query. Standalone `query_contacts`
can opt in with `{"broad_phase":true}`. Set Session `contact_options.broad_phase=false`
for exhaustive diagnostic reports, at the cost of querying every pair. A missing
candidate report is not an indeterminate backend result.

Sleeping defaults: linear speed <=0.01, each angular component <=0.5 degrees/s,
quiet for 0.5 seconds. Nonzero gravity also requires nearby support. Sleep records
zero rates and skips integration. Inputs, contact impulses, gravity changes and
body removal wake affected bodies. Loss of support wakes on the next check. This
is per-body sleeping, not a persistent island/contact-graph implementation.
Standalone hosts call `world.finish_step(reports,dt)` after solving contacts.

Fast-motion handling is **bounded adaptive substepping, not exact continuous TOI**.
The budget uses endpoint vertex travel, known linear/angular rates, rotational
sweep expansion, and body thickness. A full rate-driven turn cannot disappear
merely because its endpoint orientation repeats. Session defaults to at most 256
substeps; exceeding the limit rejects the macro frame and restores the previous
accepted state with an error. `last_motion_substeps` exposes the chosen count;
`fast_motion_enabled=false` opts out. A macro step remains one recorded frame.

This reduces tunneling and is tested on a fast box crossing a thin wall. It does
not guarantee detection for every glancing contact, arbitrarily thin non-box hull,
or a procedural path that oscillates and returns between samples. Non-box size
estimates are heuristic. Such applications need a dedicated time-of-impact backend
or tighter host timesteps. These limitations are not silently reported as exact CCD.

## Standalone host loop

```gdscript
world.step(dt)
var colliders = build_current_colliders() # {id:{geometry,world}}
var reports = world.query_contacts(colliders, {
    "include_penetration":true, "include_manifold":true, "broad_phase":true
})
world.resolve_impulses(reports, Callable(), Callable(), {"dt":dt})
world.resolve_overlaps(build_current_colliders)
world.finish_step(reports,dt)
```

The host supplies freshly evaluated world transforms. Session performs this loop
and adaptive subdivision automatically, without UI. Custom coordinate conventions
can supply linear/point-velocity and atomic impulse/displacement callbacks. The
integrator, collision backend and solvers remain independently callable.

## State and verification

Packed state: position 0..3, velocity 4..7, orientation 8..23, angular velocity
24..29, reference COM 30..33, reserved 34..39, elapsed time 40, mass 41, pending
force 42..45, pending torque 46..51, sleep timer 52, asleep flag 53. Snapshots own
copies. Body types/materials/distributions/solver settings are configuration and
require recording invalidation when changed. Recordings from older code revisions
are not a persistent serialization format.

Tests cover box manifolds, flat/tilted settling, rotational W stacks, friction
bounds and real sliding, momentum-based free rotation, torque consumption,
broad-phase rejection, sleep/wake/replay, fast thin-wall impacts and substep-limit
failure. Existing force, impulse, mass, angular-contact, recording, procedural,
core-isolation and backend-replacement tests remain applicable. Physics UI remains
absent: the sandbox's Playground and Procedural views are unchanged.
