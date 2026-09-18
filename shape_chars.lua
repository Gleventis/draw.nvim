local M = {}

local chars = {}

function M.register(values)
  for _, char in ipairs(values) do
    chars[char] = true
  end
end

function M.is(char)
  return chars[char] == true
end

return M
