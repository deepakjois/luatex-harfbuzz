-- Use LuaRocks to load packages
ufy.loader.revert_package_searchers()

local ufylayout = require("ufylayout")
local debug = require("ufylayout.debug")
local fonts = require("ufy.fonts")

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

  local newhead = ufylayout.layout_nodes(head)

  debug.show_nodes(newhead, true)

  return newhead
end)
