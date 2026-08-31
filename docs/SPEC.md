# Project Specification: Lua WebDriver Client

---

## Part 1: Steps Completed So Far (Current State)

### 1. Environment & Runtime Setup
* **Arch Linux Core Tooling**: Configured system packages (`lua`, `luarocks`, `base-devel`, `chromium` / `chromedriver`, and `firefox` / `geckodriver` for the Firefox pass).
* **Lua Ecosystem Modules**: Integrated core rocks via LuaRocks:
  * `luasocket` – TCP networking, HTTP client, and `mime` base64 decoder.
  * `luasec` – HTTPS support.
  * `lunajson` – JSON encoder/decoder.

### 2. Low-Level WebDriver Protocol Engine
* **W3C REST HTTP Client**: Implemented a request dispatcher mapping directly to the W3C WebDriver REST specification (`POST`, `GET`, `DELETE`).
* **Error Handling**: Implemented W3C error unwrapping to bubble up readable browser errors (e.g., *element not interactable*, *no such element*).
* **JSON Array/Object Serialization Fix**: Resolved Lua table ambiguity where empty tables `{}` serialize as JSON objects `{}` instead of JSON arrays `[]`. Added `json_array()` with `[0] = 0` array length metadata so endpoints like `/execute/sync` and `/value` receive compliant JSON lists.

### 3. Session & Lifecycle Management
* **Session Initialization**: `POST /session` with `alwaysMatch` and optional `firstMatch` (`first_match` option / `WebDriver.build_capabilities`).
* **Headless Mode Support**: Configured `goog:chromeOptions` with `--headless=new`, `--disable-gpu`, and window dimensions.
* **Session Teardown**: `DELETE /session/{id}` to terminate browser instances cleanly.

### 4. DOM Locators & Interactions (`WebElement`)
* **Element Identification**: Support for W3C element locator standard (`element-6066-11e4-a52e-4f735466cecf`).
* **DOM Traversal**: Single element (`find_element`) and list of elements (`find_elements`) via CSS selectors, XPath, etc.
* **Interactive Operations**:
  * `WebElement:click()`
  * `WebElement:send_keys()` with UTF-8 codepoint decomposition for universal driver compatibility.
  * `WebElement:clear()`
  * `WebElement:get_text()`
  * `WebElement:get_attribute(name)` / `get_property(name)` / `get_css_value(name)` / `get_tag_name()` / `get_rect()`
  * `is_displayed()` / `is_enabled()` / `is_selected()`
  * Element screenshots and `shadow_root()`
* **Navigation**: `back()`, `forward()`, `refresh()`, `get_page_source()`, `get_active_element()`.
* **Script bridge**: `execute_script` / `execute_async_script` marshal `WebElement` arguments and wrap element results.
* **Waits**: `wait_until` plus `WebDriver.EC` (`title_is`, `presence_of_element`, `visibility_of_element`, `element_to_be_clickable`, `alert_is_present`, `text_to_be_present_in_element`, `text_to_be_present_in_element_value`, `frame_to_be_available_and_switch_to_it`, `number_of_windows_to_be`, …).
* **`<select>` helper**: `driver:select(element)` with `select_by_visible_text` / `select_by_value` / `select_by_index`.

### 5. Advanced Utilities
* **JavaScript Evaluation**: `driver:execute_script(script, args)` to run arbitrary synchronous JS and return values back to Lua.
* **Explicit Polling/Wait Engine**: `driver:wait_until(condition_func, timeout, interval)` to eliminate flaky hardcoded sleep timers.
* **Binary Screenshot Engine**: `driver:save_screenshot(filename)` via `GET /session/{id}/screenshot` with Base64-to-PNG binary decoding.

### 6. Core API Completeness (Phase 1)
* **Locator Strategy Class (`By`)**: `By.css()`, `By.xpath()`, `By.id()`, `By.tag_name()`, `By.name()`, `By.class_name()`, `By.link_text()`, `By.partial_link_text()`. `find_element` / `find_elements` accept either a `By.*` locator or the original `(using, value)` pair.
* **Nested Element Finding**: `WebElement:find_element(...)` and `WebElement:find_elements(...)` via `POST /session/{id}/element/{el_id}/element[s]`.
* **Window & Tab Management**: current/all handles, `new_window`, `switch_to_window`, `close_window`, `set_window_size` / `set_window_rect`, `maximize_window`.
* **Frame / iFrame Switching**: `switch_to_frame` (element, index, or default), `switch_to_parent_frame`, `switch_to_default_content`.
* **Alert / Dialog Handling**: `driver:alert():get_text()`, `:accept()`, `:dismiss()`, `:send_keys()`.
* **Cookie Engine**: `get_cookies`, `get_cookie`, `add_cookie`, `delete_cookie`, `delete_all_cookies`.
* **Timeout Configuration**: `get_timeouts` / `set_timeouts` for implicit, page load, and script timeouts (milliseconds). Session create: `page_load_strategy`, `unhandled_prompt_behavior`, `proxy`, `strict_file_interactability`, `platform_name`, `timeouts`.
* **Status / a11y**: `driver:status()` / `WebDriver.get_status(url)` (`GET /status`). `element:get_computed_role()` / `get_computed_label()`.

