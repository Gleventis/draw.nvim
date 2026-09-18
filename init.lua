local canvas =
  require "draw.canvas"

local line =
  require "draw.line"

local arrows =
  require "draw.arrows"

local erase =
  require "draw.erase"

local edit =
  require "draw.edit"

local deletion =
  require "draw.delete"

local label =
  require "draw.label"

local shapes =
  require "draw.shapes"

local navigation =
  require "draw.navigation"

local rectangle =
  require "draw.shapes.rectangle"

local rounded_rectangle =
  require "draw.shapes.rounded_rectangle"

local diamond =
  require "draw.shapes.diamond"

local discovery =
  require "draw.discovery"

local connector =
  require "draw.connector"

local M = {}

local states = {}

---------------------------------------------------------------------
-- Shape definitions
---------------------------------------------------------------------

local shape_types = {
  rectangle = {
    name = "BOX",
    key = "B",
    renderer = rectangle,
  },

  rounded_rectangle = {
    name = "ROUNDED BOX",
    key = "R",
    renderer = rounded_rectangle,
  },

  diamond = {
    name = "DIAMOND",
    key = "D",
    renderer = diamond,
  },
}

---------------------------------------------------------------------
-- Rediscover shapes
--
-- Neovim undo/redo only modifies the buffer. Our tracked shape
-- metadata lives separately in Lua state.
--
-- After undo/redo we therefore rebuild state.shapes from what is
-- actually present in the buffer.
---------------------------------------------------------------------

local function rediscover_shapes(
  state
)
  if state == nil then
    return
  end

  state.shapes = {}
  state.next_shape_id = 0

  local discovered_shapes =
    discovery.scan(
      state.buf
    )

  for _, shape
    in ipairs(discovered_shapes)
  do
    shapes.add(
      state,
      shape
    )
  end
end

---------------------------------------------------------------------
-- Arrow behavior
---------------------------------------------------------------------

local function handle_arrow(direction)
  local buf =
    vim.api.nvim_get_current_buf()

  local state =
    states[buf]

  if state == nil then
    return
  end

  -------------------------------------------------------------------
  -- ERASE
  -------------------------------------------------------------------

  if state.mode == "erase" then
    erase.move(direction)
    return
  end

  -------------------------------------------------------------------
  -- Shape selection
  --
  -- While choosing the second corner, arrows only move.
  -------------------------------------------------------------------

  if state.mode == "box" then
    canvas.move_only(direction)
    return
  end

  -------------------------------------------------------------------
  -- DRAW
  -------------------------------------------------------------------

  line.draw(direction)
end

---------------------------------------------------------------------
-- Toggle ERASE
---------------------------------------------------------------------

local function toggle_erase()
  local buf =
    vim.api.nvim_get_current_buf()

  local state =
    states[buf]

  if state == nil then
    return
  end

  -------------------------------------------------------------------
  -- Don't enter ERASE while creating a shape.
  -------------------------------------------------------------------

  if state.mode == "box" then
    local pending =
      state.pending_shape

    local name =
      pending
      and pending.name
      or "shape"

    local key =
      pending
      and pending.key
      or "?"

    vim.notify(
      "Finish "
        .. name
        .. " with "
        .. key
        .. " or cancel with Esc",
      vim.log.levels.WARN
    )

    return
  end

  -------------------------------------------------------------------
  -- ERASE -> DRAW
  -------------------------------------------------------------------

  if state.mode == "erase" then
    state.mode =
      "draw"

    vim.b[buf].draw_submode =
      "draw"

    vim.notify("-- DRAW --")

    return
  end

  -------------------------------------------------------------------
  -- DRAW -> ERASE
  -------------------------------------------------------------------

  state.mode =
    "erase"

  vim.b[buf].draw_submode =
    "erase"

  -------------------------------------------------------------------
  -- Erase the cell we're currently standing on.
  -------------------------------------------------------------------

  local row, col =
    canvas.current_position()

  erase.at(
    buf,
    row,
    col
  )

  canvas.set_cursor(
    buf,
    row,
    col
  )

  vim.notify("-- ERASE --")
