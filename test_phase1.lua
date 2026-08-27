local WebDriver = require("webdriver")
local By = WebDriver.By
local test = require("webdriver_test")

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
    local ok = actual == expected
    check(name, ok, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

print("Launching " .. test.requested_browser() .. " (headless)...")
local ok, err = xpcall(function()
    test.with_local_session({
        fixture_port = 8765,
        spawn = true,
        port = 9520,
    }, function(driver, fixture_url)
    print("\n[Timeouts]")
    driver:set_timeouts({ implicit = 2000, page_load = 30000, script = 15000 })
    local timeouts = driver:get_timeouts()
    check_eq("implicit timeout ms", timeouts.implicit, 2000)
    check_eq("pageLoad timeout ms", timeouts.pageLoad, 30000)
    check_eq("script timeout ms", timeouts.script, 15000)

    print("\n[Navigation + By locators]")
    driver:get(fixture_url)
    check_eq("title", driver:get_title(), "Lua Selenium Fixture")

    local by_css = driver:find_element(By.css("#title"))
    check_eq("By.css text", by_css:get_text(), "Fixture Home")

    local by_id = driver:find_element(By.id("title"))
    check_eq("By.id text", by_id:get_text(), "Fixture Home")

    local by_xpath = driver:find_element(By.xpath("//h1[@id='title']"))
    check_eq("By.xpath text", by_xpath:get_text(), "Fixture Home")

    local by_tag = driver:find_elements(By.tag_name("span"))
    check("By.tag_name found spans", #by_tag >= 2, "count=" .. tostring(#by_tag))

    local by_name = driver:find_element(By.name("q"))
    check_eq("By.name tag", by_name:get_attribute("id"), "searchInput")

    local by_class = driver:find_elements(By.class_name("child"))
    check_eq("By.class_name count", #by_class, 2)

    local by_link = driver:find_element(By.link_text("Lua Language"))
    check_eq("By.link_text id", by_link:get_attribute("id"), "wiki-link")

    local by_partial = driver:find_element(By.partial_link_text("Lua"))
    check_eq("By.partial_link_text id", by_partial:get_attribute("id"), "wiki-link")

    -- raw strategy strings still work
    local raw = driver:find_element("css selector", "#title")
    check_eq("raw css strategy", raw:get_text(), "Fixture Home")

    print("\n[Nested element finding]")
    local parent = driver:find_element(By.id("parent"))
    local nested = parent:find_element(By.css(".child"))
    check_eq("parent:find_element text", nested:get_text(), "nested text")
    local children = parent:find_elements(By.class_name("child"))
    check_eq("parent:find_elements count", #children, 2)

    print("\n[Window & tab management]")
    local original = driver:get_window_handle()
    check("current window handle", type(original) == "string" and #original > 0)

    local handles_before = driver:get_window_handles()
    check_eq("one window initially", #handles_before, 1)

    local created = driver:new_window("tab")
    check("new_window returned handle", created and created.handle ~= nil)
    driver:switch_to_window(created.handle)
    driver:get(fixture_url)
    local handles_after = driver:get_window_handles()
    check_eq("two windows after new tab", #handles_after, 2)

    driver:close_window()
    driver:switch_to_window(original)
    check_eq("back to one window", #driver:get_window_handles(), 1)
    check_eq("still on fixture", driver:get_title(), "Lua Selenium Fixture")

    local sized = driver:set_window_size(800, 600)
    check_eq("resized width", sized.width, 800)
    check_eq("resized height", sized.height, 600)

    local maximized = driver:maximize_window()
    check("maximize returned rect", type(maximized.width) == "number" and maximized.width >= 800)

    print("\n[Frame / iframe switching]")
    local frame = driver:find_element(By.id("frame1"))
    driver:switch_to_frame(frame)
    local inside = driver:wait_until(function(d)
        return d:find_element(By.id("inside"))
    end, 5)
    check_eq("text inside iframe", inside:get_text(), "in frame")

    driver:switch_to_parent_frame()
    local title_after_parent = driver:find_element(By.id("title"))
    check_eq("parent frame restored", title_after_parent:get_text(), "Fixture Home")

    driver:switch_to_frame(0)
    check_eq("index frame", driver:find_element(By.id("inside")):get_text(), "in frame")
    driver:switch_to_default_content()
    check_eq("default content restored", driver:find_element(By.id("title")):get_text(), "Fixture Home")

    print("\n[Alert / dialog handling]")
    driver:find_element(By.id("alert-btn")):click()
    local alert = driver:alert()
    check_eq("alert text", alert:get_text(), "hello-alert")
    alert:accept()
    check("alert accepted", driver:find_element(By.id("title")) ~= nil)

    driver:find_element(By.id("confirm-btn")):click()
    check_eq("confirm text", driver:alert():get_text(), "sure?")
    driver:alert():dismiss()

    driver:find_element(By.id("prompt-btn")):click()
    local prompt = driver:alert()
    check_eq("prompt text", prompt:get_text(), "enter")
    prompt:send_keys("from-lua")
    prompt:accept()
    local prompt_val = driver:execute_script("return window.__promptVal;")
    check_eq("prompt value", prompt_val, "from-lua")

    print("\n[Cookie engine]")
    driver:delete_all_cookies()
    driver:add_cookie({ name = "lua_session", value = "abc123", path = "/" })
    local cookie = driver:get_cookie("lua_session")
    check_eq("get_cookie value", cookie.value, "abc123")

    local all = driver:get_cookies()
    local found = false
    for _, c in ipairs(all) do
        if c.name == "lua_session" then found = true end
    end
    check("cookie listed in get_cookies", found)

    driver:delete_cookie("lua_session")
    local after_delete = driver:get_cookies()
    local still_there = false
    for _, c in ipairs(after_delete) do
        if c.name == "lua_session" then still_there = true end
    end
        check("cookie deleted", not still_there)
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
print("[+] Phase 1 tests completed successfully!")