### 7. Advanced Interaction & Driver Automation (Phase 2)
* **W3C Actions API**: Fluent `driver:actions()` chain (`move_to`, `click`, `double_click`, `context_click`, `drag_and_drop`, `key_down` / `key_up`, `send_keys`, `scroll`) posted to `/session/{id}/actions`. Pointer, key, and wheel sources share ticks. Shortcuts: `element:hover()`, `:double_click()`, `:context_click()`, `driver:drag_and_drop(src, dest)`, `driver:scroll(dx, dy)`. `WebDriver.Keys` holds W3C key code points.
* **Automatic Driver Lifecycle**: If no `server_url` is given, spawn `chromedriver` / `geckodriver` / `safaridriver` on a free port. The process is tied to a pipe so `quit()`, `__close` (`<close>`), and GC of the driver object kill it.
* **Multi-Browser Capabilities**: `goog:chromeOptions`, `moz:firefoxOptions`, `safari:options`, `ms:edgeOptions`, plus `bstack:options` / `sauce:options`. Remote URLs via `provider = "browserstack"|"saucelabs"`, `grid_url`, or `username`/`access_key`. HTTPS via luasec.

### 8. Modern Tooling & Ecosystem (Phase 3)
* **WebDriver BiDi**: Session capability `webSocketUrl: true` (`bidi = true`). RFC 6455 client in `src/webdriver/ws.lua`. JSON-RPC via `driver:bidi()`: `subscribe`, `on`, `navigate`, `get_tree`, `create_context` / `close_context` / `activate`, `reload`, `evaluate`, `call_function`, `capture_screenshot`, `click_at`, console logs, JS exceptions, `mock_request` / `fail_request` / `remove_intercept`, `get_cookies` / `set_cookie`. Chrome and Firefox both run this in `tests/phase3.lua`.
* **CDP**: `driver:execute_cdp(cmd, params)` via ChromeDriver `/goog/cdp/execute`.
* **Test runners**: `require("webdriver.test")` assertions (`equal`, `contains`, `matches`), `with_driver`, and `with_local_session` (HTTP fixture + session). Busted example in `spec/webdriver_spec.lua`, run by `tests/run_spec.lua` (no busted package required). Wikipedia examples stay network-optional and are not in `tests/run.lua`.
* **Page Object Model**: `driver:page({ locators })` and `Page.extend({ locators })` with `el` / `els` / `type` / `click` / `component` for nested regions. `Page.generate(driver, { name, url, out })` / `driver:generate_page` scans the current page for stable locators and writes a `Page.extend` module.
* **Shadow DOM**: open roots via `element:shadow_root()`; finds from a shadow root use W3C `POST /shadow/{id}/element` (required by Gecko). Closed roots via `shadow_root({ pierce = true })` / `pierce_shadow()` / `find_in_shadow` (Chromium CDP). Slot helpers: `assigned_slot`, `assigned_nodes`, `assigned_elements`.
* **Live browsers**: `lua tests/run.lua` runs the local suites on Chrome, then again on Firefox (`LUA_SELENIUM_BROWSER=firefox`) when `geckodriver` is on PATH. That includes BiDi console logs and `mock_request`. Shadow-root finds use W3C `/shadow/{id}/element` (Gecko requires it). CDP pierce and `goog:loggingPrefs` stay Chromium-only. Safari is out of scope.
* **Launch / downloads**: `download_dir` (Chrome prefs + CDP `setDownloadBehavior`, Firefox `moz:firefoxOptions.prefs`). `user_data_dir` (Chrome/Edge `--user-data-dir`). `firefox_prefs` / `chrome_prefs`. `driver:wait_for_download(name, timeout)` waits for a finished file (ignores `.crdownload` / `.part`, requires stable non-empty size). POSIX spawn uses `sh`; Windows uses `start /b` (`WebDriver.wrap_spawn_command`).
* **CI / editors**: GitHub Actions tests Lua 5.4 and 5.5 with `actions/checkout@v5`. Edge `api.lua` runs when `msedgedriver` and Edge are on PATH. `.luarc.json` plus `---@class` annotations. Wikipedia examples stay out of `tests/run.lua`.
* **Storage / permissions / WebAuthn**: `localStorage` and `sessionStorage` get/set/clear. `set_permission` (`POST /session/{id}/permissions`). Virtual authenticators (`add_virtual_authenticator`, credentials, `set_user_verified`). Drivers that do not implement those endpoints are skipped in tests.
* **Packaging**: `src/webdriver.lua` with submodules `webdriver.ws`, `webdriver.bidi`, `webdriver.test`. SCM rockspec only (`luaselenium-scm-1.rockspec`); install from git. GitHub Actions runs `lua tests/run.lua`. CI Chromium sessions add `--no-sandbox` / `--disable-dev-shm-usage`. Linting is `luacheck` (Lua 5.1 in CI; 5.4/5.5 cannot run luacheck 1.2.0).