end

---------------------------------------------------------------------
-- Start / finish shape
---------------------------------------------------------------------

local function toggle_shape(kind)
  local buf =
    vim.api.nvim_get_current_buf()

  local state =
    states[buf]

  if state == nil then
    return
  end

  local config =
    shape_types[kind]

  if config == nil then
    return
  end

  -------------------------------------------------------------------
  -- Shapes cannot be created from ERASE mode.
  -------------------------------------------------------------------

  if state.mode == "erase" then
    vim.notify(
      "Exit ERASE mode with x first",
      vim.log.levels.WARN
    )

    return
  end

  -------------------------------------------------------------------
  -- First key press
  -------------------------------------------------------------------

  if state.mode ~= "box" then
    local row, col =
      canvas.current_position()

    state.box_start = {
      row = row,
      col = col,
    }

    state.pending_shape = {
      kind = kind,
      name = config.name,
      key = config.key,
      renderer = config.renderer,
    }

    state.mode =
      "box"

    vim.b[buf].draw_submode =
      kind

    vim.notify(
      "-- "
        .. config.name
        .. " -- move to opposite corner, press "
        .. config.key
    )

    return
  end

  -------------------------------------------------------------------
  -- Already creating a different shape.
  -------------------------------------------------------------------

  local pending =
    state.pending_shape

  if
    pending == nil
    or pending.kind ~= kind
  then
    local current_name =
      pending
      and pending.name
      or "shape"

    local current_key =
      pending
      and pending.key
      or "?"

    vim.notify(
      "Currently creating "
        .. current_name
        .. ". Finish with "
        .. current_key
        .. " or cancel with Esc",
      vim.log.levels.WARN
    )

    return
  end

  -------------------------------------------------------------------
  -- Second matching key press
  -------------------------------------------------------------------

  local end_row,
    end_col =
    canvas.current_position()

  local start =
    state.box_start

  if start == nil then
    state.mode =
      "draw"

    state.pending_shape =
      nil

    vim.b[buf].draw_submode =
      "draw"

    return
  end

  local success,
    shape =
    pending.renderer.draw(
      buf,
      start.row,
      start.col,
      end_row,
      end_col
    )

  if not success then
    return
  end

  -------------------------------------------------------------------
  -- Register shape
  --
  -- LABEL mode and hb/jb/kb/lb use this metadata.
  -------------------------------------------------------------------

  shapes.add(
    state,
    shape
  )

  state.box_start =
    nil

  state.pending_shape =
    nil

  state.mode =
    "draw"

  vim.b[buf].draw_submode =
    "draw"

  -------------------------------------------------------------------
  -- Move directly into the new shape.
  -------------------------------------------------------------------

  local entry_row,
    entry_col =
    shapes.entry_point(shape)

  canvas.set_cursor(
    buf,
    entry_row,
    entry_col
  )

  vim.notify("-- DRAW --")
end

---------------------------------------------------------------------
-- Cancel pending shape
---------------------------------------------------------------------

local function cancel_shape()
  local buf =
    vim.api.nvim_get_current_buf()

  local state =
    states[buf]

  if state == nil then
    return
  end

  if state.mode ~= "box" then
    return
  end

  state.box_start =
    nil

  state.pending_shape =
    nil

  state.mode =
    "draw"

  vim.b[buf].draw_submode =
    "draw"

  vim.notify(
    "Shape cancelled"
  )
end

---------------------------------------------------------------------
-- LABEL
---------------------------------------------------------------------

local function start_label()
  local buf =
    vim.api.nvim_get_current_buf()

  local state =
    states[buf]

  if state == nil then
    return
  end

  label.start(
    buf,
    state
  )
end

---------------------------------------------------------------------
-- Spatial shape navigation
---------------------------------------------------------------------

local function jump_shape(direction)
  local buf =
    vim.api.nvim_get_current_buf()

  local state =
    states[buf]

  if state == nil then
    return
  end

  navigation.jump(
    state,
    direction
  )
