-- Use LuaRocks to load packages
ufy.loader.revert_package_searchers()

local debug = dofile("debug.lua")
local bidi = require("bidi")
local ucdn = require("ucdn")
local fonts = require("ufy.fonts")
local hb = require("harfbuzz")

local function upem_to_sp(v,metrics)
  return math.floor(v / metrics.units_per_em * metrics.size)
end

-- Convert a node list to a table for easier processing. Returns a table
-- containing entries for all nodes in the order they appear in the list. Each
-- entry contains the following fields:
--
-- * The node corresponding to the position in the table
--
-- * The character corresponding to the node
--
--   - Glyph nodes are stored as their corresponding character codepoints
--
--   - Glue nodes of subtype 13 (spaceskip) are stored as 0x20 whitespace character
--     (FIXME what about other types of space-like glue inserted when using \quad etc)
--
--    - All other nodes are stored as 0xFFFC (OBJECT REPLACEMENT CHARACTER)
--
--  * A script identifier for each node.
--
local function nodelist_to_table(head)
  -- Build text
  local nodetable = {}
  local last_font = nil
  for n in node.traverse(head) do
    local item = {}
    item.node = n
    table.insert(nodetable,item)
    if n.id == node.id("glyph") then -- regular char node
      item.char = n.char
      item.script = hb.unicode.script(item.char)
      item.font = n.font
      last_font = item.font
    elseif n.id == node.id("glue") and n.subtype == 13 then -- space skip
      item.char = 0x0020
      item.script = hb.unicode.script(item.char)
      item.font = last_font
    else
      item.char = 0xfffc
    end
  end

  return nodetable
end

-- FIXME use BiDi properties (via UCDN) to determine whether characters are paired
-- or not.
local paired_chars = {
  0x0028, 0x0029, -- ascii paired punctuation
  0x003c, 0x003e,
  0x005b, 0x005d,
  0x007b, 0x007d,
  0x00ab, 0x00bb, -- guillemets
  0x2018, 0x2019, -- general punctuation
  0x201c, 0x201d,
  0x2039, 0x203a,
  0x3008, 0x3009, -- chinese paired punctuation
  0x300a, 0x300b,
  0x300c, 0x300d,
  0x300e, 0x300f,
  0x3010, 0x3011,
  0x3014, 0x3015,
  0x3016, 0x3017,
  0x3018, 0x3019,
  0x301a, 0x301b
}

local function get_pair_index(char)
  local lower = 1
  local upper = #paired_chars

  while (lower <= upper) do
    local mid = math.floor((lower + upper) / 2)
    if char < paired_chars[mid] then
      upper = mid - 1
    elseif char > paired_chars[mid] then
      lower = mid + 1
    else
      return mid
    end
  end
  return 0
end

local function is_open(pair_index)
  return bit32.band(pair_index, 1) == 1 -- odd index is open
end

-- Resolve the script for each character in the node table.
--
-- If the character script is common or inherited it takes the script of the
-- character before it except paired characters which we try to make them use
-- the same script.
local function resolve_scripts(nodetable)
  local last_script_index = 0
  local last_set_index = 0
  local last_script_value = hb.Script.HB_SCRIPT_INVALID
  local stack = { top = 0 }

  for i,v in ipairs(nodetable) do
    if v.script == hb.Script.HB_SCRIPT_COMMON and last_script_index ~= 0 then
      local pair_index = get_pair_index(v.char)
      if pair_index > 0 then
        if is_open(pair_index) then -- paired character (open)
          v.script = last_script_value
          last_set_index = i
          stack.top = stack.top + 1
          stack[stack.top] = { script = v.script, pair_index = pair_index}
        else -- is a close paired character
          -- find matching opening (by getting the last odd index for current
          -- even index)
          local pi = pair_index - 1
          while stack.top > 0 and stack[stack.top].pair_index ~= pi do
            stack.top = stack.top - 1
          end

          if stack.top > 0 then
            v.script = stack[stack.top].script
            last_script_value = v.script
            last_set_index = i
          else
            v.script = last_script_value
            last_set_index = i
          end
        end
      else
        nodetable[i].script = last_script_value
        last_set_index = i
      end
    elseif v.script == hb.Script.HB_SCRIPT_INHERITED and last_script_index ~= 0 then
      v.script = last_script_value
      last_set_index = i
    else
      for j = last_set_index + 1, i do nodetable[j].script = v.script end
      last_script_value = v.script
      last_script_index = i
      last_set_index = i
    end
  end