---

## Part 2: Yet to be done

Nothing queued for library work.

* **Safari**: out of scope. `safaridriver` is macOS-only.
* **Closed-shadow pierce**: Chromium CDP only; Gecko does not expose closed trees.
* **Pen/touch pointer types**: not implemented (mouse / keyboard / wheel only).

```text
+-------------------------------------------------------------------------------+
|                               Lua-Selenium Stack                              |
+-------------------------------------------------------------------------------+
| High-Level:   Page objects | Test helpers (`webdriver.test` / Busted fixture)    |
| Mid-Level:    Fluent locators (`By`)  |  Actions API  |  Wait conditions      |
| Transport:    W3C REST (HTTP)         |  WebDriver BiDi / CDP (WebSocket)     |
| Engine:       Chromedriver / GeckoDriver / Selenium Grid / Cloud providers    |
+-------------------------------------------------------------------------------+
```

---

## Part 3: Iteration log

What landed each pass, and what was left afterward.

### Iteration 1 — Phase 1 core API
**Done:** `By` locators, nested `find_element`, windows/tabs, frames, alerts, cookies, timeouts. `test_phase1.lua` (36 checks).
**Yet to do:** Actions, auto-spawn, multi-browser, BiDi, packaging.

### Iteration 2 — Phase 2 automation
**Done:** W3C Actions (hover, drag-and-drop, double/right click, modifier keys), managed chromedriver/geckodriver spawn + teardown, Chrome/Firefox/Safari/Edge capability builders, BrowserStack/Sauce/Grid URL + HTTPS.
**Yet to do:** BiDi/CDP, test-runner helpers, rockspec.

### Iteration 3 — Phase 3 tooling
**Done:** WebSocket client, BiDi console/exceptions/network mock, `execute_cdp`, `webdriver_test` assertions + `with_driver`, busted example spec, `luaselenium-0.1.0-1.rockspec`.
**Yet to do:** Unversion until stable; W3C holes (nav, element state, script wrap); Page Objects.

### Iteration 4 — Harden, don't version
**Done:** Replaced numbered rockspec with `luaselenium-scm-1.rockspec`. `json_array` no longer mutates caller tables. HTTP failures and W3C error codes (`[no such element]`). ChromeDriver `--allowed-origins=* --allowed-ips=`. `back`/`forward`/`refresh`/`get_page_source`/`get_active_element`. `execute_async_script`. Element `get_property`/`get_css_value`/`get_tag_name`/`get_rect`/`is_displayed`/`is_enabled`/`is_selected`/screenshots/`shadow_root`. Script argument/result `WebElement` round-trip. `WebDriver.EC` wait conditions. `driver:select()` for `<select>`. `test_api.lua` (28 checks). `test.lua` uses auto-spawn + EC.
**Yet to do:** Page Objects, shadow DOM coverage, file upload, shared fixture helper.

### Iteration 5 — Page objects, shadow DOM, uploads
**Done:** `WebDriver.Page` / `Page.extend` (`el`, `els`, `type`, `click`, `component`, `wait_el`). Open shadow root find + click. File `<input>` via `send_keys(path)`. `with_local_session` + `start_fixture`. `test_pom.lua` (9 checks). `run_tests.lua` local suite (108 checks).
**Yet to do:** Items in Part 2 (LuaRocks upload, `switch_to` sugar, wait-error surfacing, test DRY, offline Wikipedia tests, print/PDF, closed shadow, README).