end

---------------------------------------------------------------------
-- Smart connector
---------------------------------------------------------------------

local function connect_shape(direction)
  local buf =
    vim.api.nvim_get_current_buf()

  local state =
    states[buf]

  if state == nil then
    return
  end

  connector.connect(
    state,
    direction
  )
end

---------------------------------------------------------------------
-- Safe dd
--
-- Instead of deleting the entire Neovim buffer line, clear only the
-- writable part of the current shape row.
---------------------------------------------------------------------

local function clear_shape_row()
  local buf =
    vim.api.nvim_get_current_buf()

  local state =
    states[buf]

  if state == nil then
    return
  end

  edit.clear_row(
    state
  )
end

---------------------------------------------------------------------
-- Delete whole shape
--
-- db removes the shape under the cursor, including its attached
-- connectors.
---------------------------------------------------------------------

local function delete_shape()
  local buf =
    vim.api.nvim_get_current_buf()

  local state =
    states[buf]

  if state == nil then
    return
  end

  deletion.delete_shape(
    state
  )
end

---------------------------------------------------------------------
-- Undo
--
-- Native undo restores buffer text, but not our Lua shape metadata.
-- Rediscover shapes immediately afterwards so both remain in sync.
---------------------------------------------------------------------

local function undo()
  local buf =
    vim.api.nvim_get_current_buf()

  local state =
    states[buf]

  if state == nil then
    return
  end

  local success =
    pcall(
      vim.cmd,
      "undo"
    )

  if not success then
    return
  end

  rediscover_shapes(
    state
  )
end

---------------------------------------------------------------------
-- Redo
--
-- Same reason as undo: rebuild metadata after the buffer changes.
---------------------------------------------------------------------

local function redo()
  local buf =
    vim.api.nvim_get_current_buf()

  local state =
    states[buf]

  if state == nil then
    return
  end

  local success =
    pcall(
      vim.cmd,
      "redo"
    )

  if not success then
    return
  end

  rediscover_shapes(
    state
  )
end

---------------------------------------------------------------------
-- Mapping helper
---------------------------------------------------------------------

local function map(
  state,
  mode,
  lhs,
  rhs,
  opts
)
  opts =
    opts or {}

  local nowait =
    true

  if opts.nowait ~= nil then
    nowait =
      opts.nowait
  end

  vim.keymap.set(
    mode,
    lhs,
    rhs,
    {
      buffer = state.buf,
      silent = true,
      nowait = nowait,
    }
  )

  table.insert(
    state.maps,
    {
      mode = mode,
      lhs = lhs,
    }
  )
end

---------------------------------------------------------------------
-- Stop Draw mode
---------------------------------------------------------------------

function M.stop()
  local buf =
    vim.api.nvim_get_current_buf()

  local state =
    states[buf]

  if state == nil then
    return
  end

  -------------------------------------------------------------------
  -- Remove buffer-local Draw mappings
  -------------------------------------------------------------------

  for _, mapping
    in ipairs(state.maps)
  do
    pcall(
      vim.keymap.del,
      mapping.mode,
      mapping.lhs,
      {
        buffer = buf,
      }
    )
  end

  -------------------------------------------------------------------
  -- Restore previous window options
  -------------------------------------------------------------------

  if
    vim.api.nvim_win_is_valid(
      state.win
    )
  then
    pcall(
      vim.api.nvim_set_option_value,
      "virtualedit",
      state.virtualedit,
      {
        win = state.win,
      }
    )

    pcall(
      vim.api.nvim_set_option_value,
      "wrap",
      state.wrap,
      {
        win = state.win,
      }
    )
  end

  vim.b[buf].draw_mode =
    false

  vim.b[buf].draw_submode =
    nil

  states[buf] =
    nil

  vim.notify(
    "Draw mode disabled"
  )
end

---------------------------------------------------------------------
-- Start Draw mode
---------------------------------------------------------------------

