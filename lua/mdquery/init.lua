-- mdquery: filter Markdown list-item metadata with a query language.
local config = require("mdquery.config")
local ui = require("mdquery.ui")

local M = {}

function M.setup(opts)
  config.setup(opts)
end

-- :MdQuery [query]
function M.open(query)
  ui.open(query)
end

return M
