# SEAM: coordinate-system revision

## Correction to the first playable

The first campaign replaced the demo's changing coordinate systems with fixed W layers. This revision removes that replacement. There is one authored 4D world and one persistent 4D player position. Changing XYZ/XZW/XYW/YZW changes which coordinate is hidden, which three coordinates can move, and how those coordinates are drawn. It never sets the player W to a layer number. Held cells are treated as attachments and follow the player into the new coordinate frame; released objects keep their 4D coordinates.

W movement is continuous, with the same grounded motor as X/Y movement whenever W is horizontal. A coordinate becomes frozen only when hidden by the current frame. Gravity always belongs to the visible axes, and the rendered scene is oriented so that the chosen gravity points down on screen. The player collider, eye offset, jump, carry offset, targeting and floor support all use the same frame.

This follows the demo's underlying geometry/slice and swept-collision approach, adding human-sized gravity-oriented movement in place of flying. The technical demo and its original scenes are preserved.

## Gravity comparison and recommendation

**Priority (`Z > X > Y > W`) is the campaign default.** Each system has a stable, learnable down direction. The player chooses a coordinate system at a station and can predict its floor. This reduces extra decisions while learning a difficult spatial mechanic. Room one teaches a single change: XYZ uses −Z with an XY floor; XYW uses −X with a YW floor. The original X wall is the new supporting floor.

The exact proposed priority has an important limitation: among the four three-axis systems, Z wins in XYZ, XZW and YZW; X wins in XYW. Y and W never win. Therefore XYZ → XZW does **not** change gravity with this order. That isn't a reason to silently substitute another rule; it is shown in the HUD and documented in the controls.

**Selectable gravity is a playable comparison mode.** At a station the player cycles the negative direction of each visible axis. Their selection persists through a system change if the axis survives; otherwise the priority rule supplies a valid axis. This permits XZW with −W gravity, giving the requested XZ floor. It also permits gravity on Y and multiple ways to traverse the same world. The cost is another state to reason about: returning to XYZ may retain −X until the player explicitly chooses −Z. Room three makes that difference concrete.

Both rules have passing, physically traversed solution routes through all three rooms. Additional tests exercise −W jumping, −Y landing and clearance rejection. This verifies their mechanical consistency. It does not establish which is more enjoyable for human players. The recommendation is to use priority for the authored introduction and keep selectable gravity accessible for experimenting before deciding whether later puzzles should require it.

A third option for a future revision is a fixed gravity assigned separately to each coordinate system (for example XYZ→Z, XZW→W). That would make the example transition automatic without giving the player another control. It is not currently mixed into either tested rule.

## Station constraint

Stations authorize frame/gravity changes. They are finite 4D trigger regions at actual corners and landmarks. Their positions do not move between frames. Station A in room one offers all four systems for calibration; later rooms focus on the two systems used by their puzzle. Number keys select directly; Tab cycles only the supported systems.

A frame change preserves every player coordinate exactly and tests the reoriented 1.7m standing box against 4D solids before committing. Unsupported space is allowed so a gravity change can cause a real fall. Grounded station visits establish recovery checkpoints; choosing gravity that pulls the player away from the station does not overwrite the last stable checkpoint. B restores that checkpoint. No timed switches or expendable charges are used.

## 01 — The Wall Is a Floor

A barrier divides the XYZ room in Y and occupies the full X/Z range, so neither jumping nor walking farther sideways in XYZ gets around it. It is finite in W. Near the X wall, the calibration station lets the player choose XYW. Removing Z makes it fixed, and the priority rule moves down from Z to X. The existing X boundary now supports the player as a floor; the floor axes are Y and W.

The player walks W from approximately 0.9 to 4, walks past Y=0 beyond the barrier's fourth-dimensional edge, then uses the far station to return to XYZ and reach the exit at Y=7, W=4. Every coordinate change during the route comes from walking, jumping or gravity. Other calibration systems are intentionally available so the player can compare alternate solutions.

## 02 — A Different Depth

The wall's doorway exists only for 5.6 < W < 7.4. XZW keeps Z as down and exposes W as a floor direction while freezing Y. The player carries a cell to W≈6.5, then returns to XYZ to pass the opening and feed the far-side receiver.

Held cargo follows the player into the new frame automatically. Its local carry pose is transformed and its hidden coordinate is centered on the player's slice, with collision-aware placement near architecture. The player can return to XYZ while looking in any direction; no separate cell alignment or exact positioning test is required. The room focuses on finding the doorway through continuous W movement. Released cells retain their physical 4D positions.

## 03 — Above and Beside

The barrier spans W but ends below Z=2.8. A staircase raises the player to Z≈3.25. Switching to XYW freezes that earned height while X becomes down. Walking along the old X wall now carries the player above the obstruction without flying. W must also change to reach the far station and the exit's slice.

The held cell follows the visible-axis motion and accompanies each frame change automatically. At the far station, returning to XYZ restores Z movement; the player lands on the far platform, descends, powers the exit and finishes. Under selectable gravity, returning to XYZ retains −X, so the player must choose −Z before descending. This is a useful comparison of predictable system rules versus explicit player control.

## Sprint and movement

Double-tap W within 280ms and hold the second press to run. Walking is 4.5m/s and running is 7.2m/s; jump height stays the same. Movement is relative to horizontal look in the current floor plane. The sprint latch clears on W release, pause, focus loss, survey, recovery and frame changes. Keyboard repeat does not count as a second tap.

There is no pitch-driven flight, automatic stair stepping or arbitrary coordinate-entry control. Jump is a grounded impulse opposite current gravity. Carrying uses swept collision on the active axes. Released cells keep their gravity axis, so a camera change alone does not move them.

## Next human playtest

- Does the first wall-to-floor change make sense without reading coordinates? Surface colors remain tied to physical axes to aid recognition.
- Do players discover continuous W movement, or expect switching to teleport them?
- Does the held cell remain easy to track across frame changes and gravity changes? Carrying should stay reliable without precise alignment.
- Is selectable gravity worth the extra control/state? Try XZW with −W and compare the same room under priority.
- Is the raised-station route readable and comfortable in first person? The basis reorients the world immediately; a small camera bank settles quickly. A longer full 4D transition animation is not implemented.
