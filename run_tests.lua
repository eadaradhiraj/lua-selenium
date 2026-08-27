-- Run local suite (no Wikipedia / external network).
-- Chrome first, then the W3C suites again on Firefox when geckodriver is present.
local chrome_tests = {
    "test_api.lua",
    "test_phase1.lua",
    "test_phase2.lua",
    "test_phase3.lua",
    "test_pom.lua",
    "example.lua",
}

local firefox_tests = {
    "test_api.lua",
    "test_phase1.lua",
    "test_phase2.lua",
    "test_phase3.lua",
    "test_pom.lua",
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

print("======== all local tests passed")
