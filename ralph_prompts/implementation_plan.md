# draw.nvim — Simplification & Extensibility Plan

## Overview

Simplify the codebase by eliminating duplication, and introduce clean extension points so future features (move shapes, resize, new shape types, obstacle-aware routing, shape selection, centered labels) can be added without scattering type checks across modules.

**Priorities**: correctness > clarity > performance.

**Constraint**: Every change must keep the plugin functionally identical. No new features, no behavior changes.

---

## Phase 1: Foundation — Centralize shared utilities

These changes are leaf-level. Nothing depends on them yet, so they can't break anything.

### ~~Step 1: Add `canvas.safe_get_char(buf, row, col)`~~ ✅ Done

Add a non-mutating character accessor to `canvas.lua` that returns `""` for out-of-bounds positions without extending the buffer.

Currently duplicated as local `char_at()` in: `connector.lua`, `discovery.lua`, `erase.lua`.

- **File**: `canvas.lua`
- **Change**: Add `M.safe_get_char(buf, row, col)` function
- **Verify**: `:Draw`, draw lines, erase cells, create shapes, connect shapes, undo/redo — all behave identically

### Step 2: Replace `char_at()` in `connector.lua` with `canvas.safe_get_char`

- **File**: `connector.lua`
- **Change**: Remove local `char_at`, replace all calls with `canvas.safe_get_char`
- **Verify**: Create two shapes, connect them in all 4 directions, delete shape with connectors

### Step 3: Replace `char_at()` in `discovery.lua` with `canvas.safe_get_char`

- **File**: `discovery.lua`
- **Change**: Remove local `char_at`, replace all calls with `canvas.safe_get_char`
- **Verify**: Create rectangles, rounded rectangles, diamonds → exit Draw → re-enter Draw → shapes rediscovered correctly

### Step 4: Replace `char_at()` in `erase.lua` with `canvas.safe_get_char`

- **File**: `erase.lua`
- **Change**: Remove local `char_at` usage (erase.lua uses inline bounds checks rather than a named function, but the pattern is the same — replace inline bounds-checked reads with `canvas.safe_get_char`)
- **Verify**: Enter ERASE mode, erase lines/corners/arrowheads/diamond edges, verify neighbor repair works

### Step 5: Expose `arrows.arrowheads` table

`connector.lua` duplicates the arrowheads lookup table `{ left = "◀", right = "▶", up = "▲", down = "▼" }`.

- **File**: `arrows.lua`
- **Change**: Expose the existing local `arrowheads` table as `M.arrowheads`
- **Verify**: Existing `arrows.place()` still works. No behavior change.

### Step 6: Replace local `arrowheads` in `connector.lua` with `arrows.arrowheads`

- **File**: `connector.lua`
- **Change**: Remove local `arrowheads` table, use `arrows.arrowheads` everywhere
- **Verify**: Connectors draw arrowheads correctly in all 4 directions, bidirectional upgrade works

### Step 7: Replace local `opposite` in `connector.lua` with `canvas.directions`

`connector.lua` has `local opposite = { left = "right", ... }`. This is already available as `canvas.directions[dir].opposite`.

- **File**: `connector.lua`
- **Change**: Remove local `opposite` table, replace `opposite[dir]` with `canvas.directions[dir].opposite`
- **Verify**: All connector operations (create, reverse detection, deletion, pruning) work correctly

---

## Phase 2: Shape interface enrichment

Eliminate scattered `if shape.type == "diamond"` checks by giving shapes self-describing methods.

### Step 8: Add `shape.span(shape, row)` method to rectangle shapes

Returns `(left, right)` — all cells owned by the shape on that row (for deletion). For rectangles this is `(shape.left, shape.right)` on rows `top..bottom`.

- **File**: `shapes/rectangle.lua`
- **Change**: Attach `span` function to the shape metadata returned by `M.draw()`
- **Verify**: Create rectangle, inspect returned shape table has `.span` method

