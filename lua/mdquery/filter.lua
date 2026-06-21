-- mdquery filter (minimal, AND-only)
--
-- Query syntax (space-separated, all ANDed together):
--   #tag             tag match
--   @key(value)      meta exact match
--   key:value        meta substring match (case-insensitive)
--   checked:true     checkbox state
--   checked:false
--   bareWord         text substring search (case-insensitive)
--
-- OR / negation / comparison / relative-date are NOT handled (MVP).

local M = {}

local function lower(s)
  return (s or ""):lower()
end

-- Classify a single token into a condition table.
local function classify(tok)
  -- #tag
  local tag = tok:match("^#(.+)$")
  if tag then
    return { kind = "tag", tag = tag }
  end

  -- @key(value)
  local akey, aval = tok:match("^@([%w%.%-_]+)%((.*)%)$")
  if akey then
    return { kind = "meta_exact", key = akey, value = aval }
  end

  -- checked:true / checked:false
  local ckey, cval = tok:match("^([%w%.%-_]+):(.+)$")
  if ckey then
    if ckey == "checked" and (cval == "true" or cval == "false") then
      return { kind = "checked", value = (cval == "true") }
    end
    return { kind = "meta_sub", key = ckey, value = cval }
  end

  -- bare word
  return { kind = "text", text = tok }
end

-- Parse query string into a list of conditions.
function M.parse(query)
  local conds = {}
  for tok in (query or ""):gmatch("%S+") do
    table.insert(conds, classify(tok))
  end
  return conds
end

local function has_tag(item, tag)
  for _, t in ipairs(item.tags) do
    if t == tag then return true end
  end
  return false
end

local function match_one(item, c)
  if c.kind == "tag" then
    return has_tag(item, c.tag)
  elseif c.kind == "meta_exact" then
    return item.meta[c.key] == c.value
  elseif c.kind == "meta_sub" then
    local v = item.meta[c.key]
    if v == nil then return false end
    return lower(v):find(lower(c.value), 1, true) ~= nil
  elseif c.kind == "checked" then
    return item.checked == c.value
  elseif c.kind == "text" then
    return lower(item.text):find(lower(c.text), 1, true) ~= nil
  end
  return false
end

local function match_all(item, conds)
  for _, c in ipairs(conds) do
    if not match_one(item, c) then return false end
  end
  return true
end

-- Filter items by query string.
-- Returns: matched(list), matched_count, total_count
function M.filter(items, query)
  local conds = M.parse(query)
  local matched = {}
  -- Empty query matches everything.
  for _, item in ipairs(items) do
    if #conds == 0 or match_all(item, conds) then
      table.insert(matched, item)
    end
  end
  return matched, #matched, #items
end

return M
