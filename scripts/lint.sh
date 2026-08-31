#!/bin/sh
# luacheck 1.2.0 crashes on Lua 5.4+ (assigns to a for-loop variable).
# Use a Lua 5.1 (or 5.3) luacheck: luarocks --lua-version 5.1 --local install luacheck
set -e
cd "$(dirname "$0")/.."
if ! command -v luacheck >/dev/null 2>&1; then
    echo "luacheck not on PATH. Install with: luarocks --lua-version 5.1 --local install luacheck" >&2
    exit 1
fi
exec luacheck src tests examples spec
