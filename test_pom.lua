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
    check(name, actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local LoginPage = WebDriver.Page.extend({
    locators = {
        user = By.id("user"),
        pass = By.id("pass"),
        submit = By.id("login-btn"),
        status = By.id("login-status"),
    }
})

function LoginPage:sign_in(user, password)
    self:type("user", user)
    self:type("pass", password)
    self:click("submit")
    return self:wait_el("status", 3):get_text()
end

local ok, err = xpcall(function()
    test.with_local_session({ fixture_port = 8771, port = 9519 }, function(driver, url)
        print("[Page Object]")
        driver:get(url)
        local login = LoginPage.new(driver)
        check_eq("login success", login:sign_in("lua", "rocks"), "welcome")
        check_eq("login denied", login:sign_in("nope", "nope"), "denied")

        local home = driver:page({
            title = By.id("title"),
            children = By.class_name("child"),
            parent = By.id("parent"),
        })
        check_eq("page:text", home:text("title"), "Fixture Home")
        check_eq("page:els", #home:els("children"), 2)

        local card = home:component("parent", {
            nested = By.id("nested"),
        })
        check_eq("component nested", card:text("nested"), "nested text")

        print("\n[Shadow DOM]")
        local host = driver:find_element(By.id("shadow-host"))
        local root = host:shadow_root()
        check("shadow root returned", root ~= nil and root.find_element ~= nil)
        check_eq("text inside shadow", root:find_element(By.id("shadow-text")):get_text(), "inside shadow")
        root:find_element(By.id("shadow-btn")):click()
        check_eq("shadow click reaches host", host:get_attribute("data-clicked"), "1")

        local closed = driver:find_element(By.id("closed-host"))
        local light_ok = pcall(function()
            return driver:find_element(By.id("closed-text"))
        end)
        check("closed internals not in light DOM", not light_ok)

        if driver:is_chromium() then
            local pierced = closed:shadow_root({ pierce = true })
            check("pierced closed shadow root", pierced ~= nil and pierced.find_element ~= nil)
            check_eq("text inside closed shadow", pierced:find_element(By.id("closed-text")):get_text(), "inside closed")
            closed:find_in_shadow(By.id("closed-btn")):click()
            check_eq("closed shadow click reaches host", closed:get_attribute("data-clicked"), "1")
        else
            print("  SKIP  closed shadow pierce — Chromium CDP only")
        end

        print("\n[Shadow slots]")
        local slotted = driver:find_element(By.id("slotted-title"))
        local slot = slotted:assigned_slot()
        check("assigned_slot returned", slot ~= nil and slot.find_element ~= nil)
        check_eq("assigned slot id", slot:get_attribute("id") or slot:get_property("id"), "title-slot")
        local assigned = slot:assigned_elements()
        check("assigned_elements", type(assigned) == "table" and #assigned >= 1)
        check_eq("assigned node text", assigned[1]:get_text(), "hello slot")

        local Home = WebDriver.Page.extend({
            locators = { title = By.id("title") }
        })
        check_eq("Page.extend open(url)", Home.new(driver, { url = url }):open():text("title"), "Fixture Home")

        print("\n[POM generator]")
        local gen_path = "/tmp/lua-selenium-generated-page.lua"
        local gen = driver:generate_page({ name = "FixturePage", out = gen_path })
        check("generated locators include user", gen.locators.user ~= nil)
        check("generated locators include login_btn", gen.locators.login_btn ~= nil)
        check("generated source is Lua", gen.source:find("WebDriver.Page.extend", 1, true) ~= nil)
        local Generated = assert(loadfile(gen_path))()
        local generated = Generated.new(driver)
        check_eq("generated page title", generated:text("title"), "Fixture Home")
        generated:type("user", "lua")
        generated:type("pass", "rocks")
        generated:click("login_btn")
        check_eq("generated page login", generated:wait_el("login_status", 3):get_text(), "welcome")
        os.remove(gen_path)

        print("\n[File upload]")
        local path = "/tmp/lua-selenium-upload.txt"
        local f = assert(io.open(path, "w"))
        f:write("hello upload")
        f:close()
        local file_input = driver:find_element(By.id("file-input"))
        file_input:send_keys(path)
        local uploaded = driver:execute_script(
            "return arguments[0].files[0] && arguments[0].files[0].name;",
            { file_input }
        )
        check_eq("uploaded file name", uploaded, "lua-selenium-upload.txt")
        os.remove(path)
    end)
end, debug.traceback)

if not ok then
    failed = failed + 1
    print("\nERROR: " .. tostring(err))
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
print("[+] POM / shadow / upload tests completed successfully!")
