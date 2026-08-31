local json = require("lunajson")
local socket = require("socket")
local WebSocket = require("webdriver.ws")

---@class BiDi
---@field driver WebDriver
---@field websocket_url string|nil
---@field context_id string|nil
local BiDi = {}
BiDi.__index = BiDi

-- lunajson encodes {} as an object; BiDi list fields need a real JSON array.
local function json_array(tbl)
    local out = {}
    if type(tbl) == "table" then
        for i, v in ipairs(tbl) do
            out[i] = v
        end
    end
    if #out == 0 then
        out[0] = 0
    end
    return out
end

local function encode_headers(headers)
    local out = {}
    if not headers then
        return out
    end
    -- array of {name, value} or map of name -> value
    if headers[1] then
        for _, h in ipairs(headers) do
            local value = h.value
            if type(value) == "string" then
                value = { type = "string", value = value }
            end
            out[#out + 1] = { name = h.name, value = value }
        end
    else
        for name, value in pairs(headers) do
            if type(value) == "string" then
                value = { type = "string", value = value }
            end
            out[#out + 1] = { name = name, value = value }
        end
    end
    return out
end

function BiDi.connect(driver)
    local url = driver.websocket_url
    if not url then
        error("BiDi WebSocket URL is not available (create the session with bidi=true)")
    end
    local ws = WebSocket.connect(url)
    local self = setmetatable({
        driver = driver,
        ws = ws,
        next_id = 1,
        listeners = {},
        logs = {},
        exceptions = {},
        mocks = {},
        context_id = nil,
        intercept_id = nil,
    }, BiDi)
    self:subscribe({
        "log.entryAdded",
        "network.beforeRequestSent",
        "network.responseCompleted",
    })
    return self
end

function BiDi:_emit(method, params)
    local list = self.listeners[method]
    if list then
        for _, fn in ipairs(list) do
            pcall(fn, params, method)
        end
    end
    local any = self.listeners["*"]
    if any then
        for _, fn in ipairs(any) do
            pcall(fn, params, method)
        end
    end
end

function BiDi:_handle_intercept(params)
    if not (params and params.isBlocked) then
        return
    end
    local req = params.request or {}
    local request_id = req.request
    local url = req.url or ""
    local mock
    for _, entry in ipairs(self.mocks) do
        if url:find(entry.pattern, 1, true) or url:find(entry.pattern) then
            mock = entry
            break
        end
    end
    if mock then
        if mock.fail then
            self:send("network.failRequest", { request = request_id })
            return
        end
        local response = mock.response or {}
        local body = response.body or ""
        local headers = encode_headers(response.headers or {
            ["Content-Type"] = response.content_type or "application/json; charset=utf-8"
        })
        -- ensure array encoding
        if #headers == 0 then
            headers[0] = 0
        end
        self:send("network.provideResponse", {
            request = request_id,
            statusCode = response.status_code or response.status or 200,
            reasonPhrase = response.reason or "OK",
            headers = headers,
            body = { type = "string", value = body },
        })
    else
        self:send("network.continueRequest", { request = request_id })
    end
end

function BiDi:_dispatch(msg)
    if not msg or not msg.method then
        return
    end
    if msg.method == "log.entryAdded" then
        local params = msg.params or {}
        table.insert(self.logs, params)
        if params.type == "javascript" or params.level == "error" then
            table.insert(self.exceptions, params)
        end
    elseif msg.method == "network.beforeRequestSent" then
        self:_handle_intercept(msg.params)
    end
    self:_emit(msg.method, msg.params)
end

function BiDi:_read_message(timeout)
    if timeout ~= nil then
        self.ws:settimeout(timeout)
    else
        self.ws:settimeout(10)
    end
    local text, err = self.ws:recv_text()
    if not text then
        return nil, err
    end
    local ok, msg = pcall(json.decode, text)
    if not ok then
        return nil, "invalid JSON from BiDi"
    end
    return msg
end

function BiDi:send(method, params)
    local id = self.next_id
    self.next_id = id + 1
    self.ws:settimeout(10)
    self.ws:send_text(json.encode({
        id = id,
        method = method,
        params = params or {},
    }))
    while true do
        local msg, err = self:_read_message(10)
        if not msg then
            error("BiDi command failed (" .. method .. "): " .. tostring(err))
        end
        if msg.id == id then
            if msg.error then
                local err_obj = msg.error
                if type(err_obj) == "table" then
                    error("BiDi error (" .. method .. "): " .. tostring(err_obj.message or err_obj.error))
                end
                error("BiDi error (" .. method .. "): " .. tostring(msg.message or err_obj))
            end
            return msg.result
        elseif msg.method then
            self:_dispatch(msg)
        end
    end
end

function BiDi:subscribe(events, contexts)
    local params = { events = json_array(events) }
    if contexts then
        params.contexts = json_array(contexts)
    end
    return self:send("session.subscribe", params)
end

function BiDi:on(method, fn)
    self.listeners[method] = self.listeners[method] or {}
    table.insert(self.listeners[method], fn)
    return self
end

function BiDi:get_tree()
    return self:send("browsingContext.getTree", {})
end

function BiDi:get_context_id()
    if self.context_id then
        return self.context_id
    end
    local tree = self:get_tree()
    local contexts = tree and tree.contexts
    if contexts and contexts[1] then
        self.context_id = contexts[1].context
        return self.context_id
    end
    error("No BiDi browsing context available")
end

function BiDi:reload(wait)
    return self:send("browsingContext.reload", {
        context = self:get_context_id(),
        wait = wait or "complete",
    })
end

function BiDi:capture_screenshot()
    local res = self:send("browsingContext.captureScreenshot", {
        context = self:get_context_id(),
    })
    return res and res.data
end

local function bidi_remote_value(remote)
    if type(remote) ~= "table" then
        return remote
    end
    if remote.type == "undefined" or remote.type == "null" then
        return nil
    end
    if remote.value ~= nil then
        return remote.value
    end
    return remote
end

local function bidi_script_result(res)
    if type(res) ~= "table" then
        return res
    end
    if res.type == "exception" then
        local detail = res.exceptionDetails or {}
        error("BiDi script exception: " .. tostring(detail.text or "unknown"))
    end
    return bidi_remote_value(res.result or res)
end

local function bidi_local_value(value)
    local t = type(value)
    if value == nil then
        return { type = "undefined" }
    end
    if t == "boolean" then
        return { type = "boolean", value = value }
    end
    if t == "number" then
        return { type = "number", value = value }
    end
    if t == "string" then
        return { type = "string", value = value }
    end
    error("BiDi local value type not supported: " .. t)
end

function BiDi:evaluate(expression, opts)
    opts = opts or {}
    local res = self:send("script.evaluate", {
        expression = expression,
        target = { context = opts.context or self:get_context_id() },
        awaitPromise = opts.await_promise == true,
        resultOwnership = opts.result_ownership or "none",
    })
    return bidi_script_result(res)
end

function BiDi:call_function(declaration, args, opts)
    opts = opts or {}
    local arguments = {}
    if type(args) == "table" then
        for i, value in ipairs(args) do
            arguments[i] = bidi_local_value(value)
        end
    end
    local res = self:send("script.callFunction", {
        functionDeclaration = declaration,
        arguments = json_array(arguments),
        this = { type = "undefined" },
        target = { context = opts.context or self:get_context_id() },
        awaitPromise = opts.await_promise == true,
        resultOwnership = opts.result_ownership or "none",
    })
    return bidi_script_result(res)
end

function BiDi:navigate(url, wait)
    return self:send("browsingContext.navigate", {
        context = self:get_context_id(),
        url = url,
        wait = wait or "complete",
    })
end

function BiDi:mock_request(url_pattern, response)
    table.insert(self.mocks, { pattern = url_pattern, response = response or {} })
    local result = self:send("network.addIntercept", {
        phases = json_array({ "beforeRequestSent" }),
        urlPatterns = json_array({
            { type = "string", pattern = url_pattern }
        })
    })
    self.intercept_id = result and result.intercept
    return self
end

function BiDi:fail_request(url_pattern)
    table.insert(self.mocks, { pattern = url_pattern, fail = true })
    local result = self:send("network.addIntercept", {
        phases = json_array({ "beforeRequestSent" }),
        urlPatterns = json_array({
            { type = "string", pattern = url_pattern }
        })
    })
    self.intercept_id = result and result.intercept
    return self
end

function BiDi:remove_intercept(intercept)
    intercept = intercept or self.intercept_id
    if not intercept then
        return
    end
    local res = self:send("network.removeIntercept", { intercept = intercept })
    if intercept == self.intercept_id then
        self.intercept_id = nil
        self.mocks = {}
    end
    return res
end

function BiDi:create_context(url, opts)
    opts = opts or {}
    local res = self:send("browsingContext.create", {
        type = opts.type or "tab",
        referenceContext = opts.reference or self:get_context_id(),
    })
    local id = res and res.context
    if url and id then
        self:send("browsingContext.navigate", {
            context = id,
            url = url,
            wait = opts.wait or "complete",
        })
    end
    return id
end

function BiDi:close_context(context)
    context = context or self.context_id
    local res = self:send("browsingContext.close", { context = context })
    if context == self.context_id then
        self.context_id = nil
    end
    return res
end

function BiDi:activate(context)
    return self:send("browsingContext.activate", {
        context = context or self:get_context_id(),
    })
end

function BiDi:get_cookies(opts)
    opts = opts or {}
    return self:send("storage.getCookies", {
        partition = {
            type = "context",
            context = opts.context or self:get_context_id(),
        }
    })
end

function BiDi:set_cookie(cookie, opts)
    opts = opts or {}
    cookie = cookie or {}
    return self:send("storage.setCookie", {
        cookie = {
            name = cookie.name,
            value = {
                type = "string",
                value = tostring(cookie.value or ""),
            },
            domain = cookie.domain,
            path = cookie.path or "/",
            httpOnly = cookie.http_only or cookie.httpOnly,
            secure = cookie.secure,
            sameSite = cookie.same_site or cookie.sameSite,
        },
        partition = {
            type = "context",
            context = opts.context or self:get_context_id(),
        }
    })
end

function BiDi:click_at(x, y)
    local moves = json_array({
        { type = "pointerMove", x = x, y = y, duration = 0, origin = "viewport" },
        { type = "pointerDown", button = 0 },
        { type = "pointerUp", button = 0 },
    })
    return self:send("input.performActions", {
        context = self:get_context_id(),
        actions = json_array({
            {
                type = "pointer",
                id = "bidi-mouse",
                parameters = { pointerType = "mouse" },
                actions = moves,
            }
        })
    })
end

function BiDi:pump(timeout_sec)
    timeout_sec = timeout_sec or 0.3
    local deadline = socket.gettime() + timeout_sec
    while socket.gettime() < deadline do
        local remain = deadline - socket.gettime()
        if remain <= 0 then break end
        local msg, err = self:_read_message(remain)
        if msg then
            self:_dispatch(msg)
        elseif err == "timeout" then
            break
        else
            break
        end
    end
end

function BiDi:wait_for_log(predicate, timeout_sec)
    timeout_sec = timeout_sec or 5
    local deadline = socket.gettime() + timeout_sec
    local function match()
        for _, entry in ipairs(self.logs) do
            if predicate(entry) then
                return entry
            end
        end
        return nil
    end
    local found = match()
    if found then return found end
    while socket.gettime() < deadline do
        local remain = deadline - socket.gettime()
        local msg, err = self:_read_message(remain)
        if msg then
            self:_dispatch(msg)
            found = match()
            if found then return found end
        elseif err == "timeout" then
            break
        else
            break
        end
    end
    error("Timeout waiting for BiDi log event")
end

function BiDi:console_logs()
    self:pump(0.05)
    return self.logs
end

function BiDi:js_exceptions()
    self:pump(0.05)
    return self.exceptions
end

function BiDi:close()
    if self.ws then
        pcall(function() self.ws:close() end)
        self.ws = nil
    end
end

return BiDi
