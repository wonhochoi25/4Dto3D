# 4D → 3D Projection Lab

## Runtime architecture

The reusable Godot-dependent runtime is now in **`scripts/core/`**. It runs without sandbox UI, IO, asset files, cameras, or renderers. See [the architecture and API guide](docs/ARCHITECTURE.md) for the canonical directory map and a minimal in-memory example.

- `scripts/core/`: geometry, math, transform tracks, hierarchy, simulation, recording, playback, and Session API.
- `scripts/io/`: file loading and application asset catalog.
- `scripts/rendering/`: projection presentation and Godot mesh adapters.
- `scripts/sandbox/`: Playground, procedural editor, controls, tabs, camera input.

Older paths mentioned below remain compatibility aliases. New code should import the canonical paths from the architecture guide. Session mutations own history invalidation; inspector widgets are views of objects, not their owners. Simulation evaluates 4D transforms only, and projection occurs when displaying a frame.

Run `python3 tools/verify_core_isolation.py /path/to/godot` to verify dependency boundaries and execute the core in a minimal temporary project containing no other application code.


Godot 4.7 viewer for editing 4D vertex coordinates and displaying a linear 3D projection. The 4D model is authoritative; rendering never changes it.

## Run and controls

Open `project.godot` and press F5.

- Select a shape from the left dropdown. Each shape retains its edits during the session; switching clears undo history.
- Edit the 3×4 matrix, then Apply. Reset matrix restores XYZ. Shape switching leaves the matrix unchanged.
- Select a vertex ID or focus its field. Gold highlights that vertex and its incident edges.
- Edit X/Y/Z/W and commit with Enter or by leaving the field. Connections remain fixed.
- Previous/Next navigates 16-vertex pages. Selection uses global vertex IDs and can remain on another page.
- Reset selected / Reset all restores generated coordinates. Undo/Redo includes edits and resets, but not camera or projection changes.
- Screen-edge arrow tabs independently collapse and restore the panels.
- Hold right mouse outside the panels to look. Release or press Esc to free the cursor. WASD moves relative to the camera; Q/E moves vertically; Shift triples speed. Movement pauses while UI has focus.

The single numeric increment is `FIELD_STEP` in `scripts/ui/ui_settings.gd`, currently **0.001**, preserving the user's latest setting. Both matrix and vertex fields use it, without shape-specific overrides. SpinBox values are quantized to that increment when edited; generated model coordinates retain full precision until changed.

## Available shapes

All initial vertices lie at distance 2 from the origin for comparable framing. Editing is unrestricted and can break regularity or move hypersphere samples off their surface.

| Shape | Vertices | Edges | Edges per vertex |
| --- | ---: | ---: | ---: |
| Tesseract (8-cell) | 16 | 32 | 4 |
| Hypersphere (sampled) | 80 | 208 | Varies |
| 5-cell (simplex) | 5 | 10 | 4 |
| 16-cell | 8 | 24 | 6 |
| 24-cell | 24 | 96 | 8 |
| 120-cell | 600 | 1200 | 4 |
| 600-cell | 120 | 720 | 12 |

The hypersphere is a coarse wireframe approximation: normalize the nonzero `{-1,0,1}⁴` boundary lattice points to radius 2, then connect neighboring samples on shared cube-boundary faces. These lines are chords, not intrinsic sphere edges. The six regular polytopes have their actual vertex-edge graphs; faces and 3D cells are not rendered.

## Architecture

```text
scripts/
  main.gd                         Signal wiring, active model selection/cache
  fly_camera.gd                   Independent viewing camera
  shapes/
    shape_4d.gd                   Base model and common generator helpers
    shape_registry.gd             Dropdown catalog and factory
    tesseract.gd                  One generator per shape
    hypersphere.gd
    simplex.gd
    cell16.gd
    cell24.gd
    cell120.gd
    cell600.gd
    coordinate_orbits.gd          Signed/even permutation helper
  geometry/
    projection_4d.gd              Pure matrix projection
    geometry_editor.gd            Coordinate edits, reset, undo/redo
  rendering/
    shape_renderer.gd             Wireframe, MultiMesh markers, axes, highlight
  ui/
    collapsible_panel.gd          Shared panel shell and edge tab
    projection_panel.gd           Shape dropdown and matrix form
    vertex_editor_panel.gd        Paged coordinate editor
    ui_settings.gd                Shared numeric field increment
```

