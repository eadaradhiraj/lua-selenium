dofile("tests/env.lua")
local WebDriver = require("webdriver")
local By = WebDriver.By
local Keys = WebDriver.Keys
local test = require("webdriver.test")
local socket = require("socket")

local passed = 0
local failed = 0

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

print("[Capability builders]")
local chrome_caps = WebDriver.build_capabilities({ browser_name = "chrome", headless = true })
check("chrome browserName", chrome_caps.alwaysMatch.browserName == "chrome")
check("chrome options present", chrome_caps.alwaysMatch["goog:chromeOptions"] ~= nil)
local chrome_args = chrome_caps.alwaysMatch["goog:chromeOptions"].args
local has_headless = false
for _, a in ipairs(chrome_args) do
    if a == "--headless=new" then has_headless = true end
end
check("chrome headless arg", has_headless)

local ff_caps = WebDriver.build_capabilities({ browser = "firefox", headless = true })
check_eq("firefox browserName", ff_caps.alwaysMatch.browserName, "firefox")
check("firefox options present", ff_caps.alwaysMatch["moz:firefoxOptions"] ~= nil)
check("firefox has no chrome options", ff_caps.alwaysMatch["goog:chromeOptions"] == nil)
local ff_args = ff_caps.alwaysMatch["moz:firefoxOptions"].args
local ff_headless = false
for _, a in ipairs(ff_args) do
    if a == "-headless" then ff_headless = true end
end
check("firefox headless arg", ff_headless)

local safari_caps = WebDriver.build_capabilities({ browser_name = "safari" })
check_eq("safari browserName", safari_caps.alwaysMatch.browserName, "safari")
check("safari options present", type(safari_caps.alwaysMatch["safari:options"]) == "table")

local bstack = WebDriver.build_capabilities({
    browser_name = "chrome",
    bstack_options = { os = "Windows", osVersion = "11" }
})
check_eq("browserstack options os", bstack.alwaysMatch["bstack:options"].os, "Windows")

local sauce = WebDriver.build_capabilities({
    browser_name = "chrome",
    sauce_options = { name = "lua-selenium" }
})
check_eq("sauce options name", sauce.alwaysMatch["sauce:options"].name, "lua-selenium")

local eager = WebDriver.build_capabilities({ page_load_strategy = "eager" })
check_eq("pageLoadStrategy", eager.alwaysMatch.pageLoadStrategy, "eager")
local prompt = WebDriver.build_capabilities({ unhandled_prompt_behavior = "ignore" })
check_eq("unhandledPromptBehavior", prompt.alwaysMatch.unhandledPromptBehavior, "ignore")
local proxied = WebDriver.build_capabilities({
    proxy = { proxyType = "manual", httpProxy = "127.0.0.1:8080" }
})
check_eq("proxy type", proxied.alwaysMatch.proxy.proxyType, "manual")

local chrome_ud = WebDriver.build_capabilities({
    browser_name = "chrome",
    user_data_dir = "/tmp/lua-selenium-profile",
})
local ud_arg = false
for _, a in ipairs(chrome_ud.alwaysMatch["goog:chromeOptions"].args) do
    if tostring(a):find("user-data-dir=/tmp/lua-selenium-profile", 1, true) then ud_arg = true end
end
check("chrome user-data-dir arg", ud_arg)

local ff_dl = WebDriver.build_capabilities({
    browser = "firefox",
    download_dir = "/tmp/lua-selenium-dl-caps",
})
local ff_prefs = ff_dl.alwaysMatch["moz:firefoxOptions"].prefs
check_eq("firefox download pref", ff_prefs["browser.download.dir"], "/tmp/lua-selenium-dl-caps")