function M.start()
  local buf =
    vim.api.nvim_get_current_buf()

  if states[buf] ~= nil then
    return
  end

  local win =
    vim.api.nvim_get_current_win()

  local state = {
    buf = buf,
    win = win,

    maps = {},

    mode =
      "draw",

    -----------------------------------------------------------------
    -- Pending shape state
    -----------------------------------------------------------------

    box_start =
      nil,

    pending_shape =
      nil,

    -----------------------------------------------------------------
    -- Tracked shapes
    -----------------------------------------------------------------

    shapes = {},

    next_shape_id =
      0,

    -----------------------------------------------------------------
    -- Window options to restore on exit
    -----------------------------------------------------------------

    virtualedit =
      vim.api.nvim_get_option_value(
        "virtualedit",
        {
          win = win,
        }
      ),

    wrap =
      vim.api.nvim_get_option_value(
        "wrap",
        {
          win = win,
        }
      ),
  }

  states[buf] =
    state

  -------------------------------------------------------------------
  -- Rediscover shapes already stored in the file
  -------------------------------------------------------------------

  local discovered_shapes =
    discovery.scan(buf)

  for _, shape
    in ipairs(discovered_shapes)
  do
    shapes.add(
      state,
      shape
    )
  end

  -------------------------------------------------------------------
  -- Canvas behavior
  -------------------------------------------------------------------

  vim.api.nvim_set_option_value(
    "virtualedit",
    "all",
    {
      win = win,
    }
  )

  vim.api.nvim_set_option_value(
    "wrap",
    false,
    {
      win = win,
    }
  )

  vim.b[buf].draw_mode =
    true

  vim.b[buf].draw_submode =
    "draw"

  -------------------------------------------------------------------
  -- Arrow keys
  --
  -- DRAW:
  --     draw
  --
  -- ERASE:
  --     erase while moving
  --
  -- shape selection:
  --     move only
  -------------------------------------------------------------------

  map(
    state,
    "n",
    "<Left>",
    function()
      handle_arrow "left"
    end
  )

  map(
    state,
    "n",
    "<Right>",
    function()
      handle_arrow "right"
    end
  )

  map(
    state,
    "n",
    "<Up>",
    function()
      handle_arrow "up"
    end
  )

  map(
    state,
    "n",
    "<Down>",
    function()
      handle_arrow "down"
    end
  )

  -------------------------------------------------------------------
  -- Shift + Arrow = move only
  -------------------------------------------------------------------

  map(
    state,
    "n",
    "<S-Left>",
    function()
      canvas.move_only "left"
    end
  )

  map(
    state,
    "n",
    "<S-Right>",
    function()
      canvas.move_only "right"
    end
  )

  map(
    state,
    "n",
    "<S-Up>",
    function()
      canvas.move_only "up"
    end
  )

  map(
    state,
    "n",
    "<S-Down>",
    function()
      canvas.move_only "down"
    end
  )

  -------------------------------------------------------------------
  -- LABEL
  -------------------------------------------------------------------

  map(
    state,
    "n",
    "i",
    start_label
  )

  -------------------------------------------------------------------
  -- ERASE
  -------------------------------------------------------------------

  map(
    state,
    "n",
    "x",
    toggle_erase
  )

  -------------------------------------------------------------------
  -- RECTANGLE
  --
  -- B ... B
  -------------------------------------------------------------------

  map(
    state,
    "n",
    "B",
    function()
      toggle_shape "rectangle"
    end
  )

  -------------------------------------------------------------------
  -- ROUNDED RECTANGLE
  --
  -- R ... R
  -------------------------------------------------------------------

  map(
    state,
    "n",
    "R",
    function()
      toggle_shape "rounded_rectangle"
    end
  )

  -------------------------------------------------------------------
  -- DIAMOND
  --
  -- D ... D
  -------------------------------------------------------------------

  map(
    state,
    "n",
    "D",
    function()
      toggle_shape "diamond"
    end
  )

  -------------------------------------------------------------------
  -- Cancel shape selection
  -------------------------------------------------------------------

  map(
    state,
    "n",
    "<Esc>",
    cancel_shape
  )

  -------------------------------------------------------------------
  -- Spatial shape navigation
  --
  -- hb = left
  -- jb = below
  -- kb = above
  -- lb = right
  -------------------------------------------------------------------

  map(
    state,
    "n",
    "hb",
    function()
      jump_shape "left"
    end,
    {
      nowait = false,
    }
  )

  map(
    state,
    "n",
    "jb",
    function()
      jump_shape "down"
    end,
    {
      nowait = false,
    }
  )

  map(
    state,
    "n",
    "kb",
    function()
      jump_shape "up"
    end,
    {
      nowait = false,
    }
  )

  map(
    state,
    "n",
    "lb",
    function()
      jump_shape "right"
    end,
    {
      nowait = false,
    }
  )

  -------------------------------------------------------------------
  -- Smart connectors
  --
  -- hc = connect left
  -- jc = connect down
  -- kc = connect up
  -- lc = connect right
  -------------------------------------------------------------------

  map(
    state,
    "n",
    "hc",
    function()
      connect_shape "left"
    end,
    {
      nowait = false,
    }
  )

  map(
    state,
    "n",
    "jc",
    function()
      connect_shape "down"
    end,
    {
      nowait = false,
    }
  )

  map(
    state,
    "n",
    "kc",
    function()
      connect_shape "up"
    end,
    {
      nowait = false,
    }
  )

  map(
    state,
    "n",
    "lc",
    function()
      connect_shape "right"
    end,
    {
      nowait = false,
    }
  )

  -------------------------------------------------------------------
  -- Safe line clearing
  --
  -- dd no longer deletes the entire underlying buffer line.
  -------------------------------------------------------------------

  map(
    state,
    "n",
    "dd",
    clear_shape_row,
    {
      nowait = false,
    }
  )

  -------------------------------------------------------------------
  -- Delete whole shape
  --
  -- db removes the shape and its attached connectors.
  -------------------------------------------------------------------

  map(
    state,
    "n",
    "db",
    delete_shape,
    {
      nowait = false,
    }
  )

  -------------------------------------------------------------------
  -- Undo / redo
  --
  -- These wrap Neovim's normal operations and then reconstruct
  -- state.shapes so buffer state and Draw state stay synchronized.
  -------------------------------------------------------------------

  map(
    state,
    "n",
    "u",
    undo
  )

  map(
    state,
    "n",
    "<C-r>",
    redo
  )

  -------------------------------------------------------------------
  -- Arrowheads
  -------------------------------------------------------------------

  map(
    state,
    "n",
    "LA",
    function()
      arrows.place(
        buf,
        state,
        "left"
      )
    end
  )

  map(
    state,
    "n",
    "RA",
    function()
      arrows.place(
        buf,
        state,
        "right"
      )
    end
  )

  map(
    state,
    "n",
    "UA",
    function()
      arrows.place(
        buf,
        state,
        "up"
      )
    end
  )

  map(
    state,
    "n",
    "DA",
    function()
      arrows.place(
        buf,
        state,
        "down"
      )
    end
  )

  -------------------------------------------------------------------
  -- Exit Draw mode
  -------------------------------------------------------------------

  map(
    state,
    "n",
    "q",
    function()
      M.stop()
    end
  )

  if #discovered_shapes > 0 then
    local suffix =
      #discovered_shapes == 1
        and " shape"
        or " shapes"

    vim.notify(
      "-- DRAW -- loaded "
        .. #discovered_shapes
        .. suffix
    )
  else
    vim.notify("-- DRAW --")
  end
end

---------------------------------------------------------------------
-- Toggle Draw
---------------------------------------------------------------------

function M.toggle()
  local buf =
    vim.api.nvim_get_current_buf()

  if states[buf] then
    M.stop()
  else
    M.start()
  end
end

---------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------

function M.setup()
  vim.api.nvim_create_user_command(
    "Draw",
    function()
      M.toggle()
    end,
    {
      desc = "Toggle Draw mode",
    }
  )
end

return M