end

local function reverse_runs(runs, start, len)
  for i = 1, math.floor(len/2) do
    local temp = runs[start + i - 1]
    runs[start + i - 1] = runs[start + len - i]
    runs[start + len - i] = temp
  end
end

-- Apply the Unicode BiDi algorithm, segment the nodes into runs, and reorder the runs.
--
-- Returns a table containing the runs after reordering.
--
local function bidi_reordered_runs(nodetable, base_dir)
  local codepoints = {}
  for _,v in ipairs(nodetable) do
    table.insert(codepoints, v.char)
  end
  local types = bidi.codepoints_to_types(codepoints)
  local pair_types = bidi.codepoints_to_pair_types(codepoints)
  local pair_values = bidi.codepoints_to_pair_values(codepoints)

  local para = bidi.Paragraph.new(types, pair_types, pair_values, base_dir)

  local linebreaks = { #codepoints + 1 }
  local levels = para:getLevels(linebreaks)

  -- FIXME handle embedded RLE, LRE, RLI, LRI and PDF characters at this point and remove them.

  if #levels == 0 then return {} end

  -- L1. Reset the embedding level of the following characters to the paragraph embedding level:
  -- …<snip>…
  --   4. Any sequence of whitespace characters …<snip>… at the end of the line.
  -- …<snip>…
  do
    local i = #levels
    while i > 0 and (types[i] == ucdn.UCDN_BIDI_CLASS_BN or types[i] == ucdn.UCDN_BIDI_CLASS_WS)  do
      levels[i] = base_dir
      i = i - 1
    end
  end

  local max_level = 0
  local min_odd_level = bidi.MAX_DEPTH + 2
  for i,l in ipairs(levels) do
    debug.log("idx: %d, level: %d", i, l)
    if l > max_level then max_level = l end
    if bit32.band(l, 1) ~= 0 and l < min_odd_level then min_odd_level = l end
  end

  debug.log("max_level: %d, min_odd_level: %d", max_level, min_odd_level)

  local runs = {}
  local run_start = 1
  local run_index = 1
  while run_start <= #levels do
    local run_end = run_start
    while run_end <= #levels and levels[run_start] == levels[run_end] do run_end = run_end + 1 end
    local run = {}
    run.pos = run_start
    run.level = levels[run_start]
    run.len = run_end - run_start
    runs[run_index] = run
    run_index = run_index + 1
    run_start = run_end
  end

  debug.log("No. of runs: %d", #runs)

  -- L2. From the highest level found in the text to the lowest odd level on
  -- each line, including intermediate levels not actually present in the text,
  -- reverse any contiguous sequence of characters that are at that level or
  -- higher.
  for l = max_level, min_odd_level, -1 do
    local i = #runs
    while i > 0 do
      if runs[i].level >= l then
        local e = i
        i = i - 1
        while i > 0 and runs[i].level >= l do i = i - 1 end
        reverse_runs(runs, i+1, e - i)
      end
      i = i - 1
    end
  end

  return runs
end

-- FIXME handle vertical directions as well.
local function hb_dir(_, level)
  local dir = hb.Direction.HB_DIRECTION_LTR

  if bit32.band(level, 1) ~= 0 then dir = hb.Direction.HB_DIRECTION_RTL end

  return dir
end

local function is_hb_font(fontid)
  return font.getfont(fontid).harfbuzz
end

local function shape_runs(runs, text)
  local run = runs
  while run ~= nil do
    debug.log("Shaping run. length: %d start at pos: %d", run.len, run.pos)
    if run.font ~= nil and is_hb_font(run.font) then -- Only process runs with a valid font.
      debug.log("Valid Harfbuzz shaping run.")
      run.buffer = hb.Buffer.new()
      run.buffer:add_codepoints(text, run.pos - 1, run.len) -- Zero indexed offset
      run.buffer:set_script(run.script)
      -- FIXME implement setting language as well
      run.buffer:set_direction(run.direction)

      -- FIXME have a fallback for native TeX fonts
      local metrics = font.getfont(run.font)
      local face = hb.Face.new(metrics.filename)
      local hb_font = hb.Font.new(face)

      run.buffer:set_cluster_level(hb.Buffer.HB_BUFFER_CLUSTER_LEVEL_CHARACTERS)
      -- FIXME implement support for features
      hb.shape(hb_font,run.buffer)
    end
    run = run.next
  end
end

local function nodetable_to_list(nodetable, runs, dir)
  debug.log("Constructing new nodelist…")
  local newhead, current
  local run = runs
  if dir == "TRT" then -- add a prev pointer to runs
    while run.next ~= nil do
      run.next.prev = run
      run = run.next
    end
  end
  while run ~= nil do
    if run.font == nil or not is_hb_font(run.font) then
      local start = run.pos
      local end_ = run.pos + run.len - 1
      local inc = 1
      if dir == 'TRT' and run.font ~= nil then
        start, end_ = end_,start
        inc = -1
      end

      debug.log("copying %d to %d as is", start, end_)
      -- Copy the nodes as-is
      for i = start, end_, inc do
        newhead, current = node.insert_after(newhead, current, nodetable[i].node)
      end
    else
      local metrics = font.getfont(run.font)
      -- Get the glyphs and append them to list
      if dir == 'TRT' then run.buffer:reverse() end
      local glyphs = run.buffer:get_glyph_infos_and_positions()
      debug.log("Run start: %d, Run length: %d, No. of glyphs: %d", run.pos, run.len, #glyphs)

      for _, v in ipairs(glyphs) do
        local n,k -- Node and (optional) Kerning
        local char = metrics.backmap[v.codepoint]
        debug.log("glyph idx: U+%04X, glyph cluster: %d", char, v.cluster + 1)
        if nodetable[v.cluster+1].char == 0x20 then
          assert(char == 0x20 or char == 0xa0, "Expected char to be 0x20 or 0xa0")
          n = node.new("glue")
          n.subtype = 13
          n.width = metrics.parameters.space
          n.stretch = metrics.parameters.space_stretch
          n.shrink = metrics.parameters.space_shrink
          newhead,current = node.insert_after(newhead, current, n)
        else
          -- Create glyph node
          n = node.new("glyph")
          n.font = run.font
          n.char = char
          n.subtype = 0

          -- Set offsets from Harfbuzz data
          n.yoffset = upem_to_sp(v.y_offset, metrics)
          n.xoffset = upem_to_sp(v.x_offset, metrics)
          if dir == 'TRT' then n.xoffset = n.xoffset * -1 end

          -- Adjust kerning if Harfbuzz’s x_advance does not match glyph width
          local x_advance = upem_to_sp(v.x_advance, metrics)
          debug.log("v.x_advance: %d, x_advance: %d, n.width: %d", v.x_advance, x_advance, n.width)
          if math.abs(x_advance - n.width) > 1 then -- needs kerning
            k = node.new("kern")
            k.subtype = 1
            k.kern = (x_advance - n.width)
          end

          -- Insert glyph node into new list,
          -- adjusting for direction and kerning.
          if k then
            if dir == 'TRT' then -- kerning goes before glyph
              k.next = n
              current.next = k
              current = n
            else -- kerning goes after glyph
              n.next = k
              current.next = n
              current = k
            end
          else -- no kerning
            newhead, current = node.insert_after(newhead,current,n)
          end
        end
      end
    end
    if dir == "TRT" then run = run.prev else run = run.next end
  end
  return newhead
end

local function layout_nodes(head)
  debug.log("Paragraph Direction: %s\n", head.dir)
  local base_dir
  if head.dir == "TRT" then
    base_dir = 1
  elseif head.dir == "TLT" then
    base_dir = 0
  else
    -- FIXME handle this better, and don’t throw an error.
    debug.log("Paragraph direction %s unsupported. Bailing!\n", head.dir)
    return head
  end

  -- Convert node list to table
  local nodetable = nodelist_to_table(head)

  debug.log("No. of nodes in table: %d", #nodetable)

  -- Resolve scripts
  resolve_scripts(nodetable)

  -- Apply BiDi algorithm and reorder Runs
  local bidi_runs = bidi_reordered_runs(nodetable, base_dir)
  debug.log("No. of bidi runs: %d", #bidi_runs)

  -- Break up runs further if required
  local runs
  local last
  for _, bidi_run in ipairs(bidi_runs) do
    local run = {}
    if last then
      last.next = run
    else
      runs = run
    end

    run.direction = hb_dir(base_dir, bidi_run.level)

    if hb.Direction.HB_DIRECTION_IS_BACKWARD(run.direction) then
      run.pos = bidi_run.pos + bidi_run.len - 1
      run.script = nodetable[run.pos].script
      run.font = nodetable[run.pos].font
      run.len = 0
      for j = bidi_run.len - 1, 0, -1 do
        if nodetable[run.pos].script ~= nodetable[bidi_run.pos + j].script or
           nodetable[run.pos].font   ~= nodetable[bidi_run.pos + j].font then
          -- Break run
          local newrun = {}
          newrun.pos = bidi_run.pos + j
          newrun.len = 1
          newrun.direction = hb_dir(base_dir, bidi_run.level)
          newrun.script = nodetable[newrun.pos].script
          newrun.font = nodetable[newrun.pos].font
          run.next = newrun
          run = newrun
        else
          run.len = run.len + 1
          run.pos = bidi_run.pos + j
        end
      end
    else
      run.pos = bidi_run.pos
      run.script = nodetable[run.pos].script
      run.font = nodetable[run.pos].font
      run.len = 0
      for j = 0, bidi_run.len - 1 do
        if nodetable[run.pos].script ~= nodetable[bidi_run.pos + j].script or
           nodetable[run.pos].font   ~= nodetable[bidi_run.pos + j].font then
          debug.log("Breaking Run")
          -- Break run
          local newrun = {}
          newrun.pos = bidi_run.pos + j
          newrun.len = 1
          newrun.direction = hb_dir(base_dir, bidi_run.level)
          newrun.script = nodetable[bidi_run.pos + j].script
          newrun.font = nodetable[bidi_run.pos + j].font
          run.next = newrun
          run = newrun
        else
          run.len = run.len + 1
        end
      end
    end
    last = run
    last.next = nil
  end

  -- Do shaping
  local text = {}
  for _, n in ipairs(nodetable) do
    table.insert(text, n.char)
  end
  shape_runs(runs, text)

  -- Convert shaped nodes to node list
  local newhead = nodetable_to_list(nodetable, runs, head.dir)
  return newhead
end

-- Switch off some callbacks.
callback.register("hyphenate", false)
callback.register("ligaturing", false)
callback.register("kerning", false)

-- Callback to load fonts.
local function read_font(file, size)
  print("Loading font…", file)
  local metrics = fonts.read_font_metrics(file, size)
  metrics.harfbuzz = true -- Mark as being able to be shaped by Harfbuzz
  return metrics
end

-- Register OpenType font loader in define_font callback.
callback.register('define_font', read_font, "font loader")

callback.register("pre_linebreak_filter", function(head, groupcode)
  debug.log("PRE LINE BREAK. Group Code is %s", groupcode == "" and "main vertical list" or groupcode)
  debug.show_nodes(head)

  local newhead = layout_nodes(head)

  debug.show_nodes(newhead, true)

  return newhead
end)