`scripts/shape_4d.gd` is only a compatibility alias for the base class; use the registry to construct concrete shapes. Main creates the renderer and panels at runtime. The scene stores the root and camera.

### Shape contract

Every shape extends `shapes/shape_4d.gd` and provides:

- `display_name` and optional `description`.
- `vertices: Array[Vector4]`: editable coordinates with stable index IDs.
- `edges: Array[Vector2i]`: undirected pairs of vertex indices, stored once each.
- `original_vertices`: a snapshot captured after generation for exact resets.

There is no projection, UI, camera, or history logic in shape generators. Moving a vertex changes all incident edges implicitly because edges reference indices. Edge connectivity is generated once, never reconstructed from edited distances.

### Data flow

```text
Dropdown → Main → Registry/cache → GeometryEditor + vertex table
Vertex field → coordinate_changed → GeometryEditor → changed
  → synchronize visible fields → Projection4D → ShapeRenderer
Matrix Apply → matrix_applied → Projection4D → redraw
Selection → vertex_selected → renderer highlight
```

`GeometryEditor` stores copies of before/after vertex arrays in UndoRedo. Undo restores through the same path as an edit, and field synchronization suppresses edit signals to prevent recursive history actions. History is cleared on a model switch because vertex IDs belong to a specific shape.

The table constructs only 16 rows at a time. The renderer uses one MultiMesh for vertex spheres instead of hundreds of separate marker nodes. Edits rebuild the modest line mesh; camera movement does not. Selection updates only the highlight. Gold ignores depth testing so overlapping projections remain selectable through the table.

## Projection math

For a column vector `p = (x,y,z,w)`, `q = P p` where P is 3×4:

```text
q.x = rows[0].dot(p)
q.y = rows[1].dot(p)
q.z = rows[2].dot(p)
```

Columns represent input X/Y/Z/W; rows represent output X/Y/Z. XYZ selects the first three coordinates. Setting rows to `(1,0,0,0)`, `(0,1,0,0)`, `(0,0,0,1)` gives XYW. Arbitrary coefficients mix and scale axes. This is a linear map, not a slice or perspective division.

Discarded directions are invisible in that projection. Distinct 4D vertices can overlap, but remain separate model vertices. Output axes label the 3D view, not the original 4D axes.

## Generator construction

- Tesseract: the four bits of ID 0–15 encode coordinate signs; XOR of one bit finds a neighbor. Edge length is 2.
- Simplex: a tetrahedral base at constant W plus a fifth point yields five equidistant centered vertices.
- 16-cell: positive and negative coordinate-axis points.
- 24-cell: signed permutations of `(1,1,0,0)`.
- 600-cell: signed permutations of `(2,0,0,0)` and `(1,1,1,1)`, plus even coordinate permutations of `(φ,1,1/φ,0)` with all sign choices.
- 120-cell: four full signed-permutation orbits and three even-permutation orbits, explicitly listed in its generator.

Here `φ=(1+sqrt(5))/2`. Even refers to coordinate permutation parity, not the number of negative signs. Duplicate orbit points are removed before normalization. For regular polytopes, shortest-distance vertex pairs give edges. These checks are performed during generation only.

Coordinate references:

