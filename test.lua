local WebDriver = require("webdriver")
local socket = require("socket")

print("[1] Connecting to ChromeDriver on port 9515...")
local driver = WebDriver.new("http://127.0.0.1:9515", "chrome")

print("[2] Navigating to Wikipedia...")
driver:get("https://www.wikipedia.org")

print("[3] Title: " .. driver:get_title())

print("[4] Entering search query...")
local search_box = driver:find_element("css selector", "#searchInput")
search_box:click()
search_box:send_keys("Lua (programming language)\n")

-- Wait for page navigation
socket.sleep(2)

print("[5] Current URL: " .. driver:get_current_url())

local heading = driver:find_element("css selector", "h1#firstHeading")
print("[6] Page Heading: " .. heading:get_text())

print("[7] Closing browser session...")
driver:quit()
print("[+] Test completed successfully!")
