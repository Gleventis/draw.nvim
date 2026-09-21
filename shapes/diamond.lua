local canvas =
  require "draw.canvas"

local discovery =
  require "draw.discovery"

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

    ----------------------------------------------------------------
    -- span(shape, row) → left, right
    --
    -- Returns the two outline-column positions owned by this diamond
    -- on `row`.  Delegates to outline_for_row so the caller does not
    -- need to know about diamond geometry.
    ----------------------------------------------------------------
    span = function(s, row)
      local left, right =
        outline_for_row(s, row)

      return left, right
    end,

    ----------------------------------------------------------------
    -- on_boundary(shape, row, col) → boolean
    --
    -- Returns true if (row, col) lies on the diamond's outline.
    -- A cell is on the outline when it is within the bounding row
    -- range AND its column matches one of the two outline cells for
    -- that row as computed by outline_for_row.
    ----------------------------------------------------------------
    on_boundary = function(s, row, col)
      if row < s.top or row > s.bottom then
        return false
      end

      local left, right =
        outline_for_row(s, row)

      return col == left or col == right
    end,

    ----------------------------------------------------------------
    -- outside_cells(shape, side) → list of {row, col}
    --
    -- Returns cells just outside the diamond on the given side.
    -- Used by connector.lua to find candidate connector start/end
    -- positions adjacent to the shape boundary.
    --
    -- left/right: one column beyond the outline, for each interior
    --             row that has writable space (mirrors side_outside_cells
    --             logic in connector.lua)
    -- up/down:    one row beyond the apex, at the horizontal center
    ----------------------------------------------------------------
    outside_cells = function(s, side)
      local result = {}

      if side == "left" or side == "right" then
        for row = s.top + 1, s.bottom - 1 do
          local wl, wr =
            writable_bounds(s, row)

          if wl ~= nil and wr ~= nil then
            local left, right =
              outline_for_row(s, row)

            local col =
              side == "left"
              and left - 1
              or right + 1

            if col >= 0 then
              table.insert(
                result,
                { row = row, col = col }
              )
            end
          end
        end

        return result
      end

      local col =
        math.floor(
          (s.left + s.right) / 2
        )

      local row =
        side == "up"
        and s.top - 1
        or s.bottom + 1

      if row >= 0 then
        table.insert(
          result,
          { row = row, col = col }
        )
      end

      return result
    end,
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

---------------------------------------------------------------------
-- Character width of a row (used by the scanner)
---------------------------------------------------------------------

local function row_width(buf, row)
  local line =
    canvas.get_line(buf, row)

  return canvas.char_count(line)
end

---------------------------------------------------------------------
-- Maximum actual line width over a row range
---------------------------------------------------------------------

local function widest_row(buf, top, bottom)
  local widest = 0

  for row = top, bottom do
    widest =
      math.max(
        widest,
        row_width(buf, row)
      )
  end

  return widest
end

---------------------------------------------------------------------
-- Validate reconstructed diamond against buffer content
---------------------------------------------------------------------

local function diamond_matches(buf, shape)
  for row = shape.top, shape.bottom do
    local left, right, upper =
      outline_for_row(shape, row)

    local expected_left
    local expected_right

    if upper then
      expected_left = "╱"
      expected_right = "╲"
    else
      expected_left = "╲"
      expected_right = "╱"
    end

    if
      canvas.safe_get_char(
        buf,
        row,
        left
      ) ~= expected_left
    then
      return false
    end

    if
      canvas.safe_get_char(
        buf,
        row,
        right
      ) ~= expected_right
    then
      return false
    end
  end

  return true
end

---------------------------------------------------------------------
-- Scan diamonds
--
-- Diamond geometry is already distinctive because it uses:
--
--     ╱ ╲
--
-- rather than orthogonal connector topology.
---------------------------------------------------------------------

local function scan_diamonds(buf, results, seen)
  local line_count =
    vim.api.nvim_buf_line_count(buf)

  for top = 0, line_count - 1 do
    local width = row_width(buf, top)

    for center_left = 0, width - 2 do
      local center_right = center_left + 1

      ----------------------------------------------------------------
      -- Top apex:
      --
      --     ╱╲
      ----------------------------------------------------------------

      if
        canvas.safe_get_char(
          buf,
          top,
          center_left
        ) == "╱"

        and canvas.safe_get_char(
          buf,
          top,
          center_right
        ) == "╲"
      then
        ----------------------------------------------------------------
        -- Search for bottom apex:
        --
        --     ╲╱
        ----------------------------------------------------------------

        for bottom = top + 4, line_count - 1 do
          if
            canvas.safe_get_char(
              buf,
              bottom,
              center_left
            ) == "╲"

            and canvas.safe_get_char(
              buf,
              bottom,
              center_right
            ) == "╱"
          then
            local widest =
              widest_row(buf, top, bottom)

            local maximum_expand =
              math.min(
                center_left,
                widest - center_right - 1
              )

            local found = false

            ----------------------------------------------------------------
            -- Reconstruct possible original diamond width.
            ----------------------------------------------------------------

            for max_expand = 1, maximum_expand do
              local shape =
                M.make_shape(
                  top,
                  bottom,
                  center_left,
                  center_right,
                  max_expand
                )

              if diamond_matches(buf, shape) then
                local key =
                  table.concat(
                    {
                      shape.type,
                      shape.top,
                      shape.bottom,
                      shape.left,
                      shape.right,
                    },
                    ":"
                  )

                if not seen[key] then
                  seen[key] = true

                  table.insert(results, shape)
                end

                found = true

                break
              end
            end

            if found then
              break
            end
          end
        end
      end
    end
  end
end

---------------------------------------------------------------------
-- Register with the discovery system
--
-- Called at require-time so that discovery.scan() finds diamonds
-- without hard-coding the scanner inside discovery.lua.
---------------------------------------------------------------------

discovery.register(function(buf, results, seen)
  scan_diamonds(buf, results, seen)
end)

return M
