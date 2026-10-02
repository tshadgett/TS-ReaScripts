-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Search.lua -- forgiving plugin search, ranked.

  Used by the add-a-plugin picker (TS_CV_Browser) and by the web
  companion's picker (TS_ChannelView_Web.lua), so the two find the same
  things in the same order. Nothing in here draws.

  Every term you type has to find a home in the plugin's full name
  ("VST3: Pro-Q 4 (FabFilter)" -- format, name and vendor), but there are
  several ways in, best first:

    word start   "fab", "sat"         -> FabFilter Saturn
    anywhere     "proq", "q4"         punctuation and spaces don't count,
                                      so "proq" is Pro-Q and "ssleq" SSL EQ
    in order     "pq4", "fbsat"       the letters, in order, close together
    one slip     "saturm", "compresor", "satrun"
                                      a wrong, missing, extra or swapped
                                      letter (two in a long word)

  A better way in scores higher, a name that starts with what you typed
  higher still, and a plugin you've used recently gets a nudge -- so the
  likely one is at the top for Enter to take.
--]]

local S = {}

local function alnum(s) return (s:lower():gsub("[^%w]", "")) end

-- The searchable form of an entry ({ name, short }), worked out once and
-- kept on the entry.
function S.key(e)
  if e.sk then return e.sk end
  local lower = (e.name or ""):lower()
  local words, starts, at = {}, {}, 1
  for w in lower:gmatch("%w+") do
    words[#words + 1] = w
    starts[at] = true            -- where each word begins in `flat`
    at = at + #w
  end
  local sk = {
    flat  = alnum(lower),
    words = words,
    starts = starts,
    short = alnum(e.short or e.name or ""),
    first = ((e.short or ""):lower():match("%w+")) or "",
    len   = #(e.short or e.name or ""),
  }
  e.sk = sk
  return sk
end

-- The query as terms: split on spaces, each one letters and digits only.
function S.terms(q)
  local out = {}
  for t in (q or ""):gmatch("%S+") do
    local a = alnum(t)
    if a ~= "" then out[#out + 1] = a end
  end
  return out
end

-- Optimal string alignment distance (Levenshtein plus swapped neighbours),
-- giving up as soon as it's sure to exceed `cap`.
local function osa(a, b, cap)
  local la, lb = #a, #b
  if math.abs(la - lb) > cap then return cap + 1 end
  local prev2, prev, cur = {}, {}, {}
  for j = 0, lb do prev[j] = j end
  for i = 1, la do
    cur = { [0] = i }
    local best = i
    local ai = a:byte(i)
    for j = 1, lb do
      local bj = b:byte(j)
      local cost = (ai == bj) and 0 or 1
      local v = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
      if i > 1 and j > 1 and ai == b:byte(j - 1) and a:byte(i - 1) == bj then
        v = math.min(v, prev2[j - 2] + 1)
      end
      cur[j] = v
      if v < best then best = v end
    end
    if best > cap then return cap + 1 end
    prev2, prev = prev, cur
  end
  return prev[lb]
end

-- The letters of t, in order, in s, starting at the start of a word: the
-- tightest span they fit in, or nil.
local function subseq_span(t, s, starts)
  local best = nil
  local first = t:sub(1, 1)
  local start = 1
  while true do
    local p = s:find(first, start, true)
    if not p then break end
    if not starts[p] then start = p + 1; goto continue end
    local q = p
    local ok = true
    for k = 2, #t do
      q = s:find(t:sub(k, k), q + 1, true)
      if not q then ok = false break end
    end
    if not ok then break end
    do
      local span = q - p + 1
      if not best or span < best then best = span end
    end
    start = p + 1
    ::continue::
  end
  return best
end

-- How well one term fits, or nil.
local function term_score(sk, t)
  local n = #t
  for _, w in ipairs(sk.words) do
    if w:sub(1, n) == t then
      return (w == t) and 120 or 100
    end
  end
  if sk.flat:find(t, 1, true) then return 75 end
  if n >= 2 then
    local span = subseq_span(t, sk.flat, sk.starts)
    if span and span <= n * 2 + 1 then return 45 - math.min(20, span - n) end
  end
  -- A slip: against the start of a word, about as long as the term. Not
  -- for short terms, where one letter either way matches half the list;
  -- and an extra letter (matching a shorter stretch) only from six up.
  if n >= 5 then
    local cap = (n >= 8) and 2 or 1
    for _, w in ipairs(sk.words) do
      local lo = (n >= 6) and (n - cap) or n
      for L = math.max(1, lo), math.min(#w, n + cap) do
        if osa(t, w:sub(1, L), cap) <= cap then return 30 end
      end
    end
  end
  return nil
end

-- The entry's score for these terms, or nil when one of them has no home.
-- `bonus` is added on top (recently used, say).
function S.score(e, terms, bonus)
  local sk = S.key(e)
  local total = 0
  for _, t in ipairs(terms) do
    local s = term_score(sk, t)
    if not s then return nil end
    total = total + s
  end
  if #terms > 0 then
    local joined = table.concat(terms)
    if sk.short:sub(1, #joined) == joined then total = total + 40
    elseif sk.first ~= "" and sk.first:sub(1, #terms[1]) == terms[1] then total = total + 20 end
  end
  return total + (bonus or 0) - sk.len * 0.25
end

-- The entries of `list` that match `q`, best first. `keep(e)` filters
-- (nil for all), `bonus(e)` nudges (nil for none), `limit` caps the result.
-- Ties keep the list's own order (alphabetical, as the pickers build it).
function S.search(list, q, keep, bonus, limit)
  local terms = S.terms(q)
  local hits = {}
  for i, e in ipairs(list) do
    if not keep or keep(e) then
      local s = S.score(e, terms, bonus and bonus(e) or 0)
      if s then hits[#hits + 1] = { e = e, s = s, i = i } end
    end
  end
  table.sort(hits, function(a, b)
    if a.s ~= b.s then return a.s > b.s end
    return a.i < b.i
  end)
  local out = {}
  for k = 1, math.min(#hits, limit or #hits) do out[k] = hits[k].e end
  return out
end

return S