### Iteration 6 — switch_to, wait errors, extra EC, print, offline skip
**Done:** `driver:switch_to():frame/window/alert/default_content/parent_frame/active_element`. `wait_until` appends the last condition error on timeout. `EC.url_is`, `EC.staleness_of`, `EC.invisibility_of_element`. `print_page()` (W3C PDF). `test.lua` / `test_advanced.lua` skip when Wikipedia is unreachable; advanced test auto-spawns ChromeDriver. `webdriver_test.reachable`. `close_window` retries once (Chrome can stall under load).
**Yet to do:** Items in Part 2 (LuaRocks upload, test DRY, classic logs, closed shadow, POM extras, README).

### Iteration 7 — DRY local suites onto with_local_session
**Done:** `test_phase1.lua`, `test_phase2.lua`, and `test_phase3.lua` start the HTML fixture and Chrome through `webdriver_test.with_local_session` (no hand-rolled pid files). Phase 1 no longer depends on a pre-existing chromedriver on 9515.
**Yet to do:** Items in Part 2 (LuaRocks upload, classic logs, closed shadow, POM extras, README).

### Iteration 8 — daily-driver API, docs, logs
**Done:** README + MIT LICENSE + `example.lua` (offline data-URL smoke). Second-based `implicitly_wait` / `set_page_load_timeout` / `set_script_timeout` (W3C `set_timeouts` stays milliseconds). `get_window_size` / `get_window_position` / `set_window_position`. `WebElement:location`, `:size`, `:submit`. `localStorage` get/set/clear. `get_log` via `/se/log`, `/log`, or BiDi console buffer. `goog:loggingPrefs` when `logging` / `browser_log` is set. Closed shadow roots asserted unreadable. `Page.extend` + `open(url)` covered in tests. Fixed W3C JSON unwrap so `false` / `null` are not replaced by the whole response envelope.
**Yet to do:** Items in Part 2 (LuaRocks upload deferred, Firefox/Safari live runs, closed-shadow pierce, POM generator).

### Iteration 9 — Firefox live, shadow pierce, POM generator
**Done:** Live Firefox session in `test_browsers.lua` (spawn geckodriver, fixture smoke). Safari runs the same smoke when `safaridriver` exists and is skipped on Linux. `WebDriver.has_driver` / `command_exists`. Closed shadow pierce via Chromium CDP (`shadow_root({ pierce = true })`, `pierce_shadow`, `find_in_shadow`) plus `assigned_slot` / `assigned_nodes` / `assigned_elements`. `Page.generate` / `driver:generate_page` writes a `Page.extend` module from ids/names/testids. LuaRocks upload left deferred.
**Yet to do:** Items in Part 2 (LuaRocks deferred; Safari needs macOS; closed pierce is Chromium-only).

### Iteration 10 — Firefox parity on the real suites
**Done:** `LUA_SELENIUM_BROWSER` selects Chrome or Firefox for `with_local_session` / `with_driver`. `run_tests.lua` runs api/phase1/phase2/pom on Firefox after Chrome. Shadow-root `find_element` uses W3C `/shadow/{id}/element` so Gecko can search open trees (Chrome still works via fallback). Closed pierce, CDP, and `goog:loggingPrefs` stay Chromium-only. Safari dropped from the live suite. Firefox passed api (46), phase1 (36), phase2 (24), pom (20).
**Yet to do:** Items in Part 2 (LuaRocks deferred; Safari out of scope; Firefox BiDi; closed pierce Chromium-only).

### Iteration 11 — Firefox BiDi
**Done:** `test_phase3.lua` (console, exceptions, `mock_request`) runs on Firefox; CDP still skipped there. `run_tests.lua` includes it in the Firefox pass. BiDi `session.subscribe` / `network.addIntercept` list fields go through `json_array` so lunajson emits JSON arrays. Firefox phase3: 11 passed.
**Yet to do:** Items in Part 2 (LuaRocks deferred; Safari out of scope; closed pierce Chromium-only).

### Iteration 12 — BiDi WebSocket RFC 6455 hardening
**Done:** Handshake verifies `Sec-WebSocket-Accept` (RFC example vector in `test_phase3.lua`). Close frames send/parse a 2-byte code and reason (`close(code, reason)`, `close_status()`). RSV bits, fragmented control frames, and oversize control frames are rejected. Part 1 BiDi/WebSocket (and env / shadow-find) text brought in line with the code.
**Yet to do:** Items in Part 2 (LuaRocks deferred; Safari out of scope; closed pierce Chromium-only).

