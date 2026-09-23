local M = {}

---------------------------------------------------------------------
-- Comment marker lookup table
--
-- Maps file extension to the line comment marker for that language.
---------------------------------------------------------------------

M.comment_markers = {
  yaml = "#",
  yml  = "#",
  py   = "#",
  go   = "//",
}

---------------------------------------------------------------------
-- Get comment marker for the current buffer's file extension
--
-- Returns:
--   marker string, or nil if the extension is unsupported
---------------------------------------------------------------------

function M.get_marker()
  local ext =
    vim.fn.expand("%:e")

  return M.comment_markers[ext]
end

---------------------------------------------------------------------
-- Detect leading whitespace from the nearest non-empty surrounding line
--
-- Scans upward from row first, then downward. Returns the leading
-- whitespace of the first non-empty line found, or "" if none exists.
---------------------------------------------------------------------

function M.detect_indent(buf, row)
  local line_count =
    vim.api.nvim_buf_line_count(buf)

  local r = row - 1

  while r >= 0 do
    local lines =
      vim.api.nvim_buf_get_lines(
        buf,
        r,
        r + 1,
        false
      )

    local line =
      lines[1] or ""

    if line:match("%S") then
      return line:match("^(%s*)") or ""
    end

    r = r - 1
  end

  r = row + 1

  while r < line_count do
    local lines =
      vim.api.nvim_buf_get_lines(
        buf,
        r,
        r + 1,
        false
      )

    local line =
      lines[1] or ""

    if line:match("%S") then
      return line:match("^(%s*)") or ""
    end

    r = r + 1
  end

  return ""
end

---------------------------------------------------------------------
-- Find the contiguous block of comment lines sharing the given prefix
--
-- Scans upward then downward from row, stopping at the first line
-- that does not start with prefix.
--
-- Returns:
--   top_row, bottom_row  (both inclusive, 0-based)
---------------------------------------------------------------------

function M.detect_block(buf, row, prefix)
  local line_count =
    vim.api.nvim_buf_line_count(buf)

  local top_row = row
  local r = row - 1

  while r >= 0 do
    local lines =
      vim.api.nvim_buf_get_lines(
        buf,
        r,
        r + 1,
        false
      )

    local line =
      lines[1] or ""

    if line:sub(1, #prefix) == prefix then
      top_row = r
      r = r - 1
    else
      break
    end
  end

  local bottom_row = row
  r = row + 1

  while r < line_count do
    local lines =
      vim.api.nvim_buf_get_lines(
        buf,
        r,
        r + 1,
        false
      )

    local line =
      lines[1] or ""

    if line:sub(1, #prefix) == prefix then
      bottom_row = r
      r = r + 1
    else
      break
    end
  end

  return top_row, bottom_row
end

---------------------------------------------------------------------
-- Create a region at the given buffer row
--
-- Determines the comment prefix from the file extension and
-- indentation, then:
--   - existing comment line: detects the surrounding block and returns
--     its boundaries for re-editing
--   - empty line: inherits indent from the nearest non-empty neighbour,
--     writes the prefix to that line
--   - non-empty non-comment line: inherits indent from the current
--     line itself, inserts a new prefixed line below it
--
-- Returns:
--   region table  { prefix, prefix_len, top_row, bottom_row, start_row }
--   or nil, error_message on failure
---------------------------------------------------------------------

function M.create(buf, row)
  local marker =
    M.get_marker()

  if marker == nil then
    local ext =
      vim.fn.expand("%:e")

    return nil,
      "unsupported filetype: " .. ext
  end

  local lines =
    vim.api.nvim_buf_get_lines(
      buf,
      row,
      row + 1,
      false
    )

  local line =
    lines[1] or ""

  -------------------------------------------------------------------
  -- Empty line: inherit indent from nearest non-empty neighbour.
  -- Non-empty line: use the current line's own leading whitespace
  -- so the inserted comment below matches its indentation level.
  -------------------------------------------------------------------

  local indent

  if line:match("^%s*$") then
    indent =
      M.detect_indent(buf, row)
  else
    indent =
      line:match("^(%s*)") or ""
  end

  local prefix =
    indent .. marker .. " "

  local prefix_len =
    vim.fn.strchars(prefix)

  -------------------------------------------------------------------
  -- Re-editing: cursor is already on a commented diagram line.
  -- Detect the full block and return its boundaries.
  -------------------------------------------------------------------

  if line:sub(1, #prefix) == prefix then
    local top_row, bottom_row =
      M.detect_block(buf, row, prefix)

    return {
      prefix     = prefix,
      prefix_len = prefix_len,
      top_row    = top_row,
      bottom_row = bottom_row,
      start_row  = row,
    }
  end

  local start_row

  if line:match("^%s*$") then
    vim.api.nvim_buf_set_lines(
      buf,
      row,
      row + 1,
      false,
      { prefix }
    )

    start_row = row
  else
    vim.api.nvim_buf_set_lines(
      buf,
      row + 1,
      row + 1,
      false,
      { prefix }
    )

    start_row = row + 1
  end

  return {
    prefix     = prefix,
    prefix_len = prefix_len,
    top_row    = start_row,
    bottom_row = start_row,
    start_row  = start_row,
  }
end

return M