### Step 9: Add `shape.span(shape, row)` method to rounded_rectangle shapes

Same as Step 8 but for rounded rectangles. Identical implementation (same bounding box).

- **File**: `shapes/rounded_rectangle.lua`
- **Change**: Attach `span` function to shape metadata
- **Verify**: Create rounded rectangle, inspect returned shape table has `.span` method

### Step 10: Add `shape.span(shape, row)` method to diamond shapes

For diamonds, `span` delegates to `outline_for_row()` which returns the actual left/right outline cells.

- **File**: `shapes/diamond.lua`
- **Change**: Attach `span` function to shape metadata (using existing `outline_for_row`)
- **Verify**: Create diamond, inspect returned shape table has `.span` method

### Step 11: Use `shape.span()` in `delete.lua` instead of type-checking

- **File**: `delete.lua`
- **Change**: Remove local `shape_span()` function and its `if shape.type == "diamond"` check. Replace with `shape.span(shape, row)` call. Remove `require "draw.shapes.diamond"` import.
- **Verify**: Delete a rectangle, a rounded rectangle, and a diamond. Each is fully erased without affecting surrounding content.

### Step 12: Add `shape.on_boundary(shape, row, col)` method to rectangle shapes

Returns `true` if `(row, col)` is on the shape's perimeter.

- **File**: `shapes/rectangle.lua`
- **Change**: Attach `on_boundary` function to shape metadata
- **Verify**: Shape table has method, returns correct results for corner/edge/interior/outside cells

### Step 13: Add `shape.on_boundary(shape, row, col)` method to rounded_rectangle shapes

Same perimeter logic as rectangle.

- **File**: `shapes/rounded_rectangle.lua`
- **Change**: Attach `on_boundary` function to shape metadata
- **Verify**: Same as Step 12 for rounded rectangles

### Step 14: Add `shape.on_boundary(shape, row, col)` method to diamond shapes

For diamonds, delegates to `outline_for_row()` and checks `col == left or col == right`.

- **File**: `shapes/diamond.lua`
- **Change**: Attach `on_boundary` function to shape metadata
- **Verify**: Returns correct results for diamond outline cells vs interior vs outside

### Step 15: Use `shape.on_boundary()` in `connector.lua` instead of type-checking

- **File**: `connector.lua`
- **Change**: Remove local `on_shape_boundary()` function and its diamond/rectangle branches. Replace `on_shape_boundary(shape, row, col)` calls with `shape.on_boundary(shape, row, col)`. Remove `require "draw.shapes.diamond"` import (if no longer needed after this + Step 17).
- **Verify**: Connect shapes in all directions, verify collision detection still rejects paths through other shapes

### Step 16: Add `shape.outside_cells(shape, side)` method to rectangle shapes

Returns a list of `{row, col}` cells just outside the shape on the given side. For rectangles: all cells one step outside the perimeter edge.

- **File**: `shapes/rectangle.lua`
- **Change**: Attach `outside_cells` function to shape metadata
- **Verify**: Method returns correct cells for all 4 sides

### Step 17: Add `shape.outside_cells(shape, side)` method to rounded_rectangle shapes

Same as rectangle (identical bounding box geometry).

- **File**: `shapes/rounded_rectangle.lua`
- **Change**: Attach `outside_cells` function to shape metadata
- **Verify**: Method returns correct cells for all 4 sides

### Step 18: Add `shape.outside_cells(shape, side)` method to diamond shapes

For diamonds: top/bottom use the apex area, left/right use writable rows offset outward.

- **File**: `shapes/diamond.lua`
- **Change**: Attach `outside_cells` function to shape metadata
- **Verify**: Method returns correct cells for all 4 sides of a diamond

### Step 19: Use `shape.outside_cells()` in `connector.lua` instead of type-checking

- **File**: `connector.lua`
- **Change**: Remove local `side_outside_cells()` function and its diamond/rectangle branches. Replace calls with `shape.outside_cells(shape, side)`. Remove `require "draw.shapes.diamond"` if now unused.
- **Verify**: Connect shapes in all directions (rectangle↔rectangle, rectangle↔diamond, diamond↔diamond). Reverse detection and bidirectional upgrade still work.

