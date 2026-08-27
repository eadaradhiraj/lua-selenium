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
    <input id="name-field" name="fullname" type="text" value="initial" />
    <input id="chk" type="checkbox" checked />
    <button id="disabled-btn" disabled>nope</button>
    <select id="color">
      <option value="r">Red</option>
      <option value="g" selected>Green</option>
      <option value="b">Blue</option>
    </select>
  </form>
  <div id="hidden-box" style="display:none">secret</div>
  <input id="file-input" type="file" />
  <form id="login-form">
    <input id="user" />
    <input id="pass" type="password" />
    <button id="login-btn" type="button">Log in</button>
    <p id="login-status"></p>
  </form>
  <div id="shadow-host"></div>
  <div id="closed-host"></div>
  <div id="slot-host"></div>
  <form id="submit-form" action="#" onsubmit="window.__submitted=true; return false;">
    <input id="submit-field" name="q" />
    <button id="submit-btn" type="submit">go</button>
  </form>
  <iframe id="frame1" srcdoc="<!DOCTYPE html><html><body><p id='inside'>in frame</p></body></html>"></iframe>
  <button id="alert-btn" onclick="alert('hello-alert')">Alert</button>
  <button id="confirm-btn" onclick="confirm('sure?')">Confirm</button>
  <button id="prompt-btn" onclick="window.__promptVal = prompt('enter');">Prompt</button>
  <div id="hover-target" style="width:120px;padding:8px;background:#eee;">hover me</div>
  <div id="dbl-target" style="width:120px;padding:8px;background:#ddd;">double click</div>
  <div id="ctx-target" style="width:120px;padding:8px;background:#ccc;">right click</div>
  <div id="shift-target" style="width:120px;padding:8px;background:#bbb;">shift click</div>
  <div id="src" style="position:absolute;left:20px;top:420px;width:48px;height:48px;background:#c00;color:#fff;">src</div>
  <div id="dst" style="position:absolute;left:220px;top:420px;width:96px;height:96px;background:#00c;color:#fff;">dst</div>
  <script>
    window.__api = null;
    document.getElementById('login-btn').addEventListener('click', function() {
      var u = document.getElementById('user').value;
      var p = document.getElementById('pass').value;
      document.getElementById('login-status').textContent =
        (u === 'lua' && p === 'rocks') ? 'welcome' : 'denied';
    });
    (function() {
      var host = document.getElementById('shadow-host');
      var root = host.attachShadow({ mode: 'open' });
      root.innerHTML = '<p id="shadow-text">inside shadow</p><button id="shadow-btn">press</button>';
      root.getElementById('shadow-btn').addEventListener('click', function() {
        host.dataset.clicked = '1';
      });
    })();
    (function() {
      var closed = document.getElementById('closed-host');
      var closedRoot = closed.attachShadow({ mode: 'closed' });
      closedRoot.innerHTML = '<p id="closed-text">inside closed</p><button id="closed-btn">press closed</button>';
      closedRoot.getElementById('closed-btn').addEventListener('click', function() {
        closed.dataset.clicked = '1';
      });
    })();
    (function() {
      var host = document.getElementById('slot-host');
      host.innerHTML = '<span slot="title" id="slotted-title">hello slot</span>';
      var root = host.attachShadow({ mode: 'open' });
      root.innerHTML = '<slot id="title-slot" name="title">fallback</slot>';
    })();
    document.getElementById('hover-target').addEventListener('mouseover', function() {
      this.dataset.hovered = '1';
    });
    document.getElementById('dbl-target').addEventListener('dblclick', function() {
      this.dataset.dbl = '1';
    });
    document.getElementById('ctx-target').addEventListener('contextmenu', function(e) {
      e.preventDefault();
      this.dataset.ctx = '1';
    });
    document.getElementById('shift-target').addEventListener('click', function(e) {
      this.dataset.shift = e.shiftKey ? '1' : '0';
    });
    (function() {
      var src = document.getElementById('src');
      var dst = document.getElementById('dst');
      var dragging = false;
      src.addEventListener('mousedown', function() { dragging = true; src.dataset.down = '1'; });
      dst.addEventListener('mouseover', function() { if (dragging) dst.dataset.over = '1'; });
      dst.addEventListener('mouseup', function() { if (dragging) dst.dataset.dropped = '1'; dragging = false; });
      document.addEventListener('mouseup', function() { dragging = false; });
    })();
  </script>
</body>
</html>]]

while true do
    local client = server:accept()
    if client then
        client:settimeout(2)
        local request_line = client:receive("*l")
        local path = "/"
        if request_line then
            path = request_line:match("^%w+ ([^%s?]+)") or "/"
        end
        while true do
            local line = client:receive("*l")
            if not line or line == "" then break end
        end
        local body, content_type
        if path == "/api.json" then
            body = '{"source":"real"}'
            content_type = "application/json; charset=utf-8"
        else
            body = html
            content_type = "text/html; charset=utf-8"
        end
        client:send(
            "HTTP/1.1 200 OK\r\n" ..
            "Content-Type: " .. content_type .. "\r\n" ..
            "Content-Length: " .. tostring(#body) .. "\r\n" ..
            "Connection: close\r\n\r\n" ..
            body
        )
        client:close()
    end
end
