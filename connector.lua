local canvas =
  require "draw.canvas"

local topology =
  require "draw.topology"

local arrows =
  require "draw.arrows"

local shape_chars =
  require "draw.shape_chars"

local shapes =
  require "draw.shapes"

local navigation =
  require "draw.navigation"

local diamond =
  require "draw.shapes.diamond"

local M = {}

---------------------------------------------------------------------
-- Direction helpers
---------------------------------------------------------------------

local opposite = {
  left = "right",
  right = "left",
  up = "down",
  down = "up",
}

local arrowheads = {
  left = "◀",
  right = "▶",
  up = "▲",
  down = "▼",
}

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

  if
    col >= canvas.char_count(line)
  then
    return ""
  end

  return canvas.get_char(
    buf,
    row,
    col
  )
end

---------------------------------------------------------------------
-- Does topology actually contain a connection?
---------------------------------------------------------------------

local function has_connections(
  connections
)
  if connections == nil then
    return false
  end

  return
    connections.left
    or connections.right
    or connections.up
    or connections.down
end

---------------------------------------------------------------------
-- Position key
---------------------------------------------------------------------

local function position_key(
  row,
  col
)
  return
    tostring(row)
    .. ":"
    .. tostring(col)
end

---------------------------------------------------------------------
-- Shape middle row
---------------------------------------------------------------------

local function middle_writable_row(shape)
  local desired =
    math.floor(
      (shape.top + shape.bottom)
      / 2
    )

  local max_distance =
    shape.bottom - shape.top

  for distance = 0, max_distance do
    local candidates = {
      desired - distance,
      desired + distance,
    }

    for _, row
      in ipairs(candidates)
    do
      if
        row > shape.top
        and row < shape.bottom
      then
        local left,
          right =
          shapes.row_bounds(
            shape,
            row
          )

        if
          left ~= nil
          and right ~= nil
        then
          return
            row,
            left,
            right
        end
      end
    end
  end

  return nil, nil, nil
end

---------------------------------------------------------------------
-- Normal single anchor
--
-- Used when creating a NEW connector.
---------------------------------------------------------------------

local function border_anchor(
  shape,
  direction
)
  if
    direction == "left"
    or direction == "right"
  then
    local row,
      left,
      right =
      middle_writable_row(
        shape
      )

    if row == nil then
      return nil, nil
    end

    if direction == "left" then
      return
        row,
        left - 1
    end

    return
      row,
      right + 1
  end

  local col =
    math.floor(
      (shape.left + shape.right)
      / 2
    )

  if direction == "up" then
    return
      shape.top,
      col
  end

  return
    shape.bottom,
    col
end

---------------------------------------------------------------------
-- Normal outside anchor
---------------------------------------------------------------------

local function outside_anchor(
  shape,
  direction
)
  local row,
    col =
    border_anchor(
      shape,
      direction
    )

  if row == nil then
    return nil, nil
  end

  local delta =
    canvas.directions[
      direction
    ]

  return
    row + delta.row,
    col + delta.col
end

---------------------------------------------------------------------
-- ALL possible outside cells along one side of a shape
--
-- This is the important difference from the old implementation.
--
-- Reverse-connection detection no longer assumes that an old
-- connector used exactly the same anchor that we'd choose today.
---------------------------------------------------------------------

local function side_outside_cells(
  shape,
  side
)
  local result = {}

  -------------------------------------------------------------------
  -- Left / right side
  -------------------------------------------------------------------

  if
    side == "left"
    or side == "right"
  then
    for row =
      shape.top + 1,
      shape.bottom - 1
    do
      local left,
        right =
        shapes.row_bounds(
          shape,
          row
        )

      if
        left ~= nil
        and right ~= nil
      then
        local col

        if side == "left" then
          ----------------------------------------------------------------
          -- interior left -> border -> outside
          ----------------------------------------------------------------

          col =
            left - 2
        else
          col =
            right + 2
        end

        if col >= 0 then
          table.insert(
            result,
            {
              row = row,
              col = col,
            }
          )
        end
      end
    end

    return result
  end

  -------------------------------------------------------------------
  -- Top / bottom side
  --
  -- Rectangles can be connected across the whole horizontal edge.
  --
  -- For diamonds we use the center/apex area because that's how our
  -- current connector anchors are generated.
  -------------------------------------------------------------------

  if shape.type == "diamond" then
    local col =
      math.floor(
        (shape.left + shape.right)
        / 2
      )

    local row

    if side == "up" then
      row =
        shape.top - 1
    else
      row =
        shape.bottom + 1
    end

    if row >= 0 then
      table.insert(
        result,
        {
          row = row,
          col = col,
        }
      )
    end

    return result
  end

  local row

  if side == "up" then
    row =
      shape.top - 1
  else
    row =
      shape.bottom + 1
  end

  if row < 0 then
    return result
  end

  for col =
    shape.left + 1,
    shape.right - 1
  do
    table.insert(
      result,
      {
        row = row,
        col = col,
      }
    )
  end

  return result
