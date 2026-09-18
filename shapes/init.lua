local M = {}

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
