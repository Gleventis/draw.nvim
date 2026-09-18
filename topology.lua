local M = {}

local function connections(
  up,
  down,
  left,
  right
)
  return {
    up = up or false,
    down = down or false,
    left = left or false,
    right = right or false,
  }
end

local char_to_connections = {
  -------------------------------------------------------------------
  -- Straight lines
  -------------------------------------------------------------------

  ["─"] = connections(
    false,
    false,
    true,
    true
  ),

  ["│"] = connections(
    true,
    true,
    false,
    false
  ),

  -------------------------------------------------------------------
  -- Square corners
  -------------------------------------------------------------------

  ["┌"] = connections(
    false,
    true,
    false,
    true
  ),

  ["┐"] = connections(
    false,
    true,
    true,
    false
  ),

  ["└"] = connections(
    true,
    false,
    false,
    true
  ),

  ["┘"] = connections(
    true,
    false,
    true,
    false
  ),

  -------------------------------------------------------------------
  -- Rounded corners
  --
  -- Topologically they are identical to square corners.
  -------------------------------------------------------------------

  ["╭"] = connections(
    false,
    true,
    false,
    true
  ),

  ["╮"] = connections(
    false,
    true,
    true,
    false
  ),

  ["╰"] = connections(
    true,
    false,
    false,
    true
  ),

  ["╯"] = connections(
    true,
    false,
    true,
    false
  ),

  -------------------------------------------------------------------
  -- T junctions
  -------------------------------------------------------------------

  ["┬"] = connections(
    false,
    true,
    true,
    true
  ),

  ["┴"] = connections(
    true,
    false,
    true,
    true
  ),

  ["├"] = connections(
    true,
    true,
    false,
    true
  ),

  ["┤"] = connections(
    true,
    true,
    true,
    false
  ),

  -------------------------------------------------------------------
  -- Intersection
  -------------------------------------------------------------------

  ["┼"] = connections(
    true,
    true,
    true,
    true
  ),
}

local function clone(value)
  return {
    up = value.up,
    down = value.down,
    left = value.left,
    right = value.right,
  }
end

function M.from_char(char)
  if char == "" or char == " " then
    return connections()
  end

  local value =
    char_to_connections[char]

  if value == nil then
    return nil
  end

  return clone(value)
end

function M.to_char(conn)
  local up = conn.up
  local down = conn.down
  local left = conn.left
  local right = conn.right

  if
    not up
    and not down
    and not left
    and not right
  then
    return " "
  end

  -------------------------------------------------------------------
  -- Straight lines
  -------------------------------------------------------------------

  if
    (left or right)
    and not up
    and not down
  then
    return "─"
  end

  if
    (up or down)
    and not left
    and not right
  then
    return "│"
  end

  -------------------------------------------------------------------
  -- Corners
  -------------------------------------------------------------------

  if
    down
    and right
    and not up
    and not left
  then
    return "┌"
  end

  if
    down
    and left
    and not up
    and not right
  then
    return "┐"
  end

  if
    up
    and right
    and not down
    and not left
  then
    return "└"
  end

  if
    up
    and left
    and not down
    and not right
  then
    return "┘"
  end

  -------------------------------------------------------------------
  -- T junctions
  -------------------------------------------------------------------

  if
    down
    and left
    and right
    and not up
  then
    return "┬"
  end

  if
    up
    and left
    and right
    and not down
  then
    return "┴"
  end

  if
    up
    and down
    and right
    and not left
  then
    return "├"
  end

  if
    up
    and down
    and left
    and not right
  then
    return "┤"
  end

  -------------------------------------------------------------------
  -- Intersection
  -------------------------------------------------------------------

  if
    up
    and down
    and left
    and right
  then
    return "┼"
  end

  return " "
end

function M.add(
  conn,
  direction
)
  conn[direction] = true

  return conn
end

function M.remove(
  conn,
  direction
)
  conn[direction] = false

  return conn
end

function M.is_drawable(char)
  return
    char == " "
    or char == ""
    or char_to_connections[char] ~= nil
end

return M
