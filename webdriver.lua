local http = require("socket.http")
local ltn12 = require("ltn12")
local json = require("lunajson")
local mime = require("mime")
local socket = require("socket")
local utf8 = require("utf8")

local https

local WebDriver = {}
WebDriver.__index = WebDriver

local WebElement = {}
WebElement.__index = WebElement

local Alert = {}
Alert.__index = Alert

local Actions = {}
Actions.__index = Actions

local By = {}

local ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf"

local DEFAULT_PORTS = {
    chrome = 9515,
    firefox = 4444,
    safari = 5555,
    MicrosoftEdge = 9515,
}

local DRIVER_BINS = {
    chrome = "chromedriver",
    firefox = "geckodriver",
    safari = "safaridriver",
    MicrosoftEdge = "msedgedriver",
}

local BROWSER_NAMES = {
    chrome = "chrome",
    chromium = "chrome",
    firefox = "firefox",
    safari = "safari",
    edge = "MicrosoftEdge",
    MicrosoftEdge = "MicrosoftEdge",
}

-- W3C WebDriver key code points
local Keys = {
    NULL = "\u{E000}",
    CANCEL = "\u{E001}",
    HELP = "\u{E002}",
    BACKSPACE = "\u{E003}",
    TAB = "\u{E004}",
    CLEAR = "\u{E005}",
    RETURN = "\u{E006}",
    ENTER = "\u{E007}",
    SHIFT = "\u{E008}",
    CONTROL = "\u{E009}",
    CTRL = "\u{E009}",
    ALT = "\u{E00A}",
    PAUSE = "\u{E00B}",
    ESCAPE = "\u{E00C}",
    SPACE = "\u{E00D}",
    PAGE_UP = "\u{E00E}",
    PAGE_DOWN = "\u{E00F}",
    END = "\u{E010}",
    HOME = "\u{E011}",
    LEFT = "\u{E012}",
    ARROW_LEFT = "\u{E012}",
    UP = "\u{E013}",
    ARROW_UP = "\u{E013}",
    RIGHT = "\u{E014}",
    ARROW_RIGHT = "\u{E014}",
    DOWN = "\u{E015}",
    ARROW_DOWN = "\u{E015}",
    INSERT = "\u{E016}",
    DELETE = "\u{E017}",
    SEMICOLON = "\u{E018}",
    EQUALS = "\u{E019}",
    NUMPAD0 = "\u{E01A}",
    NUMPAD1 = "\u{E01B}",
    NUMPAD2 = "\u{E01C}",
    NUMPAD3 = "\u{E01D}",
    NUMPAD4 = "\u{E01E}",
    NUMPAD5 = "\u{E01F}",
    NUMPAD6 = "\u{E020}",
    NUMPAD7 = "\u{E021}",
    NUMPAD8 = "\u{E022}",
    NUMPAD9 = "\u{E023}",
    MULTIPLY = "\u{E024}",
    ADD = "\u{E025}",
    SEPARATOR = "\u{E026}",
    SUBTRACT = "\u{E027}",
    DECIMAL = "\u{E028}",
    DIVIDE = "\u{E029}",
    F1 = "\u{E031}",
    F2 = "\u{E032}",
    F3 = "\u{E033}",
    F4 = "\u{E034}",
    F5 = "\u{E035}",
    F6 = "\u{E036}",
    F7 = "\u{E037}",
    F8 = "\u{E038}",
    F9 = "\u{E039}",
    F10 = "\u{E03A}",
    F11 = "\u{E03B}",
    F12 = "\u{E03C}",
    META = "\u{E03D}",
    COMMAND = "\u{E03D}",
}

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

