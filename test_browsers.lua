-- Live sessions for Firefox (and Safari when safaridriver is on PATH).
local WebDriver = require("webdriver")
local By = WebDriver.By
local test = require("webdriver_test")

local passed = 0
local failed = 0
local skipped = 0

local function check(name, cond, extra)
    if cond then
        passed = passed + 1
        print("  PASS  " .. name)
    else
        failed = failed + 1
        print("  FAIL  " .. name .. (extra and (" — " .. tostring(extra)) or ""))
    end
end

local function check_eq(name, actual, expected)
    check(name, actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function skip(name, reason)
    skipped = skipped + 1
    print("  SKIP  " .. name .. " — " .. reason)
end

local function smoke(driver, url, label)
    driver:get(url)
    check_eq(label .. " title", driver:get_title(), "Lua Selenium Fixture")
    check_eq(label .. " h1", driver:find_element(By.id("title")):get_text(), "Fixture Home")
    local user = driver:find_element(By.id("user"))
    user:clear()
    user:send_keys("lua")
    local typed = user:get_property("value") or user:get_attribute("value")
    check_eq(label .. " send_keys", typed, "lua")
    driver:find_element(By.id("login-btn")):click()
    check_eq(label .. " click", driver:find_element(By.id("login-status")):get_text(), "denied")
end

print("[Capability / driver detection]")
check("has_driver chrome", WebDriver.has_driver("chrome") == true)
local expect_ff = WebDriver.command_exists("geckodriver") and WebDriver.command_exists("firefox")
check("has_driver firefox", WebDriver.has_driver("firefox") == expect_ff)
check("has_driver safari", WebDriver.has_driver("safari") == WebDriver.command_exists("safaridriver"))

print("\n[Firefox live session]")
if not WebDriver.has_driver("firefox") then
    skip("firefox session", "geckodriver or firefox not on PATH")
else
    local ok, err = xpcall(function()
        test.with_local_session({
            browser_name = "firefox",
            headless = true,
            fixture_port = 8772,
            port = 9521,
            spawn = true,
            startup_timeout = 30,
        }, function(driver, url)
            check_eq("firefox browserName", driver.browser_name, "firefox")
            check("firefox managed spawn", driver._managed == true)
            smoke(driver, url, "firefox")
        end)
    end, debug.traceback)
    if not ok then
        failed = failed + 1
        print("\nERROR firefox: " .. tostring(err))
    end
end

print("\n[Safari live session]")
if not WebDriver.has_driver("safari") then
    skip("safari session", "safaridriver not on PATH (macOS only)")
else
    local ok, err = xpcall(function()
        test.with_local_session({
            browser_name = "safari",
            headless = false,
            fixture_port = 8773,
            port = 9522,
            spawn = true,
            startup_timeout = 30,
        }, function(driver, url)
            check_eq("safari browserName", driver.browser_name, "safari")
            smoke(driver, url, "safari")
        end)
    end, debug.traceback)
    if not ok then
        failed = failed + 1
        print("\nERROR safari: " .. tostring(err))
    end
end

print(string.format("\n%d passed, %d failed, %d skipped", passed, failed, skipped))
if failed > 0 then
    os.exit(1)
end
print("[+] Browser live-session tests completed successfully!")