end

---------------------------------------------------------------------
-- Append an orthogonal segment
---------------------------------------------------------------------

local function append_segment(
  path,
  start_row,
  start_col,
  end_row,
  end_col
)
  local row =
    start_row

  local col =
    start_col

  local last =
    path[#path]

  if
    last == nil
    or last.row ~= row
    or last.col ~= col
  then
    table.insert(
      path,
      {
        row = row,
        col = col,
      }
    )
  end

  while
    row ~= end_row
    or col ~= end_col
  do
    if row < end_row then
      row =
        row + 1

    elseif row > end_row then
      row =
        row - 1

    elseif col < end_col then
      col =
        col + 1

    elseif col > end_col then
      col =
        col - 1
    end

    table.insert(
      path,
      {
        row = row,
        col = col,
      }
    )
  end
end

---------------------------------------------------------------------
-- Build a NEW connector route
---------------------------------------------------------------------

local function build_path(
  direction,
  start_row,
  start_col,
  end_row,
  end_col
)
  local path = {}

  -------------------------------------------------------------------
  -- Straight horizontal
  -------------------------------------------------------------------

  if
    (
      direction == "left"
      or direction == "right"
    )
    and start_row == end_row
  then
    append_segment(
      path,
      start_row,
      start_col,
      end_row,
      end_col
    )

    return path
  end

  -------------------------------------------------------------------
  -- Horizontal connector with vertical offset
  -------------------------------------------------------------------

  if
    direction == "left"
    or direction == "right"
  then
    local pivot_col =
      math.floor(
        (start_col + end_col)
        / 2
      )

    append_segment(
      path,
      start_row,
      start_col,
      start_row,
      pivot_col
    )

    append_segment(
      path,
      start_row,
      pivot_col,
      end_row,
      pivot_col
    )

    append_segment(
      path,
      end_row,
      pivot_col,
      end_row,
      end_col
    )

    return path
  end

  -------------------------------------------------------------------
  -- Straight vertical
  -------------------------------------------------------------------

  if
    start_col == end_col
  then
    append_segment(
      path,
      start_row,
      start_col,
      end_row,
      end_col
    )

    return path
  end

  -------------------------------------------------------------------
  -- Vertical connector with horizontal offset
  -------------------------------------------------------------------

  local pivot_row =
    math.floor(
      (start_row + end_row)
      / 2
    )

  append_segment(
    path,
    start_row,
    start_col,
    pivot_row,
    start_col
  )

  append_segment(
    path,
    pivot_row,
    start_col,
    pivot_row,
    end_col
  )

  append_segment(
    path,
    pivot_row,
    end_col,
    end_row,
    end_col
  )

  return path
end

---------------------------------------------------------------------
-- Direction between adjacent cells
---------------------------------------------------------------------

local function direction_between(
  a,
  b
)
  local row_delta =
    b.row - a.row

  local col_delta =
    b.col - a.col

  if row_delta == -1 then
    return "up"
  end

  if row_delta == 1 then
    return "down"
  end

  if col_delta == -1 then
    return "left"
  end

  if col_delta == 1 then
    return "right"
  end

  return nil
end

---------------------------------------------------------------------
-- Actual shape boundary
---------------------------------------------------------------------

local function on_shape_boundary(
  shape,
  row,
  col
)
  if
    row < shape.top
    or row > shape.bottom
    or col < shape.left
    or col > shape.right
  then
    return false
  end

  -------------------------------------------------------------------
  -- Diamond
  -------------------------------------------------------------------

  if shape.type == "diamond" then
    local left,
      right =
      diamond.outline_for_row(
        shape,
        row
      )

    return
      col == left
      or col == right
  end

  -------------------------------------------------------------------
  -- Rectangle / rounded rectangle
  -------------------------------------------------------------------

  local horizontal =
    (
      row == shape.top
      or row == shape.bottom
    )
    and col >= shape.left
    and col <= shape.right

  local vertical =
    (
      col == shape.left
      or col == shape.right
    )
    and row >= shape.top
    and row <= shape.bottom

  return
    horizontal
    or vertical
end

---------------------------------------------------------------------
-- Other-shape collision
---------------------------------------------------------------------

local function intersects_other_shape(
  state,
  source,
  target,
  row,
  col
)
  for _, shape
    in ipairs(state.shapes)
  do
    if
      shape.id ~= source.id
      and shape.id ~= target.id
      and on_shape_boundary(
        shape,
        row,
        col
      )
    then
      return true
    end
  end

  return false
end

---------------------------------------------------------------------
-- Are two topology cells actually connected?
---------------------------------------------------------------------

local function cells_connected(
  buf,
  from,
  to,
  direction
)
  local from_char =
    char_at(
      buf,
      from.row,
      from.col
    )

  local to_char =
    char_at(
      buf,
      to.row,
      to.col
    )

  local from_connections =
    topology.from_char(
      from_char
    )

  local to_connections =
    topology.from_char(
      to_char
    )

  if
    not has_connections(
      from_connections
    )
    or not has_connections(
      to_connections
    )
  then
    return false
  end

  return
    from_connections[
      direction
    ]
    and to_connections[
      opposite[direction]
    ]
end

---------------------------------------------------------------------
-- Walk existing topology and return every reachable cell
---------------------------------------------------------------------

local function reachable_topology(
  buf,
  start_row,
  start_col
)
  local visited = {}

  local start_char =
    char_at(
      buf,
      start_row,
      start_col
    )

  local start_connections =
    topology.from_char(
      start_char
    )

  if
    not has_connections(
      start_connections
    )
  then
    return visited
  end

  local queue = {
    {
      row = start_row,
      col = start_col,
    },
  }

  local head = 1

  visited[
    position_key(
      start_row,
      start_col
    )
  ] = true

  while head <= #queue do
    local current =
      queue[head]

    head =
      head + 1

    local current_char =
      char_at(
        buf,
        current.row,
        current.col
      )

    local connections =
      topology.from_char(
        current_char
      )

    if has_connections(connections) then
      for direction,
        delta
        in pairs(
          canvas.directions
        )
      do
        if
          connections[
            direction
          ]
        then
          local next_row =
            current.row
            + delta.row

          local next_col =
            current.col
            + delta.col

          if
            next_row >= 0
            and next_col >= 0
          then
            local key =
              position_key(
                next_row,
                next_col
              )

            if not visited[key] then
              local next_cell = {
                row = next_row,
                col = next_col,
              }

              if
                cells_connected(
                  buf,
                  current,
                  next_cell,
                  direction
                )
              then
                visited[key] =
                  true

                table.insert(
                  queue,
                  next_cell
                )
              end
            end
          end
        end
      end
    end
  end

  return visited
end

---------------------------------------------------------------------
-- Find an existing reverse connector.
--
-- Example:
--
--     ┌───┐
--     │ A │◀────┐
--     └───┘     │
--               └────┌───┐
--                    │ B │
--                    └───┘
--
-- A -> B:
--
-- 1. find ◀ somewhere outside A's right side
-- 2. step from that arrow into the topology
-- 3. walk the real topology graph
-- 4. see whether it reaches ANY valid outside cell on B's left side
-- 5. replace that real endpoint with ▶
---------------------------------------------------------------------

local function find_reverse_connection(
  buf,
  source,
  target,
  direction
)
  local source_side =
    direction

  local target_side =
    opposite[
      direction
    ]

  local expected_source_arrow =
    arrowheads[
      opposite[direction]
    ]

  local wanted_target_arrow =
    arrowheads[
      direction
    ]

  local source_candidates =
    side_outside_cells(
      source,
      source_side
    )

  local target_candidates =
    side_outside_cells(
      target,
      target_side
    )

  local source_delta =
    canvas.directions[
      direction
    ]

  local incoming_direction =
    opposite[
      direction
    ]

  -------------------------------------------------------------------
  -- Try every possible reverse arrow along the source-facing side.
  -------------------------------------------------------------------

  for _, source_cell
    in ipairs(source_candidates)
  do
    local source_char =
      char_at(
        buf,
        source_cell.row,
        source_cell.col
      )

    if
      source_char
      == expected_source_arrow
    then
      ----------------------------------------------------------------
      -- Step away from source and into the existing connector.
      ----------------------------------------------------------------

      local start_row =
        source_cell.row
        + source_delta.row

      local start_col =
        source_cell.col
        + source_delta.col

      local visited =
        reachable_topology(
          buf,
          start_row,
          start_col
        )

      ----------------------------------------------------------------
      -- Inspect every possible target-side endpoint.
      ----------------------------------------------------------------

      for _, target_cell
        in ipairs(target_candidates)
      do
        local target_char =
          char_at(
            buf,
            target_cell.row,
            target_cell.col
          )

        --------------------------------------------------------------
        -- Already bidirectional
        --------------------------------------------------------------

        if
          target_char
          == wanted_target_arrow
        then
          local previous_delta =
            canvas.directions[
              incoming_direction
            ]

          local previous_row =
            target_cell.row
            + previous_delta.row

          local previous_col =
            target_cell.col
            + previous_delta.col

          if
            visited[
              position_key(
                previous_row,
                previous_col
              )
            ]
          then
            return
              "bidirectional",
              target_cell
          end
        end

        --------------------------------------------------------------
        -- Existing reverse topology reaches the target side.
        --------------------------------------------------------------

        local target_connections =
          topology.from_char(
            target_char
          )

        if
          has_connections(
            target_connections
          )
          and target_connections[
            incoming_direction
          ]
          and visited[
            position_key(
              target_cell.row,
              target_cell.col
            )
          ]
        then
          return
            "reverse",
            target_cell
        end
      end
    end
  end

  return nil, nil
end

---------------------------------------------------------------------
-- Upgrade reverse connector
---------------------------------------------------------------------

local function upgrade_reverse_connector(
  buf,
  target_cell,
  direction
)
  canvas.set_char(
    buf,
    target_cell.row,
    target_cell.col,
    arrowheads[
      direction
    ]
  )
end

---------------------------------------------------------------------
-- Validate a brand-new connector
---------------------------------------------------------------------

local function validate_new_path(
  buf,
  state,
  source,
  target,
  path
)
  -------------------------------------------------------------------
  -- Bounds and other shapes
  -------------------------------------------------------------------

  for _, cell
    in ipairs(path)
  do
    if
      cell.row < 0
      or cell.col < 0
    then
      return
        false,
        "Not enough canvas space in that direction"
    end

    if
      intersects_other_shape(
        state,
        source,
        target,
        cell.row,
        cell.col
      )
    then
      return
        false,
        "Connector would cross another shape"
    end
  end

  -------------------------------------------------------------------
  -- New destination must be empty
  -------------------------------------------------------------------

  local final =
    path[#path]

  local final_char =
    char_at(
      buf,
      final.row,
      final.col
    )

  if
    final_char ~= ""
    and final_char ~= " "
  then
    return
      false,
      "Connector destination is blocked"
  end

  -------------------------------------------------------------------
  -- Intermediate cells
  -------------------------------------------------------------------

  for index = 1, #path - 1 do
    local cell =
      path[index]

    local char =
      char_at(
        buf,
        cell.row,
        cell.col
      )

    if
      arrows.is_arrowhead(
        char
      )
    then
      return
        false,
        "Connector would cross an arrowhead"
    end

    if
      shape_chars.is(
        char
      )
    then
      return
        false,
        "Connector would cross shape geometry"
    end

    if
      topology.from_char(
        char
      ) == nil
    then
      return
        false,
        "Connector would cross text"
    end
  end

  return true
end

---------------------------------------------------------------------
-- Draw a new path
---------------------------------------------------------------------

local function draw_path(
  buf,
  path,
  arrow_direction
)
  if #path == 0 then
    return false
  end

  local first_change =
    true

  for index = 1, #path - 1 do
    local cell =
      path[index]

    canvas.ensure_col(
      buf,
      cell.row,
      cell.col
    )

    local char =
      canvas.get_char(
        buf,
        cell.row,
        cell.col
      )

    local connections =
      topology.from_char(
        char
      )

    if connections == nil then
      return false
    end

    -----------------------------------------------------------------
    -- Previous connection
    -----------------------------------------------------------------

    if index > 1 then
      local previous_direction =
        direction_between(
          cell,
          path[
            index - 1
          ]
        )

      if previous_direction then
        topology.add(
          connections,
          previous_direction
        )
      end
    end

    -----------------------------------------------------------------
    -- Next connection
    -----------------------------------------------------------------

    local next_direction =
      direction_between(
        cell,
        path[
          index + 1
        ]
      )

    if next_direction then
      topology.add(
        connections,
        next_direction
      )
    end

    if not first_change then
      canvas.undo_join()
    end

    canvas.set_char(
      buf,
      cell.row,
      cell.col,
      topology.to_char(
        connections
      )
    )

    first_change =
      false
  end

  -------------------------------------------------------------------
  -- Arrowhead
  -------------------------------------------------------------------

  local final =
    path[#path]

  canvas.ensure_col(
    buf,
    final.row,
    final.col
  )

  if not first_change then
    canvas.undo_join()
  end

  canvas.set_char(
    buf,
    final.row,
    final.col,
    arrowheads[
      arrow_direction
    ]
  )

  return true
end

---------------------------------------------------------------------
-- Number of active connections in one topology cell
---------------------------------------------------------------------

local function connection_count(
  connections
)
  if connections == nil then
    return 0
  end

  local count = 0

  for _, direction in ipairs {
    "left",
    "right",
    "up",
    "down",
  } do
    if connections[direction] then
      count = count + 1
    end
  end

  return count
end

---------------------------------------------------------------------
-- Write while keeping connector deletion in one undo block
---------------------------------------------------------------------

local function delete_write(
  buf,
  row,
  col,
  char,
  context
)
  local current =
    char_at(
      buf,
      row,
      col
    )

  if current == char then
    return
  end

  if context.changed then
    canvas.undo_join()
  end

  canvas.set_char(
    buf,
    row,
    col,
    char
  )

  context.changed =
    true
end

---------------------------------------------------------------------
-- Rewrite one topology cell after removing a connection
---------------------------------------------------------------------

local function rewrite_topology(
  buf,
  row,
  col,
  connections,
  context
)
  if
    not has_connections(
      connections
    )
  then
    delete_write(
      buf,
      row,
      col,
      " ",
      context
    )

    return
  end

  delete_write(
    buf,
    row,
    col,
    topology.to_char(
      connections
    ),
    context
  )
end

---------------------------------------------------------------------
-- Remove one connector branch
--
-- incoming_direction means:
--
--   "the direction from this cell back toward the shape/previous
--    connector cell"
--
-- We walk until:
--
--   * the connector ends
--   * we reach an arrowhead
--   * we reach shared topology
--
-- Shared topology is preserved. Only the incoming branch is removed.
---------------------------------------------------------------------

local function prune_branch(
  buf,
  start_row,
  start_col,
  incoming_direction,
  context
)
  local row =
    start_row

  local col =
    start_col

  local incoming =
    incoming_direction

  local visited = {}

  while row >= 0 and col >= 0 do
    local key =
      position_key(
        row,
        col
      )

    if visited[key] then
      return
    end

    visited[key] =
      true

    local char =
      char_at(
        buf,
        row,
        col
      )

    -----------------------------------------------------------------
    -- Arrowhead = connector endpoint
    -----------------------------------------------------------------

    if arrows.is_arrowhead(char) then
      delete_write(
        buf,
        row,
        col,
        " ",
        context
      )

      return
    end

    local connections =
      topology.from_char(
        char
      )

    if
      not has_connections(
        connections
      )
    then
      return
    end

    -----------------------------------------------------------------
    -- Remove the edge leading back toward the branch we just erased.
    -----------------------------------------------------------------

    if
      incoming ~= nil
      and connections[incoming]
    then
      connections[incoming] =
        false
    end

    local remaining =
      connection_count(
        connections
      )

    -----------------------------------------------------------------
    -- Nothing remains.
    -----------------------------------------------------------------

    if remaining == 0 then
      delete_write(
        buf,
        row,
        col,
        " ",
        context
      )

      return
    end

    -----------------------------------------------------------------
    -- More than one route remains.
    --
    -- We've reached shared topology.
    --
    -- Example:
    --
    --       branch being deleted
    --              │
    --              ▼
    --        ──────┼──────
    --
    -- becomes:
    --
    --        ─────────────
    --
    -- Do not continue deleting past this point.
    -----------------------------------------------------------------

    if remaining > 1 then
      rewrite_topology(
        buf,
        row,
        col,
        connections,
        context
      )

      return
    end

    -----------------------------------------------------------------
    -- Exactly one direction remains.
    --
    -- That's the continuation of this connector.
    -----------------------------------------------------------------

    local next_direction

    for _, direction in ipairs {
      "left",
      "right",
      "up",
      "down",
    } do
      if connections[direction] then
        next_direction =
          direction

        break
      end
    end

    if next_direction == nil then
      return
    end

    local delta =
      canvas.directions[
        next_direction
      ]

    local next_row =
      row + delta.row

    local next_col =
      col + delta.col

    local next_char =
      char_at(
        buf,
        next_row,
        next_col
      )

    -----------------------------------------------------------------
    -- Current cell belongs exclusively to the branch being deleted.
    -----------------------------------------------------------------

    delete_write(
      buf,
      row,
      col,
      " ",
      context
    )

    -----------------------------------------------------------------
    -- Arrowhead on the other end
    -----------------------------------------------------------------

    if
      arrows.is_arrowhead(
        next_char
      )
    then
      delete_write(
        buf,
        next_row,
        next_col,
        " ",
        context
      )

      return
    end

    -----------------------------------------------------------------
    -- Continue through real topology.
    -----------------------------------------------------------------

    local next_connections =
      topology.from_char(
        next_char
      )

    if
      not has_connections(
        next_connections
      )
    then
      return
    end

    row =
      next_row

    col =
      next_col

    incoming =
      opposite[
        next_direction
      ]
  end
end

---------------------------------------------------------------------
-- Inspect one side of a shape for attached connectors
---------------------------------------------------------------------

local function delete_side_connectors(
  buf,
  shape,
  side,
  context
)
  local candidates =
    side_outside_cells(
      shape,
      side
    )

  local outward =
    canvas.directions[
      side
    ]

  local inward =
    opposite[
      side
    ]

  -------------------------------------------------------------------
  -- Any arrowhead touching a shape must point INTO that shape.
  --
  -- Example:
  --
  -- shape on right:
  --
  -- ─────▶┌──────┐
  --
  -- side = left
  -- arrow = right
  -------------------------------------------------------------------

  local expected_arrow =
    arrowheads[
      inward
    ]

  for _, candidate
    in ipairs(candidates)
  do
    local row =
      candidate.row

    local col =
      candidate.col

    local char =
      char_at(
        buf,
        row,
        col
      )

    -----------------------------------------------------------------
    -- Connector ends at this shape.
    -----------------------------------------------------------------

    if char == expected_arrow then
      delete_write(
        buf,
        row,
        col,
        " ",
        context
      )

      local start_row =
        row + outward.row

      local start_col =
        col + outward.col

      prune_branch(
        buf,
        start_row,
        start_col,
        inward,
        context
      )

    else
      ----------------------------------------------------------------
      -- Connector starts at this shape.
      --
      -- Generated connectors leave the shape in the direction of the
      -- side they're attached to.
      ----------------------------------------------------------------

      local connections =
        topology.from_char(
          char
        )

      if
        has_connections(
          connections
        )
        and connections[side]
      then
        prune_branch(
          buf,
          row,
          col,
          inward,
          context
        )

      elseif
        char == ""
        or char == " "
      then
        --------------------------------------------------------------
        -- Legacy geometry support.
        --
        -- Some older diagrams may have one blank cell between the
        -- shape and the connector endpoint.
        --------------------------------------------------------------

        local legacy_row =
          row + outward.row

        local legacy_col =
          col + outward.col

        local legacy_char =
          char_at(
            buf,
            legacy_row,
            legacy_col
          )

        if
          legacy_char
          == expected_arrow
        then
          delete_write(
            buf,
            legacy_row,
            legacy_col,
            " ",
            context
          )

          prune_branch(
            buf,
            legacy_row
              + outward.row,
            legacy_col
              + outward.col,
            inward,
            context
          )

        else
          local legacy_connections =
            topology.from_char(
              legacy_char
            )

          if
            has_connections(
              legacy_connections
            )
            and legacy_connections[
              side
            ]
          then
            prune_branch(
              buf,
              legacy_row,
              legacy_col,
              inward,
              context
            )
          end
        end
      end
    end
  end
end

---------------------------------------------------------------------
-- Delete every connector attached to a shape
---------------------------------------------------------------------

function M.delete_attached(
  state,
  shape
)
  if
    state == nil
    or shape == nil
  then
    return false
  end

  local buf =
    state.buf

  local context = {
    changed = false,
  }

  for _, side in ipairs {
    "left",
    "right",
    "up",
    "down",
  } do
    delete_side_connectors(
      buf,
      shape,
      side,
      context
    )
  end

  return context.changed
end

---------------------------------------------------------------------
-- Public connector
---------------------------------------------------------------------

function M.connect(
  state,
  direction
)
  if state == nil then
    return
  end

  if
    state.mode ~= "draw"
  then
    vim.notify(
      "Connectors are available in DRAW mode",
      vim.log.levels.WARN
    )

    return
  end

  local buf =
    vim.api.nvim_get_current_buf()

  local row,
    col =
    canvas.current_position()

  -------------------------------------------------------------------
  -- Source
  -------------------------------------------------------------------

  local source =
    shapes.find_containing(
      state.shapes,
      row,
      col
    )

  if source == nil then
    vim.notify(
      "Move inside a tracked shape first",
      vim.log.levels.WARN
    )

    return
  end

  -------------------------------------------------------------------
  -- Target
  -------------------------------------------------------------------

  local target =
    navigation.find_target(
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

  -------------------------------------------------------------------
  -- FIRST:
  --
  -- Search the actual existing connector graph for a reverse
  -- connection.
  -------------------------------------------------------------------

  local reverse_status,
    reverse_endpoint =
    find_reverse_connection(
      buf,
      source,
      target,
      direction
    )

  if
    reverse_status
    == "bidirectional"
  then
    vim.notify(
      "Connector is already bidirectional"
    )

    return
  end

  if
    reverse_status
    == "reverse"
  then
    upgrade_reverse_connector(
      buf,
      reverse_endpoint,
      direction
    )

    vim.notify(
      "-- CONNECTED --"
    )

    return
  end

  -------------------------------------------------------------------
  -- Otherwise build a brand-new connector.
  -------------------------------------------------------------------

  local start_row,
    start_col =
    outside_anchor(
      source,
      direction
    )

  local target_side =
    opposite[
      direction
    ]

  local end_row,
    end_col =
    outside_anchor(
      target,
      target_side
    )

  if
    start_row == nil
    or start_col == nil
    or end_row == nil
    or end_col == nil
  then
    vim.notify(
      "Could not calculate connector anchors",
      vim.log.levels.WARN
    )

    return
  end

  local path =
    build_path(
      direction,
      start_row,
      start_col,
      end_row,
      end_col
    )

  local valid,
    reason =
    validate_new_path(
      buf,
      state,
      source,
      target,
      path
    )

  if not valid then
    vim.notify(
      reason,
      vim.log.levels.WARN
    )

    return
  end

  local success =
    draw_path(
      buf,
      path,
      direction
    )

  if success then
    vim.notify(
      "-- CONNECTED --"
    )
  end
end

return M
