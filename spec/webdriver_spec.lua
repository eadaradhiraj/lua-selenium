-- Example busted spec. Run with: busted spec/webdriver_spec.lua
local test = require("webdriver_test")

describe("luaselenium", function()
    it("creates a headless Chrome session and reads the page title", function()
        test.with_driver({ headless = true, spawn = true }, function(driver)
            driver:get("data:text/html,<html><head><title>busted</title></head><body>ok</body></html>")
            assert.are.equal("busted", driver:get_title())
        end)
    end)
end)