### Step 20: Ensure `discovery.lua` attaches shape methods to discovered shapes

Discovery reconstructs shape metadata from buffer content. The discovered shapes must also have the new methods.

- **File**: `discovery.lua`
- **Change**: For rectangular shapes, attach `span`, `on_boundary`, `outside_cells` to discovered metadata. For diamonds, this is already handled via `diamond.make_shape()` — verify it includes the new methods from Step 10/14/18.
- **Verify**: Exit Draw, re-enter Draw, then delete/connect discovered shapes — all operations work

---

## Phase 3: Unify rectangle and rounded rectangle drawing

### Step 21: Extract shared rectangular validation logic

Both `rectangle.lua` and `rounded_rectangle.lua` have identical validation: size check, `ensure_col`, perimeter loop checking arrowheads and non-drawable chars.

- **File**: New helper or within `shapes/rectangle.lua` (to be shared)
- **Change**: Extract `validate_rectangular_perimeter(buf, top, bottom, left, right)` returning `(success, error_message)`
- **Verify**: Create rectangles and rounded rectangles on empty space (succeeds), on text (fails), on arrowheads (fails)

### Step 22: Extract shared `connections_for()` function

Identical function exists in both rectangle.lua and rounded_rectangle.lua.

- **File**: Same location as Step 21
- **Change**: Extract to a shared location (either `shapes/init.lua` or keep in `rectangle.lua` and import)
- **Verify**: Rectangle and rounded rectangle perimeter topology is identical to before

### Step 23: Extract shared rectangular drawing loop

The perimeter drawing loop is identical except for corner cell rendering. Extract the loop, parameterize the corner strategy.

- **File**: Same shared location
- **Change**: Extract `draw_rectangular_perimeter(buf, top, bottom, left, right, corner_renderer)` where `corner_renderer(row, col, top, bottom, left, right, current_char, connections)` returns the character to write. Rectangle: always `topology.to_char(connections)`. Rounded rectangle: rounded char if cell was empty, topology otherwise.
- **Verify**: Create both shape types, verify they render identically to before, including when overlapping existing lines

### Step 24: Simplify `rectangle.lua` to use shared drawing

- **File**: `shapes/rectangle.lua`
- **Change**: Replace validation + drawing with calls to shared functions from Steps 21-23
- **Verify**: Rectangles draw correctly in all cases (empty space, overlapping lines, adjacent shapes)

### Step 25: Simplify `rounded_rectangle.lua` to use shared drawing

- **File**: `shapes/rounded_rectangle.lua`
- **Change**: Replace validation + drawing with calls to shared functions, passing rounded corner renderer
- **Verify**: Rounded rectangles draw correctly, corners are rounded on empty cells and topology junctions on intersections

---

## Phase 4: Simplify init.lua

### Step 26: Extract state-access helper in `init.lua`

- **File**: `init.lua`
- **Change**: Add `local function get_state()` that returns `buf, state` or `nil, nil`. Replace the repeated `local buf = ... local state = states[buf] if state == nil then return end` pattern in all action functions.
- **Verify**: All Draw mode operations work (draw, erase, shapes, labels, navigation, connectors, delete, undo/redo, quit)

### Step 27: Convert directional arrow keymaps to table-driven registration

- **File**: `init.lua`
- **Change**: Replace the 4 individual `map()` calls for arrow keys and 4 for shift-arrow keys with a loop over `canvas.directions`
- **Verify**: Arrow keys draw in all 4 directions, shift-arrow keys move without drawing

### Step 28: Convert shape keymaps to table-driven registration

- **File**: `init.lua`
- **Change**: Replace the 3 individual `map()` calls for B/R/D with a loop over `shape_types`
- **Verify**: B, R, D create rectangles, rounded rectangles, and diamonds respectively

