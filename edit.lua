local canvas =
  require "draw.canvas"

local shapes =
  require "draw.shapes"

local M = {}

---------------------------------------------------------------------
-- Clear the writable part of the current shape row
---------------------------------------------------------------------

function M.clear_row(state)
  if state == nil then
    return
  end

  if state.mode ~= "draw" then
    vim.notify(
      "dd is available in DRAW mode",
      vim.log.levels.WARN
    )

    return
  end

  local buf =
    vim.api.nvim_get_current_buf()

  local region =
    state.region

  local row, col =
    canvas.current_position(region)

  -------------------------------------------------------------------
  -- Find the shape we're currently inside
  -------------------------------------------------------------------

  local shape =
    shapes.find_containing(
      state.shapes,
      row,
      col
    )

  if shape == nil then
    vim.notify(
      "Cursor is not inside a tracked shape",
      vim.log.levels.WARN
    )

    return
  end

  -------------------------------------------------------------------
  -- Find writable bounds for this particular row.
  --
  -- Rectangle:
  --
  -- │ hello world │
  --   ^^^^^^^^^^^
  --
  -- Diamond:
  --
  --     ╱ hello ╲
  --       ^^^^^
  -------------------------------------------------------------------

  local left, right =
    shapes.row_bounds(
      shape,
      row
    )

  if left == nil or right == nil then
    return
  end

  -------------------------------------------------------------------
  -- Blank cells instead of deleting characters.
  -------------------------------------------------------------------

  local first_change = true

  for current_col = left, right do
    if not first_change then
      canvas.undo_join()
    end

    canvas.set_char(
      buf,
      row,
      current_col,
      " ",
      region
    )

    first_change = false
  end

  -------------------------------------------------------------------
  -- Put cursor back at the first writable cell
  -------------------------------------------------------------------

  canvas.set_cursor(
    buf,
    row,
    left,
    region
  )
end

return M
