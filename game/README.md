# SEAM — coordinate frames and changing gravity

Open `project.godot` in Godot and press **F5**, or double-click `game/launch.command` on macOS. Enter starts the room. Direct review: `game/launch.command -- --room 2` (1–3). The old demo remains at `hybrid/training.tscn`; the lab remains at `scenes/app.tscn` (F6).

This version restores the demo's coordinate-system mechanic. **Switching preserves every player X/Y/Z/W coordinate.** Held cells travel with the player into the new frame and stay centered in its visible slice. It changes the three visible/movable axes and which axis is down. W changes continuously through ordinary walking when it is a horizontal axis in the current system. There are no W-layer teleports.

| Control | Action |
| --- | --- |
| WASD / mouse | Walk relative to look / look around |
| Double-tap W, hold the second press | Sprint at 7.2 m/s; ordinary walking is 4.5 m/s |
| Space | Grounded jump opposite current gravity |
| 1 / 2 / 3 / 4 | Request XYZ / XZW / XYW / YZW at a station |
| Tab | Cycle the coordinate systems supported by the station |
| G | Cycle visible gravity axes at a station, in selectable-gravity mode |
| E | Aim at a cell to carry; aim at a receiver to power; otherwise release |
| F | Survey the current slice, with physics paused |
| H | Reveal the next of three optional hints |
| B | Return to the last stable station; carried cell returns to its start |
| T | Recall unsecured cells, keeping powered receivers |
| R | Restart the room |
| Esc | Pause / resume |

Sprint stops on forward release, pause, survey, recovery, focus loss or a frame change. Holding W alone or its keyboard-repeat events never starts sprinting. Walking remains horizontal in the current gravity-aligned view; mouse pitch does not make the player fly.

## Compare the two gravity rules

The pause menu has a **Gravity** button. It switches rules and restarts the room so both trials begin in the same state. Priority is the default. The first room's stations expose all four coordinate systems for experimentation; later stations focus on the pairs used by their puzzles.

| System | Priority down (`Z > X > Y > W`) | Floor axes | Frozen axis |
| --- | --- | --- | --- |
| XYZ | −Z | XY | W |
| XZW | −Z | XW | Y |
| XYW | −X | YW | Z |
| YZW | −Z | YW | X |

In selectable mode, G cycles the **negative** direction of each visible axis. A system change keeps your selected gravity if that axis is still visible; otherwise it falls back to the priority rule. You can explicitly return to −Z when returning to XYZ. Hidden axes cannot be selected as gravity.

For the proposed **XYZ → XZW, floor XY → XZ** example: choose selectable mode, switch to XZW at a station, then choose −W with G. Under the exact priority rule, XYZ → XZW keeps −Z; the first room instead teaches XYZ → XYW, which turns the original X wall into a YW floor. Only Z or X can win that particular priority order among three-of-four-axis systems; selecting Y or W requires the selectable rule.

## Rooms

1. **The Wall Is a Floor:** switch into XYW, land against the old X wall, walk continuously along W around the finite-W barrier, and return to XYZ to exit. Alternate systems are allowed at the calibration stations.
2. **A Different Depth:** carry a cell in XZW to align yourself with the W-dependent doorway. Return to XYZ with the cell held; it automatically follows into the new slice. No separate cargo alignment is required.
3. **Above and Beside:** jump up the gold staircase, switch into XYW to freeze an elevated Z, carry the cell along the old wall above the barrier, move W to the far station, then return to XYZ and deliver it. In selectable mode explicitly choose −Z at the far station before descending.

Cells have real 4D positions and swept collision. Held cells are attachments: their carry pose is transformed to the new frame and their hidden coordinate is aligned with the player. Collision limits the attachment position near walls without imposing a cargo-alignment requirement on switching. Receivers require proximity in all four dimensions. Released cells retain the gravity axis they had while carried. Secured cells remain secured. Unlocks save locally on completion; rooms do not have mid-puzzle saves. This iteration uses a new progress file so completion of the old W-layer rooms does not skip these rooms.

## Implementation and art

- `frame.gd`: four coordinate systems, world/view conversion, gravity selection and rotated standing bounds.
- `world.gd`: authoritative 4D boxes, grounded motion, gravity, cells, stations, collision, recovery and completion. Reuses the demo's swept 4D motor and core collision backend.
- `levels.gd`: all bounds, stations, cells, receivers, landmarks and hints in physical `Vector4` coordinates.
- `view.gd`: true axis-aligned sections, gravity-aligned rendering, cameras and placeholder art. The lower X/Y/Z/W faces keep their blue/amber/violet/green surface colors when they become floors.
- `sprint.gd`: double-tap timing and sprint latch.
- `main.gd`: input, menus, policy comparison, progression and HUD.

The visible axes form a coordinate slice at the player's frozen hidden coordinate. Axis-aligned 4D boxes have exact box sections, so the same authored bounds drive rendering and the 4D collision queries. The player is 1.7 metres tall along the selected gravity axis. Frame changes rotate that box and check clearance atomically. They never translate the player. Held cargo follows the transformed carry pose; released cargo stays at its physical 4D position. The camera's horizontal look direction is preserved where it survives the basis change. This is discrete selection of coordinate systems with continuous movement inside them; there is no continuous six-plane rotational control yet.

## Verification

```sh
python3 game/tests/run_tests.py
python3 game/tests/run_tests.py --rendered
```

The gameplay suite solves all three rooms under both gravity rules through actual walking/jumping/carrying. It checks exact coordinate preservation, W motion, hidden-coordinate locking, gravity on X/Y/Z/W, collider clearance and sprint timing/speed. Presentation checks dispatch keyboard input, switch systems, compare policies, and check survey, menus and progression. Rendered captures go to `/tmp/seam-basis-*.png`.

See `DESIGN.md` for the comparison and playtest questions. Automated solvability is established; first-time human playtesting is still needed for discovery and pacing.
