local WebDriver = require("webdriver")
local By = WebDriver.By
local test = require("webdriver_test")
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

print("Starting fixture server...")
os.execute("lua fixture_server.lua 8768 >/tmp/lua-selenium-fixture-api.log 2>&1 & echo $! >/tmp/lua-selenium-fixture-api.pid")
socket.sleep(0.3)
local fixture_url = "http://127.0.0.1:8768/"

local function stop_fixture()
    local pid_file = io.open("/tmp/lua-selenium-fixture-api.pid", "r")
    if pid_file then
        local pid = pid_file:read("*l")
        pid_file:close()
        if pid and #pid > 0 then
            os.execute("kill " .. pid .. " >/dev/null 2>&1")
        end
    end
end

local ok, err = xpcall(function()
    test.with_driver({ headless = true, spawn = true, port = 9518 }, function(driver)
        driver:get(fixture_url)

        print("\n[Navigation / source]")
        check_eq("EC.title_is", driver:wait_until(WebDriver.EC.title_is("Lua Selenium Fixture"), 2), "Lua Selenium Fixture")
        check("page source", tostring(driver:get_page_source()):find("Fixture Home", 1, true) ~= nil)

        driver:find_element(By.id("wiki-link")):click()
        driver:wait_until(WebDriver.EC.url_contains("#section"), 3)
        check("url has hash", driver:get_current_url():find("#section", 1, true) ~= nil)
        driver:back()
        driver:wait_until(function(d)
            return not d:get_current_url():find("#section", 1, true)
        end, 3)
        check("back() dropped hash", not driver:get_current_url():find("#section", 1, true))
        driver:forward()
        driver:wait_until(WebDriver.EC.url_contains("#section"), 3)
        check("forward() restored hash", driver:get_current_url():find("#section", 1, true) ~= nil)
        driver:back()
        driver:refresh()
        check_eq("title after refresh", driver:get_title(), "Lua Selenium Fixture")

        print("\n[Element state]")
        local hidden = driver:find_element(By.id("hidden-box"))
        check_eq("hidden is_displayed", hidden:is_displayed(), false)
        check_eq("title is_displayed", driver:find_element(By.id("title")):is_displayed(), true)
        check_eq("disabled is_enabled", driver:find_element(By.id("disabled-btn")):is_enabled(), false)
        check_eq("checkbox is_selected", driver:find_element(By.id("chk")):is_selected(), true)
        check_eq("tag name", driver:find_element(By.id("title")):get_tag_name(), "h1")

        local field = driver:find_element(By.id("name-field"))
        check_eq("attribute value", field:get_attribute("value"), "initial")
        field:clear()
        field:send_keys("typed")
        check_eq("property value after type", field:get_property("value"), "typed")
        local rect = field:get_rect()
        check("get_rect width", type(rect.width) == "number" and rect.width > 0)
        local color = driver:find_element(By.id("title")):get_css_value("display")
        check_eq("css display", color, "block")

        field:click()
        local active = driver:get_active_element()
        check("active element equals field", active == field)

        print("\n[Select]")
        local select = driver:select(driver:find_element(By.id("color")))
        check_eq("default selected", select:first_selected_option():get_text(), "Green")
        select:select_by_visible_text("Blue")
        check_eq("select by text", select:first_selected_option():get_attribute("value"), "b")
        select:select_by_value("r")
        check_eq("select by value", select:first_selected_option():get_text(), "Red")
        select:select_by_index(1)
        check_eq("select by index", select:first_selected_option():get_text(), "Green")

        print("\n[execute_script wrap]")
        local returned = driver:execute_script("return arguments[0];", { driver:find_element(By.id("title")) })
        check("script returns WebElement", getmetatable(returned) == WebDriver.WebElement)
        check_eq("returned element text", returned:get_text(), "Fixture Home")
        check("element equality", returned == driver:find_element(By.id("title")))

        local args = {}
        local n = driver:execute_script("return arguments.length;", args)
        check_eq("empty args length", n, 0)
        check("empty args table not mutated", args[0] == nil)

        local async_val = driver:execute_async_script([[
            var cb = arguments[arguments.length - 1];
            cb(40 + 2);
        ]])
        check_eq("execute_async_script", async_val, 42)

        print("\n[wait EC]")
        local el = driver:wait_until(WebDriver.EC.visibility_of_element(By.id("title")), 2)
        check_eq("visibility_of_element", el:get_text(), "Fixture Home")
        local clickable = driver:wait_until(WebDriver.EC.element_to_be_clickable(By.id("alert-btn")), 2)
        check("element_to_be_clickable", clickable ~= nil)
        check("invisibility_of_element", driver:wait_until(WebDriver.EC.invisibility_of_element(By.id("hidden-box")), 2) == true)

        local boom_ok, boom_err = pcall(function()
            driver:wait_until(function()
                error("boom-wait")
            end, 0.5, 0.1)
        end)
        check("wait_until surfaces last error", (not boom_ok) and tostring(boom_err):find("boom-wait", 1, true) ~= nil)

        print("\n[switch_to facade]")
        driver:switch_to():frame(driver:find_element(By.id("frame1")))
        check_eq("switch_to().frame", driver:find_element(By.id("inside")):get_text(), "in frame")
        driver:switch_to():default_content()
        check_eq("switch_to().default_content", driver:find_element(By.id("title")):get_text(), "Fixture Home")

        local stale_el = driver:find_element(By.id("nested"))
        driver:execute_script("arguments[0].remove();", { stale_el })
        check("staleness_of", driver:wait_until(WebDriver.EC.staleness_of(stale_el), 3) == true)

        local pdf = driver:print_page()
        check("print_page PDF", type(pdf) == "string" and #pdf > 100)
    end)
end, debug.traceback)

if not ok then
    failed = failed + 1
    print("\nERROR: " .. tostring(err))
end

stop_fixture()
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
print("[+] API tests completed successfully!")
