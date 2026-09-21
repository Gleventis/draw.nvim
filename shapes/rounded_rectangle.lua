local canvas =
  require "draw.canvas"

local discovery =
  require "draw.discovery"

local topology =
  require "draw.topology"

local rect_utils =
  require "draw.shapes.rect_utils"

local M = {}

---------------------------------------------------------------------
-- Rounded corner characters
---------------------------------------------------------------------

local corners = {
  top_left = "╭",
  top_right = "╮",
  bottom_left = "╰",
  bottom_right = "╯",
}

---------------------------------------------------------------------
-- Is this perimeter cell one of our corners?
---------------------------------------------------------------------

local function corner_char(
  row,
  col,
  top,
  bottom,
  left,
  right
)
  if row == top and col == left then
    return corners.top_left
  end

  if row == top and col == right then
    return corners.top_right
  end

  if row == bottom and col == left then
    return corners.bottom_left
  end

  if row == bottom and col == right then
    return corners.bottom_right
  end

  return nil
end

---------------------------------------------------------------------
-- Construct rounded rectangle metadata (no drawing)
--
-- Used both when creating a new shape and when rediscovering one
-- from buffer content.  All shape methods are attached here so that
-- both paths produce identical shape tables.
---------------------------------------------------------------------

function M.make_shape(top, bottom, left, right)
  return {
    type = "rounded_rectangle",

    top = top,
    bottom = bottom,
    left = left,
    right = right,

    -------------------------------------------------------------------
    -- span(shape, row) → left, right
    -------------------------------------------------------------------
    span = function(s, _row)
      return s.left, s.right
    end,

    -------------------------------------------------------------------
    -- on_boundary(shape, row, col) → boolean
    -------------------------------------------------------------------
    on_boundary = function(s, row, col)
      local within =
        row >= s.top
        and row <= s.bottom
        and col >= s.left
        and col <= s.right

      local edge =
        row == s.top
        or row == s.bottom
        or col == s.left
        or col == s.right

      return within and edge
    end,

    -------------------------------------------------------------------
    -- outside_cells(shape, side) → list of {row, col}
    -------------------------------------------------------------------
    outside_cells = function(s, side)
      local result = {}

      if side == "left" or side == "right" then
        local col =
          side == "left"
          and s.left - 1
          or s.right + 1

        if col < 0 then
          return result
        end

        for row = s.top + 1, s.bottom - 1 do
          table.insert(result, { row = row, col = col })
        end

        return result
      end

      local row =
        side == "up"
        and s.top - 1
        or s.bottom + 1

      if row < 0 then
        return result
      end

      for col = s.left + 1, s.right - 1 do
        table.insert(result, { row = row, col = col })
      end

      return result
    end,
  }
end

---------------------------------------------------------------------
-- Draw rounded rectangle
---------------------------------------------------------------------

function M.draw(
  buf,
  start_row,
  start_col,
  end_row,
  end_col,
  region
)
  local top =
    math.min(start_row, end_row)

  local bottom =
    math.max(start_row, end_row)

  local left =
    math.min(start_col, end_col)

  local right =
    math.max(start_col, end_col)

  -------------------------------------------------------------------
  -- Need actual width and height
  -------------------------------------------------------------------

  if top == bottom or left == right then
    vim.notify(
      "Rounded box needs both width and height",
      vim.log.levels.WARN
    )

    return false
  end

  canvas.ensure_col(
    buf,
    bottom,
    right,
    region
  )

  -------------------------------------------------------------------
  -- Validate the entire perimeter before changing anything
  -------------------------------------------------------------------

  local ok, err =
    rect_utils.validate_rectangular_perimeter(
      buf,
      top,
      bottom,
      left,
      right,
      region
    )

  if not ok then
    vim.notify(err, vim.log.levels.WARN)
    return false
  end

  -------------------------------------------------------------------
  -- Draw perimeter
  --
  -- Use the shared loop, passing a rounded corner renderer.
  -- If the corner cell was empty, write the rounded char.
  -- If another line already occupies it, fall back to topology
  -- so we get a proper junction.
  -------------------------------------------------------------------

  rect_utils.draw_rectangular_perimeter(
    buf,
    top,
    bottom,
    left,
    right,
    function(row, col, t, b, l, r, current_char, connections)
      local rc = corner_char(row, col, t, b, l, r)

      if
        rc ~= nil
        and (
          current_char == ""
          or current_char == " "
        )
      then
        return rc
      end

      return topology.to_char(connections)
    end,
    region
  )

  -------------------------------------------------------------------
  -- Return normal shape metadata.
  --
  -- LABEL and navigation only care about these bounds.
  -------------------------------------------------------------------

  return true, M.make_shape(top, bottom, left, right)
end

---------------------------------------------------------------------
-- Register with the discovery system
--
-- Called at require-time so that discovery.scan() finds rounded
-- rectangles without hard-coding this scanner inside discovery.lua.
---------------------------------------------------------------------

discovery.register_rectangular_scanner {
  type = "rounded_rectangle",

  top_left =
    "╭",

  top_right =
    "╮",

  bottom_left =
    "╰",

  bottom_right =
    "╯",

  make_shape =
    M.make_shape,
}

return M
