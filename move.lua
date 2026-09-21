local canvas =
  require "draw.canvas"

local M = {}

---------------------------------------------------------------------
-- Capture all cells the shape currently occupies.
--
-- Iterates every row in the shape's bounding box, uses
-- shape.span(shape, row) to get the column range for that row,
-- then reads each character from the buffer.
--
-- Returns a list of tables, each with absolute coordinates and the
-- character stored there:
--
--   { { row = r, col = c, char = ch }, ... }
---------------------------------------------------------------------

function M.capture_cells(buf, shape, region)
  local cells = {}

  for row = shape.top, shape.bottom do
    local left, right =
      shape.span(shape, row)

    if left ~= nil and right ~= nil then
      for col = left, right do
        local char =
          canvas.get_char(buf, row, col, region)

        table.insert(cells, {
          row = row,
          col = col,
          char = char,
        })
      end
    end
  end

  return cells
end

---------------------------------------------------------------------
-- Blank all cells the shape currently occupies.
--
-- Uses canvas.undo_join() before each write when context.changed is
-- already true so that all erasures collapse into one undo block.
-- Sets context.changed = true after the first write.
---------------------------------------------------------------------

function M.erase_cells(buf, shape, context, region)
  for row = shape.top, shape.bottom do
    local left, right =
      shape.span(shape, row)

    if left ~= nil and right ~= nil then
      for col = left, right do
        if context.changed then
          canvas.undo_join()
        end

        canvas.set_char(buf, row, col, " ", region)
        context.changed = true
      end
    end
  end
end

---------------------------------------------------------------------
-- Write previously captured cells at a new position.
--
-- Each cell is placed at (cell.row + delta_row, cell.col + delta_col).
-- Uses canvas.undo_join() before each write when context.changed is
-- already true so all writes collapse into one undo block.
-- Sets context.changed = true after the first write.
---------------------------------------------------------------------

function M.write_cells(buf, cells, delta_row, delta_col, context, region)
  for _, cell in ipairs(cells) do
    local row = cell.row + delta_row
    local col = cell.col + delta_col

    if context.changed then
      canvas.undo_join()
    end

    canvas.set_char(buf, row, col, cell.char, region)
    context.changed = true
  end
end

---------------------------------------------------------------------
-- Check that the destination is clear for a one-cell move.
--
-- Rejects the move if any destination cell:
--   - has row < 0 or col < 0 (out of buffer bounds)
--   - contains a non-space character not currently occupied by the shape
--   - overlaps a boundary cell of any other tracked shape
--
-- Returns true when the move is safe, false otherwise.
---------------------------------------------------------------------

function M.validate(buf, state, shape, delta_row, delta_col, region)
  -- Build a set of current cell positions for fast lookup.
  local current = {}
  for row = shape.top, shape.bottom do
    local left, right = shape.span(shape, row)
    if left ~= nil and right ~= nil then
      for col = left, right do
        current[row .. "," .. col] = true
      end
    end
  end

  -- Check every destination cell.
  for row = shape.top, shape.bottom do
    local left, right = shape.span(shape, row)
    if left ~= nil and right ~= nil then
      for col = left, right do
        local new_row = row + delta_row
        local new_col = col + delta_col

        -- Reject out-of-bounds destinations.
        if new_row < 0 or new_col < 0 then
          return false
        end

        -- Only check cells not already occupied by this shape.
        if not current[new_row .. "," .. new_col] then
          -- Reject non-empty cells.
          local ch = canvas.safe_get_char(buf, new_row, new_col, region)
          if ch ~= "" and ch ~= " " then
            return false
          end

          -- Reject if another shape's boundary is here.
          for _, other in ipairs(state.shapes) do
            if
              other.id ~= shape.id
              and other.on_boundary(other, new_row, new_col)
            then
              return false
            end
          end
        end
      end
    end
  end

  return true
end

---------------------------------------------------------------------
-- Shift all coordinate fields on the shape table.
--
-- Updates top, bottom, left, right by the given deltas.
-- For diamonds, also updates center_left and center_right.
---------------------------------------------------------------------

function M.update_metadata(shape, delta_row, delta_col)
  shape.top    = shape.top    + delta_row
  shape.bottom = shape.bottom + delta_row
  shape.left   = shape.left   + delta_col
  shape.right  = shape.right  + delta_col

  if shape.center_left ~= nil then
    shape.center_left  = shape.center_left  + delta_col
    shape.center_right = shape.center_right + delta_col
  end
end

---------------------------------------------------------------------
-- Orchestrate a single one-cell move in the given direction.
--
-- Sequence: validate → capture → erase → write → update_metadata.
-- Returns true when the move was applied, false when the destination
-- is blocked (collision with another shape or out-of-bounds).
--
-- All buffer writes are joined into the caller's undo block via
-- context.changed (same contract as erase_cells / write_cells).
---------------------------------------------------------------------

function M.execute(buf, state, shape, direction, context, region)
  local delta = canvas.directions[direction]
  local delta_row = delta.row
  local delta_col = delta.col

  if not M.validate(buf, state, shape, delta_row, delta_col, region) then
    return false
  end

  local cells = M.capture_cells(buf, shape, region)
  M.erase_cells(buf, shape, context, region)
  M.write_cells(buf, cells, delta_row, delta_col, context, region)
  M.update_metadata(shape, delta_row, delta_col)

  return true
end

return M
