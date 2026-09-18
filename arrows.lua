local canvas =
  require "draw.canvas"

local topology =
  require "draw.topology"

local M = {}

local arrowheads = {
  left = "◀",
  right = "▶",
  up = "▲",
  down = "▼",
}

local arrowhead_lookup = {
  ["◀"] = true,
  ["▶"] = true,
  ["▲"] = true,
  ["▼"] = true,
}

function M.is_arrowhead(char)
  return
    arrowhead_lookup[char] == true
end

function M.place(
  buf,
  state,
  direction
)
  if state.mode == "erase" then
    vim.notify(
      "Exit ERASE mode with x first",
      vim.log.levels.WARN
    )

    return
  end

  if state.mode == "box" then
    vim.notify(
      "Finish the box with B or cancel with Esc first",
      vim.log.levels.WARN
    )

    return
  end

  local row, col =
    canvas.current_position()

  local char =
    canvas.get_char(
      buf,
      row,
      col
    )

  if char == "" or char == " " then
    vim.notify(
      "Move cursor onto a line endpoint first",
      vim.log.levels.WARN
    )

    return
  end

  -------------------------------------------------------------------
  -- Allow changing an existing arrowhead.
  -------------------------------------------------------------------

  if M.is_arrowhead(char) then
    canvas.set_char(
      buf,
      row,
      col,
      arrowheads[direction]
    )

    canvas.set_cursor(
      buf,
      row,
      col
    )

    return
  end

  local connections =
    topology.from_char(char)

  if connections == nil then
    vim.notify(
      "Cannot place arrowhead on normal text",
      vim.log.levels.WARN
    )

    return
  end

  -------------------------------------------------------------------
  -- Horizontal arrowheads
  -------------------------------------------------------------------

  if
    direction == "left"
    or direction == "right"
  then
    if char ~= "─" then
      vim.notify(
        "LA and RA work on horizontal line cells",
        vim.log.levels.WARN
      )

      return
    end

  -------------------------------------------------------------------
  -- Vertical arrowheads
  -------------------------------------------------------------------

  else
    if char ~= "│" then
      vim.notify(
        "UA and DA work on vertical line cells",
        vim.log.levels.WARN
      )

      return
    end
  end

  canvas.set_char(
    buf,
    row,
    col,
    arrowheads[direction]
  )

  canvas.set_cursor(
    buf,
    row,
    col
  )
end

return M
