-- mdquery UI
--
-- Layout:
--   * the source markdown buffer stays in its window (jump target)
--   * a vertical-split scratch buffer on the right shows the filtered List
--   * a small floating prompt buffer captures the query, with incremental
--     (debounced) updates on every keystroke.

local config = require("mdquery.config")
local parser = require("mdquery.parser")
local filter = require("mdquery.filter")

local M = {}

local ns = vim.api.nvim_create_namespace("mdquery")
vim.api.nvim_set_hl(0, "MdQueryAncestor", { link = "LineNr", default = true })

-- Active session state.
local S = nil

local function reset_state()
  S = {
    src_win = nil, -- window showing the source markdown
    src_buf = nil, -- source markdown buffer
    res_win = nil, -- result split window
    res_buf = nil, -- result scratch buffer
    prompt_win = nil, -- floating prompt window
    prompt_buf = nil, -- floating prompt buffer
    items = {}, -- parsed items from src_buf
    row_to_line = {}, -- result display row (1-based) -> source line
    query = "",
    debounce_timer = nil,
  }
end

local function is_valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

-- Render the filtered list into the result buffer.
local function render()
  if not (S and is_valid_win(S.res_win) and vim.api.nvim_buf_is_valid(S.res_buf)) then
    return
  end
  local matched, mcount, total = filter.filter(S.items, S.query)

  local lines = {}
  S.row_to_line = {}
  local ancestor_rows = {}

  -- Header (3 lines).
  local q = S.query ~= "" and S.query or "(all)"
  table.insert(lines, "query " .. q)
  table.insert(lines, string.format("matched %d / %d", mcount, total))
  table.insert(lines, string.rep("-", math.max(10, config.options.result_width - 2)))

  local header_rows = #lines

  -- Recursive render helper for UI tree.
  local function render_tree(tree_items, level)
    for _, item in ipairs(tree_items) do
      local parts = {}
      local indent_prefix = string.rep("  ", level)

      -- checkbox
      if item.checked == true then
        table.insert(parts, "[x]")
      elseif item.checked == false then
        table.insert(parts, "[ ]")
      end

      -- Display text
      local item_text = item.text ~= "" and item.text or "(empty)"
      table.insert(parts, item_text)

      for _, t in ipairs(item.tags) do
        table.insert(parts, "#" .. t)
      end
      for k, v in pairs(item.meta) do
        table.insert(parts, "@" .. k .. ":" .. v)
      end

      local display_text = table.concat(parts, " ")
      if item.type == "heading" then
        local hashes = string.rep("#", item.heading_level)
        display_text = hashes .. " " .. display_text
      end

      local row_text = indent_prefix .. display_text .. "  :" .. item.line
      table.insert(lines, row_text)

      local current_row = #lines
      S.row_to_line[current_row] = item.line

      if item.is_ancestor then
        table.insert(ancestor_rows, current_row)
      end

      if item.children then
        render_tree(item.children, level + 1)
      end
    end
  end

  render_tree(matched, 0)

  if mcount == 0 then
    table.insert(lines, "")
    table.insert(lines, "  (no matches)")
  end

  vim.bo[S.res_buf].modifiable = true
  vim.api.nvim_buf_set_lines(S.res_buf, 0, -1, false, lines)
  vim.bo[S.res_buf].modifiable = false

  -- Highlight header lines.
  vim.api.nvim_buf_clear_namespace(S.res_buf, ns, 0, -1)
  for i = 0, header_rows - 1 do
    vim.api.nvim_buf_add_highlight(S.res_buf, ns, "Title", i, 0, -1)
  end

  -- Highlight ancestor rows (MdQueryAncestor group).
  for _, row_idx in ipairs(ancestor_rows) do
    vim.api.nvim_buf_add_highlight(S.res_buf, ns, "MdQueryAncestor", row_idx - 1, 0, -1)
  end

  S.first_data_row = header_rows + 1
end

-- Place the cursor on the first result row (if any).
local function cursor_to_first_result()
  if not (S and is_valid_win(S.res_win)) then return end
  local row = S.first_data_row or 1
  if S.row_to_line[row] then
    pcall(vim.api.nvim_win_set_cursor, S.res_win, { row, 0 })
  end
end

-- Jump from a result row to the source line.
local function jump()
  if not S then return end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = S.row_to_line[row]
  if not line then return end
  if not (is_valid_win(S.src_win) and vim.api.nvim_buf_is_valid(S.src_buf)) then
    return
  end
  vim.api.nvim_set_current_win(S.src_win)
  vim.api.nvim_win_set_cursor(S.src_win, { line, 0 })
  vim.cmd("normal! zz")
end

local function close_all()
  if not S then return end
  if S.debounce_timer then
    S.debounce_timer:stop()
    S.debounce_timer:close()
    S.debounce_timer = nil
  end
  if is_valid_win(S.prompt_win) then
    vim.api.nvim_win_close(S.prompt_win, true)
  end
  if is_valid_win(S.res_win) then
    vim.api.nvim_win_close(S.res_win, true)
  end
  S = nil
end

