-- mdquery filter (supports AND, OR, negation, comparisons, relative dates)
--
-- Query syntax:
--   #tag             tag match
--   !#tag            negated tag
--   @key(value)      meta exact match
--   !@key(value)     negated meta exact
--   key:value        meta substring match (case-insensitive)
--   !key:value       negated meta substring
--   key>value        comparison (numeric or lexicographic)
--   key<value        comparison
--   checked:true     checkbox state
--   checked:false
--   bareWord         text substring search (case-insensitive)
--   !bareWord        negated text search
--
--   (space)          AND
--   OR               OR (surrounded by spaces)

local M = {}

local function lower(s)
  return (s or ""):lower()
end

-- Match today, today+N, today-N (case-insensitive) and convert to YYYY-MM-DD
local function resolve_relative_date(value)
  local val_lower = value:lower()
  local offset = val_lower:match("^today([+-]%d+)$")
  if val_lower == "today" or offset then
    local diff = 0
    if offset then
      diff = tonumber(offset)
    end
    local target_time = os.time() + diff * 24 * 3600
    return os.date("%Y-%m-%d", target_time)
  end
  return value
end

-- Numerical or lexicographic comparison
local function smart_compare(a, b, op)
  local na = tonumber(a)
  local nb = tonumber(b)
  if na and nb then
    if op == ">" then return na > nb end
    if op == "<" then return na < nb end
  end
  if op == ">" then return a > b end
  if op == "<" then return a < b end
  return false
end

-- Classify a single token into a condition table.
local function classify(tok)
  local neg = false
  if tok:sub(1, 1) == "!" and #tok > 1 then
    neg = true
    tok = tok:sub(2)
  end

  -- #tag
  local tag = tok:match("^#(.+)$")
  if tag then
    return { kind = "tag", tag = tag, neg = neg }
  end

  -- @key(value)
  local akey, aval = tok:match("^@([%w%.%-_]+)%((.*)%)$")
  if akey then
    return { kind = "meta_exact", key = akey, value = aval, neg = neg }
  end

  -- key>value  key<value
  local cmp_key, op, cmp_val = tok:match("^([%w%.%-_]+)([><])(.+)$")
  if cmp_key then
    return { kind = "cmp", key = cmp_key, op = op, value = cmp_val }
  end

  -- checked:true / checked:false / key:value
  local ckey, cval = tok:match("^([%w%.%-_]+):(.+)$")
  if ckey then
    if ckey == "checked" and (cval == "true" or cval == "false") then
      return { kind = "checked", value = (cval == "true"), neg = neg }
    end
    return { kind = "meta_sub", key = ckey, value = cval, neg = neg }
  end

  -- bare word
  return { kind = "text", text = tok, neg = neg }
end

-- Helper to split query by ' OR ' (case-sensitive, surrounded by whitespace)
local function split_by_or(str)
  local result = {}
  local start = 1
  while true do
    local s, e = str:find("%s+OR%s+", start)
    if not s then
      table.insert(result, str:sub(start))
      break
    end
    table.insert(result, str:sub(start, s - 1))
    start = e + 1
  end
  return result
end

-- Parse query string into OR-of-ANDs condition groups.
-- Returns: Condition[][]
function M.parse(query)
  if not query or query:match("^%s*$") then
    return {}
  end

  local or_groups = {}
  for _, group_str in ipairs(split_by_or(query)) do
    local conds = {}
    for tok in group_str:gmatch("%S+") do
      table.insert(conds, classify(tok))
    end
    if #conds > 0 then
      table.insert(or_groups, conds)
    end
  end
  return or_groups
end

local function has_tag(item, tag)
  for _, t in ipairs(item.tags) do
    if t:lower() == tag:lower() then return true end
  end
  return false
end

-- Evaluate a single condition against an item.
local function match_one(item, c)
  local matched = false
  if c.kind == "tag" then
    matched = has_tag(item, c.tag)
  elseif c.kind == "meta_exact" then
    local val = item.meta[c.key]
    if val ~= nil then
      matched = resolve_relative_date(val) == resolve_relative_date(c.value)
    end
  elseif c.kind == "meta_sub" then
    local v = item.meta[c.key]
    if v ~= nil then
      local resolved_val = resolve_relative_date(v)
      local resolved_target = resolve_relative_date(c.value)
      matched = lower(resolved_val):find(lower(resolved_target), 1, true) ~= nil
    end
  elseif c.kind == "checked" then
    matched = item.checked == c.value
  elseif c.kind == "text" then
    matched = lower(item.text):find(lower(c.text), 1, true) ~= nil
  elseif c.kind == "cmp" then
    local val = item.meta[c.key]
    if val ~= nil then
      matched = smart_compare(resolve_relative_date(val), resolve_relative_date(c.value), c.op)
    end
  end

  if c.neg then
    return not matched
  else
    return matched
  end
