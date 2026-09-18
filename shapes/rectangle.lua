local canvas =
  require "draw.canvas"

local topology =
  require "draw.topology"

local arrows =
  require "draw.arrows"

local M = {}

---------------------------------------------------------------------
-- Required topology for a perimeter cell
---------------------------------------------------------------------

local function connections_for(
  row,
  col,
  top,
  bottom,
  left,
  right
)
  if row == top and col == left then
    return {
      down = true,
      right = true,
    }
  end

  if row == top and col == right then
    return {
      down = true,
      left = true,
    }
  end

  if row == bottom and col == left then
    return {
      up = true,
      right = true,
    }
  end

  if row == bottom and col == right then
    return {
      up = true,
      left = true,
    }
  end

  if row == top or row == bottom then
    return {
      left = true,
      right = true,
    }
  end

  return {
    up = true,
    down = true,
  }
end

---------------------------------------------------------------------
-- Draw rectangle
---------------------------------------------------------------------

function M.draw(
  buf,
  start_row,
  start_col,
  end_row,
  end_col
)
  local top =
    math.min(
      start_row,
      end_row
    )

  local bottom =
    math.max(
      start_row,
      end_row
    )

  local left =
    math.min(
      start_col,
      end_col
    )

  local right =
    math.max(
      start_col,
      end_col
    )

  if
    top == bottom
    or left == right
  then
    vim.notify(
      "Box needs both width and height",
      vim.log.levels.WARN
    )

    return false
  end

  canvas.ensure_col(
    buf,
    bottom,
    right
  )

  -------------------------------------------------------------------
  -- Validate perimeter
  -------------------------------------------------------------------

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
          vim.notify(
            "Cannot draw box over arrowheads",
            vim.log.levels.WARN
          )

          return false
        end

        local connections =
          topology.from_char(char)

        if connections == nil then
          vim.notify(
            "Cannot draw box over normal text",
            vim.log.levels.WARN
          )

          return false
        end
      end
    end
  end

  -------------------------------------------------------------------
  -- Draw perimeter
  -------------------------------------------------------------------

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
          connections_for(
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
          topology.to_char(
            connections
          )
        )

        first_change = false
      end
    end
  end

  -------------------------------------------------------------------
  -- Return metadata describing the shape.
  -------------------------------------------------------------------

  return true, {
    type = "rectangle",

    top = top,
    bottom = bottom,
    left = left,
    right = right,
  }
end

return M