-- Debounced incremental update from the prompt buffer contents.
local function schedule_update()
  if not S then return end
  if S.debounce_timer then
    S.debounce_timer:stop()
  else
    S.debounce_timer = vim.loop.new_timer()
  end
  local delay = config.options.debounce_ms
  S.debounce_timer:start(delay, 0, vim.schedule_wrap(function()
    if not (S and vim.api.nvim_buf_is_valid(S.prompt_buf)) then return end
    local txt = vim.api.nvim_buf_get_lines(S.prompt_buf, 0, 1, false)[1] or ""
    local prefix = vim.fn.prompt_getprompt(S.prompt_buf)
    if prefix ~= "" and txt:sub(1, #prefix) == prefix then
      txt = txt:sub(#prefix + 1)
    end
    S.query = txt
    render()
  end))
end

local function create_result_split()
  vim.cmd("botright vsplit")
  S.res_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(S.res_win, config.options.result_width)
  S.res_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(S.res_win, S.res_buf)

  vim.bo[S.res_buf].buftype = "nofile"
  vim.bo[S.res_buf].bufhidden = "wipe"
  vim.bo[S.res_buf].swapfile = false
  vim.bo[S.res_buf].modifiable = false
  vim.bo[S.res_buf].filetype = "mdquery-result"
  vim.wo[S.res_win].number = false
  vim.wo[S.res_win].relativenumber = false
  vim.wo[S.res_win].wrap = false
  vim.wo[S.res_win].cursorline = true

  -- Result buffer keymaps.
  local opts = { buffer = S.res_buf, nowait = true, silent = true }
  vim.keymap.set("n", "<CR>", jump, opts)
  vim.keymap.set("n", "q", close_all, opts)
  vim.keymap.set("n", "i", function() M.focus_prompt() end, opts)
end

local function create_prompt()
  S.prompt_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[S.prompt_buf].buftype = "prompt"
  vim.bo[S.prompt_buf].bufhidden = "wipe"
  vim.fn.prompt_setprompt(S.prompt_buf, "› ")

  local width = math.min(60, vim.o.columns - 4)
  S.prompt_win = vim.api.nvim_open_win(S.prompt_buf, true, {
    relative = "editor",
    anchor = "NW",
    row = 1,
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = 1,
    style = "minimal",
    border = "rounded",
    title = " MdQuery ",
    title_pos = "center",
  })
  vim.wo[S.prompt_win].wrap = false

  -- Incremental update on every change.
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = S.prompt_buf,
    callback = schedule_update,
  })

  -- Esc (insert or normal) closes the prompt only, keeping the results,
  -- and moves focus to the result window.
  local function close_prompt()
    vim.cmd("stopinsert")
    if is_valid_win(S.prompt_win) then
      vim.api.nvim_win_close(S.prompt_win, true)
      S.prompt_win = nil
    end
    if is_valid_win(S.res_win) then
      vim.api.nvim_set_current_win(S.res_win)
      cursor_to_first_result()
    end
  end

  -- Enter confirms, closes the prompt, and moves focus to the results.
  vim.fn.prompt_setcallback(S.prompt_buf, function(text)
    -- strip prompt prefix if present
    local prefix = vim.fn.prompt_getprompt(S.prompt_buf)
    if prefix ~= "" and text:sub(1, #prefix) == prefix then
      text = text:sub(#prefix + 1)
    end
    S.query = text
    render()
    close_prompt()
  end)

  local opts = { buffer = S.prompt_buf, nowait = true, silent = true }
  vim.keymap.set({ "n", "i" }, "<Esc>", close_prompt, opts)

  vim.cmd("startinsert")
end

-- Re-open / focus the prompt for an existing session.
function M.focus_prompt()
  if not S then return end
  if is_valid_win(S.prompt_win) then
    vim.api.nvim_set_current_win(S.prompt_win)
    vim.cmd("startinsert!")
    return
  end
  create_prompt()
  -- Restore previous query text (prompt line must include the prompt prefix).
  if S.query ~= "" then
    local prefix = vim.fn.prompt_getprompt(S.prompt_buf)
    vim.api.nvim_buf_set_lines(S.prompt_buf, 0, -1, false, { prefix .. S.query })
    vim.cmd("startinsert!")
  end
end

-- Entry point: open MdQuery for the current buffer.
function M.open(initial_query)
  -- If a session is already open, just focus the prompt.
  if S and is_valid_win(S.res_win) then
    M.focus_prompt()
    return
  end

  reset_state()
  S.src_win = vim.api.nvim_get_current_win()
  S.src_buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(S.src_buf, 0, -1, false)
  S.items = parser.parse(lines)
  S.query = initial_query or ""

  create_result_split()
  -- Return focus to source before opening the prompt so prompt anchors over editor.
  render()
  create_prompt()
  if S.query ~= "" then
    local prefix = vim.fn.prompt_getprompt(S.prompt_buf)
    vim.api.nvim_buf_set_lines(S.prompt_buf, 0, -1, false, { prefix .. S.query })
    vim.cmd("startinsert!")
    render()
  end
end

return M
