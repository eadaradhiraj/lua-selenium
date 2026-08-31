-- Run local suite (no Wikipedia / external network).
-- examples/wikipedia.lua and wikipedia_advanced.lua stay opt-in: they skip
-- when Wikipedia is unreachable and are not listed here.
-- Chrome first, then the W3C suites again on Firefox when geckodriver is present.
dofile("tests/env.lua")

local chrome_tests = {
    "tests/api.lua",
    "tests/phase1.lua",
    "tests/phase2.lua",
    "tests/phase3.lua",
    "tests/pom.lua",
    "tests/run_spec.lua",
    "examples/example.lua",
}

local firefox_tests = {
    "tests/api.lua",
    "tests/phase1.lua",
    "tests/phase2.lua",
    "tests/phase3.lua",
    "tests/pom.lua",
}

local function run(cmd, label)
    print("======== " .. (label or cmd))
    local ok, why, code = os.execute(cmd)
    if not ok then
        io.stderr:write((label or cmd) .. " failed (" .. tostring(why) .. " " .. tostring(code) .. ")\n")
        os.exit(code or 1)
    end
end

for _, name in ipairs(chrome_tests) do
    run("lua " .. name, name)
end

local WebDriver = require("webdriver")
if WebDriver.has_driver("firefox") then
    for _, name in ipairs(firefox_tests) do
        run("LUA_SELENIUM_BROWSER=firefox lua " .. name, "firefox " .. name)
    end
else
    print("======== firefox parity skipped (geckodriver or firefox not on PATH)")
end

if WebDriver.has_driver("edge") then
    run("LUA_SELENIUM_BROWSER=edge lua tests/api.lua", "edge tests/api.lua")
else
    print("======== edge live skipped (msedgedriver or Edge not on PATH)")
end

print("======== all local tests passed")
