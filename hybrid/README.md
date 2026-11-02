# Hybrid training: walk, inspect, return

This is the combined first-/third-person version of all four training chambers. Everything added for this integration lives in `hybrid/` inside the repository. The original third-person project is preserved separately; the upstream prototype files remain unchanged. The local checkout folder may be renamed without changing resource paths or the launcher.

## Run

Open this repository's `project.godot` in Godot, open **hybrid/training.tscn**, and press **F6** (Run Current Scene). F5 still opens the upstream lab. On macOS, `hybrid/launch.command` launches the new scene directly using the Compatibility renderer. It also accepts a `GODOT_BIN` environment override.

## Controls

| Action | Control |
| --- | --- |
| Enter first-person mouse look | Click inside the scene |
| Look | Move mouse while captured |
| Move in first person | WASD, relative to horizontal look direction |
| Move vertically | Q / E |
| Move precisely | Hold Shift |
| Switch first/third person | F or the sidebar button |
| Release cursor / pause movement | Escape |
| Change dimension set | 1 XYZ, 2 YZW, 3 XYW where unlocked; Tab toggles XYZ/YZW |
| Rotate inspection camera | Enable Camera rotation, then left- or right-drag the scene |
| Lock inspection angle | Disable Camera rotation |
| Inspection zoom | Mouse wheel |
| Inspection X-ray | V or the X-ray button |
| Optional detailed hint | H |
| Grab / release key (chamber four, first person only) | G or the button |
| Reset camera/look | C |
| Restart chamber | R |
| Next chamber after completion | Enter |

First person starts with a free cursor; click the scene to begin. Escape releases it so all UI buttons can be clicked. Switching into inspection releases it automatically. Returning to first person captures it again. Losing focus pauses input and releases the cursor. Leaving the scene also releases it.

Only first person permits movement, including vertical movement. Inspection cannot move the player even through the controller's movement API. The slice can be changed in either mode, keeping all four coordinates fixed. The displayed LOOK values are the horizontal forward direction expressed in the current world axes. They help distinguish camera-relative WASD from world X/Z/W.

Both camera poses persist independently across view toggles. C deliberately resets the active camera; restarting resets both. First-person walls are solid. Inspection retains its separate X-ray preference. X-ray, hints, and markers are visual aids, not collider changes.

## The four puzzles

1. **A Different Direction:** advance along W to the doorway's slice, then cross along X.
2. **The Elbow:** pass the first gate at W=3, turn along Z in the central tunnel, return along W to zero, and cross the second gate.
3. **A Step Back:** W forward, X backward, Z around the core, then X forward to the exit.
4. **The Right Fit:** carry a constant-size key to W=3, through a wider opening, then release it onto a plate to unlock the exit. See [chamber-four notes](CHAMBER_FOUR.md).

The original authored solid bounds, tunnel cuts, route coordinates, and player collision dimensions are preserved. All three routes are tested using first-person forward movement after orienting the camera along each segment. Optional hints now give coordinate targets rather than prescribing a world-axis D/A press, since WASD is camera-relative.

This retains the original no-gravity movement and small cube-sized player, with the first-person camera at the collider center. It does not add a human-height capsule or gravity: those would require resizing the existing corridors. Q/E remains available for the original free vertical movement. Looking up/down does not change walking elevation. The cyan cube is visible in inspection and hidden in first person. A procedural wall grid adds scale and motion cues without assets or collision changes.

## Integration boundary

- `controller.gd`: camera mode, input capture, camera-relative movement, inspection movement lock, adapted UI/hints.
- `view.gd`: perspective first-person camera and the original orthographic inspection camera over the same sliced meshes.
- `wall_grid.gdshader`: first-person surface grid for close-range readability.
- `imported/`: namespaced copies of the prior third-person campaign, its four game support scripts, true-slice math, authored levels, and geometry test. Resource paths were updated to stay inside this folder; these copies do not depend on the sibling checkout.
- Shared upstream scene graph, transforms, geometry, collision backend, and hull renderer are used from this repository's `scripts/` tree. Their APIs are unchanged.

The first-person interaction adopts the upstream prototype's captured mouse look and yaw-relative movement, but routes locomotion through the existing 4D swept motor. It intentionally does not instantiate the prototype's gravity-driven `CharacterBody3D` controller or projected 3D artifact physics, which would change the spatial rules of these puzzles. The upstream artifact and guided prototypes remain available as separate scenes.

Chamber four adds a fixed-size 4D key, a wall opening that varies along W, and a geometric pressure plate. No mass/weight mechanic is used. The plate secures the released key and latches the exit gate open. The first three chambers remain object-free.

## Validation

Run from the repository root:

```sh
python3 hybrid/tests/run_tests.py
```

This checks the original 803 chamber geometry assertions, the hybrid first-person routes and camera/movement invariants, the fourth chamber’s key/plate tests, and the upstream artifact/guided-experience suites. The hybrid test also supports rendered captures:

```sh
godot --path . --rendering-method gl_compatibility --windowed \
  --script res://hybrid/tests/test_hybrid.gd -- --captures /tmp/hybrid-captures
```

The headless backend cannot capture a physical mouse, so the graphical run additionally exercises captured-mouse look. Tests are automated, not a substitute for first-time human playtesting of the tutorial.
