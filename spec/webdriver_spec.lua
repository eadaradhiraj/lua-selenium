-- Example busted spec. Run with: lua tests/run_spec.lua
-- or: busted spec/webdriver_spec.lua
dofile("tests/env.lua")
local test = require("webdriver.test")

describe("luaselenium", function()
    it("creates a headless Chrome session and reads the page title", function()
        test.with_driver({ headless = true, spawn = true }, function(driver)
            driver:get("data:text/html,<html><head><title>busted</title></head><body>ok</body></html>")
            test.equal(driver:get_title(), "busted")
        end)
    end)
end)
