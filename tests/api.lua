dofile("tests/env.lua")
local WebDriver = require("webdriver")
local By = WebDriver.By
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

print("Starting fixture server...")
os.execute(
    "lua tests/fixture.lua 8768 >/tmp/lua-selenium-fixture-api.log 2>&1"
        .. " & echo $! >/tmp/lua-selenium-fixture-api.pid"
)
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

local dl_dir = string.format("/tmp/lua-selenium-dl-%d", math.floor(socket.gettime() * 1000))

local ok, err = xpcall(function()
    test.with_driver({ headless = true, spawn = true, port = 9518, download_dir = dl_dir }, function(driver)
        driver:get(fixture_url)

        print("\n[Status / a11y]")
        local st = driver:status()
        check("GET /status", type(st) == "table" and type(st.ready) == "boolean", "got " .. tostring(st and st.ready))
        local role = driver:find_element(By.id("title")):get_computed_role()
        local is_heading = role == "heading" or tostring(role):find("heading", 1, true)
        check("computedrole heading", is_heading ~= nil and is_heading ~= false, "got " .. tostring(role))
        local label = driver:find_element(By.id("title")):get_computed_label()
        check("computedlabel", type(label) == "string" and #label > 0, "got " .. tostring(label))

        print("\n[Navigation / source]")
        local title = driver:wait_until(WebDriver.EC.title_is("Lua Selenium Fixture"), 2)
        check_eq("EC.title_is", title, "Lua Selenium Fixture")
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

        print("\n[Seconds timeouts / window / storage]")
        driver:implicitly_wait(1)
        driver:set_page_load_timeout(20)
        driver:set_script_timeout(8)
        local t = driver:get_timeouts()
        check_eq("implicitly_wait seconds->ms", t.implicit, 1000)
        check_eq("page load seconds->ms", t.pageLoad, 20000)
        check_eq("script seconds->ms", t.script, 8000)
        driver:implicitly_wait(0)

        local sized = driver:set_window_size(900, 700)
        local wsz = driver:get_window_size()
        check_eq("get_window_size width", wsz.width, sized.width)
        local pos = driver:get_window_position()
        check("get_window_position", type(pos.x) == "number")
        local moved = driver:set_window_position(80, 60)
        check("set_window_position", type(moved.x) == "number" and type(moved.y) == "number")

        local function skip_or_pass(name, fn)
            local ok, res = pcall(fn)
            if ok then
                check(name, type(res) == "table" and type(res.width) == "number")
                return
            end
            print("  SKIP  " .. name .. " — " .. tostring(res):sub(1, 90))
        end
        skip_or_pass("minimize_window", function()
            return driver:minimize_window()
        end)
        skip_or_pass("fullscreen_window", function()
            return driver:fullscreen_window()
        end)
        driver:set_window_size(900, 700)

        local png = string.char(137, 80, 78, 71, 13, 10, 26, 10)
        local win_shot = "/tmp/lua-selenium-window.png"
        driver:save_screenshot(win_shot)
        local wf = io.open(win_shot, "rb")
        local wmagic = wf and wf:read(8) or ""
        if wf then wf:close() end
        os.remove(win_shot)
        check("save_screenshot PNG", wmagic == png)

        local el_shot = "/tmp/lua-selenium-el.png"
        driver:find_element(By.id("title")):save_screenshot(el_shot)
        local ef = io.open(el_shot, "rb")
        local emagic = ef and ef:read(8) or ""
        if ef then ef:close() end
        os.remove(el_shot)
        check("element screenshot PNG", emagic == png)

        driver:set_local_storage("k", "v")
        check_eq("localStorage get", driver:get_local_storage("k"), "v")
        driver:clear_local_storage()
        check_eq("localStorage cleared", driver:get_local_storage("k"), nil)
        driver:set_session_storage("sk", "sv")
        check_eq("sessionStorage get", driver:get_session_storage("sk"), "sv")
        driver:clear_session_storage()
        check_eq("sessionStorage cleared", driver:get_session_storage("sk"), nil)

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
        local loc = field:location()
        check("location x", type(loc.x) == "number")
        local sz = field:size()
        check("size width", type(sz.width) == "number" and sz.width > 0)
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
        check_eq("script returns false", driver:execute_script("return false;"), false)
        check_eq("script returns null", driver:execute_script("return null;"), nil)

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
        local gone = driver:wait_until(WebDriver.EC.invisibility_of_element(By.id("hidden-box")), 2)
        check("invisibility_of_element", gone == true)
        check("text_to_be_present_in_element", driver:wait_until(
            WebDriver.EC.text_to_be_present_in_element(By.id("title"), "Fixture"), 2
        ) ~= nil)
        local box = driver:find_element(By.id("searchInput"))
        pcall(function() box:clear() end)
        box:send_keys("hello-ec")
        check("text_to_be_present_in_element_value", driver:wait_until(
            WebDriver.EC.text_to_be_present_in_element_value(By.id("searchInput"), "hello-ec"), 2
        ) ~= nil)
        driver:wait_until(WebDriver.EC.frame_to_be_available_and_switch_to_it(By.id("frame1")), 3)
        check_eq("frame_to_be_available_and_switch_to_it", driver:find_element(By.id("inside")):get_text(), "in frame")
        driver:switch_to_default_content()
        check("number_of_windows_to_be 1", driver:wait_until(WebDriver.EC.number_of_windows_to_be(1), 2) ~= nil)

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
        local pdf2 = driver:print_page({
            orientation = "landscape",
            scale = 0.8,
            background = true,
            shrink_to_fit = true,
        })
        check("print_page landscape", type(pdf2) == "string" and #pdf2 > 100)

        driver:find_element(By.id("submit-field")):submit()
        local submitted = driver:execute_script("return window.__submitted === true;")
        check("element:submit", submitted == true)

        print("\n[Scroll / download]")
        local y = test.wheel_scroll_y(driver, 600)
        check("driver:scroll", type(y) == "number" and y > 50, "scrollY=" .. tostring(y))

        driver:get(fixture_url)
        driver:find_element(By.id("download-link")):click()
        local path = driver:wait_for_download("lua-selenium", 8)
        local f = io.open(path, "r")
        local body = f and f:read("*a") or ""
        if f then f:close() end
        check("download file", body:find("hello lua-selenium download", 1, true) ~= nil,
            (path or "") .. " body=" .. tostring(body):sub(1, 120))

        print("\n[Permissions / WebAuthn]")
        local origin = driver:execute_script("return location.origin;")
        local perm_ok, perm_err = pcall(function()
            driver:set_permission("geolocation", "denied", { origin = origin })
        end)
        if perm_ok then
            check("set_permission", true)
        else
            print("  SKIP  set_permission — " .. tostring(perm_err):sub(1, 90))
        end

        local auth_ok, auth_id = pcall(function()
            return driver:add_virtual_authenticator({
                protocol = "ctap2",
                transport = "internal",
                has_resident_key = true,
                has_user_verification = true,
                is_user_verified = true,
            })
        end)
        if auth_ok and auth_id then
            check("virtual authenticator", type(auth_id) == "string" or type(auth_id) == "number")
            local creds = driver:get_credentials()
            check("credentials list", type(creds) == "table")
            driver:set_user_verified(true)
            -- Selenium's documented EC256 PKCS#8 key (unpadded base64url).
            local cred_id = "AQIDBA"
            local pk = "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg8_zMDQDYAxlU-Q"
                .. "hk1Dwkf0v18GZca1DMF3SaJ9HPdmShRANCAASNYX5lyVCOZLzFZzrIKmeZ2jwU"
                .. "RmgsJYxGP__fWN_S-j5sN4tT15XEpN_7QZnt14YvI6uvAgO0uJEboFaZlOEB"
            local host = driver:execute_script("return location.hostname;") or "127.0.0.1"
            driver:add_credential({
                credential_id = cred_id,
                is_resident_credential = false,
                rp_id = host,
                private_key = pk,
                sign_count = 0,
            })
            local after_add = driver:get_credentials()
            check("add_credential", type(after_add) == "table" and #after_add >= 1)
            local listed = after_add[1]
            local listed_id = cred_id
            if type(listed) == "table" then
                listed_id = listed.credentialId or listed.credential_id or listed.id or cred_id
            end
            driver:remove_credential(listed_id)
            local after_del = driver:get_credentials()
            check("remove_credential", type(after_del) == "table")
            driver:remove_all_credentials()
            driver:remove_virtual_authenticator()
            check("remove virtual authenticator", true)
        else
            print("  SKIP  virtual authenticator — " .. tostring(auth_id):sub(1, 90))
        end
    end)
end, debug.traceback)

if not ok then
    failed = failed + 1
    print("\nERROR: " .. tostring(err))
end

stop_fixture()
os.execute("rm -rf " .. dl_dir)
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
print("[+] API tests completed successfully!")