- [Heckman, Coxeter Groups](https://www.math.ru.nl/~heckman/CoxeterGroups.pdf), H4 / 600-cell coordinates.
- [ENS research report LIENS-96-6](https://www.di.ens.fr/reports/1996/liens-96-6.A4.pdf), 120-cell coordinate groups.

## Add a shape

1. Create `scripts/shapes/my_shape.gd` extending the base model.
2. Generate vertices and valid edge pairs in `_init()`; set the display name.
3. Optionally normalize the initial size. Use `connect_shortest_pairs()` only when shortest pairs are the intended edges; it is not a general-purpose topology detector.
4. Call `capture_original()` after generation.
5. Add one entry with a unique stable ID, dropdown name, and preloaded generator to `ShapeRegistry.ENTRIES`.
6. Add expected counts and geometric invariants to the verification script.

No changes to Main, projection, renderer, or UI are required. Generators should provide finite, unique positions and a nonempty edge graph; the current renderer expects connected wireframe geometry.

## Verification

From the project directory:

```sh
godot --headless --path . --script res://tests/verify.gd
```

The suite checks all shape counts, unique vertices/edges, index validity, connectedness, radius/centering, and regular-polytope edge lengths/degrees. Integration checks cover scene startup, seven dropdown entries, bounded page sizes, page edits, selection, exact reset, undo/redo, cached geometry, matrix application, discarded-axis behavior, panel collapse, and layout bounds.

## Scope

One shape is displayed at a time. There is no persistent save/load, multiple-object scene editing, face/cell rendering, constraint solver, slicing, or procedural animation. Manual 4D transforms are available in the Transform tab. UI is designed for the configured 1440×900 viewport; narrow windows can crowd the two panels. Rendering and actual mouse behavior should be checked in an interactive Godot run as well as headless tests.

## 4D transforms (PRSA)

The left panel now has **Projection** and **Transform** tabs. The shape dropdown is shared above them, and the edge tab collapses both. Transform controls scroll if needed.

- Position X/Y/Z/W: the destination of the local anchor.
- Anchor X/Y/Z/W: the local pivot, subtracted before scale and rotation.
- Scale X/Y/Z/W: identity is `(1,1,1,1)`; negative and zero scales are allowed.
- Uniform scale: when enabled, the next scale-field edit sets all four factors to that value. Enabling the toggle alone does not alter the shape.
- Rotation: six plane angles in degrees, applied in order **XY → XZ → XW → YZ → YW → ZW**. A positive rotation in plane (i,j) sends `i' = cos(t)i - sin(t)j`, `j' = sin(t)i + cos(t)j`.
- Reset transform restores zero position/anchor/angles and unit scale. It preserves the uniform-scale and anchor-compensation preferences.
- Keep shape in place defaults on. An anchor change `delta` adds `RS * delta` to Position, so the complete transformed shape is unchanged. Turn it off to change the pivot without compensating Position.

Committed parameter edits immediately redraw. The selected-vertex readout shows original 4D coordinates, transformed 4D coordinates, and projected 3D coordinates, rounded to three decimals for display.

`scripts/geometry/transform_4d.gd` owns the math and parameters; `scripts/ui/transform_panel.gd` emits input signals. Main connects them and caches a transform for each shape. The vertex editor continues to edit the original model. Vertex undo/redo does not include transform changes, and transforms are not saved between runs.

The pipeline is now:

```text
base vertices → Transform4D (5×5 PRSA) → Projection4D (3×4) → renderer
```

Matrices use row-major arrays of 25 floats and column-vector multiplication. The homogeneous coordinate is the fifth component; physical W is still the fourth. The combined matrix is `P * R * S * A`, where `A = T(-anchor)` and `P = T(position)`. Applying it gives `R S (v-anchor) + position`. Plane rotation matrices are left-multiplied in application order, so `R = Rzw Ryw Ryz Rxw Rxz Rxy`.

The combined matrix is built once per transformed vertex batch. Transforming never overwrites the base geometry or its reset snapshot. Selection highlights, counts, and readouts all use transformed positions.

Run the transform checks with:

```sh
godot --headless --path . --script res://tests/verify_transform.gd
```

They cover identity, translation, six 90° rotations, the worked PRSA example, independent sequential composition, distance preservation, compensated/uncompensated anchors, field signals, uniform scale, per-shape transform caching, reset, base-geometry preservation, readouts, and layout bounds. Animation is not implemented yet; it can later drive these same parameters.

Rotation controls include live sliders for all six planes alongside precise numeric fields. Sliders default to −180°…180° and expand to accommodate typed multi-turn angles. Reset and shape switching synchronize both controls.

Scale controls also have four live sliders and shared **Min / Max / Apply range** controls, initially −3…3. Bounds are session-wide UI settings and do not change geometry. Applying a narrower range expands it to include every current scale; typed out-of-range scales also expand it. Invalid or inverted bounds are rejected. Uniform scale updates all sliders; Reset transform restores scale 1 while retaining the range (expanding it if necessary). Zero collapses an axis and negative scale reflects it.

## Procedural workspace and browser-style tabs

F5 now launches `scenes/app.tscn`. The original `scenes/main.tscn` and Playground scripts are unchanged and instantiated inside the first, unclosable tab. **+** opens a new empty procedural experiment. **×** frees that experiment; switching away pauses its timeline. Each tab owns a separate SubViewport/World3D, camera, input processing, and data. Tabs exist only in memory; closing a procedural tab discards it.

In Procedural, choose a shape and **Add shape**. Add multiple instances independently. Select its tree row to open its inline editor, which has visibility, color, opacity, optional edge overlay, Remove, and five expression sections:

- Position: four scalar expressions (default 0).
- Rotation: XY/XZ/XW/YZ/YW/ZW angle expressions, output in degrees (default 0).
- Scale: four expressions (default 1).
- Anchor: four expressions (default 0), with optional edit-time compensation described below.
- Projection: twelve independent scalar expressions, one for each output/input coefficient (default XYZ). For example, `X ← W` controls the contribution of W to displayed X.

**Apply expressions** compiles and validates all 30 fields as a unit. Editing text does not alter the running programs until Apply succeeds. Syntax/name errors identify the field and preserve the previously applied expressions. Runtime errors pause playback and preserve the time and geometry of the last fully valid frame across every shape. Scrubbing back to a valid time clears runtime errors.

`t` is seconds and can be negative. Examples:

```text
Rotation XW: 30*t
Position W: 2*sin(t)
Scale X: 1+0.25*cos(2*t)
Projection X ← X: cos(t)
Projection X ← W: sin(t)
```

The expression evaluator allows arithmetic and a whitelist of pure scalar functions: `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`, `abs`, `sqrt`, `pow`, `exp`, `log`, `floor`, `ceil`, `round`, `min`, `max`, `clamp`, `lerp`, `fmod`, `sign`, `deg_to_rad`, and `rad_to_deg`. Constants are `PI`, `TAU`, and `E`. Trig functions take radians. Exponentiation uses `pow(x,y)`. There is no scene/object access, arbitrary scripting, stateful integration, or random function. Expressions are limited to 512 characters.

The timeline has forward/reverse play, Pause, Restart, speed, looping, an exact time field, a slider, and editable Start/End bounds. **Set range** validates both bounds together. Scrubbing pauses; it evaluates all objects directly at that time rather than stepping through previous states. At a range boundary, playback stops unless Loop is enabled. Restart pauses and returns to Start.

### Projected faces

Procedural objects render transparent, lit, double-sided projected faces, not a convex hull. Polygon face tables live in `data/faces/`; their vertex IDs match the existing generators. There are 24 tesseract squares, 10 simplex triangles, 32 16-cell triangles, 96 24-cell triangles, 720 120-cell pentagons, and 1200 600-cell triangles. The sampled hypersphere has 192 quadrilateral patches; they approximate its surface structure and need not be planar after normalization. Each patch is triangulated consistently.

At each requested time the renderer fan-triangulates transformed/projected faces and skips collapsed triangles. Shared face cycles are stored once. Overlap is intentional: these are internal and external projected 4D faces. Standard alpha blending can show ordering artifacts, especially where transparent faces intersect or lie within one mesh. Color/opacity and an optional edge overlay are available for interpretation. This is not order-independent transparency.

`tools/generate_faces.gd` regenerates the tables deterministically from the graph's shortest face cycles. When exporting a packaged game, include `data/faces/*.json` in the export preset's non-resource file filter.

### New components

- `app_shell.gd`: tab lifecycle, isolated viewports, active/inactive processing.
- `procedural/procedural_scene.gd`: experiment composition and atomic time evaluation.
- `procedural/procedural_object.gd`: independent model, expressions, face data, appearance.
- `procedural/math_expression.gd`: restricted compile/evaluate wrapper.
- `procedural/object_card.gd`: draft expression form and field errors.
- `procedural/timeline.gd`: playback and scrubbing controls.
- `procedural/face_renderer.gd`: projected triangle surfaces and optional edges.

Run `res://tests/verify_procedural.gd` headlessly for tab lifecycle/isolation, deterministic reverse evaluation, independent projection, compile/runtime error handling, face mesh creation, timeline bounds/looping, negative time, and UI size checks. Existing Playground and transform suites remain applicable. A local headless CPU benchmark with all seven shapes was about 4 ms per frame for evaluation plus mesh generation; this excludes GPU transparency rendering and is not an interactive framerate guarantee.

Procedural sidebar selection uses an indented scene tree. Select one shape to open its inline Geometry and Group tabs. Expression drafts survive selection and hierarchy changes. The sidebar fits its visible content and scrolls when needed. Playback buttons and time status are centered.

Procedural anchor edits now have a per-shape **Keep shape in place when editing anchor** checkbox (on by default) in the Anchor section. On Apply, an anchor expression change adds the constant correction `RS(t_edit) * (a_new(t_edit) - a_old(t_edit))` to the Position expressions. The adjusted expressions are shown in the Position fields. This preserves the pose at the current time for anchor-only edits; simultaneously changing scale/rotation/position still has its intended effect. Compensation runs only when applying changed anchor expressions, never during playback. Animated anchors remain animated, and their future trajectory can change; scrubbing remains deterministic. Disable the checkbox for direct anchor edits without compensation.

## Custom JSON shapes

Put one shape per JSON file in `data/custom_shapes/`, then restart the application. The registry scans this folder once at startup, sorts filenames, and adds each file to both shape dropdowns using its `name`. Built-ins keep their existing entries. File paths are cache IDs, so identical names do not share geometry. Each procedural Add shape creates a fresh instance; Playground caches its own instance.

`vertices` contains `[x,y,z,w]` points, `edges` contains pairs of zero-based indices, and optional `faces` contains ordered convex planar polygon index lists. Coordinates are loaded literally. Without faces, procedural rendering defaults to edges. The files remain trusted sandbox data, not a general import format with extensive validation.

Optional expression defaults use this structure (shown separately from the required geometry):

```json
{
  "procedural_defaults": {
    "geometry": {
      "position": {"X": "sin(t)", "W": "2"},
      "rotation": {"XW": "30*t"},
      "scale": {"X": "2", "Y": "1"},
      "anchor": {"W": "1"},
      "projection": [["1","0","0","0"], ["0","1","0","0"], ["0","0","1","0"]]
    },
    "group": {
      "position": {"Y": "3"},
      "rotation": {"ZW": "15*t"},
      "scale": "1",
      "anchor": {"X": "0"}
    }
  }
}
```

Position, geometry scale, and anchor use X/Y/Z/W keys. Rotation uses XY/XZ/XW/YZ/YW/ZW in degrees. Group scale is one uniform expression. Projection is three output rows by four input columns. Values may be expression strings or numbers; omitted fields keep identity defaults.

Both sets of defaults compile before inserting the pair, at the current timeline time. Invalid expressions report their component and field in the sidebar and prevent insertion. Position and anchor initialize literally, without edit-time compensation. After loading, both editor tabs are editable normally and no longer depend on the file. Playground reads geometry only and ignores these procedural defaults.

The supplied `hi_4d.json` contains the word geometry and the rotation/projection expressions for the reveal. Use a 0–10 second timeline to see HI → 4D → HI. Timeline and parenting are not stored in shape files.

Include `data/custom_shapes/*.json` and `data/faces/*.json` in export non-resource filters when packaging. Run `tests/verify_custom_shapes.gd` to check discovery, independent instances, defaults, editor values, and anchor initialization.

## Procedural scene hierarchy

The tree starts at **World**. Parents appear above indented children, with vertical hierarchy guides. **Add shape** automatically creates a group and its geometry leaf, shown as one shape row under World. There are no separate Add group or Wrap actions. Playground remains independent.

- Click a tree row to select it and open its editor beneath that row. Click **World** or empty viewport space to close the editor. Only one editor is open at a time.
- Click a rendered shape to select it. Selection highlights its edges in gold without changing its saved edge-overlay setting. Picking chooses the closest projected face; wire-only shapes use screen-space edge proximity.
- Drag a shape onto another shape to parent it, or onto **World** to unparent it. The selected shape also has a **Parent** dropdown. Internally, its group becomes a child of the destination group, never of the destination geometry. Cycles are rejected.
- Group arrows collapse descendants independently of selection. Rename the selected node with its name field and Enter.
- **Remove shape** in either tab deletes the selected group/geometry pair. Child shapes move up to its parent, preserving their current world poses.

The **Group** tab exposes position, six rotation planes, one uniform scale, and anchor expressions. These affect the shape itself and its descendants. The **Geometry** tab retains independent four-axis scale, appearance, and its own 3×4 projection, affecting only that shape. Both tabs preserve drafts and the selected tab across tree rebuilds. Group transforms affect all descendants; geometry transforms affect only that leaf. Group uniform scale keeps inherited transforms free of nonuniform-scale-induced shear. Projection happens after the complete 4D transform chain and is never inherited from another shape.

`procedural/scene_graph_4d.gd` owns stable node IDs, parent links, matrix offsets, and recursive time evaluation independently of Godot's 3D node hierarchy. `hierarchy_row.gd` supplies drag/drop behavior; `procedural_scene.gd` builds the tree and manages selection. `procedural_object.gd` evaluates local expressions for either node type.

For each node, the 5×5 world matrix is:

```text
world(t) = parent_world(t) * parenting_offset * local_PRSA(t)
```

Parenting pauses time and preserves the world pose at that time by replacing the group’s fixed offset. The geometry matrix and both tabs’ expressions stay unchanged:

```text
new_offset = inverse(new_parent_world(t_edit))
             * old_parent_world(t_edit) * old_offset
```

Expressions and their drafts remain intact. Later motion follows the new parent, so the trajectory at other times may change. Scrubbing remains deterministic because the offset is constant. This requires no inverse of the child's transform, so zero-scale children can be reparented. A singular destination parent is rejected because a world-preserving inverse is unavailable.

Run `res://tests/verify_hierarchy.gd` headlessly for nested transforms, keep-world parenting/unparenting, cycle prevention, singular-parent handling, group removal, reverse-time determinism, implicit pairs, Geometry versus Group transform scope, editor/tab preservation, drag/drop, and viewport selection.


## Fixed-step simulation timeline

Procedural time now uses 1/60-second steps relative to Start. Slider and time-field requests snap to the nearest step within the range; an End value between steps stops at the last complete step. Speed changes playback rate, not simulation step size. Fractional playback time accumulates across render frames.

Forward playback restores recorded states before extending the recording. Reverse restores earlier snapshots; it never integrates physics backward. Restart restores Start without deleting the recording. Loop wraps the playback cursor and restores the recorded state, rather than carrying the final state into the next loop. Unrecorded seeks simulate forward in bounded batches and display progress; the previously displayed frame stays visible until the target is ready. Invalid steps pause playback and preserve the displayed frame.

Changing position, rotation, scale, anchor, adding/removing shapes, or parenting clears the recording and returns to Start. Projection-only edits, camera changes, and appearance do not invalidate physics state. Changing Start resets; changing End trims or extends the available range. Each experiment has independent in-memory history, discarded when closed. There is no recording before Start.

`simulation_4d.gd` owns the stepping state. Its initial test-body API supports constant 4D linear velocity and six-plane angular velocity, with packed position, velocity, orientation, and angular-velocity snapshots. `simulation_recording.gd` owns history and restoration. `timeline.gd` owns playback controls, and `procedural_scene.gd` coordinates seeking and display.

Current user-created shapes are still expression-driven: procedural transforms are recomputed at the selected time, while step validation checks expressions along unrecorded forward paths. Snapshots store dynamic state only, never vertex arrays or meshes. No dynamic-body UI, forces, gravity, or collision response has been introduced yet; the stepping API is the foundation for that next stage. Memory grows with recorded steps and dynamic-body count within the chosen range.

Run `tests/verify_recording.gd` for constant-velocity integration, exact restoration, extending history after reverse playback, bounded seeks, trimming, edit invalidation, projection preservation, and fractional-step accumulation.
