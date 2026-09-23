local M = {}

---------------------------------------------------------------------
-- Directions
---------------------------------------------------------------------

M.directions = {
  left = {
    row = 0,
    col = -1,
    opposite = "right",
  },

  right = {
    row = 0,
    col = 1,
    opposite = "left",
  },

  up = {
    row = -1,
    col = 0,
    opposite = "down",
  },

  down = {
    row = 1,
    col = 0,
    opposite = "up",
  },
}

---------------------------------------------------------------------
-- Buffer helpers
---------------------------------------------------------------------

function M.get_line(buf, row, region)
  local lines = vim.api.nvim_buf_get_lines(
    buf,
    row,
    row + 1,
    false
  )

  local line = lines[1] or ""

  if region then
    line = vim.fn.strcharpart(line, region.prefix_len)
  end

  return line
end

function M.set_line(buf, row, line, region)
  local content = region
    and (region.prefix .. line)
    or line

  vim.api.nvim_buf_set_lines(
    buf,
    row,
    row + 1,
    false,
    { content }
  )
end

---------------------------------------------------------------------
-- Upward region growth.
--
-- Inserts blank prefixed lines at region.top_row, pushing existing
-- region content (and all code below it) down.  Returns the number
-- of lines inserted so callers can shift ALL their row variables by
-- the same amount.  region.top_row stays unchanged (it now points to
-- the first new blank comment line).
---------------------------------------------------------------------

function M.grow_region_up(buf, target_row, region)
  if not region then
    return 0
  end

  if target_row >= region.top_row then
    return 0
  end

  local count =
    region.top_row - target_row

  local new_lines = {}

  for _ = 1, count do
    table.insert(
      new_lines,
      region.prefix
    )
  end

  vim.api.nvim_buf_set_lines(
    buf,
    region.top_row,
    region.top_row,
    false,
    new_lines
  )

  if region.shapes then
    for _, shape
      in ipairs(region.shapes)
    do
      shape.top =
        shape.top + count

      shape.bottom =
        shape.bottom + count
    end
  end

  region.bottom_row =
    region.bottom_row + count

  return count
end

function M.ensure_row(buf, row, region)
  if region then
    -------------------------------------------------------------------
    -- Downward growth: insert new prefixed lines directly after
    -- region.bottom_row so that downstream code is pushed down rather
    -- than overwritten.
    -------------------------------------------------------------------
    while row > region.bottom_row do
      local insert_at =
        region.bottom_row + 1

      vim.api.nvim_buf_set_lines(
        buf,
        insert_at,
        insert_at,
        false,
        { region.prefix }
      )

      region.bottom_row =
        region.bottom_row + 1
    end

    return
  end

  local line_count =
    vim.api.nvim_buf_line_count(buf)

  while row >= line_count do
    vim.api.nvim_buf_set_lines(
      buf,
      line_count,
      line_count,
      false,
      { "" }
    )

    line_count = line_count + 1
  end
end

function M.char_count(line)
  return vim.fn.strchars(line)
end

function M.ensure_col(buf, row, col, region)
  if region and row < region.top_row then
    return
  end

  M.ensure_row(buf, row, region)

  local line = M.get_line(buf, row, region)
  local length = M.char_count(line)

  if col >= length then
    local missing =
      col - length + 1

    M.set_line(
      buf,
      row,
      line .. string.rep(" ", missing),
      region
    )
  end
end

function M.get_char(buf, row, col, region)
  if region and (row < region.top_row or row > region.bottom_row) then
    return " "
  end

  M.ensure_col(buf, row, col, region)

  local line =
    M.get_line(buf, row, region)

  return vim.fn.strcharpart(
    line,
    col,
    1
  )
end

-- Non-mutating read: returns "" for out-of-bounds without extending the buffer.
function M.safe_get_char(buf, row, col, region)
  if row < 0 or col < 0 then
    return ""
  end

  if region and (row < region.top_row or row > region.bottom_row) then
    return ""
  end

  local line_count =
    vim.api.nvim_buf_line_count(buf)

  if row >= line_count then
    return ""
  end

  local line =
    M.get_line(buf, row, region)

  if col >= M.char_count(line) then
    return ""
  end

  return vim.fn.strcharpart(line, col, 1)
end

function M.set_char(buf, row, col, value, region)
  if region and row < region.top_row then
    return
  end

  M.ensure_col(buf, row, col, region)

  local line =
    M.get_line(buf, row, region)

  local before =
    vim.fn.strcharpart(
      line,
      0,
      col
    )

  local after =
    vim.fn.strcharpart(
      line,
      col + 1
    )

  M.set_line(
    buf,
    row,
    before .. value .. after,
    region
  )
end

---------------------------------------------------------------------
-- Cursor helpers
---------------------------------------------------------------------

function M.current_position(region)
  local cursor =
    vim.api.nvim_win_get_cursor(0)

  local row =
    cursor[1] - 1

  local byte_col =
    cursor[2]

  local line =
    vim.api.nvim_get_current_line()

  -- Neovim cursor columns are byte-based.
  -- Our drawing system works with character positions.
  local prefix =
    line:sub(1, byte_col)

  local col =
    vim.fn.strchars(prefix)

  if region then
    col = col - region.prefix_len

    if col < 0 then
      col = 0
    end
  end

  return row, col
end

function M.set_cursor(buf, row, col, region)
  M.ensure_col(buf, row, col, region)

  local line =
    M.get_line(buf, row)

  local effective_col =
    col + (region and region.prefix_len or 0)

  local char_len =
    M.char_count(line)

  local byte_col

  if effective_col <= char_len then
    local prefix =
      vim.fn.strcharpart(
        line,
        0,
        effective_col
      )

    byte_col = #prefix
  else
    byte_col =
      #line + (effective_col - char_len)
  end

  vim.api.nvim_win_set_cursor(
    0,
    {
      row + 1,
      byte_col,
    }
  )
end

---------------------------------------------------------------------
-- Movement
---------------------------------------------------------------------

function M.move_only(direction, region)
  local buf =
    vim.api.nvim_get_current_buf()

  local delta =
    M.directions[direction]

  local row, col =
    M.current_position(region)

  local target_row =
    row + delta.row

  local target_col =
    col + delta.col

  if target_row < 0 then
    target_row = 0
  end

  if target_col < 0 then
    target_col = 0
  end

  local effective_col =
    target_col
    + (region and region.prefix_len or 0)

  -- Pad the raw line so the cursor can reach the
  -- target column.  Bypass the region guard so this
  -- works on any line (code or comment).
  M.ensure_col(
    buf,
    target_row,
    effective_col
  )

  M.set_cursor(
    buf,
    target_row,
    target_col,
    region
  )
end

---------------------------------------------------------------------
-- Undo helper
---------------------------------------------------------------------

function M.undo_join()
  pcall(
    vim.cmd,
    "undojoin"
  )
end

return M
