local canvas =
  require "draw.canvas"

local shape_chars =
  require "draw.shape_chars"

local M = {}

---------------------------------------------------------------------
-- Register diamond outline characters
---------------------------------------------------------------------

shape_chars.register {
  "╱",
  "╲",
}

---------------------------------------------------------------------
-- Calculate the two outline cells for a row
---------------------------------------------------------------------

local function outline_for_row(
  shape,
  row
)
  local relative =
    row - shape.top

  local height =
    shape.bottom - shape.top

  local half =
    height / 2

  local factor
  local upper

  if relative <= half then
    upper = true

    factor =
      relative / half
  else
    upper = false

    factor =
      (height - relative)
      / (height - half)
  end

  local expansion =
    math.floor(
      factor
        * shape.max_expand
        + 0.5
    )

  local left =
    shape.center_left
    - expansion

  local right =
    shape.center_right
    + expansion

  return
    left,
    right,
    upper
end

---------------------------------------------------------------------
-- Writable interior for a particular row
---------------------------------------------------------------------

local function writable_bounds(
  shape,
  row
)
  if
    row <= shape.top
    or row >= shape.bottom
  then
    return nil, nil
  end

  local left, right =
    outline_for_row(
      shape,
      row
    )

  local writable_left =
    left + 1

  local writable_right =
    right - 1

  if writable_left > writable_right then
    return nil, nil
  end

  return
    writable_left,
    writable_right
end

---------------------------------------------------------------------
-- Preferred entry point
---------------------------------------------------------------------

local function entry_point(shape)
  local best_row = nil
  local best_left = nil
  local best_right = nil
  local best_width = -1

  for row =
    shape.top + 1,
    shape.bottom - 1
  do
    local left, right =
      writable_bounds(
        shape,
        row
      )

    if left ~= nil then
      local width =
        right - left + 1

      if width > best_width then
        best_width = width
        best_row = row
        best_left = left
        best_right = right
      end
    end
  end

  if best_row == nil then
    return
      math.floor(
        (shape.top + shape.bottom)
        / 2
      ),
      math.floor(
        (shape.left + shape.right)
        / 2
      )
  end

  return
    best_row,
    math.floor(
      (best_left + best_right)
      / 2
    )
end

---------------------------------------------------------------------
-- Construct diamond metadata
--
-- This is used both when:
--
--   1. creating a new diamond
--   2. rediscovering one from an existing file
---------------------------------------------------------------------

function M.make_shape(
  top,
  bottom,
  center_left,
  center_right,
  max_expand
)
  return {
    type = "diamond",

    top = top,
    bottom = bottom,

    left =
      center_left
      - max_expand,

    right =
      center_right
      + max_expand,

    center_left =
      center_left,

    center_right =
      center_right,

    max_expand =
      max_expand,

    writable_bounds =
      writable_bounds,

    entry_point =
      entry_point,
  }
end

---------------------------------------------------------------------
-- Expose geometry to the discovery system
---------------------------------------------------------------------

M.outline_for_row =
  outline_for_row

---------------------------------------------------------------------
-- Draw diamond
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

  local requested_left =
    math.min(
      start_col,
      end_col
    )

  local requested_right =
    math.max(
      start_col,
      end_col
    )

  local height =
    bottom - top

  local width =
    requested_right
    - requested_left

  -------------------------------------------------------------------
  -- Need enough room
  -------------------------------------------------------------------

  if
    height < 4
    or width < 4
  then
    vim.notify(
      "Diamond needs more width and height",
      vim.log.levels.WARN
    )

    return false
  end

  -------------------------------------------------------------------
  -- Two-character apex:
  --
  --     ╱╲
  -------------------------------------------------------------------

  local center_left =
    math.floor(
      (
        requested_left
        + requested_right
      ) / 2
    )

  local center_right =
    center_left + 1

  local left_capacity =
    center_left
    - requested_left

  local right_capacity =
    requested_right
    - center_right

  local max_expand =
    math.min(
      left_capacity,
      right_capacity
    )

  if max_expand < 1 then
    vim.notify(
      "Diamond is too narrow",
      vim.log.levels.WARN
    )

    return false
  end

  local shape =
    M.make_shape(
      top,
      bottom,
      center_left,
      center_right,
      max_expand
    )

  canvas.ensure_col(
    buf,
    bottom,
    shape.right
  )

  -------------------------------------------------------------------
  -- Validate outline first
  -------------------------------------------------------------------

  for row = top, bottom do
    local left,
      right =
      outline_for_row(
        shape,
        row
      )

    local left_char =
      canvas.get_char(
        buf,
        row,
        left
      )

    local right_char =
      canvas.get_char(
        buf,
        row,
        right
      )

    if
      left_char ~= ""
      and left_char ~= " "
    then
      vim.notify(
        "Cannot draw diamond over existing content",
        vim.log.levels.WARN
      )

      return false
    end

    if
      right_char ~= ""
      and right_char ~= " "
    then
      vim.notify(
        "Cannot draw diamond over existing content",
        vim.log.levels.WARN
      )

      return false
    end
  end

  -------------------------------------------------------------------
  -- Draw outline
  -------------------------------------------------------------------

  local first_change = true

  for row = top, bottom do
    local left,
      right,
      upper =
      outline_for_row(
        shape,
        row
      )

    local left_char
    local right_char

    if upper then
      left_char = "╱"
      right_char = "╲"
    else
      left_char = "╲"
      right_char = "╱"
    end

    if not first_change then
      canvas.undo_join()
    end

    canvas.set_char(
      buf,
      row,
      left,
      left_char
    )

    first_change = false

    canvas.undo_join()

    canvas.set_char(
      buf,
      row,
      right,
      right_char
    )
  end

  return true, shape
end

return M
