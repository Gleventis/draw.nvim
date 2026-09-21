local M = {}

---------------------------------------------------------------------
-- Shape contract
--
-- Every shape table must contain:
--
--   type    string   Shape type name ("rectangle", "rounded_rectangle",
--                    "diamond", ...). Used for display and discovery.
--
--   top     number   Top row of the bounding box (0-indexed).
--   bottom  number   Bottom row of the bounding box (0-indexed).
--   left    number   Leftmost column of the bounding box (0-indexed).
--   right   number   Rightmost column of the bounding box (0-indexed).
--
-- Optional methods (called as shape.method(shape, ...)):
--
--   writable_bounds(shape, row) -> left, right | nil, nil
--       Writable interior columns for one row.
--       Default: left+1..right-1 for rows inside top..bottom.
--       Override for non-rectangular interiors (e.g. diamonds).
--
--   entry_point(shape) -> row, col
--       Preferred cursor position when entering the shape.
--       Default: top+1, left+1.
--
--   center(shape) -> row, col
--       Center coordinates for navigation scoring.
--       Default: midpoint of bounding box.
--
--   span(shape, row) -> left, right | nil, nil
--       All cells owned by the shape on this row (outline + interior).
--       Used by delete.lua to erase the full shape.
--
--   on_boundary(shape, row, col) -> boolean
--       Whether (row, col) sits on the shape outline.
--       Used by connector.lua for collision detection.
--
--   outside_cells(shape, side) -> { {row, col}, ... }
--       Cells just outside the shape on the given side
--       ("left", "right", "up", "down").
--       Used by connector.lua for anchor and reverse detection.
--
-- Shapes are constructed by their renderer's make_shape() function,
-- which attaches the appropriate methods. Discovery must use the
-- same make_shape() so rediscovered shapes carry the full interface.
---------------------------------------------------------------------

---------------------------------------------------------------------
-- Register shape
---------------------------------------------------------------------

function M.add(state, shape)
  state.next_shape_id =
    (state.next_shape_id or 0) + 1

  shape.id =
    state.next_shape_id

  table.insert(
    state.shapes,
    shape
  )

  return shape
end

---------------------------------------------------------------------
-- Unregister shape
---------------------------------------------------------------------

function M.remove(
  state,
  shape
)
  if
    state == nil
    or shape == nil
  then
    return false
  end

  for index =
    #state.shapes,
    1,
    -1
  do
    local candidate =
      state.shapes[index]

    if candidate.id == shape.id then
      table.remove(
        state.shapes,
        index
      )

      return true
    end
  end

  return false
end

---------------------------------------------------------------------
-- Writable horizontal bounds for one row
--
-- Returns:
--
--   left, right
--
-- where both values are writable cells.
---------------------------------------------------------------------

function M.row_bounds(shape, row)
  if shape.writable_bounds then
    return shape.writable_bounds(
      shape,
      row
    )
  end

  -------------------------------------------------------------------
  -- Default rectangular behavior
  -------------------------------------------------------------------

  if
    row <= shape.top
    or row >= shape.bottom
  then
    return nil, nil
  end

  return
    shape.left + 1,
    shape.right - 1
end

---------------------------------------------------------------------
-- Is a cell inside the writable part of a shape?
---------------------------------------------------------------------

function M.contains(shape, row, col)
  local left, right =
    M.row_bounds(
      shape,
      row
    )

  if
    left == nil
    or right == nil
  then
    return false
  end

  return
    col >= left
    and col <= right
end

---------------------------------------------------------------------
-- Find shape containing a point
---------------------------------------------------------------------

function M.find_containing(
  shape_list,
  row,
  col
)
  for i = #shape_list, 1, -1 do
    local shape =
      shape_list[i]

    if
      M.contains(
        shape,
        row,
        col
      )
    then
      return shape
    end
  end

  return nil
end

---------------------------------------------------------------------
-- Shape center
---------------------------------------------------------------------

function M.center(shape)
  if shape.center then
    return shape.center(shape)
  end

  return
    (shape.top + shape.bottom) / 2,
    (shape.left + shape.right) / 2
end

---------------------------------------------------------------------
-- Preferred navigation entry point
---------------------------------------------------------------------

function M.entry_point(shape)
  if shape.entry_point then
    return shape.entry_point(shape)
  end

  return
    shape.top + 1,
    shape.left + 1
end

return M
