local canvas =
  require "draw.canvas"

local shapes =
  require "draw.shapes"

local M = {}

---------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------

local function cleanup(buf, state)
  local label =
    state.label

  if label == nil then
    return
  end

  for _, lhs in ipairs(label.maps or {}) do
    pcall(
      vim.keymap.del,
      "i",
      lhs,
      {
        buffer = buf,
      }
    )
  end

  if label.augroup then
    pcall(
      vim.api.nvim_del_augroup_by_id,
      label.augroup
    )
  end

  if
    label.win
    and vim.api.nvim_win_is_valid(label.win)
  then
    pcall(
      vim.api.nvim_set_option_value,
      "virtualedit",
      label.virtualedit,
      {
        win = label.win,
      }
    )
  end

  state.label = nil
end

---------------------------------------------------------------------
-- Materialize writable rows
---------------------------------------------------------------------

local function materialize_shape(buf, shape)
  for row =
    shape.top + 1,
    shape.bottom - 1
  do
    local _, right =
      shapes.row_bounds(
        shape,
        row
      )

    if right ~= nil then
      canvas.ensure_col(
        buf,
        row,
        right
      )
    end
  end
end

---------------------------------------------------------------------
-- Clamp preferred label column to a particular row
---------------------------------------------------------------------

local function row_start_col(
  label,
  row
)
  local left, right =
    shapes.row_bounds(
      label.shape,
      row
    )

  if left == nil then
    return nil
  end

  return math.max(
    left,
    math.min(
      label.start_col,
      right
    )
  )
end

---------------------------------------------------------------------
-- Next writable row
---------------------------------------------------------------------

local function next_row(
  label,
  current_row
)
  for row =
    current_row + 1,
    label.shape.bottom - 1
  do
    local left, right =
      shapes.row_bounds(
        label.shape,
        row
      )

    if
      left ~= nil
      and right ~= nil
      and left <= right
    then
      return
        row,
        left,
        right
    end
  end

  return nil, nil, nil
end

---------------------------------------------------------------------
-- Clear range
---------------------------------------------------------------------

local function clear_range(
  buf,
  row,
  start_col,
  end_col
)
  for col = start_col, end_col do
    canvas.set_char(
      buf,
      row,
      col,
      " "
    )
  end
end

---------------------------------------------------------------------
-- Write character list
---------------------------------------------------------------------

local function write_chars(
  buf,
  row,
  start_col,
  chars
)
  for index, char in ipairs(chars) do
    canvas.set_char(
      buf,
      row,
      start_col + index - 1,
      char
    )
  end
end

---------------------------------------------------------------------
-- Find trailing word
---------------------------------------------------------------------

local function trailing_word(
  buf,
  row,
  start_col,
  end_col
)
  local col =
    end_col

  while col >= start_col do
    local char =
      canvas.get_char(
        buf,
        row,
        col
      )

    if char == "" or char == " " then
      break
    end

    col =
      col - 1
  end

  local word_start =
    col + 1

  if word_start <= start_col then
    return nil, nil
  end

  local chars = {}

  for current_col =
    word_start,
    end_col
  do
    table.insert(
      chars,
      canvas.get_char(
        buf,
        row,
        current_col
      )
    )
  end

  return
    word_start,
    chars
end

---------------------------------------------------------------------
-- Enter
---------------------------------------------------------------------

local function newline(buf, state)
  local label =
    state.label

  if label == nil then
    return
  end

  local row =
    select(
      1,
      canvas.current_position()
    )

  local target_row =
    next_row(
      label,
      row
    )

  if target_row == nil then
    return
  end

  local target_col =
    row_start_col(
      label,
      target_row
    )

  if target_col == nil then
    return
  end

  canvas.set_cursor(
    buf,
    target_row,
    target_col
  )
end

---------------------------------------------------------------------
-- Backspace
---------------------------------------------------------------------

