local canvas =
  require "draw.canvas"

local topology =
  require "draw.topology"

local arrows =
  require "draw.arrows"

local shape_chars =
  require "draw.shape_chars"

local M = {}

---------------------------------------------------------------------
-- Erase one cell
---------------------------------------------------------------------

function M.at(buf, row, col)
  local char =
    canvas.get_char(
      buf,
      row,
      col
    )

  -------------------------------------------------------------------
  -- Arrowheads
  -------------------------------------------------------------------

  if arrows.is_arrowhead(char) then
    canvas.set_char(
      buf,
      row,
      col,
      " "
    )

    return
  end

  -------------------------------------------------------------------
  -- Non-topology shape characters
  --
  -- Diamond:
  --
  --     ╱ ╲
  -------------------------------------------------------------------

  if shape_chars.is(char) then
    canvas.set_char(
      buf,
      row,
      col,
      " "
    )

    return
  end

  -------------------------------------------------------------------
  -- Normal topology
  -------------------------------------------------------------------

  local connections =
    topology.from_char(char)

  if connections == nil then
    return
  end

  if char == "" or char == " " then
    return
  end

  canvas.set_char(
    buf,
    row,
    col,
    " "
  )

  -------------------------------------------------------------------
  -- Repair connected neighbors
  -------------------------------------------------------------------

  for direction, delta
    in pairs(canvas.directions)
  do
    if connections[direction] then
      local neighbor_row =
        row + delta.row

      local neighbor_col =
        col + delta.col

      local neighbor_char =
        canvas.safe_get_char(
          buf,
          neighbor_row,
          neighbor_col
        )

      if
        not arrows.is_arrowhead(
          neighbor_char
        )
        and not shape_chars.is(
          neighbor_char
        )
      then
        local neighbor_connections =
          topology.from_char(
            neighbor_char
          )

        if
          neighbor_connections
          ~= nil
        then
          topology.remove(
            neighbor_connections,
            delta.opposite
          )

          canvas.undo_join()

          canvas.set_char(
            buf,
            neighbor_row,
            neighbor_col,
            topology.to_char(
              neighbor_connections
            )
          )
        end
      end
    end
  end
end

---------------------------------------------------------------------
-- Move and erase
---------------------------------------------------------------------

function M.move(direction)
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

  if target_row < 0 then
    target_row = 0
  end

  if target_col < 0 then
    target_col = 0
  end

  canvas.ensure_col(
    buf,
    target_row,
    target_col
  )

  M.at(
    buf,
    target_row,
    target_col
  )

  canvas.set_cursor(
    buf,
    target_row,
    target_col
  )
end

return M
