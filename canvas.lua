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

function M.ensure_row(buf, row, region)
  local line_count =
    vim.api.nvim_buf_line_count(buf)

  while row >= line_count do
    local new_line = region and region.prefix or ""

    vim.api.nvim_buf_set_lines(
      buf,
      line_count,
      line_count,
      false,
      { new_line }
    )

    line_count = line_count + 1
  end

  if region and row > region.bottom_row then
    region.bottom_row = row
  end
end

function M.char_count(line)
  return vim.fn.strchars(line)
end

function M.ensure_col(buf, row, col, region)
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
  end

  return row, col
end

function M.set_cursor(buf, row, col, region)
  M.ensure_col(buf, row, col, region)

  local line =
    M.get_line(buf, row)

  local effective_col =
    col + (region and region.prefix_len or 0)

  local prefix =
    vim.fn.strcharpart(
      line,
      0,
      effective_col
    )

  local byte_col =
    #prefix

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

function M.move_only(direction)
  local buf =
    vim.api.nvim_get_current_buf()

  local delta =
    M.directions[direction]

  local row, col =
    M.current_position()

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

  M.set_cursor(
    buf,
    target_row,
    target_col
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