end

-- Evaluate a single AND group with positive propagation.
-- Returns: matches(bool), is_positive_propagation_source(bool)
local function eval_and_group(item, and_group, parent_positive_matched)
  local positives = {}
  local negatives = {}
  for _, c in ipairs(and_group) do
    if c.neg then
      table.insert(negatives, c)
    else
      table.insert(positives, c)
    end
  end

  -- 1) Negatives MUST always pass
  for _, c in ipairs(negatives) do
    if not match_one(item, c) then
      return false, false
    end
  end

  -- 2) Positives pass if parent matched positively, OR if all positives match
  local positive_matched = false
  if parent_positive_matched then
    positive_matched = true
  else
    local all_pos_passed = true
    for _, c in ipairs(positives) do
      if not match_one(item, c) then
        all_pos_passed = false
        break
      end
    end
    if all_pos_passed then
      positive_matched = true
    end
  end

  -- Propagation source only if there actually are positive conditions that matched
  local is_propagation_source = positive_matched and (#positives > 0)

  return positive_matched, is_propagation_source
end

-- Evaluate if item matches the query (OR of AND groups).
-- Returns: matches(bool), is_positive_propagation_source(bool)
local function eval_query(item, or_groups, parent_positive_matched)
  if #or_groups == 0 then return true, false end

  local any_match = false
  local any_prop = false
  for _, and_group in ipairs(or_groups) do
    local matched, prop = eval_and_group(item, and_group, parent_positive_matched)
    if matched then
      any_match = true
      if prop then
        any_prop = true
      end
    end
  end
  return any_match, any_prop
end

-- Helper to count all items in a tree (including nested children)
local function count_items(items)
  local n = 0
  for _, it in ipairs(items) do
    n = n + 1
    if it.children then
      n = n + count_items(it.children)
    end
  end
  return n
end

-- Shallow copy helper
local function clone_item(item)
  return {
    type = item.type,
    text = item.text,
    raw = item.raw,
    tags = item.tags,
    meta = item.meta,
    checked = item.checked,
    line = item.line,
    heading_level = item.heading_level,
    indent = item.indent,
    children = item.children,
  }
end

-- Recursive tree filter with positive propagation.
-- Returns: matched_items, matched_count, ancestor_lines
local function filter_tree(items, or_groups, parent_positive_matched)
  local result = {}
  local matched_count = 0
  local ancestor_lines = {}

  for _, item in ipairs(items) do
    local self_matches, child_prop = eval_query(item, or_groups, parent_positive_matched)

    if self_matches then
      local copy = clone_item(item)
      
      -- Filter children, propagating our positive match status.
      -- Children violating negative rules will still be filtered out.
      local child_result, child_count, child_anc = {}, 0, {}
      if item.children then
        child_result, child_count, child_anc = filter_tree(item.children, or_groups, child_prop)
      end

      if item.children and #child_result > 0 then
        copy.children = child_result
      else
        copy.children = nil
      end

      table.insert(result, copy)
      matched_count = matched_count + 1 + child_count
      for l, _ in pairs(child_anc) do
        ancestor_lines[l] = true
      end
    elseif item.children then
      -- If parent doesn't match, evaluate children with parent_positive_matched = false
      local child_result, child_count, child_anc = filter_tree(item.children, or_groups, false)
      if #child_result > 0 then
        local copy = clone_item(item)
        copy.children = child_result
        copy.is_ancestor = true -- Mark as context container
        table.insert(result, copy)
        matched_count = matched_count + child_count
        ancestor_lines[item.line] = true
        for l, _ in pairs(child_anc) do
          ancestor_lines[l] = true
        end
      end
    end
  end

  return result, matched_count, ancestor_lines
end

-- Filter items by query string.
-- Returns: matched(list), matched_count, total_count
function M.filter(items, query)
  local or_groups = M.parse(query)
  local total_count = count_items(items)
  local matched_items, matched_count, _ = filter_tree(items, or_groups, false)
  return matched_items, matched_count, total_count
end

return M
