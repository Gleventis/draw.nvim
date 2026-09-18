local canvas =
  require "draw.canvas"

local diamond =
  require "draw.shapes.diamond"

local M = {}

---------------------------------------------------------------------
-- Safe character access
---------------------------------------------------------------------

local function char_at(
  buf,
  row,
  col
)
  if row < 0 or col < 0 then
    return ""
  end

  local line_count =
    vim.api.nvim_buf_line_count(buf)

  if row >= line_count then
    return ""
  end

  local line =
    canvas.get_line(
      buf,
      row
    )

  if col >= canvas.char_count(line) then
    return ""
  end

  return canvas.get_char(
    buf,
    row,
    col
  )
end

---------------------------------------------------------------------
-- Character width of a row
---------------------------------------------------------------------

local function row_width(
  buf,
  row
)
  local line =
    canvas.get_line(
      buf,
      row
    )

  return canvas.char_count(line)
end

---------------------------------------------------------------------
-- Duplicate protection
---------------------------------------------------------------------

local function shape_key(shape)
  return table.concat(
    {
      shape.type,
      shape.top,
      shape.bottom,
      shape.left,
      shape.right,
    },
    ":"
  )
end

local function add_result(
  results,
  seen,
  shape
)
  local key =
    shape_key(shape)

  if seen[key] then
    return
  end

  seen[key] =
    true

  table.insert(
    results,
    shape
  )
end

---------------------------------------------------------------------
-- Strict horizontal edge
--
-- IMPORTANT:
--
-- Shape discovery should identify SHAPES, not arbitrary topology.
--
-- Previously we accepted:
--
--     ─ ┬ ┴ ┼
--
-- along an edge.
--
-- That made bent connectors capable of looking like rectangles.
--
-- Our smart connector system deliberately stops OUTSIDE shapes, so
-- real shape borders should remain pure:
--
--     ─────────────
--
-- Therefore discovery now requires literal ─ cells.
---------------------------------------------------------------------

local function strict_horizontal_edge(
  buf,
  row,
  left,
  right
)
  if right - left < 2 then
    return false
  end

  for col =
    left + 1,
    right - 1
  do
    if
      char_at(
        buf,
        row,
        col
      ) ~= "─"
    then
      return false
    end
  end

  return true
end

---------------------------------------------------------------------
-- Strict vertical edge
--
-- Same principle:
--
-- actual box:
--
--     │
--     │
--     │
--
-- not arbitrary connector topology.
---------------------------------------------------------------------

local function strict_vertical_edge(
  buf,
  col,
  top,
  bottom
)
  if bottom - top < 2 then
    return false
  end

  for row =
    top + 1,
    bottom - 1
  do
    if
      char_at(
        buf,
        row,
        col
      ) ~= "│"
    then
      return false
    end
  end

  return true
end

---------------------------------------------------------------------
-- Scan rectangular shapes
---------------------------------------------------------------------

local function scan_rectangular(
  buf,
  style,
  results,
  seen
)
  local line_count =
    vim.api.nvim_buf_line_count(buf)

  for top = 0, line_count - 1 do
    local width =
      row_width(
        buf,
        top
      )

    for left = 0, width - 1 do
      ----------------------------------------------------------------
      -- Find exact top-left corner
      ----------------------------------------------------------------

      if
        char_at(
          buf,
          top,
          left
        ) == style.top_left
      then
        ----------------------------------------------------------------
        -- Look for exact top-right corner
        ----------------------------------------------------------------

        for right =
          left + 2,
          width - 1
        do
          if
            char_at(
              buf,
              top,
              right
            ) == style.top_right
            and strict_horizontal_edge(
              buf,
              top,
              left,
              right
            )
          then
            ------------------------------------------------------------
            -- Search downward for exact matching bottom
            ------------------------------------------------------------

            for bottom =
              top + 2,
              line_count - 1
            do
              if
                char_at(
                  buf,
                  bottom,
                  left
                ) == style.bottom_left

                and char_at(
                  buf,
                  bottom,
                  right
                ) == style.bottom_right

                and strict_horizontal_edge(
                  buf,
                  bottom,
                  left,
                  right
                )

                and strict_vertical_edge(
                  buf,
                  left,
                  top,
                  bottom
                )

                and strict_vertical_edge(
                  buf,
                  right,
                  top,
                  bottom
                )
              then
                add_result(
                  results,
                  seen,
                  {
                    type =
                      style.type,

                    top =
                      top,

                    bottom =
                      bottom,

                    left =
                      left,

                    right =
                      right,
                  }
                )

                ----------------------------------------------------------------
                -- First valid matching bottom belongs to this top edge.
                ----------------------------------------------------------------

                break
              end
            end
          end
        end
      end
    end
  end
