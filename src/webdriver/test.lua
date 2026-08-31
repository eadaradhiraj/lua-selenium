-- Assertion helpers and session fixtures for Lua test runners (busted, telescope, or plain Lua).
local M = {}

local function fmt(value)
    local t = type(value)
    if t == "string" then
        return string.format("%q", value)
    end
    return tostring(value)
end

function M.equal(actual, expected, message)
    if actual ~= expected then
        error((message and (message .. ": ") or "") ..
            "expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
    end
end

function M.is_true(cond, message)
    if not cond then
        error(message or "expected condition to be true", 2)
    end
end

function M.is_false(cond, message)
    if cond then
        error(message or "expected condition to be false", 2)
    end
end

function M.is_nil(value, message)
    if value ~= nil then
        error(message or ("expected nil, got " .. fmt(value)), 2)
    end
end

function M.not_nil(value, message)
    if value == nil then
        error(message or "expected a non-nil value", 2)
    end
end

function M.matches(str, pattern, message)
    if type(str) ~= "string" or not str:find(pattern) then
        error(message or ("expected " .. fmt(str) .. " to match " .. fmt(pattern)), 2)
    end
end

function M.contains(haystack, needle, message)
    if type(haystack) == "string" then
        if not haystack:find(needle, 1, true) then
            error(message or ("expected " .. fmt(haystack) .. " to contain " .. fmt(needle)), 2)
        end
        return
    end
    if type(haystack) == "table" then
        for _, item in ipairs(haystack) do
            if item == needle then return end
        end
        error(message or ("expected list to contain " .. fmt(needle)), 2)
    end
    error("contains() requires a string or list", 2)
end

-- Fixture: create a driver, run fn, always quit.
function M.with_driver(opts, fn)
    if type(opts) == "function" then
        fn = opts
        opts = nil
    end
    opts = opts or {}
    opts = M.apply_browser(opts)
    if opts.headless == nil then
        opts.headless = true
    end
    local WebDriver = require("webdriver")
    local driver = WebDriver.new(opts)
    local ok, result = xpcall(function()
        return fn(driver)
    end, debug.traceback)
    pcall(function() driver:quit() end)
    if not ok then
        error(result, 0)
    end
    return result
end

-- Optional busted integration: register a before_each/after_each driver.
function M.install_busted(busted_assert, opts)
    local WebDriver = require("webdriver")
    opts = opts or { headless = true }
    local driver
    local helpers = {
        driver = function()
            return driver
        end
    }
    local before = rawget(_G, "before_each")
    local after = rawget(_G, "after_each")
    if type(before) == "function" then
        before(function()
            driver = WebDriver.new(opts)
        end)
    end
    if type(after) == "function" then
        after(function()
            if driver then
                pcall(function() driver:quit() end)
                driver = nil
            end
        end)
    end
    helpers.assert = busted_assert or M
    return helpers
end

function M.reachable(url, timeout)
    url = url or "https://www.wikipedia.org"
    timeout = timeout or 4
    local ok_ssl, https = pcall(require, "ssl.https")
    if ok_ssl then
        https.TIMEOUT = timeout
        local _, code = https.request(url)
        return type(code) == "number" and code >= 200 and code < 500
    end
    local http = require("socket.http")
    http.TIMEOUT = timeout
    local _, code = http.request(url)
    return type(code) == "number" and code >= 200 and code < 500
end

function M.start_fixture(port)
    port = port or 8765
    local socket = require("socket")
    local pidfile = "/tmp/lua-selenium-fixture-" .. tostring(port) .. ".pid"
    local script = "tests/fixture.lua"
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) == "@" then
        local dir = src:sub(2):match("(.+)/[^/]+$")
        if dir then
            script = dir .. "/../../tests/fixture.lua"
        end
    end
    os.execute(string.format(
        "lua %s %d >/tmp/lua-selenium-fixture-%d.log 2>&1 & echo $! > %s",
        "'" .. script:gsub("'", "'\\''") .. "'",
        port, port, pidfile
    ))
    local start = socket.gettime()
    while socket.gettime() - start < 3 do
        local tcp = socket.tcp()
        tcp:settimeout(0.15)
        local ok = tcp:connect("127.0.0.1", port)
        tcp:close()
        if ok then
            local url = "http://127.0.0.1:" .. tostring(port) .. "/"
            local function stop()
                local f = io.open(pidfile, "r")
                if f then
                    local pid = f:read("*l")
                    f:close()
                    if pid and #pid > 0 then
                        os.execute("kill " .. pid .. " >/dev/null 2>&1")
                    end
                end
            end
            return url, stop
        end
        socket.sleep(0.05)
    end
    error("fixture server did not start on port " .. tostring(port))
end

-- Chrome for Testing in CI can have a viewport taller than the page, so a
-- wheel action is a no-op (scrollY stays 0). Shrink the window, origin the
-- wheel on the pad, and wait for scrollY.
function M.wheel_scroll_y(driver, dy)
    dy = dy or 600
    pcall(function()
        driver:set_window_size(800, 500)
    end)
    driver:execute_script([[
        var el = document.getElementById('scroll-pad');
        if (el) {
            el.style.height = '4000px';
            el.style.width = '100%';
        }
        document.documentElement.style.overflow = 'auto';
        window.scrollTo(0, 0);
    ]])
    local WebDriver = require("webdriver")
    local pad = driver:find_element(WebDriver.By.id("scroll-pad"))
    driver:scroll(0, dy, { origin = pad, duration = 250 })
    return driver:wait_until(function(d)
        local y = d:execute_script("return window.scrollY || window.pageYOffset || 0;")
        return type(y) == "number" and y > 50 and y
    end, 5)
end

-- driver + local HTML fixture; always stops both.
function M.with_local_session(opts, fn)
    if type(opts) == "function" then
        fn = opts
        opts = nil
    end
    opts = opts or {}
    local fixture_port = opts.fixture_port or 8770
    local driver_opts = {}
    for k, v in pairs(opts) do
        if k ~= "fixture_port" then
            driver_opts[k] = v
        end
    end
    driver_opts = M.apply_browser(driver_opts)
    if driver_opts.headless == nil then driver_opts.headless = true end
    if driver_opts.spawn == nil then driver_opts.spawn = true end

    local url, stop = M.start_fixture(fixture_port)
    local ok, result = xpcall(function()
        return M.with_driver(driver_opts, function(driver)
            return fn(driver, url)
        end)
    end, debug.traceback)
    pcall(stop)
    if not ok then
        error(result, 0)
    end
    return result
end

M.assert_equal = M.equal
M.assert_true = M.is_true
M.assert_false = M.is_false

function M.requested_browser()
    local name = os.getenv("LUA_SELENIUM_BROWSER")
    if name and #name > 0 then
        return name
    end
    return "chrome"
end

function M.is_chromium(driver)
    local b = driver and driver.browser_name or M.requested_browser()
    return b == "chrome" or b == "chromium" or b == "MicrosoftEdge"
end

function M.apply_browser(opts)
    opts = opts or {}
    if opts.browser_name == nil and opts.browser == nil then
        opts.browser_name = M.requested_browser()
    end
    local browser = opts.browser_name or opts.browser
    if browser == "firefox" and opts.startup_timeout == nil then
        opts.startup_timeout = 30
    end
    return opts
end

return M
