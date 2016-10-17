local ufy_path = os.getenv("UFY_DIR")

print(string.format("Adding %s/modules to package.path", ufy_path))
package.path = package.path .. string.format(";%s/modules/?/init.lua", ufy_path)

-- Libraries required by ufy
ufy = require("ufy")

-- cache package path
local default_package_searchers = {}
default_package_searchers.lua_searcher = package.searchers[2]
default_package_searchers.clua_searcher = package.searchers[3]

-- Revert the package searchers to their default versions.
--
-- This behavior is overridden by default in LuaTeX. Calling this function reverts the
-- packaging searchers to use package.path and package.cpath.
--
-- Package Loading References:
-- 1. http://www.lua.org/manual/5.2/manual.html#pdf-package.searchers
-- 2. LuaTeX Manual, Section 3.2, Lua behavior
function ufy.switch_package_searchers()
	package.path[2] = default_package_searchers.lua_searcher
	package.path[3] = default_package_searchers.clua_searcher
end

harfbuzz = require("harfbuzz")
serpent = require("serpent")

