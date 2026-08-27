-- Offline smoke: auto-spawn Chrome, read a data: URL, quit.
dofile("tests/env.lua")
local WebDriver = require("webdriver")
local By = WebDriver.By

local driver = WebDriver.new({ headless = true, spawn = true })
local ok, err = xpcall(function()
    driver:get("data:text/html,<html><body><h1 id='h'>hello lua</h1></body></html>")
    local text = driver:find_element(By.id("h")):get_text()
    assert(text == "hello lua", "expected hello lua, got " .. tostring(text))
    print("[example] " .. text)
end, debug.traceback)
pcall(function() driver:quit() end)
if not ok then
    io.stderr:write(err .. "\n")
    os.exit(1)
end
