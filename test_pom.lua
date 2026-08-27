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
        local closed_ok = pcall(function()
            return closed:shadow_root():find_element(By.css("p"))
        end)
        check("closed shadow is not inspectable", not closed_ok)

        local Home = WebDriver.Page.extend({
            locators = { title = By.id("title") }
        })
        check_eq("Page.extend open(url)", Home.new(driver, { url = url }):open():text("title"), "Fixture Home")

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
