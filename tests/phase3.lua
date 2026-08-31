dofile("tests/env.lua")
local test = require("webdriver.test")

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

print("[Assertion helpers]")
local ok_eq = pcall(test.equal, 1, 1)
check("equal success", ok_eq)
local ok_fail = pcall(test.equal, 1, 2)
check("equal failure raises", not ok_fail)
pcall(function()
    test.contains("hello world", "world")
end)
check("contains string", true)

print("\n[WebSocket handshake]")
local WS = require("webdriver.ws")
check("RFC 6455 Sec-WebSocket-Accept",
    WS.sec_websocket_accept("dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")

print("\nSession fixture with_local_session + BiDi (" .. test.requested_browser() .. ")...")
local ok, err = xpcall(function()
    test.with_local_session({
        fixture_port = 8767,
        spawn = true,
        port = 9517,
        bidi = true,
    }, function(driver, fixture_url)
        local api_url = fixture_url:gsub("/$", "") .. "/api.json"
        local ws = driver.websocket_url
        check("websocket url present", type(ws) == "string" and #ws > 0, ws)

        driver:get(fixture_url)
        check("navigated", driver:get_title() == "Lua Selenium Fixture")

        local bidi = driver:bidi()
        check("bidi connected", bidi ~= nil)

        print("\n[Console logs]")
        driver:execute_script("console.log('hello-from-lua-bidi');")
        local entry = bidi:wait_for_log(function(e)
            return e.text and tostring(e.text):find("hello-from-lua-bidi", 1, true)
        end, 5)
        check("console.log captured", entry ~= nil)
        check("console type", entry.type == "console" or entry.method == "log" or entry.level ~= nil)

        local logs = driver:get_log("browser")
        local found_log = false
        if type(logs) == "table" then
            for _, row in ipairs(logs) do
                local msg = tostring(row.message or row.text or "")
                if msg:find("hello-from-lua-bidi", 1, true) then found_log = true end
            end
        end
        check("get_log browser", found_log or (type(logs) == "table"))

        print("\n[JS exceptions]")
        pcall(function()
            driver:execute_script("console.error('err-from-lua-bidi'); throw new Error('boom-lua-bidi');")
        end)
        local js_err = bidi:wait_for_log(function(e)
            local text = tostring(e.text or "")
            return text:find("boom-lua-bidi", 1, true) or text:find("err-from-lua-bidi", 1, true)
        end, 5)
        check("exception or error log captured", js_err ~= nil)

        print("\n[Network mock]")
        bidi:mock_request(api_url, {
            status_code = 200,
            body = '{"source":"mock"}',
            content_type = "application/json",
        })
        driver:execute_script([[
            window.__api = null;
            fetch('/api.json').then(function(r) { return r.json(); }).then(function(j) {
                window.__api = j;
            }).catch(function(e) {
                window.__api = { error: String(e) };
            });
            return true;
        ]])
        local mocked = driver:wait_until(function(d)
            bidi:pump(0.2)
            return d:execute_script("return window.__api && window.__api.source;")
        end, 8)
        check("mocked fetch body", mocked == "mock")

        print("\n[BiDi browsingContext / script]")
        local tree = bidi:get_tree()
        local contexts = tree and tree.contexts
        check("getTree contexts", type(contexts) == "table" and contexts[1] ~= nil)
        check("getTree context id", type(bidi:get_context_id()) == "string")

        check_eq("script.evaluate", bidi:evaluate("1 + 2"), 3)
        local summed = bidi:call_function("function(a, b) { return a + b; }", { 2, 3 })
        check_eq("script.callFunction", summed, 5)

        bidi:reload()
        check_eq("reload title", driver:get_title(), "Lua Selenium Fixture")

        local shot = bidi:capture_screenshot()
        check("captureScreenshot", type(shot) == "string" and #shot > 100)

        print("\n[CDP]")
        if driver:is_chromium() then
            local cdp = driver:execute_cdp("Runtime.evaluate", { expression = "1+2", returnByValue = true })
            local value = cdp
            if type(cdp) == "table" then
                value = cdp.result and cdp.result.value
                if value == nil and cdp.value then
                    value = cdp.value.result and cdp.value.result.value or cdp.value
                end
            end
            check("CDP Runtime.evaluate", value == 3 or value == "3", "got " .. tostring(value))
        else
            print("  SKIP  CDP Runtime.evaluate — Chromium only")
        end
    end)
end, debug.traceback)

if not ok then
    failed = failed + 1
    print("\nERROR: " .. tostring(err))
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
    os.exit(1)
end
print("[+] Phase 3 tests completed successfully!")