end

---------------------------------------------------------------------
-- Validate reconstructed diamond
---------------------------------------------------------------------

local function diamond_matches(
  buf,
  shape
)
  for row =
    shape.top,
    shape.bottom
  do
    local left,
      right,
      upper =
      diamond.outline_for_row(
        shape,
        row
      )

    local expected_left
    local expected_right

    if upper then
      expected_left =
        "╱"

      expected_right =
        "╲"
    else
      expected_left =
        "╲"

      expected_right =
        "╱"
    end

    if
      char_at(
        buf,
        row,
        left
      ) ~= expected_left
    then
      return false
    end

    if
      char_at(
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
-- Maximum actual line width over row range
---------------------------------------------------------------------

local function widest_row(
  buf,
  top,
  bottom
)
  local widest = 0

  for row = top, bottom do
    widest =
      math.max(
        widest,
        row_width(
          buf,
          row
        )
      )
  end

  return widest
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

local function scan_diamonds(
  buf,
  results,
  seen
)
  local line_count =
    vim.api.nvim_buf_line_count(buf)

  for top = 0, line_count - 1 do
    local width =
      row_width(
        buf,
        top
      )

    for center_left =
      0,
      width - 2
    do
      local center_right =
        center_left + 1

      ----------------------------------------------------------------
      -- Top apex:
      --
      --     ╱╲
      ----------------------------------------------------------------

      if
        char_at(
          buf,
          top,
          center_left
        ) == "╱"

        and char_at(
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

        for bottom =
          top + 4,
          line_count - 1
        do
          if
            char_at(
              buf,
              bottom,
              center_left
            ) == "╲"

            and char_at(
              buf,
              bottom,
              center_right
            ) == "╱"
          then
            local widest =
              widest_row(
                buf,
                top,
                bottom
              )

            local maximum_expand =
              math.min(
                center_left,
                widest
                  - center_right
                  - 1
              )

            local found =
              false

            ----------------------------------------------------------------
            -- Reconstruct possible original diamond width.
            ----------------------------------------------------------------

            for max_expand =
              1,
              maximum_expand
            do
              local shape =
                diamond.make_shape(
                  top,
                  bottom,
                  center_left,
                  center_right,
                  max_expand
                )

              if
                diamond_matches(
                  buf,
                  shape
                )
              then
                add_result(
                  results,
                  seen,
                  shape
                )

                found =
                  true

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
-- Public scan
---------------------------------------------------------------------

function M.scan(buf)
  local results = {}
  local seen = {}

  -------------------------------------------------------------------
  -- Normal rectangles
  -------------------------------------------------------------------

  scan_rectangular(
    buf,
    {
      type =
        "rectangle",

      top_left =
        "┌",

      top_right =
        "┐",

      bottom_left =
        "└",

      bottom_right =
        "┘",
    },
    results,
    seen
  )

  -------------------------------------------------------------------
  -- Rounded rectangles
  -------------------------------------------------------------------

  scan_rectangular(
    buf,
    {
      type =
        "rounded_rectangle",

      top_left =
        "╭",

      top_right =
        "╮",

      bottom_left =
        "╰",

      bottom_right =
        "╯",
    },
    results,
    seen
  )

  -------------------------------------------------------------------
  -- Diamonds
  -------------------------------------------------------------------

  scan_diamonds(
    buf,
    results,
    seen
  )

  -------------------------------------------------------------------
  -- Stable ordering
  -------------------------------------------------------------------

  table.sort(
    results,
    function(a, b)
      if a.top ~= b.top then
        return a.top < b.top
      end

      if a.left ~= b.left then
        return a.left < b.left
      end

      if a.bottom ~= b.bottom then
        return a.bottom < b.bottom
      end

      return
        a.right < b.right
    end
  )

  return results
end

return M
