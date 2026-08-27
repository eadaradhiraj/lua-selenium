local WebDriver = require("webdriver")
local By = WebDriver.By

print("[1] Launching Chrome in HEADLESS mode...")
local driver = WebDriver.new({
    server_url = "http://127.0.0.1:9515",
    browser_name = "chrome",
    headless = true
})

print("[2] Navigating to Wikipedia...")
driver:get("https://www.wikipedia.org")

print("[3] Searching with explicit wait...")
local search_box = driver:wait_until(function(d)
    return d:find_element(By.css("#searchInput"))
end, 5)

search_box:send_keys("Lua (programming language)\n")

local heading = driver:wait_until(function(d)
    return d:find_element(By.css("h1#firstHeading"))
end, 5)

print("[4] Article Heading: " .. heading:get_text())

-- Execute JavaScript in the browser
local user_agent = driver:execute_script("return navigator.userAgent;")
print("[5] Browser User-Agent: " .. tostring(user_agent))

-- Save screenshot
driver:save_screenshot("lua_wiki_screenshot.png")
print("[6] Saved screenshot to 'lua_wiki_screenshot.png'")

print("[7] Quitting driver...")
driver:quit()
print("[+] Advanced test completed successfully!")