local function url_decode(str)
    return (tostring(str):gsub("+", " "):gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

local function utf8_chars(text)
    local chars = {}
    for _, code in utf8.codes(tostring(text)) do
        table.insert(chars, utf8.char(code))
    end
    return chars
end

local function copy_table(src)
    local dst = {}
    if not src then return dst end
    for k, v in pairs(src) do
        dst[k] = v
    end
    return dst
end

local function append_args(dst, src)
    if not src then return dst end
    for _, arg in ipairs(src) do
        table.insert(dst, arg)
    end
    return dst
end

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function normalize_browser(name)
    name = name or "chrome"
    return BROWSER_NAMES[name] or name
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
-- Internal HTTP Helper (HTTP + HTTPS via luasec)
-----------------------------------------------------------
local function http_client_for(url)
    if url:match("^https://") then
        if not https then
            local ok, mod = pcall(require, "ssl.https")
            if not ok then
                error("HTTPS URLs require luasec (ssl.https): " .. tostring(mod))
            end
            https = mod
        end
        return https
    end
    return http
end

local function split_userinfo(url)
    local scheme, userinfo, rest = url:match("^(https?)://([^@/]+)@(.+)$")
    if not scheme or not userinfo:find(":") then
        return url, nil
    end
    local user, pass = userinfo:match("^([^:]+):(.*)$")
    return scheme .. "://" .. rest, url_decode(user) .. ":" .. url_decode(pass)
end

local function request(method, url, body_table)
    local req_body = ""
    if type(body_table) == "string" then
        req_body = body_table
    elseif type(body_table) == "table" then
        req_body = json.encode(body_table)
    end

    local clean_url, basic = split_userinfo(url)
    local resp_body_table = {}
    local headers = {
        ["Content-Type"] = "application/json; charset=utf-8",
        ["Content-Length"] = tostring(#req_body)
    }
    if basic then
        headers["Authorization"] = "Basic " .. mime.b64(basic)
    end

    local client = http_client_for(clean_url)
    local _, status = client.request{
        url = clean_url,
        method = method,
        headers = headers,
        source = ltn12.source.string(req_body),
        sink = ltn12.sink.table(resp_body_table),
        protocol = "tlsv1_2",
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
-- Capability builders
-----------------------------------------------------------
local function build_always_match(options)
    local browser = normalize_browser(options.browser_name or options.browser)
    local headless = options.headless == true
    local extra_args = options.args

    local always = {
        browserName = browser
    }
    if options.accept_insecure_certs then
        always.acceptInsecureCerts = true
    end

    if browser == "chrome" then
        local chrome = copy_table(options.chrome_options)
        local args = {}
        if headless then
            table.insert(args, "--headless=new")
            table.insert(args, "--disable-gpu")
            table.insert(args, "--window-size=1920,1080")
        end
        append_args(args, chrome.args)
        append_args(args, extra_args)
        chrome.args = json_array(args)
        if options.binary then chrome.binary = options.binary end
        always["goog:chromeOptions"] = chrome
    elseif browser == "firefox" then
        local ff = copy_table(options.firefox_options)
        local args = {}
        if headless then
            table.insert(args, "-headless")
        end
        append_args(args, ff.args)
        append_args(args, extra_args)
        ff.args = json_array(args)
        if options.binary then ff.binary = options.binary end
        always["moz:firefoxOptions"] = ff
    elseif browser == "safari" then
        always["safari:options"] = copy_table(options.safari_options)
    elseif browser == "MicrosoftEdge" then
        local edge = copy_table(options.edge_options)
        local args = {}
        if headless then
            table.insert(args, "--headless=new")
            table.insert(args, "--disable-gpu")
        end
        append_args(args, edge.args)
        append_args(args, extra_args)
        edge.args = json_array(args)
        if options.binary then edge.binary = options.binary end
        always["ms:edgeOptions"] = edge
    end

    if options.bstack_options then
        always["bstack:options"] = options.bstack_options
    end
    if options.sauce_options then
        always["sauce:options"] = options.sauce_options
    end
    if options.bidi then
        always.webSocketUrl = true
    end
    if options.capabilities then
        for k, v in pairs(options.capabilities) do
            always[k] = v
        end
    end

    return always
end

function WebDriver.build_capabilities(options)
    options = options or {}
    options.browser_name = normalize_browser(options.browser_name or options.browser)
    return { alwaysMatch = build_always_match(options) }
end

-----------------------------------------------------------
-- Remote URL helpers (Grid / BrowserStack / Sauce Labs)
-----------------------------------------------------------
local function inject_auth(url, options)
    local user = options.username or options.user
    local key = options.access_key or options.key or options.password
    if user and key and not url:find("@", 1, true) then
        return url:gsub("^(https?://)", "%1" .. url_encode(user) .. ":" .. url_encode(key) .. "@", 1)
    end
    return url
end

local function is_remote_options(options)
    if options.provider or options.grid_url or options.remote_url then
        return true
    end
    if options.server_url then
        local host = options.server_url:match("://(%[[^%]]+%])") or options.server_url:match("://([^/:]+)")
        if host and host ~= "127.0.0.1" and host ~= "localhost" and host ~= "::1" then
            return true
        end
    end
    return false
end

local function resolve_remote_url(options)
    local user = options.username or options.user
    local key = options.access_key or options.key or options.password
    local provider = options.provider

    if provider == "browserstack" then
        if not (user and key) then
            error("BrowserStack requires username and access_key")
        end
        return string.format(
            "https://%s:%s@hub.browserstack.com/wd/hub",
            url_encode(user), url_encode(key)
        )
    end

    if provider == "saucelabs" or provider == "sauce" then
        if not (user and key) then
            error("Sauce Labs requires username and access_key")
        end
        local region = options.region or "us-west-1"
        return string.format(
            "https://%s:%s@ondemand.%s.saucelabs.com:443/wd/hub",
            url_encode(user), url_encode(key), region
        )
    end

    local url = options.server_url or options.remote_url or options.grid_url
    if not url then
        error("Remote WebDriver requires server_url, remote_url, grid_url, or provider")
    end
    return inject_auth(url, options)
end

-----------------------------------------------------------
-- Local driver process lifecycle
-----------------------------------------------------------
local function port_is_open(host, port)
    local tcp = socket.tcp()
    tcp:settimeout(0.15)
    local ok = tcp:connect(host, port)
    tcp:close()
    return ok ~= nil
end

local function port_is_free(port)
    local server, err = socket.bind("127.0.0.1", port)
    if server then
        server:close()
        return true
    end
    return false, err
end

local function find_free_port(start)
    for port = start, start + 40 do
        if port_is_free(port) then
            return port
        end
    end
    error("No free TCP port in range " .. tostring(start) .. "-" .. tostring(start + 40))
end

local function wait_for_port(host, port, timeout_sec)
    timeout_sec = timeout_sec or 10
    local start = socket.gettime()
    while socket.gettime() - start < timeout_sec do
        if port_is_open(host, port) then
            return true
        end
        socket.sleep(0.1)
    end
    return false
end

local function command_exists(bin)
    local handle = io.popen("command -v " .. shell_quote(bin) .. " 2>/dev/null")
    if not handle then return nil end
    local path = handle:read("*l")
    handle:close()
    if path and #path > 0 then
        return path
    end
    return nil
end

local function driver_command(browser, port, driver_path)
    local bin = driver_path or DRIVER_BINS[browser] or "chromedriver"
    if not driver_path and not command_exists(bin) then
        error("Driver binary not found in PATH: " .. bin)
    end
    if browser == "firefox" then
        return string.format("%s --port %d", shell_quote(bin), port)
    elseif browser == "safari" then
        return string.format("%s -p %d", shell_quote(bin), port)
    else
        return string.format("%s --port=%d --whitelisted-ips=", shell_quote(bin), port)
    end
end

-- Keep stdin open; GC/close of the pipe kills the driver via trap + cat EOF.
local function spawn_driver_process(cmd)
    local script = cmd ..
        ' >/dev/null 2>&1 & pid=$!; trap "kill -TERM $pid 2>/dev/null; wait $pid 2>/dev/null" EXIT; cat >/dev/null'
    local proc = io.popen("sh -c " .. shell_quote(script), "w")
    if not proc then
        error("Failed to spawn driver process: " .. cmd)
    end
    return proc
end

local function ensure_local_service(options, browser)
    local host = "127.0.0.1"
    local port = options.port or DEFAULT_PORTS[browser] or 9515
    local want_spawn = options.spawn
    if want_spawn == nil then
        want_spawn = options.server_url == nil
    end

    if options.server_url and want_spawn ~= true then
        return options.server_url, nil
    end

    if port_is_open(host, port) then
        if want_spawn == true then
            port = find_free_port(port + 1)
        else
            local url = options.server_url or ("http://" .. host .. ":" .. tostring(port))
            return url, nil
        end
    elseif want_spawn == false then
        local url = options.server_url or ("http://" .. host .. ":" .. tostring(port))
        return url, nil
    end

    local cmd = driver_command(browser, port, options.driver_path)
    local proc = spawn_driver_process(cmd)
    if not wait_for_port(host, port, options.startup_timeout or 10) then
        pcall(function() proc:close() end)
        error("Timed out waiting for " .. browser .. " driver on port " .. tostring(port))
    end
    return "http://" .. host .. ":" .. tostring(port), proc
end

-----------------------------------------------------------
-- WebDriver Constructor & Methods
-----------------------------------------------------------
function WebDriver.new(options, browser_name)
    if type(options) == "string" then
        options = { server_url = options, browser_name = browser_name }
    end
    options = options or {}
    local browser = normalize_browser(options.browser_name or options.browser or "chrome")
    options.browser_name = browser

    local server_url, proc
    if is_remote_options(options) then
        server_url = resolve_remote_url(options)
    else
        server_url, proc = ensure_local_service(options, browser)
    end

    local payload = {
        capabilities = {
            alwaysMatch = build_always_match(options)
        }
    }

    local res = request("POST", server_url .. "/session", payload)
    local session_id = res.sessionId
    local capabilities = res.capabilities or {}

    return setmetatable({
        server_url = server_url,
        session_id = session_id,
        capabilities = capabilities,
        websocket_url = capabilities.webSocketUrl,
        base_url = server_url .. "/session/" .. session_id,
        browser_name = browser,
        _proc = proc,
        _managed = proc ~= nil,
    }, WebDriver)
end

function WebDriver:stop_service()
    if self._proc then
        pcall(function() self._proc:close() end)
        self._proc = nil
        self._managed = false
    end
end

function WebDriver:quit()
    if self._quitting then return end
    self._quitting = true
    if self._bidi then
        pcall(function() self._bidi:close() end)
        self._bidi = nil
    end
    local ok, err = true, nil
    if self.base_url then
        ok, err = pcall(request, "DELETE", self.base_url)
    end
    self:stop_service()
    if not ok then
        error(err)
    end
end

function WebDriver:__close()
    pcall(function() self:quit() end)
end
WebDriver.__gc = WebDriver.__close

function WebDriver:get(url)
    return request("POST", self.base_url .. "/url", { url = url })
end

function WebDriver:get_title()
    return request("GET", self.base_url .. "/title")
end

function WebDriver:get_current_url()
    return request("GET", self.base_url .. "/url")
end

function WebDriver:bidi()
    if self._bidi then
        return self._bidi
    end
    local BiDi = require("webdriver_bidi")
    self._bidi = BiDi.connect(self)
    return self._bidi
end

function WebDriver:on_console(fn)
    return self:bidi():on("log.entryAdded", fn)
end

function WebDriver:mock_request(url_pattern, response)
    return self:bidi():mock_request(url_pattern, response)
end

function WebDriver:get_console_logs()
    return self:bidi():console_logs()
end

function WebDriver:execute_cdp(cmd, params)
    local body = { cmd = cmd, params = params or {} }
    local ok, res = pcall(request, "POST", self.base_url .. "/goog/cdp/execute", body)
    if ok then
        return res
    end
    return request("POST", self.base_url .. "/chromium/send_command_and_get_result", body)
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

-----------------------------------------------------------
-- W3C Actions API
-----------------------------------------------------------
local function all_pauses(list)
    if #list == 0 then return true end
    for _, action in ipairs(list) do
        if action.type ~= "pause" then
            return false
        end
    end
    return true
end

function Actions.new(driver)
    return setmetatable({
        driver = driver,
        pointer = {},
        key = {},
    }, Actions)
end

function Actions:_pointer(action)
    table.insert(self.pointer, action)
    table.insert(self.key, { type = "pause", duration = action.duration or 0 })
    return self
end

function Actions:_key(action)
    table.insert(self.key, action)
    table.insert(self.pointer, { type = "pause", duration = action.duration or 0 })
    return self
end

function Actions:pause(ms)
    ms = ms or 0
    table.insert(self.pointer, { type = "pause", duration = ms })
    table.insert(self.key, { type = "pause", duration = ms })
    return self
end

function Actions:move_to(element, x, y)
    return self:_pointer({
        type = "pointerMove",
        duration = 100,
        origin = element_ref(element),
        x = x or 0,
        y = y or 0
    })
end

function Actions:move_to_location(x, y)
    return self:_pointer({
        type = "pointerMove",
        duration = 100,
        origin = "viewport",
        x = x,
        y = y
    })
end

function Actions:move_by(x, y)
    return self:_pointer({
        type = "pointerMove",
        duration = 100,
        origin = "pointer",
        x = x,
        y = y
    })
end

function Actions:click_and_hold(element, button)
    if element then self:move_to(element) end
    return self:_pointer({ type = "pointerDown", button = button or 0 })
end

function Actions:release_pointer(button)
    return self:_pointer({ type = "pointerUp", button = button or 0 })
end

function Actions:click(element, button)
    button = button or 0
    if element then self:move_to(element) end
    self:_pointer({ type = "pointerDown", button = button })
    self:_pointer({ type = "pointerUp", button = button })
    return self
end

function Actions:double_click(element)
    if element then self:move_to(element) end
    return self:click(nil, 0):click(nil, 0)
end

function Actions:context_click(element)
    return self:click(element, 2)
end

function Actions:drag_and_drop(source, target)
    return self:move_to(source):click_and_hold():pause(50):move_to(target):release_pointer()
end

function Actions:key_down(key)
    return self:_key({ type = "keyDown", value = key })
end

function Actions:key_up(key)
    return self:_key({ type = "keyUp", value = key })
end

function Actions:send_keys(text)
    for _, ch in ipairs(utf8_chars(text)) do
        self:key_down(ch)
        self:key_up(ch)
    end
    return self
end

function Actions:perform()
    local sources = {}
    if not all_pauses(self.pointer) then
        table.insert(sources, {
            type = "pointer",
            id = "mouse",
            parameters = { pointerType = "mouse" },
            actions = json_array(self.pointer)
        })
    end
    if not all_pauses(self.key) then
        table.insert(sources, {
            type = "key",
            id = "keyboard",
            actions = json_array(self.key)
        })
    end
    request("POST", self.driver.base_url .. "/actions", {
        actions = json_array(sources)
    })
    self.pointer = {}
    self.key = {}
    return self.driver
end

function Actions:release()
    request("DELETE", self.driver.base_url .. "/actions")
    return self
end

function WebDriver:actions()
    return Actions.new(self)
end

function WebDriver:drag_and_drop(source, target)
    return Actions.new(self):drag_and_drop(source, target):perform()
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
    local chars = utf8_chars(text)
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

function WebElement:hover()
    return Actions.new(self.driver):move_to(self):perform()
end

function WebElement:double_click()
    return Actions.new(self.driver):double_click(self):perform()
end

function WebElement:context_click()
    return Actions.new(self.driver):context_click(self):perform()
end

WebDriver.By = By
WebDriver.Keys = Keys
WebDriver.WebElement = WebElement
WebDriver.Alert = Alert
WebDriver.Actions = Actions
WebDriver.ELEMENT_KEY = ELEMENT_KEY
WebDriver.test = setmetatable({}, {
    __index = function(_, key)
        return require("webdriver_test")[key]
    end
})

return WebDriver
