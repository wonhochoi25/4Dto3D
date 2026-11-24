# 4D object interaction

Preload `res://hybrid/object_interaction/grab_controller_4d.gd` and create one controller per player. Create a `Grab.Box` for each grabbable object using its center, unscaled half-extents, and optional starting scale. Set `can_resize`, `can_carry`, and `min_scale`/`max_scale` on each box to match the puzzle.

- Call `pickup(box, action, player, slice, forward, obstacles)` with `Grab.Hold.RESIZE` or `Grab.Hold.CARRY`. The caller selects the candidate, and the controller checks reach, slice visibility, and line of sight.
- Call `update(player, slice, forward, delta, obstacles)` on physics ticks and apply the box’s accepted `position` and `scale` to the scene. Use `move_player` if the room needs the shared collision-checked movement behavior.
- Call `try_switch_slice` with the destination slice before switching the view. Switch when the result is `Grab.Result.OK`. A failed transfer leaves the box at its current pose.
- Call `release()` to keep the last accepted position and scale. The room can use the returned box to check a placement target or trigger.

An axis-aligned slice uses a dictionary such as `{"axes": [3, 1, 2], "hidden": 0}` for YZW with Y up. The player and all box bounds use XYZW coordinates, and `forward` uses display coordinates. Supply obstacles as `Array[Dictionary]` with `low` and `high` bounds. Exclude the candidate or held box from the obstacles. Include released solid objects for player movement.

The [perspective test room adapter](../perspective_test/test_room_world.gd) shows how to publish accepted poses to `Scene4D` and keep target checks in the room. [Box placement](box_placement_4d.gd) can also be used independently for continuous collision checks between axis-aligned 4D boxes.
