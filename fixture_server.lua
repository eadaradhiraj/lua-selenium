local socket = require("socket")

local port = tonumber(arg[1]) or 0
local server = assert(socket.bind("127.0.0.1", port))
local _, bound_port = server:getsockname()
io.stdout:write(tostring(bound_port) .. "\n")
io.stdout:flush()

local html = [[<!DOCTYPE html>
<html>
<head><title>Lua Selenium Fixture</title></head>
<body>
  <h1 id="title">Fixture Home</h1>
  <div id="parent" data-role="container">
    <span class="child" id="nested">nested text</span>
    <span class="child">second child</span>
  </div>
  <a id="wiki-link" href="#section">Lua Language</a>
  <form>
    <input id="searchInput" name="q" type="text" value="" />
  </form>
  <iframe id="frame1" srcdoc="<!DOCTYPE html><html><body><p id='inside'>in frame</p></body></html>"></iframe>
  <button id="alert-btn" onclick="alert('hello-alert')">Alert</button>
  <button id="confirm-btn" onclick="confirm('sure?')">Confirm</button>
  <button id="prompt-btn" onclick="window.__promptVal = prompt('enter');">Prompt</button>
</body>
</html>]]

while true do
    local client = server:accept()
    if client then
        client:settimeout(2)
        client:receive("*l")
        while true do
            local line = client:receive("*l")
            if not line or line == "" then break end
        end
        local body = html
        client:send(
            "HTTP/1.1 200 OK\r\n" ..
            "Content-Type: text/html; charset=utf-8\r\n" ..
            "Content-Length: " .. tostring(#body) .. "\r\n" ..
            "Connection: close\r\n\r\n" ..
            body
        )
        client:close()
    end
end
