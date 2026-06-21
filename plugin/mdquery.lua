-- plugin/mdquery.lua — command registration
if vim.g.loaded_mdquery then
  return
end
vim.g.loaded_mdquery = true

vim.api.nvim_create_user_command("MdQuery", function(opts)
  require("mdquery").open(opts.args ~= "" and opts.args or nil)
end, {
  nargs = "?",
  desc = "Open MdQuery filter for the current Markdown buffer",
})
