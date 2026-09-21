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
-- Detect the full comment prefix on a given buffer row
--
-- The prefix is: leading whitespace + comment marker + optional space.
-- Example: "    # " for an indented Python comment.
--
-- Returns:
--   prefix string, prefix_len (in characters)
--   or nil if the line does not start with the comment pattern
---------------------------------------------------------------------

function M.detect_prefix(buf, row, marker)
  local lines =
    vim.api.nvim_buf_get_lines(
      buf,
      row,
      row + 1,
      false
    )

  local line =
    lines[1] or ""

  local escaped =
    vim.pesc(marker)

  local prefix =
    line:match(
      "^(%s*" .. escaped .. "%s?)"
    )

  if prefix == nil then
    return nil
  end

  return prefix, vim.fn.strchars(prefix)
end

---------------------------------------------------------------------
-- Detect contiguous block of lines sharing the same prefix
--
-- Scans upward and downward from row, stopping when a line does
-- not start with prefix.
--
-- Returns:
--   top_row, bottom_row  (0-indexed, inclusive)
---------------------------------------------------------------------

function M.detect_block(buf, row, prefix)
  local line_count =
    vim.api.nvim_buf_line_count(buf)

  local top_row    = row
  local bottom_row = row

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

    if line:sub(1, #prefix) ~= prefix then
      break
    end

    top_row = r
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

    if line:sub(1, #prefix) ~= prefix then
      break
    end

    bottom_row = r
    r = r + 1
  end

  return top_row, bottom_row
end

---------------------------------------------------------------------
-- Create a region from the current cursor position
--
-- Reads the file extension to find the comment marker, extracts the
-- full prefix from the cursor line, and scans the contiguous block.
--
-- Returns:
--   region table  { prefix, prefix_len, top_row, bottom_row }
--   or nil, error_message on failure
---------------------------------------------------------------------

function M.create(buf)
  local marker =
    M.get_marker()

  if marker == nil then
    local ext =
      vim.fn.expand("%:e")

    return nil,
      "unsupported filetype: " .. ext
  end

  local cursor =
    vim.api.nvim_win_get_cursor(0)

  local row =
    cursor[1] - 1

  local prefix, prefix_len =
    M.detect_prefix(
      buf,
      row,
      marker
    )

  if prefix == nil then
    return nil,
      "cursor is not inside a comment block"
  end

  local top_row, bottom_row =
    M.detect_block(
      buf,
      row,
      prefix
    )

  return {
    prefix     = prefix,
    prefix_len = prefix_len,
    top_row    = top_row,
    bottom_row = bottom_row,
  }
end

return M
