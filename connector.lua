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

local M = {}

---------------------------------------------------------------------
-- Direction helpers
---------------------------------------------------------------------

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
      and shape.on_boundary(
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
  direction,
  region
)
  local from_char =
    canvas.safe_get_char(buf,
    from.row,
    from.col,
    region)

  local to_char =
    canvas.safe_get_char(buf,
    to.row,
    to.col,
    region)

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
      canvas.directions[direction].opposite
    ]
end

---------------------------------------------------------------------
-- Walk existing topology and return every reachable cell
---------------------------------------------------------------------

local function reachable_topology(
  buf,
  start_row,
  start_col,
  region
)
  local visited = {}

  local start_char =
    canvas.safe_get_char(buf,
    start_row,
    start_col,
    region)

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
      canvas.safe_get_char(buf,
      current.row,
      current.col,
      region)

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
                  direction,
                  region
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
  direction,
  region
)
  local source_side =
    direction

  local target_side =
    canvas.directions[direction].opposite

  local expected_source_arrow =
    arrows.arrowheads[
      canvas.directions[direction].opposite
    ]

  local wanted_target_arrow =
    arrows.arrowheads[
      direction
    ]

  local source_candidates =
    source.outside_cells(
      source,
      source_side
    )

  local target_candidates =
    target.outside_cells(
      target,
      target_side
    )

  local source_delta =
    canvas.directions[
      direction
    ]

  local incoming_direction =
    canvas.directions[direction].opposite

  -------------------------------------------------------------------
  -- Try every possible reverse arrow along the source-facing side.
  -------------------------------------------------------------------

  for _, source_cell
    in ipairs(source_candidates)
  do
    local source_char =
      canvas.safe_get_char(buf,
      source_cell.row,
      source_cell.col,
      region)

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
          start_col,
          region
        )

      ----------------------------------------------------------------
      -- Inspect every possible target-side endpoint.
      ----------------------------------------------------------------

      for _, target_cell
        in ipairs(target_candidates)
      do
        local target_char =
          canvas.safe_get_char(buf,
          target_cell.row,
          target_cell.col,
          region)

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
  direction,
  region
)
  canvas.set_char(
    buf,
    target_cell.row,
    target_cell.col,
    arrows.arrowheads[
      direction
    ],
    region
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
  path,
  region
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
    canvas.safe_get_char(buf,
    final.row,
    final.col,
    region)

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
      canvas.safe_get_char(buf,
      cell.row,
      cell.col,
      region)

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
  arrow_direction,
  region
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
      cell.col,
      region
    )

    local char =
      canvas.get_char(
        buf,
        cell.row,
        cell.col,
        region
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
      ),
      region
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
    final.col,
    region
  )

  if not first_change then
    canvas.undo_join()
  end

  canvas.set_char(
    buf,
    final.row,
    final.col,
    arrows.arrowheads[
      arrow_direction
    ],
    region
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
  context,
  region
)
  local current =
    canvas.safe_get_char(buf,
    row,
    col,
    region)

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
    char,
    region
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
  context,
  region
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
      context,
      region
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
    context,
    region
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
  context,
  region
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
      canvas.safe_get_char(buf,
      row,
      col,
      region)

    -----------------------------------------------------------------
    -- Arrowhead = connector endpoint
    -----------------------------------------------------------------

    if arrows.is_arrowhead(char) then
      delete_write(
        buf,
        row,
        col,
        " ",
        context,
        region
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
        context,
        region
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
        context,
        region
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
      canvas.safe_get_char(buf,
      next_row,
      next_col,
      region)

    -----------------------------------------------------------------
    -- Current cell belongs exclusively to the branch being deleted.
    -----------------------------------------------------------------

    delete_write(
      buf,
      row,
      col,
      " ",
      context,
      region
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
        context,
        region
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
      canvas.directions[next_direction].opposite
  end
end

---------------------------------------------------------------------
-- Inspect one side of a shape for attached connectors
---------------------------------------------------------------------

local function delete_side_connectors(
  buf,
  shape,
  side,
  context,
  region
)
  local candidates =
    shape.outside_cells(
      shape,
      side
    )

  local outward =
    canvas.directions[
      side
    ]

  local inward =
    canvas.directions[side].opposite

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
    arrows.arrowheads[
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
      canvas.safe_get_char(buf,
      row,
      col,
      region)

    -----------------------------------------------------------------
    -- Connector ends at this shape.
    -----------------------------------------------------------------

    if char == expected_arrow then
      delete_write(
        buf,
        row,
        col,
        " ",
        context,
        region
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
        context,
        region
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
          context,
          region
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
          canvas.safe_get_char(buf,
          legacy_row,
          legacy_col,
          region)

        if
          legacy_char
          == expected_arrow
        then
          delete_write(
            buf,
            legacy_row,
            legacy_col,
            " ",
            context,
            region
          )

          prune_branch(
            buf,
            legacy_row
              + outward.row,
            legacy_col
              + outward.col,
            inward,
            context,
            region
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
              context,
              region
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
  shape,
  region
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
      context,
      region
    )
  end

  return context.changed
end

---------------------------------------------------------------------
-- Route a new connector between two shapes
--
-- Computes anchors, builds the path, validates, draws, and
-- optionally places a reverse arrowhead for bidirectional
-- connections.  Does NOT update metadata — that is the caller's
-- responsibility.
--
-- Returns true on success, or false + reason string on failure.
---------------------------------------------------------------------

function M.route_between(
  buf,
  state,
  source,
  target,
  direction,
  bidirectional,
  region
)
  local start_row,
    start_col =
    outside_anchor(
      source,
      direction
    )

  local target_side =
    canvas.directions[direction].opposite

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
    return
      false,
      "Could not calculate connector anchors"
  end

  local path =
    build_path(
      direction,
      start_row,
      start_col,
      end_row,
      end_col
    )

  if region and #path > 0 then
    local min_row = path[1].row

    for _, cell in ipairs(path) do
      if cell.row < min_row then
        min_row = cell.row
      end
    end

    local offset =
      canvas.grow_region_up(
        buf,
        min_row,
        region
      )

    if offset > 0 then
      for _, cell in ipairs(path) do
        cell.row = cell.row + offset
      end
    end
  end

  local valid,
    reason =
    validate_new_path(
      buf,
      state,
      source,
      target,
      path,
      region
    )

  if not valid then
    return false, reason
  end

  local success =
    draw_path(
      buf,
      path,
      direction,
      region
    )

  if not success then
    return
      false,
      "Failed to draw connector path"
  end

  if bidirectional then
    canvas.undo_join()

    canvas.set_char(
      buf,
      start_row,
      start_col,
      arrows.arrowheads[
        canvas.directions[direction].opposite
      ],
      region
    )
  end

  return true
end

---------------------------------------------------------------------
-- Public connector
---------------------------------------------------------------------

function M.connect(
  state,
  direction,
  region
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
    canvas.current_position(region)

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
      direction,
      region
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
      direction,
      region
    )

    -------------------------------------------------------------------
    -- Update metadata: mark the existing reverse entry bidirectional.
    -- If not found (e.g. after undo), add a new bidirectional entry.
    -------------------------------------------------------------------

    local found = false

    for _, entry
      in ipairs(state.connectors)
    do
      if
        entry.source_id == target.id
        and entry.target_id == source.id
      then
        entry.bidirectional =
          true

        found = true

        break
      end
    end

    if not found then
      M.add_meta(
        state,
        source.id,
        target.id,
        direction,
        true
      )
    end

    vim.notify(
      "-- CONNECTED --"
    )

    return
  end

  -------------------------------------------------------------------
  -- Otherwise build a brand-new connector.
  -------------------------------------------------------------------

  local success,
    reason =
    M.route_between(
      buf,
      state,
      source,
      target,
      direction,
      false,
      region
    )

  if not success then
    vim.notify(
      reason,
      vim.log.levels.WARN
    )

    return
  end

  M.add_meta(
    state,
    source.id,
    target.id,
    direction,
    false
  )

  vim.notify(
    "-- CONNECTED --"
  )
end

---------------------------------------------------------------------
-- Append a connector metadata entry
---------------------------------------------------------------------

function M.add_meta(
  state,
  source_id,
  target_id,
  direction,
  bidirectional
)
  table.insert(
    state.connectors,
    {
      source_id = source_id,
      target_id = target_id,
      direction = direction,
      bidirectional = bidirectional,
    }
  )
end

---------------------------------------------------------------------
-- Remove all metadata entries referencing a shape
---------------------------------------------------------------------

function M.remove_meta_for_shape(
  state,
  shape_id
)
  for i = #state.connectors, 1, -1 do
    local entry =
      state.connectors[i]

    if
      entry.source_id == shape_id
      or entry.target_id == shape_id
    then
      table.remove(
        state.connectors,
        i
      )
    end
  end
end

---------------------------------------------------------------------
-- Return all metadata entries where shape is source or target
---------------------------------------------------------------------

function M.find_meta_for_shape(
  state,
  shape_id
)
  local result = {}

  for _, entry
    in ipairs(state.connectors)
  do
    if
      entry.source_id == shape_id
      or entry.target_id == shape_id
    then
      table.insert(
        result,
        entry
      )
    end
  end

  return result
end

---------------------------------------------------------------------
-- Rebuild connector metadata from buffer topology.
--
-- Scans each shape's outside cells for outgoing connectors.
-- A cell going outward in direction `side` is the source end of a
-- connector.  BFS via reachable_topology traces it to the arrowhead,
-- which sits on the target shape's opposite outside cell.
--
-- Also scans for incoming connectors.  An arrowhead pointing INTO
-- the shape is the target end.  Step outward from the arrowhead,
-- BFS, then find the source shape whose outgoing cell is reachable.
--
-- Deduplicates raw results since the same A→B connection is found
-- by both the outgoing scan on A and the incoming scan on B.
--
-- Bidirectional detection is handled separately.
---------------------------------------------------------------------

function M.rediscover_meta(
  state,
  region
)
  state.connectors = {}

  local buf = state.buf

  for _, src in ipairs(state.shapes) do
    for _, side in ipairs {
      "left",
      "right",
      "up",
      "down",
    } do
      local side_delta =
        canvas.directions[side]

      local opposite_side =
        side_delta.opposite

      local back_delta =
        canvas.directions[opposite_side]

      for _, start_cell
        in ipairs(
          src.outside_cells(src, side)
        )
      do
        local char =
          canvas.safe_get_char(
            buf,
            start_cell.row,
            start_cell.col,
            region
          )

        local conn =
          topology.from_char(char)

        if
          conn ~= nil
          and has_connections(conn)
          and conn[side]
        then
          local visited =
            reachable_topology(
              buf,
              start_cell.row,
              start_cell.col,
              region
            )

          for _, tgt
            in ipairs(state.shapes)
          do
            if tgt.id ~= src.id then
              for _, tgt_cell
                in ipairs(
                  tgt.outside_cells(
                    tgt,
                    opposite_side
                  )
                )
              do
                local tgt_char =
                  canvas.safe_get_char(
                    buf,
                    tgt_cell.row,
                    tgt_cell.col,
                    region
                  )

                if
                  tgt_char
                  == arrows.arrowheads[side]
                then
                  local behind_row =
                    tgt_cell.row
                    + back_delta.row

                  local behind_col =
                    tgt_cell.col
                    + back_delta.col

                  if
                    visited[
                      position_key(
                        behind_row,
                        behind_col
                      )
                    ]
                  then
                    M.add_meta(
                      state,
                      src.id,
                      tgt.id,
                      side,
                      false
                    )
                  end
                end
              end
            end
          end
        end
      end

      ----------------------------------------------------------------
      -- Incoming scan: arrowheads pointing INTO src on this side.
      --
      -- An arrowhead pointing into src sits at src's outside cell
      -- in direction `side`.  It points toward src, i.e. in the
      -- `opposite_side` direction.  Step further outward (in `side`)
      -- to enter the topology and BFS back to the source shape.
      ----------------------------------------------------------------

      local expected_incoming_arrow =
        arrows.arrowheads[opposite_side]

      for _, end_cell
        in ipairs(
          src.outside_cells(src, side)
        )
      do
        local end_char =
          canvas.safe_get_char(
            buf,
            end_cell.row,
            end_cell.col,
            region
          )

        if
          end_char
          == expected_incoming_arrow
        then
          local beyond_row =
            end_cell.row
            + side_delta.row

          local beyond_col =
            end_cell.col
            + side_delta.col

          local visited =
            reachable_topology(
              buf,
              beyond_row,
              beyond_col,
              region
            )

          for _, source_shape
            in ipairs(state.shapes)
          do
            if
              source_shape.id ~= src.id
            then
              for _, source_cell
                in ipairs(
                  source_shape.outside_cells(
                    source_shape,
                    opposite_side
                  )
                )
              do
                local source_char =
                  canvas.safe_get_char(
                    buf,
                    source_cell.row,
                    source_cell.col,
                    region
                  )

                local source_conn =
                  topology.from_char(
                    source_char
                  )

                if
                  source_conn ~= nil
                  and has_connections(
                    source_conn
                  )
                  and source_conn[
                    opposite_side
                  ]
                  and visited[
                    position_key(
                      source_cell.row,
                      source_cell.col
                    )
                  ]
                then
                  M.add_meta(
                    state,
                    source_shape.id,
                    src.id,
                    opposite_side,
                    false
                  )
                end
              end
            end
          end
        end
      end
    end
  end

  ----------------------------------------------------------------
  -- A→B is discovered by both the outgoing scan on A (side=right)
  -- and the incoming scan on B (side=left).  Keep only the first
  -- occurrence per (source_id, target_id, direction).
  ----------------------------------------------------------------

  local seen = {}
  local deduped = {}

  for _, entry in ipairs(state.connectors) do
    local key =
      tostring(entry.source_id)
      .. ":"
      .. tostring(entry.target_id)
      .. ":"
      .. entry.direction

    if not seen[key] then
      seen[key] = true

      table.insert(
        deduped,
        entry
      )
    end
  end

  ----------------------------------------------------------------
  -- A bidirectional connector A↔B is discovered as two entries:
  --   (source=A, target=B, direction=D)
  --   (source=B, target=A, direction=opposite(D))
  --
  -- Merge matching pairs into one entry with bidirectional = true.
  ----------------------------------------------------------------

  local merged = {}
  local consumed = {}

  for i, entry in ipairs(deduped) do
    if not consumed[i] then
      local reverse_dir =
        canvas.directions[entry.direction].opposite

      local partner_idx = nil

      for j = i + 1, #deduped do
        if
          not consumed[j]
          and deduped[j].source_id == entry.target_id
          and deduped[j].target_id == entry.source_id
          and deduped[j].direction == reverse_dir
        then
          partner_idx = j
          break
        end
      end

      if partner_idx ~= nil then
        consumed[partner_idx] = true

        table.insert(
          merged,
          {
            source_id = entry.source_id,
            target_id = entry.target_id,
            direction = entry.direction,
            bidirectional = true,
          }
        )
      else
        table.insert(
          merged,
          entry
        )
      end
    end
  end

  state.connectors = merged
end

return M
