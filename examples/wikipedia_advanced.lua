dofile("tests/env.lua")
local WebDriver = require("webdriver")
local By = WebDriver.By
local test = require("webdriver.test")

if not test.reachable("https://www.wikipedia.org") then
    print("SKIP: Wikipedia unreachable (offline)")
    os.exit(0)
end

print("[1] Launching Chrome in HEADLESS mode...")
local driver = WebDriver.new({
    browser_name = "chrome",
    headless = true
})

print("[2] Navigating to Wikipedia...")
driver:get("https://www.wikipedia.org")

print("[3] Searching with explicit wait...")
local search_box = driver:wait_until(WebDriver.EC.presence_of_element(By.css("#searchInput")), 5)
search_box:send_keys("Lua (programming language)\n")

local heading = driver:wait_until(WebDriver.EC.presence_of_element(By.css("h1#firstHeading")), 10)

print("[4] Article Heading: " .. heading:get_text())

local user_agent = driver:execute_script("return navigator.userAgent;")
print("[5] Browser User-Agent: " .. tostring(user_agent))

driver:save_screenshot("/tmp/lua-selenium-wiki.png")
print("[6] Saved screenshot to '/tmp/lua-selenium-wiki.png'")

print("[7] Quitting driver...")
driver:quit()
print("[+] Advanced test completed successfully!")
