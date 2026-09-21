local canvas =
  require "draw.canvas"

local shapes =
  require "draw.shapes"

local connector = 
  require "draw.connector"

local M = {}

---------------------------------------------------------------------
-- Delete the shape under the cursor
---------------------------------------------------------------------

function M.delete_shape(state)
  if state == nil then
    return
  end

  -------------------------------------------------------------------
  -- Only available from normal DRAW mode.
  -------------------------------------------------------------------

  if state.mode ~= "draw" then
    vim.notify(
      "Shape deletion is available in DRAW mode",
      vim.log.levels.WARN
    )

    return
  end

  local buf =
    state.buf

  local row,
    col =
    canvas.current_position()

  -------------------------------------------------------------------
  -- Find current shape
  -------------------------------------------------------------------

  local shape =
    shapes.find_containing(
      state.shapes,
      row,
      col
    )

  if shape == nil then
    vim.notify(
      "Move inside a tracked shape first",
      vim.log.levels.WARN
    )

    return
  end

    -------------------------------------------------------------------
    -- Remove connectors attached to this shape first.
    -------------------------------------------------------------------

  local connectors_changed =
    connector.delete_attached(
      state,
      shape
    )

  -------------------------------------------------------------------
  -- Erase the shape.
  --
  -- Rectangles occupy their complete rectangular span.
  --
  -- Diamonds are erased row-by-row using their actual outline,
  -- which prevents us from destroying unrelated content that may
  -- exist inside the diamond's bounding box but outside its sides.
  -------------------------------------------------------------------

  local first_change =
    true

  for current_row =
    shape.top,
    shape.bottom
  do
    local left,
      right =
      shape.span(
        shape,
        current_row
      )

    if
      left ~= nil
      and right ~= nil
    then
      for current_col =
        left,
        right
      do
        if not first_change then
          canvas.undo_join()
        end

        canvas.set_char(
          buf,
          current_row,
          current_col,
          " "
        )

        first_change =
          false
      end
    end
  end

  -------------------------------------------------------------------
  -- Remove metadata
  -------------------------------------------------------------------

  shapes.remove(
    state,
    shape
  )

  -------------------------------------------------------------------
  -- Keep the cursor where it was.
  --
  -- The cell is blank now, but this feels less surprising than
  -- jumping somewhere else after deletion.
  -------------------------------------------------------------------

  canvas.set_cursor(
    buf,
    row,
    col
  )

  vim.notify(
    "-- SHAPE DELETED --"
  )
end

return M
