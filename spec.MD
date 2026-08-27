# Project Specification: Lua WebDriver Client

---

## Part 1: Steps Completed So Far (Current State)

### 1. Environment & Runtime Setup
* **Arch Linux Core Tooling**: Configured system packages (`lua`, `luarocks`, `base-devel`, and `chromium` which bundles `chromedriver`).
* **Lua Ecosystem Modules**: Integrated core rocks via LuaRocks:
  * `luasocket` – TCP networking, HTTP client, and `mime` base64 decoder.
  * `luasec` – HTTPS support.
  * `lunajson` – JSON encoder/decoder.

### 2. Low-Level WebDriver Protocol Engine
* **W3C REST HTTP Client**: Implemented a request dispatcher mapping directly to the W3C WebDriver REST specification (`POST`, `GET`, `DELETE`).
* **Error Handling**: Implemented W3C error unwrapping to bubble up readable browser errors (e.g., *element not interactable*, *no such element*).
* **JSON Array/Object Serialization Fix**: Resolved Lua table ambiguity where empty tables `{}` serialize as JSON objects `{}` instead of JSON arrays `[]`. Added `json_array()` with `[0] = 0` array length metadata so endpoints like `/execute/sync` and `/value` receive compliant JSON lists.

### 3. Session & Lifecycle Management
* **Session Initialization**: `POST /session` with standard `alwaysMatch` capability configuration.
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
* **Waits**: `wait_until` plus `WebDriver.EC` (`title_is`, `presence_of_element`, `visibility_of_element`, `element_to_be_clickable`, `alert_is_present`, …).
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
* **Timeout Configuration**: `get_timeouts` / `set_timeouts` for implicit, page load, and script timeouts (milliseconds).

### 7. Advanced Interaction & Driver Automation (Phase 2)
* **W3C Actions API**: Fluent `driver:actions()` chain (`move_to`, `click`, `double_click`, `context_click`, `drag_and_drop`, `key_down` / `key_up`, `send_keys`) posted to `/session/{id}/actions`. Shortcuts: `element:hover()`, `:double_click()`, `:context_click()`, `driver:drag_and_drop(src, dest)`. `WebDriver.Keys` holds W3C key code points.
* **Automatic Driver Lifecycle**: If no `server_url` is given, spawn `chromedriver` / `geckodriver` / `safaridriver` on a free port. The process is tied to a pipe so `quit()`, `__close` (`<close>`), and GC of the driver object kill it.
* **Multi-Browser Capabilities**: `goog:chromeOptions`, `moz:firefoxOptions`, `safari:options`, `ms:edgeOptions`, plus `bstack:options` / `sauce:options`. Remote URLs via `provider = "browserstack"|"saucelabs"`, `grid_url`, or `username`/`access_key`. HTTPS via luasec.

### 8. Modern Tooling & Ecosystem (Phase 3)
* **WebDriver BiDi**: Session capability `webSocketUrl: true` (`bidi = true`). Minimal WebSocket client plus JSON-RPC BiDi commands. `driver:bidi()` for `subscribe`, `on`, `navigate`, console logs, JS exceptions, and `mock_request` network interception.
* **CDP**: `driver:execute_cdp(cmd, params)` via ChromeDriver `/goog/cdp/execute`.
* **Test runners**: `webdriver_test` assertions (`equal`, `contains`, `matches`), `with_driver`, and `with_local_session` (HTTP fixture + session). Busted example in `spec/webdriver_spec.lua`.
* **Page Object Model**: `driver:page({ locators })` and `Page.extend({ locators })` with `el` / `els` / `type` / `click` / `component` for nested regions.
* **Packaging**: unversioned `luaselenium-scm-1.rockspec` (`luarocks make`). No release version until the API is stable.

---

## Part 2: Yet to be done

Still open; no release version until these are settled or explicitly deferred.

* **LuaRocks publish**: `luarocks upload` of a numbered rock (blocked on API stability + account). SCM rockspec only for now.
* **Firefox/Safari live sessions**: capability builders exist; only Chrome is exercised in `run_tests.lua`.
* **Closed shadow internals**: we assert closed roots are not inspectable; no pierce/slot API.
* **POM scaffolding**: no page-object generator; `Page.extend({ url })` is manual.

```text
+-------------------------------------------------------------------------------+
|                               Lua-Selenium Stack                              |
+-------------------------------------------------------------------------------+
| High-Level:   Page objects | Test helpers (webdriver_test / Busted fixture)   |
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
**Yet to do:** Items in Part 2 (LuaRocks upload, Firefox/Safari live runs, closed-shadow pierce, POM generator).