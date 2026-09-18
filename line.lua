local canvas =
  require "draw.canvas"

local topology =
  require "draw.topology"

local M = {}

function M.draw(direction)
  local buf =
    vim.api.nvim_get_current_buf()

  local delta =
    canvas.directions[direction]

  local row, col =
    canvas.current_position()

  local target_row =
    row + delta.row

  local target_col =
    col + delta.col

  if
    target_row < 0
    or target_col < 0
  then
    return
  end

  canvas.ensure_col(
    buf,
    row,
    col
  )

  canvas.ensure_col(
    buf,
    target_row,
    target_col
  )

  local current_char =
    canvas.get_char(
      buf,
      row,
      col
    )

  local target_char =
    canvas.get_char(
      buf,
      target_row,
      target_col
    )

  local current_connections =
    topology.from_char(
      current_char
    )

  local target_connections =
    topology.from_char(
      target_char
    )

  -------------------------------------------------------------------
  -- Normal text and arrowheads are not drawable topology cells.
  -------------------------------------------------------------------

  if
    current_connections == nil
    or target_connections == nil
  then
    canvas.set_cursor(
      buf,
      target_row,
      target_col
    )

    return
  end

  topology.add(
    current_connections,
    direction
  )

  topology.add(
    target_connections,
    delta.opposite
  )

  canvas.set_char(
    buf,
    row,
    col,
    topology.to_char(
      current_connections
    )
  )

  canvas.undo_join()

  canvas.set_char(
    buf,
    target_row,
    target_col,
    topology.to_char(
      target_connections
    )
  )

  canvas.set_cursor(
    buf,
    target_row,
    target_col
  )
end

return M