local function backspace(buf, state)
  local label =
    state.label

  if label == nil then
    return
  end

  local row, col =
    canvas.current_position()

  local left, right =
    shapes.row_bounds(
      label.shape,
      row
    )

  if left == nil then
    return
  end

  local target_col =
    col - 1

  if
    target_col < left
    or target_col > right
  then
    return
  end

  canvas.set_char(
    buf,
    row,
    target_col,
    " "
  )

  canvas.set_cursor(
    buf,
    row,
    target_col
  )
end

---------------------------------------------------------------------
-- Delete
---------------------------------------------------------------------

local function delete_current(buf, state)
  local label =
    state.label

  if label == nil then
    return
  end

  local row, col =
    canvas.current_position()

  local left, right =
    shapes.row_bounds(
      label.shape,
      row
    )

  if left == nil then
    return
  end

  if col < left or col > right then
    return
  end

  canvas.set_char(
    buf,
    row,
    col,
    " "
  )

  canvas.set_cursor(
    buf,
    row,
    col
  )
end

---------------------------------------------------------------------
-- Character wrap fallback
---------------------------------------------------------------------

local function character_wrap(
  buf,
  state,
  char,
  target_row
)
  local label =
    state.label

  local target_col =
    row_start_col(
      label,
      target_row
    )

  if target_col == nil then
    return
  end

  vim.schedule(function()
    if
      not vim.api.nvim_buf_is_valid(buf)
      or state.mode ~= "label"
      or state.label == nil
    then
      return
    end

    local _, right =
      shapes.row_bounds(
        label.shape,
        target_row
      )

    if right == nil then
      return
    end

    canvas.set_char(
      buf,
      target_row,
      target_col,
      char
    )

    canvas.set_cursor(
      buf,
      target_row,
      math.min(
        target_col + 1,
        right + 1
      )
    )
  end)
end

---------------------------------------------------------------------
-- Word wrapping
---------------------------------------------------------------------

local function handle_wrap(buf, state)
  if
    state.mode ~= "label"
    or state.label == nil
  then
    return
  end

  local label =
    state.label

  local shape =
    label.shape

  local row, col =
    canvas.current_position()

  local left, right =
    shapes.row_bounds(
      shape,
      row
    )

  -------------------------------------------------------------------
  -- Row has no writable interior
  -------------------------------------------------------------------

  if left == nil then
    vim.v.char = ""
    return
  end

  -------------------------------------------------------------------
  -- Normal writable position
  -------------------------------------------------------------------

  if col >= left and col <= right then
    return
  end

  -------------------------------------------------------------------
  -- Protect outline
  -------------------------------------------------------------------

  local incoming_char =
    vim.v.char

  vim.v.char = ""

  -------------------------------------------------------------------
  -- If we somehow landed before the writable region, don't write.
  -------------------------------------------------------------------

  if col < left then
    return
  end

  -------------------------------------------------------------------
  -- Wrap to next writable row
  -------------------------------------------------------------------

  local target_row,
    target_left,
    target_right =
    next_row(
      label,
      row
    )

  if target_row == nil then
    return
  end

  local target_start =
    math.max(
      target_left,
      math.min(
        label.start_col,
        target_right
      )
    )

  -------------------------------------------------------------------
  -- Space at boundary:
  -- just move to next row
  -------------------------------------------------------------------

  if incoming_char == " " then
    vim.schedule(function()
      if
        vim.api.nvim_buf_is_valid(buf)
        and state.mode == "label"
      then
        canvas.set_cursor(
          buf,
          target_row,
          target_start
        )
      end
    end)

    return
  end

  -------------------------------------------------------------------
  -- Find trailing word
  -------------------------------------------------------------------

  local current_start =
    math.max(
      left,
      math.min(
        label.start_col,
        right
      )
    )

  local word_start,
    word_chars =
    trailing_word(
      buf,
      row,
      current_start,
      right
    )

  -------------------------------------------------------------------
  -- No useful word boundary
  -------------------------------------------------------------------

  if word_start == nil then
    character_wrap(
      buf,
      state,
      incoming_char,
      target_row
    )

    return
  end

  local available_width =
    target_right
    - target_start
    + 1

  local required_width =
    #word_chars
    + 1

  -------------------------------------------------------------------
  -- Word doesn't fit:
  -- fall back to character wrapping
  -------------------------------------------------------------------

  if required_width > available_width then
    character_wrap(
      buf,
      state,
      incoming_char,
      target_row
    )

    return
  end

  -------------------------------------------------------------------
  -- Move whole word
  -------------------------------------------------------------------

  vim.schedule(function()
    if
      not vim.api.nvim_buf_is_valid(buf)
      or state.mode ~= "label"
      or state.label == nil
    then
      return
    end

    clear_range(
      buf,
      row,
      word_start,
      right
    )

    write_chars(
      buf,
      target_row,
      target_start,
      word_chars
    )

    local incoming_col =
      target_start
      + #word_chars

    canvas.set_char(
      buf,
      target_row,
      incoming_col,
      incoming_char
    )

    canvas.set_cursor(
      buf,
      target_row,
      math.min(
        incoming_col + 1,
        target_right + 1
      )
    )
  end)
