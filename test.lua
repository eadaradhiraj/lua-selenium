local WebDriver = require("webdriver")
local By = WebDriver.By
local test = require("webdriver_test")

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

print("[3] Title: " .. driver:get_title())

print("[4] Entering search query...")
local search_box = driver:wait_until(WebDriver.EC.presence_of_element(By.css("#searchInput")), 5)
search_box:click()
search_box:send_keys("Lua (programming language)\n")

local heading = driver:wait_until(WebDriver.EC.presence_of_element(By.css("h1#firstHeading")), 10)
print("[5] Current URL: " .. driver:get_current_url())
print("[6] Page Heading: " .. heading:get_text())

print("[7] Closing browser session...")
driver:quit()
print("[+] Test completed successfully!")
