-- mdquery parser (minimal, flat)
--
-- Scans a list of lines and extracts list-item metadata:
--   #tag
--   @key(value)
--   key:value     (URL schemes excluded)
--   [ ] / [x]     checkbox state
-- Headings, HTML-comment metadata and tree nesting are NOT handled (MVP).
--
-- Each returned item:
--   { text, raw, tags = {}, meta = {}, checked = bool|nil, line = 1-based }

local M = {}

local URL_SCHEMES = {
  http = true, https = true, ftp = true, ftps = true, mailto = true,
  tel = true, ssh = true, git = true, file = true, data = true,
  javascript = true, ws = true, wss = true,
}

-- Returns content after the list marker, or nil if the line is not a list item.
-- Parses list marker and returns indent size and content after marker.
-- Returns nil if it's not a list item.
local function parse_list_item(line)
  -- bullets: -, *, +
  local indent, rest = line:match("^(%s*)[%-%*%+]%s+(.*)$")
  if indent then
    return #indent, rest
  end
  -- ordered: 1. / 1)
  indent, rest = line:match("^(%s*)%d+[%.%)]%s+(.*)$")
  if indent then
    return #indent, rest
  end
  return nil
end

-- Parses heading and returns heading level (depth) and content.
-- Returns nil if it's not a heading of level 2-4.
local function parse_heading(line)
  local hashes, rest = line:match("^%s*(#+)%s+(.*)$")
  if hashes then
    local depth = #hashes
    if depth >= 2 and depth <= 4 then
      return depth, rest
    end
  end
  return nil
end

-- Extracts checkbox state. Returns checked(bool|nil), text-without-checkbox.
local function extract_checkbox(content)
  local mark, rest = content:match("^%[(.)%]%s+(.*)$")
  if not mark then
    -- also accept "[x]" with no following space before end
    mark, rest = content:match("^%[(.)%]%s*(.*)$")
  end
  if mark == nil then return nil, content end
  if mark == "x" or mark == "X" then return true, rest end
  if mark == " " then return false, rest end
  return nil, content
end

-- Extract metadata from text. Returns tags(list), meta(table), clean text.
local function extract_metadata(text)
  local tags = {}
  local meta = {}

  -- 1) Inline annotations: @key(value)
  text = text:gsub("@([%w%.%-_]+)%(([^)]*)%)", function(key, value)
    meta[key] = value
    return ""
  end)

  -- 2) Tags: #tag (preceded by start or whitespace)
  text = (" " .. text):gsub("(%s)#([^%s#]+)", function(_, tag)
    table.insert(tags, tag)
    return " "
  end)
  text = text:gsub("^%s", "")

  -- 3) Colon KV: key:value (skip URL schemes)
  text = (" " .. text):gsub("(%s)([%a_][%w%.%-_]*):(%S+)", function(sp, key, value)
    if URL_SCHEMES[key:lower()] then
      return sp .. key .. ":" .. value
    end
    meta[key] = value
    return sp
  end)
  text = text:gsub("^%s", "")

  -- 4) Collapse whitespace
  local clean = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return tags, meta, clean
end

-- Parse an array of lines (1-based line numbers).
-- Builds a nested tree structure based on heading levels and list item indentation.
function M.parse(lines)
  local root_items = {}
  local stack = {}

  for i, line in ipairs(lines) do
    local item = nil

    -- 1. Try list item
    local indent, list_content = parse_list_item(line)
    if list_content then
      local checked, rest = extract_checkbox(list_content)
      local tags, meta, clean = extract_metadata(rest)
      item = {
        type = "list",
        text = clean,
        raw = line,
        tags = tags,
        meta = meta,
        checked = checked,
        line = i,
        indent = indent,
        children = {},
      }
    else
      -- 2. Try heading
      local depth, heading_content = parse_heading(line)
      if heading_content then
        local tags, meta, clean = extract_metadata(heading_content)
        item = {
          type = "heading",
          text = clean,
          raw = line,
          tags = tags,
          meta = meta,
          checked = nil,
          line = i,
          heading_level = depth,
          children = {},
        }
      end
    end

    if item then
      if item.type == "heading" then
        -- Pop stack while top is list OR (top is heading and top.heading_level >= item.heading_level)
        while #stack > 0 do
          local top = stack[#stack]
          if top.type == "list" or (top.type == "heading" and top.heading_level >= item.heading_level) then
            table.remove(stack)
          else
            break
          end
        end
      elseif item.type == "list" then
        -- Pop stack while top is list and top.indent >= item.indent
        while #stack > 0 do
          local top = stack[#stack]
          if top.type == "list" and top.indent >= item.indent then
            table.remove(stack)
          else
            break
          end
        end
      end

      -- Link to parent
      if #stack > 0 then
        local parent = stack[#stack]
        table.insert(parent.children, item)
      else
        table.insert(root_items, item)
      end

      -- Push to stack
      table.insert(stack, item)
    end
  end

  -- Clean up empty children tables to keep it neat
  local function prune(items)
    for _, it in ipairs(items) do
      if #it.children == 0 then
        it.children = nil
      else
        prune(it.children)
      end
    end
  end
  prune(root_items)

  return root_items
end

return M
