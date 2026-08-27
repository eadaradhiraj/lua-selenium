-- Minimal RFC 6455 WebSocket client (ws / wss) using LuaSocket (+ luasec for TLS).
local socket = require("socket")
local mime = require("mime")

local WebSocket = {}
WebSocket.__index = WebSocket

local function random_bytes(n)
    local t = {}
    for i = 1, n do
        t[i] = string.char(math.random(0, 255))
    end
    return table.concat(t)
end

local function parse_url(url)
    local scheme, host, port, path = url:match("^(wss?)://([^:/]+):(%d+)(/.*)$")
    if host then
        return scheme, host, tonumber(port), path
    end
    scheme, host, path = url:match("^(wss?)://([^:/]+)(/.*)$")
    if host then
        return scheme, host, (scheme == "wss") and 443 or 80, path
    end
    scheme, host, port = url:match("^(wss?)://([^:/]+):(%d+)$")
    if host then
        return scheme, host, tonumber(port), "/"
    end
    scheme, host = url:match("^(wss?)://([^:/]+)$")
    if host then
        return scheme, host, (scheme == "wss") and 443 or 80, "/"
    end
    error("Invalid WebSocket URL: " .. tostring(url))
end

local function mask_payload(payload, key)
    local out = {}
    for i = 1, #payload do
        out[i] = string.char(payload:byte(i) ~ key:byte(((i - 1) % 4) + 1))
    end
    return table.concat(out)
end

local function be16(n)
    return string.char((n >> 8) & 0xFF, n & 0xFF)
end

local function be64(n)
    local bytes = {}
    for i = 7, 0, -1 do
        bytes[#bytes + 1] = string.char((n >> (i * 8)) & 0xFF)
    end
    return table.concat(bytes)
end

local function from_be(str)
    local n = 0
    for i = 1, #str do
        n = (n << 8) | str:byte(i)
    end
    return n
end

function WebSocket.connect(url)
    math.randomseed((math.floor(socket.gettime() * 1000000) + os.time()) % 2147483647)
    local scheme, host, port, path = parse_url(url)
    local sock = assert(socket.tcp())
    sock:settimeout(10)
    local ok, err = sock:connect(host, port)
    if not ok then
        sock:close()
        error("WebSocket connect failed: " .. tostring(err))
    end

    if scheme == "wss" then
        local ssl = require("ssl")
        sock = assert(ssl.wrap(sock, {
            mode = "client",
            protocol = "any",
            verify = "none",
            options = { "all", "no_sslv2", "no_sslv3" },
        }))
        if sock:dohandshake() ~= true then
            error("WebSocket TLS handshake failed")
        end
    end

    local key = mime.b64(random_bytes(16))
    local req = table.concat({
        "GET " .. path .. " HTTP/1.1",
        "Host: " .. host .. ":" .. tostring(port),
        "Upgrade: websocket",
        "Connection: Upgrade",
        "Sec-WebSocket-Key: " .. key,
        "Sec-WebSocket-Version: 13",
        "\r\n",
    }, "\r\n")
    sock:send(req)

    local headers = {}
    while true do
        local line, rerr = sock:receive("*l")
        if not line then
            error("WebSocket handshake failed: " .. tostring(rerr))
        end
        if line == "" then break end
        headers[#headers + 1] = line
    end
    if not (headers[1] and headers[1]:find("101", 1, true)) then
        error("WebSocket handshake rejected: " .. tostring(headers[1]))
    end

    return setmetatable({ sock = sock, buf = "" }, WebSocket)
end

function WebSocket:_recv_exact(n)
    while #self.buf < n do
        local chunk, err, partial = self.sock:receive(n - #self.buf)
        if chunk then
            self.buf = self.buf .. chunk
        elseif partial and #partial > 0 then
            self.buf = self.buf .. partial
        else
            return nil, err
        end
    end
    local data = self.buf:sub(1, n)
    self.buf = self.buf:sub(n + 1)
    return data
end

function WebSocket:_send_frame(opcode, payload)
    payload = payload or ""
    local header
    local mask_bit = 0x80
    if #payload < 126 then
        header = string.char(0x80 | opcode, mask_bit | #payload)
    elseif #payload < 65536 then
        header = string.char(0x80 | opcode, mask_bit | 126) .. be16(#payload)
    else
        header = string.char(0x80 | opcode, mask_bit | 127) .. be64(#payload)
    end
    local key = random_bytes(4)
    self.sock:send(header .. key .. mask_payload(payload, key))
end

function WebSocket:send_text(text)
    self:_send_frame(0x1, text)
end

function WebSocket:send_pong(payload)
    self:_send_frame(0xA, payload or "")
end

function WebSocket:recv_text()
    local collected = {}
    while true do
        local hdr, err = self:_recv_exact(2)
        if not hdr then return nil, err end
        local b1, b2 = hdr:byte(1, 2)
        local opcode = b1 & 0x0F
        local masked = (b2 & 0x80) ~= 0
        local len = b2 & 0x7F
        if len == 126 then
            local ext, e2 = self:_recv_exact(2)
            if not ext then return nil, e2 end
            len = from_be(ext)
        elseif len == 127 then
            local ext, e2 = self:_recv_exact(8)
            if not ext then return nil, e2 end
            len = from_be(ext)
        end
        local mask_key
        if masked then
            mask_key = self:_recv_exact(4)
            if not mask_key then return nil, "closed" end
        end
        local payload = ""
        if len > 0 then
            payload = self:_recv_exact(len)
            if not payload then return nil, "closed" end
            if mask_key then
                payload = mask_payload(payload, mask_key)
            end
        end
        if opcode == 0x8 then
            return nil, "closed"
        elseif opcode == 0x9 then
            self:send_pong(payload)
        elseif opcode == 0xA then
            -- pong
        elseif opcode == 0x1 or opcode == 0x0 then
            collected[#collected + 1] = payload
            if (b1 & 0x80) ~= 0 then
                return table.concat(collected)
            end
        end
    end
end

function WebSocket:settimeout(sec)
    self.sock:settimeout(sec)
end

function WebSocket:close()
    pcall(function() self:_send_frame(0x8, "") end)
    pcall(function() self.sock:close() end)
end

return WebSocket
