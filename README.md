# lua-selenium

A Lua client for the [W3C WebDriver](https://www.w3.org/TR/webdriver2/) protocol. It can spawn ChromeDriver for you, talk HTTP to the classic endpoints, and optionally open a BiDi WebSocket for console logs and network mocks.

Install from LuaRocks (`luaselenium 0.1.0`) or from this tree with `luarocks make`.

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

`examples/example.lua` does the same against a `data:` URL so it works offline:

```bash
lua examples/example.lua
```

## Common options

```lua
WebDriver.new({
    headless = true,
    browser_name = "chrome",   -- firefox, safari, edge
    bidi = true,               -- WebSocket BiDi (Chrome and Firefox: console, mock_request)
    server_url = "http://127.0.0.1:9515",  -- attach instead of spawning
    args = { "--no-sandbox" },
    download_dir = "/tmp/downloads",
    user_data_dir = "/tmp/chrome-profile",  -- Chrome/Edge
    page_load_strategy = "normal",
})
```

Timeouts: `wait_until` and `implicitly_wait` / `set_page_load_timeout` / `set_script_timeout` use **seconds**. `set_timeouts({ implicit = 2000 })` is raw W3C **milliseconds**. `WebDriver.EC` includes `text_to_be_present_in_element`, `text_to_be_present_in_element_value`, `frame_to_be_available_and_switch_to_it` (locator, index, or element), and `number_of_windows_to_be`, plus title/url/visibility helpers.

`driver:wait_for_download("report.pdf")` polls `download_dir` until a finished file appears. `driver:scroll(0, 400)` is the W3C wheel action. `driver:status()` is `GET /status`.

Closed shadow trees (Chrome/Edge): `host:shadow_root({ pierce = true })` or `host:find_in_shadow(By.id("inside"))`. Open roots work with `host:shadow_root()` on all browsers.

Generate a page object from the current DOM:

```lua
local gen = driver:generate_page({ name = "LoginPage", out = "pages/login_page.lua" })
local LoginPage = require("pages.login_page")  -- or loadfile the path
```

This client covers the classic W3C WebDriver HTTP command set. WebDriver BiDi is a separate spec; only console logs, exceptions, and `mock_request` are implemented. `element:is_displayed()` is a JSON Wire leftover (W3C dropped it).

## Tests

Run from the repository root:

```bash
lua tests/run.lua                        -- Chrome suites, then Firefox when geckodriver is present
LUA_SELENIUM_BROWSER=firefox lua tests/api.lua
lua examples/wikipedia.lua               -- smoke; skips if offline
```

## Install

```bash
luarocks make luaselenium-0.1.0-1.rockspec
# development tree:
luarocks make luaselenium-scm-1.rockspec
```

`v0.1.0` is tagged. Upload to LuaRocks.org needs an API key from [luarocks.org/settings](https://luarocks.org/settings/api-keys):

```bash
luarocks upload luaselenium-0.1.0-1.rockspec --api-key=YOUR_KEY
```

## Layout

| Path | Role |
|---|---|
| `src/webdriver.lua` | Client: session, locators, actions, waits, POM |
| `src/webdriver/ws.lua` / `bidi.lua` | BiDi over WebSockets (`require("webdriver.ws")`) |
| `src/webdriver/test.lua` | Assertions + `with_local_session` (`require("webdriver.test")`) |
| `tests/` | Local Chrome/Firefox suite and HTML fixture |
| `examples/` | Offline smoke and optional Wikipedia scripts |
| `docs/SPEC.md` | Done / remaining / iteration log |
