local canvas =
  require "draw.canvas"

local topology =
  require "draw.topology"

local arrows =
  require "draw.arrows"

local M = {}

---------------------------------------------------------------------
-- Validate that every perimeter cell of the given rectangular bounds
-- can accept a box edge.
--
-- A cell is invalid if it holds an arrowhead or a non-drawable
-- character (normal text).  Pure lines and empty cells are fine.
--
-- Returns true on success, or false + an error message on failure.
-- The caller is responsible for notifying the user.
---------------------------------------------------------------------

function M.validate_rectangular_perimeter(
  buf,
  top,
  bottom,
  left,
  right
)
  for row = top, bottom do
    for col = left, right do
      local perimeter =
        row == top
        or row == bottom
        or col == left
        or col == right

      if perimeter then
        local char =
          canvas.get_char(
            buf,
            row,
            col
          )

        if arrows.is_arrowhead(char) then
          return false,
            "Cannot draw box over arrowheads"
        end

        if topology.from_char(char) == nil then
          return false,
            "Cannot draw box over normal text"
        end
      end
    end
  end

  return true
end

---------------------------------------------------------------------
-- Required topology for a perimeter cell of a rectangular shape.
--
-- Returns the set of directions that must be connected at (row, col)
-- given the bounding box (top, bottom, left, right).
---------------------------------------------------------------------

function M.connections_for(
  row,
  col,
  top,
  bottom,
  left,
  right
)
  if row == top and col == left then
    return { down = true, right = true }
  end

  if row == top and col == right then
    return { down = true, left = true }
  end

  if row == bottom and col == left then
    return { up = true, right = true }
  end

  if row == bottom and col == right then
    return { up = true, left = true }
  end

  if row == top or row == bottom then
    return { left = true, right = true }
  end

  return { up = true, down = true }
end

---------------------------------------------------------------------
-- Draw the perimeter of a rectangular bounding box.
--
-- Iterates every perimeter cell, merges the required topology
-- connections, then delegates final character selection to
-- corner_renderer, which allows callers to substitute rounded
-- corners or other decorations.
--
-- Args:
--   buf:             Neovim buffer handle (e.g. 0).
--   top:             Top row of the bounding box (e.g. 2).
--   bottom:          Bottom row of the bounding box (e.g. 6).
--   left:            Left column of the bounding box (e.g. 4).
--   right:           Right column of the bounding box (e.g. 14).
--   corner_renderer: function(row, col, top, bottom, left, right,
--                             current_char, connections) → string
--                    Returns the character to write at (row, col).
---------------------------------------------------------------------

function M.draw_rectangular_perimeter(
  buf,
  top,
  bottom,
  left,
  right,
  corner_renderer
)
  local first_change = true

  for row = top, bottom do
    for col = left, right do
      local perimeter =
        row == top
        or row == bottom
        or col == left
        or col == right

      if perimeter then
        local current_char =
          canvas.get_char(
            buf,
            row,
            col
          )

        local connections =
          topology.from_char(
            current_char
          )

        local needed =
          M.connections_for(
            row,
            col,
            top,
            bottom,
            left,
            right
          )

        for direction, enabled
          in pairs(needed)
        do
          if enabled then
            topology.add(
              connections,
              direction
            )
          end
        end

        if not first_change then
          canvas.undo_join()
        end

        canvas.set_char(
          buf,
          row,
          col,
          corner_renderer(
            row,
            col,
            top,
            bottom,
            left,
            right,
            current_char,
            connections
          )
        )

        first_change = false
      end
    end
  end
end

return M
