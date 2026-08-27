local http = require("socket.http")
local ltn12 = require("ltn12")
local json = require("lunajson")
local mime = require("mime")
local socket = require("socket")

local WebDriver = {}
WebDriver.__index = WebDriver

local WebElement = {}
WebElement.__index = WebElement

local Alert = {}
Alert.__index = Alert

local By = {}

local ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf"

-- Helper to ensure empty tables serialize as JSON arrays [] in lunajson
local function json_array(tbl)
    tbl = tbl or {}
    if #tbl == 0 then
        tbl[0] = 0
    end
    return tbl
end

local function css_attr_equals(attr, value)
    local escaped = tostring(value):gsub("\\", "\\\\"):gsub('"', '\\"')
    return ("[%s=\"%s\"]"):format(attr, escaped)
end

local function locator_args(using, value)
    if type(using) == "table" then
        return using.using, using.value
    end
    return using or "css selector", value
end

local function url_encode(str)
    return (tostring(str):gsub("([^%w%-%.%_~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

-----------------------------------------------------------
-- Locator strategies (By)
-- W3C using values: css selector, xpath, tag name, link text, partial link text
-----------------------------------------------------------
function By.css(selector)
    return { using = "css selector", value = selector }
end
By.css_selector = By.css

function By.xpath(expr)
    return { using = "xpath", value = expr }
end

function By.id(id)
    return { using = "css selector", value = css_attr_equals("id", id) }
end

function By.tag_name(name)
    return { using = "tag name", value = name }
end

function By.name(name)
    return { using = "css selector", value = css_attr_equals("name", name) }
end

function By.class_name(name)
    return { using = "css selector", value = "." .. tostring(name) }
end

function By.link_text(text)
    return { using = "link text", value = text }
end

function By.partial_link_text(text)
    return { using = "partial link text", value = text }
end

-----------------------------------------------------------
-- Internal HTTP Helper
-----------------------------------------------------------
local function request(method, url, body_table)
    local req_body = ""
    if type(body_table) == "string" then
        req_body = body_table
    elseif type(body_table) == "table" then
        req_body = json.encode(body_table)
    end

    local resp_body_table = {}
    local headers = {
        ["Content-Type"] = "application/json; charset=utf-8",
        ["Content-Length"] = tostring(#req_body)
    }

    local _, status = http.request{
        url = url,
        method = method,
        headers = headers,
        source = ltn12.source.string(req_body),
        sink = ltn12.sink.table(resp_body_table)
    }

    local resp_body_str = table.concat(resp_body_table)
    local decoded = nil
    if resp_body_str and #resp_body_str > 0 then
        local ok, res = pcall(json.decode, resp_body_str)
        if ok then decoded = res end
    end

    if status and status >= 400 then
        local err_msg = "WebDriver Error (" .. tostring(status) .. ")"
        if decoded and decoded.value and decoded.value.message then
            err_msg = err_msg .. ": " .. decoded.value.message
        end
        error(err_msg)
    end

    return decoded and decoded.value or decoded
end

local function element_ref(element)
    return { [ELEMENT_KEY] = element.id }
end

-----------------------------------------------------------
-- WebDriver Constructor & Methods
-----------------------------------------------------------
function WebDriver.new(options, browser_name)
    if type(options) == "string" then
        options = { server_url = options, browser_name = browser_name }
    end
    options = options or {}
    local server_url = options.server_url or "http://127.0.0.1:9515"
    browser_name = options.browser_name or "chrome"
    local headless = options.headless == true

    local chrome_args = {}
    if headless then
        table.insert(chrome_args, "--headless=new")
        table.insert(chrome_args, "--disable-gpu")
        table.insert(chrome_args, "--window-size=1920,1080")
    end

    local payload = {
        capabilities = {
            alwaysMatch = {
                browserName = browser_name,
                ["goog:chromeOptions"] = {
                    args = json_array(chrome_args)
                }
            }
        }
    }

    local res = request("POST", server_url .. "/session", payload)
    local session_id = res.sessionId

    return setmetatable({
        server_url = server_url,
        session_id = session_id,
        base_url = server_url .. "/session/" .. session_id
    }, WebDriver)
end

function WebDriver:get(url)
    return request("POST", self.base_url .. "/url", { url = url })
end

function WebDriver:get_title()
    return request("GET", self.base_url .. "/title")
end

function WebDriver:get_current_url()
    return request("GET", self.base_url .. "/url")
end

function WebDriver:find_element(using, value)
    using, value = locator_args(using, value)
    local res = request("POST", self.base_url .. "/element", {
        using = using,
        value = value
    })
    return WebElement.new(self, res[ELEMENT_KEY])
end

function WebDriver:find_elements(using, value)
    using, value = locator_args(using, value)
    local res = request("POST", self.base_url .. "/elements", {
        using = using,
        value = value
    })
    local elements = {}
    for _, el in ipairs(res) do
        table.insert(elements, WebElement.new(self, el[ELEMENT_KEY]))
    end
    return elements
end

function WebDriver:execute_script(script, args)
    return request("POST", self.base_url .. "/execute/sync", {
        script = script,
        args = json_array(args)
    })
end

function WebDriver:wait_until(condition_func, timeout_sec, interval_sec)
    timeout_sec = timeout_sec or 10
    interval_sec = interval_sec or 0.2
    local start_time = socket.gettime()

    while socket.gettime() - start_time < timeout_sec do
        local ok, result = pcall(condition_func, self)
        if ok and result then
            return result
        end
        socket.sleep(interval_sec)
    end
    error("Timeout: Condition was not met within " .. tostring(timeout_sec) .. " seconds")
end

function WebDriver:save_screenshot(filename)
    local base64_data = request("GET", self.base_url .. "/screenshot")
    local binary_data = mime.unb64(base64_data)
    local file = assert(io.open(filename, "wb"))
    file:write(binary_data)
    file:close()
    return true
end

-----------------------------------------------------------
-- Timeouts (values are milliseconds, matching the W3C wire protocol)
-----------------------------------------------------------
function WebDriver:get_timeouts()
    return request("GET", self.base_url .. "/timeouts")
end

function WebDriver:set_timeouts(opts)
    opts = opts or {}
    local payload = {}
    if opts.implicit ~= nil then payload.implicit = opts.implicit end
    if opts.page_load ~= nil then payload.pageLoad = opts.page_load end
    if opts.pageLoad ~= nil then payload.pageLoad = opts.pageLoad end
    if opts.script ~= nil then payload.script = opts.script end
    return request("POST", self.base_url .. "/timeouts", payload)
end

-----------------------------------------------------------
-- Window & tab management
-----------------------------------------------------------
function WebDriver:get_window_handle()
    return request("GET", self.base_url .. "/window")
end

function WebDriver:get_window_handles()
    return request("GET", self.base_url .. "/window/handles")
end

function WebDriver:switch_to_window(handle)
    return request("POST", self.base_url .. "/window", { handle = handle })
end

function WebDriver:close_window()
    return request("DELETE", self.base_url .. "/window")
end

function WebDriver:new_window(window_type)
    return request("POST", self.base_url .. "/window/new", {
        type = window_type or "tab"
    })
end

function WebDriver:get_window_rect()
    return request("GET", self.base_url .. "/window/rect")
end

function WebDriver:set_window_rect(rect)
    return request("POST", self.base_url .. "/window/rect", rect)
end

function WebDriver:set_window_size(width, height)
    return self:set_window_rect({ width = width, height = height })
end

function WebDriver:maximize_window()
    return request("POST", self.base_url .. "/window/maximize", {})
end

function WebDriver:minimize_window()
    return request("POST", self.base_url .. "/window/minimize", {})
end

function WebDriver:fullscreen_window()
    return request("POST", self.base_url .. "/window/fullscreen", {})
end

-----------------------------------------------------------
-- Frame / iframe switching
-----------------------------------------------------------
function WebDriver:switch_to_frame(target)
    if target == nil then
        -- lunajson omits nil values; W3C requires {"id":null}
        return request("POST", self.base_url .. "/frame", '{"id":null}')
    end

    local id
    if type(target) == "number" then
        id = target
    elseif type(target) == "table" and target.id then
        id = element_ref(target)
    else
        id = target
    end
    return request("POST", self.base_url .. "/frame", { id = id })
end

function WebDriver:switch_to_parent_frame()
    return request("POST", self.base_url .. "/frame/parent", {})
end

function WebDriver:switch_to_default_content()
    return self:switch_to_frame(nil)
end

-----------------------------------------------------------
-- Alert / dialog handling
-----------------------------------------------------------
function WebDriver:alert()
    return Alert.new(self)
end

function Alert.new(driver)
    return setmetatable({ driver = driver }, Alert)
end

function Alert:get_text()
    return request("GET", self.driver.base_url .. "/alert/text")
end

function Alert:accept()
    return request("POST", self.driver.base_url .. "/alert/accept", {})
end

function Alert:dismiss()
    return request("POST", self.driver.base_url .. "/alert/dismiss", {})
end

function Alert:send_keys(text)
    return request("POST", self.driver.base_url .. "/alert/text", { text = text })
end

-----------------------------------------------------------
-- Cookie engine
-----------------------------------------------------------
function WebDriver:get_cookies()
    return request("GET", self.base_url .. "/cookie")
end

function WebDriver:get_cookie(name)
    return request("GET", self.base_url .. "/cookie/" .. url_encode(name))
end

function WebDriver:add_cookie(cookie)
    return request("POST", self.base_url .. "/cookie", { cookie = cookie })
end

function WebDriver:delete_cookie(name)
    return request("DELETE", self.base_url .. "/cookie/" .. url_encode(name))
end

function WebDriver:delete_all_cookies()
    return request("DELETE", self.base_url .. "/cookie")
end

function WebDriver:quit()
    return request("DELETE", self.base_url)
end

-----------------------------------------------------------
-- WebElement Methods
-----------------------------------------------------------
function WebElement.new(driver, element_id)
    return setmetatable({
        driver = driver,
        id = element_id,
        base_url = driver.base_url .. "/element/" .. element_id
    }, WebElement)
end

function WebElement:find_element(using, value)
    using, value = locator_args(using, value)
    local res = request("POST", self.base_url .. "/element", {
        using = using,
        value = value
    })
    return WebElement.new(self.driver, res[ELEMENT_KEY])
end

function WebElement:find_elements(using, value)
    using, value = locator_args(using, value)
    local res = request("POST", self.base_url .. "/elements", {
        using = using,
        value = value
    })
    local elements = {}
    for _, el in ipairs(res) do
        table.insert(elements, WebElement.new(self.driver, el[ELEMENT_KEY]))
    end
    return elements
end

function WebElement:click()
    return request("POST", self.base_url .. "/click", {})
end

function WebElement:send_keys(text)
    local chars = {}
    for i = 1, #text do
        table.insert(chars, text:sub(i, i))
    end
    return request("POST", self.base_url .. "/value", {
        text = text,
        value = json_array(chars)
    })
end

function WebElement:clear()
    return request("POST", self.base_url .. "/clear", {})
end

function WebElement:get_text()
    return request("GET", self.base_url .. "/text")
end

function WebElement:get_attribute(name)
    return request("GET", self.base_url .. "/attribute/" .. name)
end

WebDriver.By = By
WebDriver.WebElement = WebElement
WebDriver.Alert = Alert
WebDriver.ELEMENT_KEY = ELEMENT_KEY

return WebDriver
