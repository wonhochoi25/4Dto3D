# Chamber four — The Right Fit

Run `hybrid/training.tscn` and select **CHAMBER 04**. To launch directly from the project root:

```sh
godot --path . --rendering-method gl_compatibility --windowed res://hybrid/training.tscn -- --chamber 4
```

## Play

Click the scene to enter mouse look. Aim at the orange key and press **G** to grab it. Press G again to release it. The button works too after Escape frees the cursor. Grabbing requires the key to intersect the current slice, be within 1.8 units, lie under the crosshair, and have no solid wall between it and the player.

The key is carried at a fixed **4D offset** from the player. Looking around does not rotate or reposition it. Both move together until either hits an obstacle. In YZW, a key carried ahead in X may be outside the player's current slice: it stays attached, its coordinates remain visible in the HUD, and inspection labels it OTHER SLICE. Switching back to XYZ shows it again. Switching views never teleports the key.

**F** opens third-person inspection. Player and key stay frozen, and grabbing/releasing is disabled there. Orbit, X-ray, zoom, dimension switching, and H hints remain available. F returns to first person.

## Puzzle and solution

The wall at X=0 contains one static 4D aperture:

- Narrow region: Z width 0.56, too narrow for the key's 1.20 Z width.
- Wide region: Z width 1.80, present for W between 2.0 and 4.5.
- The key's full W thickness is 0.50, so merely seeing the wide opening at W=2.1 is insufficient: part of the key still intersects the narrow region. W=3 gives ample clearance.

The key's dimensions are always **0.70 × 0.70 × 1.20 × 0.50** in X/Y/Z/W. There is no mass or weight threshold. Both rendering and collision use the same fixed 4D geometry.

Suggested solution:

1. At spawn, look ahead and press G. Trying the narrow opening demonstrates that the key stops both bodies.
2. Change to **YZW (2)** and carry the key until **W=3**. Mouse look changes WASD's directions; the LOOK readout and H/F help with orientation.
3. Restore **XYZ (1)** and carry the key through the wider opening to **X=1.8, Y=0, Z=0, W=3**. If picked up from the initial spawn, the player is at X=0.8 here.
4. Press **G** to release it. The key center only needs to be inside the outlined capture volume: within ±0.53 in X/Y, ±0.78 in Z, and ±0.43 in W of the plate target. The whole key does not need to fit inside the outline; rough placement is enough. The visible outline and trigger use the same bounds.
5. The violet plate turns green, secures the key, and latches the red exit gate open. Walk around the secured key (e.g. Z=1.2), then through the open gate to **X=5, Y=0, Z=0, W=3**.

The key still collides after release. The plate is a magnetic placement sensor: in this no-gravity prototype, release leaves the key where it is. Successful placement locks it without snapping or teleporting, and keeps the gate open until R resets the chamber. A held key, the player alone, or an XYZ-aligned key on the wrong W slice cannot activate it. This is deliberately a latched plate rather than a continuously weighted plate.

## Implementation

- `levels/04_the_right_fit.gd`: static aperture, exit gate, bounds, hints.
- `object_world.gd`: key scene object, ray/occlusion grab checks, paired swept movement, plate and gate state. Uses the existing 4D collision API with the key's own half-extents.
- `view.gd`: true-slice key rendering, plate/socket markers, fixed-size-in-screen labels, red gate styling.
- `controller.gd`: first-person G interaction and object HUD, with inspection interaction lock.
- Campaign selection/progression now supports four chambers. The original three authored level files are unchanged.

No commits or pushes are part of this development pass.

## Local verification

`python3 hybrid/tests/run_tests.py` runs all five suites. `tests/test_key_chamber.gd` checks the complete route plus narrow-hole rejection, partial-W overlap, wall occlusion, incorrect plate placement, player/key collision, camera-mode freezes, reset, and earlier-chamber isolation.

For a graphical playthrough with screenshots:

```sh
godot --path . --rendering-method gl_compatibility --windowed \
  --script res://hybrid/tests/test_key_chamber.gd -- --captures /tmp/key-captures
```