end

---------------------------------------------------------------------
-- Start LABEL
---------------------------------------------------------------------

function M.start(buf, state)
  if state == nil then
    return
  end

  if state.mode == "erase" then
    vim.notify(
      "Exit ERASE mode with x first",
      vim.log.levels.WARN
    )

    return
  end

  if state.mode == "box" then
    vim.notify(
      "Finish the shape or cancel with Esc first",
      vim.log.levels.WARN
    )

    return
  end

  local row, col =
    canvas.current_position()

  local shape =
    shapes.find_containing(
      state.shapes,
      row,
      col
    )

  if shape == nil then
    vim.notify(
      "Move inside a tracked shape before entering LABEL mode",
      vim.log.levels.WARN
    )

    return
  end

  materialize_shape(
    buf,
    shape
  )

  state.mode =
    "label"

  vim.b[buf].draw_submode =
    "label"

  local win =
    vim.api.nvim_get_current_win()

  local previous_virtualedit =
    vim.api.nvim_get_option_value(
      "virtualedit",
      {
        win = win,
      }
    )

  vim.api.nvim_set_option_value(
    "virtualedit",
    "",
    {
      win = win,
    }
  )

  local augroup =
    vim.api.nvim_create_augroup(
      "DrawLabel_" .. buf,
      {
        clear = true,
      }
    )

  state.label = {
    shape = shape,

    start_col = col,

    win = win,

    virtualedit =
      previous_virtualedit,

    maps = {
      "<CR>",
      "<BS>",
      "<Del>",
    },

    augroup =
      augroup,
  }

  vim.keymap.set(
    "i",
    "<CR>",
    function()
      newline(
        buf,
        state
      )
    end,
    {
      buffer = buf,
      silent = true,
      nowait = true,
    }
  )

  vim.keymap.set(
    "i",
    "<BS>",
    function()
      backspace(
        buf,
        state
      )
    end,
    {
      buffer = buf,
      silent = true,
      nowait = true,
    }
  )

  vim.keymap.set(
    "i",
    "<Del>",
    function()
      delete_current(
        buf,
        state
      )
    end,
    {
      buffer = buf,
      silent = true,
      nowait = true,
    }
  )

  vim.api.nvim_create_autocmd(
    "InsertCharPre",
    {
      group = augroup,
      buffer = buf,

      callback = function()
        handle_wrap(
          buf,
          state
        )
      end,
    }
  )

  vim.api.nvim_create_autocmd(
    "InsertLeave",
    {
      group = augroup,
      buffer = buf,
      once = true,

      callback = function()
        if state.mode == "label" then
          state.mode =
            "draw"

          vim.b[buf].draw_submode =
            "draw"
        end

        vim.schedule(function()
          if
            vim.api.nvim_buf_is_valid(buf)
          then
            cleanup(
              buf,
              state
            )
          end
        end)

        vim.notify("-- DRAW --")
      end,
    }
  )

  vim.notify("-- LABEL --")

  vim.cmd "startreplace"
end

return M
