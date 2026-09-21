local canvas =
  require "draw.canvas"

local shapes =
  require "draw.shapes"

local M = {}

---------------------------------------------------------------------
-- Axis overlap
---------------------------------------------------------------------

local function rows_overlap(a, b)
  return
    a.top <= b.bottom
    and a.bottom >= b.top
end

local function cols_overlap(a, b)
  return
    a.left <= b.right
    and a.right >= b.left
end

---------------------------------------------------------------------
-- Distance scoring from one shape to another
---------------------------------------------------------------------

local function score_candidate(
  source,
  target,
  direction
)
  local source_center_row,
    source_center_col =
    shapes.center(source)

  local target_center_row,
    target_center_col =
    shapes.center(target)

  local primary
  local secondary
  local aligned = false

  if direction == "left" then
    if target.right >= source.left then
      return nil
    end

    primary =
      source.left
      - target.right

    secondary =
      math.abs(
        source_center_row
        - target_center_row
      )

    aligned =
      rows_overlap(
        source,
        target
      )

  elseif direction == "right" then
    if target.left <= source.right then
      return nil
    end

    primary =
      target.left
      - source.right

    secondary =
      math.abs(
        source_center_row
        - target_center_row
      )

    aligned =
      rows_overlap(
        source,
        target
      )

  elseif direction == "up" then
    if target.bottom >= source.top then
      return nil
    end

    primary =
      source.top
      - target.bottom

    secondary =
      math.abs(
        source_center_col
        - target_center_col
      )

    aligned =
      cols_overlap(
        source,
        target
      )

  elseif direction == "down" then
    if target.top <= source.bottom then
      return nil
    end

    primary =
      target.top
      - source.bottom

    secondary =
      math.abs(
        source_center_col
        - target_center_col
      )

    aligned =
      cols_overlap(
        source,
        target
      )
  end

  -------------------------------------------------------------------
  -- Strongly prefer shapes aligned with us.
  -------------------------------------------------------------------

  local alignment_penalty =
    aligned and 0 or 1000

  return
    alignment_penalty
    + primary
    + (secondary * 0.25)
end

---------------------------------------------------------------------
-- Find target when currently inside a shape
---------------------------------------------------------------------

local function from_shape(
  state,
  source,
  direction
)
  local best = nil
  local best_score = nil

  for _, candidate
    in ipairs(state.shapes)
  do
    if candidate.id ~= source.id then
      local score =
        score_candidate(
          source,
          candidate,
          direction
        )

      if
        score ~= nil
        and (
          best_score == nil
          or score < best_score
        )
      then
        best =
          candidate

        best_score =
          score
      end
    end
  end

  return best
end

---------------------------------------------------------------------
-- Find target from arbitrary cursor position
---------------------------------------------------------------------

local function from_cursor(
  state,
  row,
  col,
  direction
)
  local best = nil
  local best_score = nil

  for _, candidate
    in ipairs(state.shapes)
  do
    local center_row,
      center_col =
      shapes.center(candidate)

    local valid = false
    local primary = 0
    local secondary = 0

    if
      direction == "left"
      and center_col < col
    then
      valid = true

      primary =
        col - center_col

      secondary =
        math.abs(
          row - center_row
        )

    elseif
      direction == "right"
      and center_col > col
    then
      valid = true

      primary =
        center_col - col

      secondary =
        math.abs(
          row - center_row
        )

    elseif
      direction == "up"
      and center_row < row
    then
      valid = true

      primary =
        row - center_row

      secondary =
        math.abs(
          col - center_col
        )

    elseif
      direction == "down"
      and center_row > row
    then
      valid = true

      primary =
        center_row - row

      secondary =
        math.abs(
          col - center_col
        )
    end

    if valid then
      local score =
        primary
        + (secondary * 0.25)

      if
        best_score == nil
        or score < best_score
      then
        best =
          candidate

        best_score =
          score
      end
    end
  end

  return best
end

---------------------------------------------------------------------
-- Public target lookup
--
-- Returns:
--
--   target, source
--
-- source will be nil when the cursor is not inside a tracked shape.
---------------------------------------------------------------------

function M.find_target(
  state,
  direction,
  row,
  col
)
  if
    state == nil
    or state.shapes == nil
    or #state.shapes == 0
  then
    return nil, nil
  end

  local source =
    shapes.find_containing(
      state.shapes,
      row,
      col
    )

  if source then
    return
      from_shape(
        state,
        source,
        direction
      ),
      source
  end

  return
    from_cursor(
      state,
      row,
      col,
      direction
    ),
    nil
end

---------------------------------------------------------------------
-- Jump
---------------------------------------------------------------------

function M.jump(
  state,
  direction,
  region
)
  if state == nil then
    return
  end

  if state.mode ~= "draw" then
    vim.notify(
      "Box navigation is available in DRAW mode",
      vim.log.levels.WARN
    )

    return
  end

  if
    state.shapes == nil
    or #state.shapes == 0
  then
    vim.notify(
      "No tracked shapes",
      vim.log.levels.WARN
    )

    return
  end

  local row, col =
    canvas.current_position(region)

  local target =
    M.find_target(
      state,
      direction,
      row,
      col
    )

  if target == nil then
    vim.notify(
      "No shape in that direction",
      vim.log.levels.INFO
    )

    return
  end

  local target_row,
    target_col =
    shapes.entry_point(target)

  local buf =
    vim.api.nvim_get_current_buf()

  canvas.set_cursor(
    buf,
    target_row,
    target_col,
    region
  )
end

return M
