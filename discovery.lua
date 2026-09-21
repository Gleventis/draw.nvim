local M = {}

---------------------------------------------------------------------
-- Scanner registry
---------------------------------------------------------------------

local scanners = {}

---------------------------------------------------------------------
-- Pre-register in package.loaded so circular requires from shape
-- modules (rectangle → discovery) receive this partial M table
-- instead of triggering a second load attempt.
---------------------------------------------------------------------

package.loaded["draw.discovery"] = M

---------------------------------------------------------------------
-- Forward declarations
--
-- add_result and scan_rectangular are referenced by
-- M.register_rectangular_scanner before they are assigned below.
-- Declaring them here creates an upvalue that the closures capture.
---------------------------------------------------------------------

local add_result
local scan_rectangular

---------------------------------------------------------------------
-- Public API — defined early so shape modules loaded below can call
-- M.register / M.register_rectangular_scanner at require-time.
---------------------------------------------------------------------

--- Register a scanner function with the discovery system.
--
-- Args:
--   scan_fn: Function called as scan_fn(buf, results, seen) that
--            appends discovered shapes via add_result().
function M.register(scan_fn)
  table.insert(
    scanners,
    scan_fn
  )
end

--- Register a rectangular scanner using a style descriptor.
--
-- Builds the scanner closure around the internal scan_rectangular
-- function and registers it. Shape modules call this at require-time
-- to self-register without knowing about scanner internals.
--
-- Args:
--   style: Table with fields type, top_left, top_right, bottom_left,
--          bottom_right, make_shape (e.g. { type = "rectangle", ... }).
function M.register_rectangular_scanner(style)
  M.register(function(buf, results, seen, region)
    scan_rectangular(
      buf,
      style,
      results,
      seen,
      region
    )
  end)
end

local canvas =
  require "draw.canvas"

---------------------------------------------------------------------
-- Character width of a row
---------------------------------------------------------------------

local function row_width(
  buf,
  row,
  region
)
  local line =
    canvas.get_line(
      buf,
      row,
      region
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

add_result = function(
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
  right,
  region
)
  if right - left < 2 then
    return false
  end

  for col =
    left + 1,
    right - 1
  do
    if
      canvas.safe_get_char(
        buf,
        row,
        col,
        region
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
  bottom,
  region
)
  if bottom - top < 2 then
    return false
  end

  for row =
    top + 1,
    bottom - 1
  do
    if
      canvas.safe_get_char(
        buf,
        row,
        col,
        region
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

scan_rectangular = function(
  buf,
  style,
  results,
  seen,
  region
)
  local line_count =
    vim.api.nvim_buf_line_count(buf)

  local top_limit =
    region and region.top_row or 0

  local bottom_limit =
    region and region.bottom_row or (line_count - 1)

  for top = top_limit, bottom_limit do
    local width =
      row_width(
        buf,
        top,
        region
      )

    for left = 0, width - 1 do
      ----------------------------------------------------------------
      -- Find exact top-left corner
      ----------------------------------------------------------------

      if
        canvas.safe_get_char(
          buf,
          top,
          left,
          region
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
            canvas.safe_get_char(
              buf,
              top,
              right,
              region
            ) == style.top_right
            and strict_horizontal_edge(
              buf,
              top,
              left,
              right,
              region
            )
          then
            ------------------------------------------------------------
            -- Search downward for exact matching bottom
            ------------------------------------------------------------

            for bottom =
              top + 2,
              bottom_limit
            do
              if
                canvas.safe_get_char(
                  buf,
                  bottom,
                  left,
                  region
                ) == style.bottom_left

                and canvas.safe_get_char(
                  buf,
                  bottom,
                  right,
                  region
                ) == style.bottom_right

                and strict_horizontal_edge(
                  buf,
                  bottom,
                  left,
                  right,
                  region
                )

                and strict_vertical_edge(
                  buf,
                  left,
                  top,
                  bottom,
                  region
                )

                and strict_vertical_edge(
                  buf,
                  right,
                  top,
                  bottom,
                  region
                )
              then
                add_result(
                  results,
                  seen,
                  style.make_shape(
                    top,
                    bottom,
                    left,
                    right
                  )
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
-- Public scan
---------------------------------------------------------------------

function M.scan(buf, region)
  local results = {}
  local seen = {}

  for _, scan_fn in ipairs(scanners) do
    scan_fn(
      buf,
      results,
      seen,
      region
    )
  end

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
