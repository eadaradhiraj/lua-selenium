# lua-selenium

A Lua client for the [W3C WebDriver](https://www.w3.org/TR/webdriver2/) protocol. It can spawn ChromeDriver for you, talk HTTP to the classic endpoints, and optionally open a BiDi WebSocket for console logs and network mocks.

Install with LuaRocks from this GitHub repo (nothing is published to luarocks.org).

## Requirements

To **install** (`luarocks install git+https://…`):

- Lua 5.3+ (developed on 5.5)
- LuaRocks and **git**
- A C compiler and OpenSSL headers (`base-devel` + `openssl` on Arch) so LuaRocks can build `luasocket` and `luasec`
- `lunajson` is pure Lua; LuaRocks fetches all three rocks from luarocks.org as dependencies — you do not install them by hand

To **run** a session (auto-spawn):

- A browser **and** its driver on `PATH`: Chromium/Chrome + `chromedriver`, or Firefox + `geckodriver`
- POSIX `sh` (Linux/macOS). The driver is spawned with a shell pipe

`luasec` is only used for `https://` remote grids and `wss://` BiDi. Local `http://127.0.0.1` ChromeDriver talks HTTP. `utf8`, `ltn12`, and `mime` come with Lua 5.3+ / luasocket. Busted is not required.

```bash
sudo pacman -S lua luarocks git base-devel openssl chromium chromedriver
luarocks install git+https://github.com/eadaradhiraj/lua-selenium.git
```

Firefox tests also need `firefox` and `geckodriver`. The installed rock is the library only; `lua tests/run.lua` needs a git clone of this repo.

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

LuaRocks clones the git source; there is no luarocks.org upload.

```bash
luarocks install git+https://github.com/eadaradhiraj/lua-selenium.git
luarocks make luaselenium-scm-1.rockspec
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