### Step 29: Convert navigation keymaps to table-driven registration

- **File**: `init.lua`
- **Change**: Replace the 4 `map()` calls for `hb/jb/kb/lb` with a loop over directions
- **Verify**: Shape navigation works in all 4 directions

### Step 30: Convert connector keymaps to table-driven registration

- **File**: `init.lua`
- **Change**: Replace the 4 `map()` calls for `hc/jc/kc/lc` with a loop over directions
- **Verify**: Connectors work in all 4 directions

### Step 31: Convert arrowhead keymaps to table-driven registration

- **File**: `init.lua`
- **Change**: Replace the 4 `map()` calls for `LA/RA/UA/DA` with a loop
- **Verify**: Arrowhead placement works in all 4 directions

---

## Phase 5: Extensible discovery

### Step 32: Add scanner registry to `discovery.lua`

- **File**: `discovery.lua`
- **Change**: Add `M.register(scan_fn)` that appends to an internal scanner list. Change `M.scan()` to iterate the registry instead of hard-coding scanner calls.
- **Verify**: Discovery still works (scanners not yet registered externally — keep existing hard-coded calls as fallback or register them inline during this step)

### Step 33: Register rectangular scanner from `shapes/rectangle.lua`

- **File**: `shapes/rectangle.lua`
- **Change**: Call `discovery.register(...)` at require-time with the rectangle corner chars and type
- **Verify**: Rectangles are discovered on `:Draw`

### Step 34: Register rounded rectangular scanner from `shapes/rounded_rectangle.lua`

- **File**: `shapes/rounded_rectangle.lua`
- **Change**: Call `discovery.register(...)` at require-time with rounded corner chars and type
- **Verify**: Rounded rectangles are discovered on `:Draw`

### Step 35: Register diamond scanner from `shapes/diamond.lua`

- **File**: `shapes/diamond.lua`
- **Change**: Call `discovery.register(...)` at require-time with diamond scan function
- **Verify**: Diamonds are discovered on `:Draw`

### Step 36: Remove hard-coded scanner calls from `discovery.lua`

- **File**: `discovery.lua`
- **Change**: Remove the explicit `scan_rectangular(...)` and `scan_diamonds(...)` calls from `M.scan()`. The registry handles it now.
- **Verify**: All three shape types still discovered correctly. Exit Draw, re-enter, verify shape count matches.

---

## Phase 6: Document the shape contract

### Step 37: Add shape interface documentation to `shapes/init.lua`

- **File**: `shapes/init.lua`
- **Change**: Add a comment block at the top documenting the shape contract — required fields (`type`, `top`, `bottom`, `left`, `right`), optional methods (`writable_bounds`, `entry_point`, `span`, `on_boundary`, `outside_cells`, `center`), and when each is called.
- **Verify**: N/A — documentation only

---

## Verification Checklist (after all phases)

Run through the full feature set:

- [ ] `:Draw` toggle on/off
- [ ] Arrow key line drawing (all 4 directions, corners, junctions)
- [ ] Shift+Arrow move without drawing
- [ ] Rectangle (B...B) — draw, label, delete, connect
- [ ] Rounded rectangle (R...R) — draw, label, delete, connect
- [ ] Diamond (D...D) — draw, label, delete, connect
- [ ] ERASE mode — erase lines, corners, arrowheads, shape edges
- [ ] `dd` safe row clearing inside all shape types
- [ ] `db` shape deletion with connector cleanup
- [ ] `hb/jb/kb/lb` navigation between shapes
- [ ] `hc/jc/kc/lc` connectors (straight, L-shaped, Z-shaped)
- [ ] Bidirectional connector upgrade
- [ ] `LA/RA/UA/DA` arrowhead placement
- [ ] Undo/redo with shape rediscovery
- [ ] Shape discovery on re-entering Draw mode
- [ ] LABEL mode with word wrapping
- [ ] `Esc` cancels pending shape
- [ ] `q` exits Draw mode, restores window options
