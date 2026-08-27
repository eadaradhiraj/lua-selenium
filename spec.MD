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
  * `WebElement:send_keys()` with full string-to-character array decomposition for universal driver compatibility.
  * `WebElement:clear()`
  * `WebElement:get_text()`
  * `WebElement:get_attribute(name)`

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

---

## Part 2: Future Roadmap & Next Steps

### Phase 2: Advanced Interaction & Driver Automation (Mid-Term)

#### 1. W3C Actions API (Advanced Inputs)
* Implement `POST /session/{id}/actions` for complex composite events:
  * Mouse hovering (`moveTo`)
  * Drag-and-drop
  * Double-click & right-click (context menu)
  * Key modifier combinations (e.g., `Ctrl+A`, `Shift+Click`)

#### 2. Automatic Driver Lifecycle Management
* Build a process spawner that:
  1. Checks if a local port (e.g., `9515`) is free.
  2. Spawns `chromedriver` / `geckodriver` automatically via `io.popen` or C-bindings (like `luaposix` / `luv`).
  3. Kills the background driver process automatically when the Lua garbage collector cleans up the driver object (`__gc` metamethod).

#### 3. Multi-Browser Support
* Add explicit capability builders for:
  * **Firefox**: `moz:firefoxOptions` (for `geckodriver`)
  * **Safari**: `safari:options` (for `safaridriver`)
  * **Remote Grids**: Authenticated support for Selenium Grid, BrowserStack, and Sauce Labs.

---

### Phase 3: Modern Tooling & Ecosystem (Long-Term)

```text
+-------------------------------------------------------------------------------+
|                             Future Lua-Selenium Stack                         |
+-------------------------------------------------------------------------------+
| High-Level:   Page Object Model (POM)  |  Test Runners (Busted / LuaUnit)     |
| Mid-Level:    Fluent API Locators (`By`)  |  Actions API  |  Wait Conditions  |
| Transport:    W3C REST (HTTP)           |  WebDriver BiDi / CDP (WebSocket)   |
| Engine:       Chromedriver / GeckoDriver / Selenium Grid / Cloud Providers     |
+-------------------------------------------------------------------------------+
```

1. **WebDriver BiDi / Chrome DevTools Protocol (CDP)**:
   * Introduce a WebSocket transport layer (e.g. `lua-websockets`) to support the new W3C BiDi protocol.
   * Real-time network request interception and mocking.
   * Streaming browser console log events and JS exception captures.
2. **Test Runner Integrations**:
   * Build assertion helpers and fixtures for popular Lua test frameworks like `busted` or `telescope`.
3. **Packaging**:
   * Create a formal `luaselenium-0.1.0-1.rockspec` file and publish it to [LuaRocks.org](https://luarocks.org) for single-command installation (`luarocks install luaselenium`).