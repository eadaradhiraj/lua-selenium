-- RFC 6455 client for WebDriver BiDi (JSON text frames + ping/pong).
-- Handshake checks Sec-WebSocket-Accept. Close frames carry a code/reason.
-- RSV bits and fragmented control frames are rejected. Not a general library:
-- no subprotocols, permessage-deflate, or binary API. LuaSocket (ws) + luasec (wss).
local socket = require("socket")
local mime = require("mime")

local WebSocket = {}
WebSocket.__index = WebSocket

local WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

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

local function be32(n)
    n = n & 0xFFFFFFFF
    return string.char(
        (n >> 24) & 0xFF,
        (n >> 16) & 0xFF,
        (n >> 8) & 0xFF,
        n & 0xFF
    )
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

local function rol32(n, b)
    n = n & 0xFFFFFFFF
    return ((n << b) | (n >> (32 - b))) & 0xFFFFFFFF
end

local function sha1(data)
    local h0, h1, h2, h3, h4 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0
    local bit_len = #data * 8
    local msg = data .. "\x80"
    while (#msg % 64) ~= 56 do
        msg = msg .. "\0"
    end
    msg = msg .. be32(math.floor(bit_len / 0x100000000)) .. be32(bit_len % 0x100000000)
    for i = 1, #msg, 64 do
        local w = {}
        for j = 0, 15 do
            local o = i + j * 4
            w[j] = (msg:byte(o) << 24) | (msg:byte(o + 1) << 16) | (msg:byte(o + 2) << 8) | msg:byte(o + 3)
        end
        for j = 16, 79 do
            w[j] = rol32(w[j - 3] ~ w[j - 8] ~ w[j - 14] ~ w[j - 16], 1)
        end
        local a, b, c, d, e = h0, h1, h2, h3, h4
        for j = 0, 79 do
            local f, k
            if j < 20 then
                f = (b & c) | ((~b) & d)
                k = 0x5A827999
            elseif j < 40 then
                f = b ~ c ~ d
                k = 0x6ED9EBA1
            elseif j < 60 then
                f = (b & c) | (b & d) | (c & d)
                k = 0x8F1BBCDC
            else
                f = b ~ c ~ d
                k = 0xCA62C1D6
            end
            local temp = (rol32(a, 5) + f + e + k + w[j]) & 0xFFFFFFFF
            e, d, c, b, a = d, c, rol32(b, 30), a, temp
        end
        h0 = (h0 + a) & 0xFFFFFFFF
        h1 = (h1 + b) & 0xFFFFFFFF
        h2 = (h2 + c) & 0xFFFFFFFF
        h3 = (h3 + d) & 0xFFFFFFFF
        h4 = (h4 + e) & 0xFFFFFFFF
    end
    return be32(h0) .. be32(h1) .. be32(h2) .. be32(h3) .. be32(h4)
end

local function b64(raw)
    return (mime.b64(raw):gsub("%s+", ""))
end

function WebSocket.sec_websocket_accept(key)
    return b64(sha1(key .. WS_GUID))
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

    local key = b64(random_bytes(16))
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

    local got_accept
    for i = 2, #headers do
        local name, value = headers[i]:match("^([^:]+):%s*(.-)%s*$")
        if name and name:lower() == "sec-websocket-accept" then
            got_accept = value
            break
        end
    end
    local expected = WebSocket.sec_websocket_accept(key)
    if got_accept ~= expected then
        sock:close()
        error("WebSocket handshake Accept mismatch (expected " ..
            expected .. ", got " .. tostring(got_accept) .. ")")
    end

    return setmetatable({
        sock = sock,
        buf = "",
        _close_code = nil,
        _close_reason = nil,
        _close_sent = false,
    }, WebSocket)
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

function WebSocket:close_status()
    return self._close_code, self._close_reason
end

function WebSocket:_note_close(payload)
    if payload and #payload >= 2 then
        self._close_code = from_be(payload:sub(1, 2))
        self._close_reason = payload:sub(3)
    else
        self._close_code = 1005
        self._close_reason = ""
    end
end

function WebSocket:_send_close(code, reason)
    if self._close_sent then
        return
    end
    self._close_sent = true
    code = code or 1000
    reason = reason or ""
    if #reason > 123 then
        reason = reason:sub(1, 123)
    end
    self:_send_frame(0x8, be16(code) .. reason)
end

function WebSocket:recv_text()
    local collected = {}
    while true do
        local hdr, err = self:_recv_exact(2)
        if not hdr then return nil, err end
        local b1, b2 = hdr:byte(1, 2)
        local fin = (b1 & 0x80) ~= 0
        local rsv = b1 & 0x70
        local opcode = b1 & 0x0F
        local masked = (b2 & 0x80) ~= 0
        local len = b2 & 0x7F
        local control = opcode == 0x8 or opcode == 0x9 or opcode == 0xA

        if rsv ~= 0 then
            return nil, "protocol error (RSV set)"
        end
        if control and not fin then
            return nil, "protocol error (fragmented control frame)"
        end
        if control and len > 125 then
            return nil, "protocol error (control frame too long)"
        end

        if len == 126 then
            local ext, e2 = self:_recv_exact(2)
            if not ext then return nil, e2 end
            len = from_be(ext)
        elseif len == 127 then
            local ext, e2 = self:_recv_exact(8)
            if not ext then return nil, e2 end
            len = from_be(ext)
        end
        if control and len > 125 then
            return nil, "protocol error (control frame too long)"
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
            self:_note_close(payload)
            if payload and #payload >= 2 then
                pcall(function() self:_send_close(self._close_code, self._close_reason) end)
            else
                pcall(function() self:_send_close(1000, "") end)
            end
            return nil, "closed"
        elseif opcode == 0x9 then
            self:send_pong(payload)
        elseif opcode == 0xA then
            -- pong
        elseif opcode == 0x1 or opcode == 0x0 then
            if opcode == 0x0 and #collected == 0 then
                return nil, "protocol error (orphan continuation)"
            end
            collected[#collected + 1] = payload
            if fin then
                return table.concat(collected)
            end
        else
            return nil, "protocol error (unknown opcode " .. tostring(opcode) .. ")"
        end
    end
end

function WebSocket:settimeout(sec)
    self.sock:settimeout(sec)
end

function WebSocket:close(code, reason)
    pcall(function() self:_send_close(code or 1000, reason or "") end)
    pcall(function() self.sock:close() end)
end

return WebSocket
