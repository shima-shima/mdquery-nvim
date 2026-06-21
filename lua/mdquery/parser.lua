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
local function strip_list_marker(line)
  -- bullets: -, *, +
  local rest = line:match("^%s*[%-%*%+]%s+(.*)$")
  if rest then return rest end
  -- ordered: 1. / 1)
  rest = line:match("^%s*%d+[%.%)]%s+(.*)$")
  return rest
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
function M.parse(lines)
  local items = {}
  for i, line in ipairs(lines) do
    local content = strip_list_marker(line)
    if content then
      local checked, rest = extract_checkbox(content)
      local tags, meta, clean = extract_metadata(rest)
      table.insert(items, {
        text = clean,
        raw = line,
        tags = tags,
        meta = meta,
        checked = checked,
        line = i,
      })
    end
  end
  return items
end

return M