### Iteration 13 — W3C leftovers and launch/download config
**Done:** `GET /status` (`driver:status` / `WebDriver.get_status`). `get_computed_role` / `get_computed_label`. Session caps `page_load_strategy`, `unhandled_prompt_behavior`, `proxy`, `strict_file_interactability`. Actions wheel source (`scroll` / `driver:scroll`). `download_dir`, Chrome `user_data_dir`, Firefox prefs, `wait_for_download`. Chrome and Firefox api/phase2 cover status, a11y, scroll, and a real file download.
**Yet to do:** Items in Part 2 (LuaRocks deferred; Safari out of scope; closed pierce Chromium-only; GitHub Actions).

### Iteration 14 — extra expected conditions
**Done:** `EC.text_to_be_present_in_element`, `text_to_be_present_in_element_value`, `frame_to_be_available_and_switch_to_it` (locator, index, or element), `number_of_windows_to_be`. Covered in `test_api.lua` on Chrome and Firefox.
**Yet to do:** Items in Part 2 (LuaRocks deferred; Safari out of scope; closed pierce Chromium-only; GitHub Actions).

### Iteration 15 — defer CI and LuaRocks
**Done:** Part 2 marks GitHub Actions and LuaRocks upload as deferred until explicitly requested. Local verification stays `lua run_tests.lua`.
**Yet to do:** Nothing queued (Safari out of scope; closed pierce Chromium-only).

### Iteration 16 — package layout, CI, LuaRocks 0.1.0
**Done:** Library lives under `src/webdriver.lua` with `webdriver.ws` / `webdriver.bidi` / `webdriver.test`. Tests, examples, and spec moved out of the repo root. Dropped `test_browsers.lua` (covered by the Firefox pass) and the Wikipedia screenshot artifact. GitHub Actions runs `lua tests/run.lua`. Numbered `luaselenium-0.1.0-1.rockspec` and git tag `v0.1.0`. Install is `luarocks install` from git, not luarocks.org.
**Yet to do:** Safari out of scope; closed pierce Chromium-only.

### Iteration 17 — drop numbered rockspec
**Done:** Removed `luaselenium-0.1.0-1.rockspec` and tag `v0.1.0`. SCM rockspec only. Dropped unused `CHROME_PATH` and `LUA_SELENIUM_FIXTURE`.
**Yet to do:** Safari out of scope; closed pierce Chromium-only.

### Iteration 18 — luacheck
**Done:** `.luacheckrc` + `scripts/lint.sh`. CI lint job runs luacheck on Lua 5.1 (1.2.0 crashes on 5.4/5.5). Tightened `switch_to_frame` and WebSocket pong handling for the linter. No `ignore` list: unused `self`, long lines, and busted hook globals are fixed in code. Spec uses `lua53+busted` only.
**Yet to do:** Safari out of scope; closed pierce Chromium-only.

### Iteration 19 — coverage, firstMatch, BiDi, permissions
**Done:** Tests for window position, screenshots, Actions `pause` / `move_by` / `click_and_hold`, and skip-safe `minimize_window` / `fullscreen_window`. `tests/run_spec.lua` runs the Busted example without the busted package; Wikipedia examples stay out of `tests/run.lua`. BiDi `get_tree`, `reload`, `evaluate`, `call_function`, `capture_screenshot`. `firstMatch` via `first_match`. `sessionStorage`. W3C `set_permission` and WebAuthn virtual authenticators. Luacheck stays on Lua 5.1. No Safari, no Gecko closed-shadow pierce, no numbered rock, no luarocks.org upload.
**Yet to do:** Safari out of scope; closed pierce Chromium-only.

### Iteration 20 — BiDi extras, Windows spawn, CI matrix
**Done:** BiDi `create_context` / `close_context`, `fail_request` / `remove_intercept`, `get_cookies` / `set_cookie`, `click_at`. Tests for `move_to_location`, `Actions:release`, cookie `sameSite` / expiry, `print_page` options, WebAuthn `add_credential` / `remove_credential`. Windows spawn/quote/lookup helpers with unit tests. `WebDriver.remote_url` coverage. Edge live `api.lua` when the driver exists. CI Lua 5.4+5.5 and `actions/checkout@v5`. LuaLS `.luarc.json` + class annotations. Wikipedia stays opt-in.
**Yet to do:** Safari out of scope; closed pierce Chromium-only.