local fm = WebDriver.build_capabilities({
    headless = true,
    accept_insecure_certs = true,
    first_match = {
        { browser_name = "chrome" },
        { browser_name = "firefox" },
    }
})
check("firstMatch length", fm.firstMatch and #fm.firstMatch == 2)
check_eq("firstMatch chrome", fm.firstMatch[1].browserName, "chrome")
check_eq("firstMatch firefox", fm.firstMatch[2].browserName, "firefox")
check("alwaysMatch has no browserName", fm.alwaysMatch.browserName == nil)
check("alwaysMatch acceptInsecureCerts", fm.alwaysMatch.acceptInsecureCerts == true)
check("chrome options in firstMatch", fm.firstMatch[1]["goog:chromeOptions"] ~= nil)
check("firefox options in firstMatch", fm.firstMatch[2]["moz:firefoxOptions"] ~= nil)
local fm_headless = false
for _, a in ipairs(fm.firstMatch[1]["goog:chromeOptions"].args) do
    if a == "--headless=new" then fm_headless = true end
end
check("firstMatch inherits headless", fm_headless)

local bstack_url = WebDriver.remote_url({
    provider = "browserstack",
    username = "user",
    access_key = "key",
})
check("browserstack remote url", tostring(bstack_url):find("hub.browserstack.com", 1, true) ~= nil)
local sauce_url = WebDriver.remote_url({
    provider = "sauce",
    username = "user",
    access_key = "key",
    region = "eu-central-1",
})
check("sauce remote url", tostring(sauce_url):find("eu-central-1.saucelabs.com", 1, true) ~= nil)
local grid_url = WebDriver.remote_url({
    grid_url = "http://grid.example:4444",
    username = "u",
    access_key = "k",
})
check("grid remote url auth", tostring(grid_url):find("u:k@", 1, true) ~= nil)

check("posix is_windows", WebDriver.is_windows("posix") == false)
check("windows is_windows", WebDriver.is_windows("windows") == true)
local posix_spawn = WebDriver.wrap_spawn_command("chromedriver --port=9", "posix")
check("posix spawn trap", posix_spawn:find("trap", 1, true) ~= nil)
local win_spawn = WebDriver.wrap_spawn_command("chromedriver --port=9", "windows")
check("windows spawn start", win_spawn:find("start /b", 1, true) ~= nil)
check("windows lookup", WebDriver.lookup_command("chromedriver", "windows"):find("where", 1, true) ~= nil)
check("posix lookup", WebDriver.lookup_command("chromedriver", "posix"):find("command -v", 1, true) ~= nil)
local win_cmd = WebDriver.driver_command("chrome", 9515, "chromedriver.exe", "windows")
check("windows driver quote", win_cmd:find('"chromedriver.exe"', 1, true) ~= nil)
local win_dir = WebDriver.list_dir_command("C:\\tmp", "windows")
check("windows list dir", win_dir:find("dir /b", 1, true) ~= nil)

print("\nAuto-spawning " .. test.requested_browser() .. " + fixture...")
local spawned_port
local ok, err = xpcall(function()
    test.with_local_session({
        fixture_port = 8766,
        spawn = true,
        port = 9516,
    }, function(driver, fixture_url)
        check("managed spawn", driver._managed == true)
        spawned_port = tonumber(driver.server_url:match(":(%d+)$"))
        check("spawned local url", spawned_port ~= nil)

        local function attr(id, name)
            return driver:find_element(By.id(id)):get_attribute(name)
        end

        driver:get(fixture_url)
        check_eq("fixture title", driver:get_title(), "Lua Selenium Fixture")

    print("\n[Actions: hover / double-click / context-click]")
    driver:find_element(By.id("hover-target")):hover()
    check_eq("hover dataset", attr("hover-target", "data-hovered"), "1")

    driver:find_element(By.id("dbl-target")):double_click()
    check_eq("double-click dataset", attr("dbl-target", "data-dbl"), "1")

    driver:find_element(By.id("ctx-target")):context_click()
    check_eq("context-click dataset", attr("ctx-target", "data-ctx"), "1")

    print("\n[Actions: drag-and-drop]")
    local src = driver:find_element(By.id("src"))
    local dst = driver:find_element(By.id("dst"))
    driver:drag_and_drop(src, dst)
    check_eq("drag mousedown", attr("src", "data-down"), "1")
    check_eq("drop received", attr("dst", "data-dropped"), "1")

    print("\n[Actions: modifier keys]")
    local box = driver:find_element(By.id("searchInput"))
    box:click()
    box:send_keys("hello world")
    driver:actions()
        :move_to(box)
        :click()
        :key_down(Keys.CONTROL)
        :send_keys("a")
        :key_up(Keys.CONTROL)
        :perform()
    local selected = driver:execute_script(
        "var e=document.getElementById('searchInput'); return e.selectionEnd - e.selectionStart;"
    )
    check_eq("Ctrl+A selected length", selected, #"hello world")

    driver:actions()
        :key_down(Keys.SHIFT)
        :click(driver:find_element(By.id("shift-target")))
        :key_up(Keys.SHIFT)
        :perform()
    check_eq("Shift+Click", attr("shift-target", "data-shift"), "1")

    print("\n[Actions: pause / move_by / click_and_hold]")
    driver:execute_script("document.getElementById('src').removeAttribute('data-down');")
    driver:actions()
        :pause(20)
        :click_and_hold(driver:find_element(By.id("src")))
        :pause(20)
        :perform()
    check_eq("click_and_hold mousedown", attr("src", "data-down"), "1")
    driver:actions():release_pointer():perform()

    driver:execute_script("document.getElementById('hover-target').removeAttribute('data-hovered');")
    local hover = driver:find_element(By.id("hover-target"))
    driver:actions():move_to(hover):move_by(1, 1):perform()
    check_eq("move_by still on hover", attr("hover-target", "data-hovered"), "1")

    driver:actions():move_to_location(2, 2):perform()
    driver:execute_script([[
        document.getElementById('hover-target').scrollIntoView({block:'nearest'});
        document.getElementById('hover-target').removeAttribute('data-hovered');
    ]])
    local hx = driver:execute_script(
        "var r=document.getElementById('hover-target').getBoundingClientRect(); return r.left+r.width/2;"
    )
    local hy = driver:execute_script(
        "var r=document.getElementById('hover-target').getBoundingClientRect(); return r.top+r.height/2;"
    )
    driver:actions():move_to_location(math.floor(hx), math.floor(hy)):perform()
    check_eq("move_to_location hover", attr("hover-target", "data-hovered"), "1")

    driver:execute_script("document.getElementById('src').removeAttribute('data-down');")
    driver:actions():click_and_hold(driver:find_element(By.id("src"))):perform()
    driver:actions():release()
    check("actions release", true)

    print("\n[Actions: wheel scroll]")
    local y = test.wheel_scroll_y(driver, 500)
    check("scrolled down", type(y) == "number" and y > 50, "scrollY=" .. tostring(y))

    print("\n[Driver lifecycle]")
    check("port open while running", spawned_port ~= nil)
    -- port check while session is alive
    local live = socket.tcp()
    live:settimeout(0.3)
    local live_ok = live:connect("127.0.0.1", spawned_port)
    live:close()
        check("driver port listening", live_ok ~= nil)
    end)
end, debug.traceback)

if not ok then
    failed = failed + 1
    print("\nERROR: " .. tostring(err))
end

socket.sleep(0.4)

if spawned_port then
    local after = socket.tcp()
    after:settimeout(0.3)
    local still = after:connect("127.0.0.1", spawned_port)
    after:close()
    check("spawned driver stopped after quit", still == nil)
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
    os.exit(1)
end
print("[+] Phase 2 tests completed successfully!")
