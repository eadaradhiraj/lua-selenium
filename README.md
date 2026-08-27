# lua-selenium

A Lua client for the [W3C WebDriver](https://www.w3.org/TR/webdriver2/) protocol. It can spawn ChromeDriver for you, talk HTTP to the classic endpoints, and optionally open a BiDi WebSocket for console logs and network mocks.

This tree is **unreleased** (`luaselenium-scm-1.rockspec`). APIs can still change.

## Requirements

- Lua 5.3+ (developed on 5.5)
- LuaRocks modules: `luasocket`, `lunajson`, `luasec`
- `chromedriver` on `PATH` (Chromium on Arch ships it). Firefox live tests also need `firefox` + `geckodriver`.

```bash
sudo pacman -S lua luarocks chromium
sudo luarocks install luasocket lunajson luasec
```

## Quick start

```lua
local WebDriver = require("webdriver")
local By = WebDriver.By

local driver = WebDriver.new({ headless = true })  -- starts chromedriver
driver:get("https://example.com")
print(driver:find_element(By.css("h1")):get_text())
driver:quit()
```

`example.lua` in this repo does the same against a `data:` URL so it works offline:

```bash
lua example.lua
```

## Common options

```lua
WebDriver.new({
    headless = true,
    browser_name = "chrome",   -- firefox, safari, edge
    bidi = true,               -- WebSocket BiDi (console, mock_request)
    server_url = "http://127.0.0.1:9515",  -- attach instead of spawning
    args = { "--no-sandbox" },
})
```

Timeouts: `wait_until` and `implicitly_wait` / `set_page_load_timeout` / `set_script_timeout` use **seconds**. `set_timeouts({ implicit = 2000 })` is raw W3C **milliseconds**.

Closed shadow trees (Chrome/Edge): `host:shadow_root({ pierce = true })` or `host:find_in_shadow(By.id("inside"))`. Open roots work with `host:shadow_root()` on all browsers.

Generate a page object from the current DOM:

```lua
local gen = driver:generate_page({ name = "LoginPage", out = "pages/login_page.lua" })
local LoginPage = require("pages.login_page")  -- or loadfile the path
```

## Tests

```bash
lua run_tests.lua          -- local fixture suite (no Wikipedia)
lua test.lua               -- Wikipedia smoke; skips if offline
```

## Install from this tree

```bash
luarocks make luaselenium-scm-1.rockspec
```

No numbered version has been published to LuaRocks yet.

## Layout

| File | Role |
|---|---|
| `webdriver.lua` | Client: session, locators, actions, waits, POM |
| `webdriver_bidi.lua` / `webdriver_ws.lua` | BiDi over WebSockets |
| `webdriver_test.lua` | Assertions + `with_local_session` |
| `spec.MD` | Done / remaining / iteration log |
