-- mdquery configuration
local M = {}

M.defaults = {
  -- Debounce time (ms) for incremental updates while typing the query.
  debounce_ms = 200,
  -- Width of the result split window (columns).
  result_width = 60,
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M
