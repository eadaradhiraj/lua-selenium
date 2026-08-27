-- Assertion helpers and session fixtures for Lua test runners (busted, telescope, or plain Lua).
local M = {}

local function fmt(value)
    local t = type(value)
    if t == "string" then
        return string.format("%q", value)
    end
    return tostring(value)
end

function M.equal(actual, expected, message)
    if actual ~= expected then
        error((message and (message .. ": ") or "") ..
            "expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
    end
end

function M.is_true(cond, message)
    if not cond then
        error(message or "expected condition to be true", 2)
    end
end

function M.is_false(cond, message)
    if cond then
        error(message or "expected condition to be false", 2)
    end
end

function M.is_nil(value, message)
    if value ~= nil then
        error(message or ("expected nil, got " .. fmt(value)), 2)
    end
end

function M.not_nil(value, message)
    if value == nil then
        error(message or "expected a non-nil value", 2)
    end
end

function M.matches(str, pattern, message)
    if type(str) ~= "string" or not str:find(pattern) then
        error(message or ("expected " .. fmt(str) .. " to match " .. fmt(pattern)), 2)
    end
end

function M.contains(haystack, needle, message)
    if type(haystack) == "string" then
        if not haystack:find(needle, 1, true) then
            error(message or ("expected " .. fmt(haystack) .. " to contain " .. fmt(needle)), 2)
        end
        return
    end
    if type(haystack) == "table" then
        for _, item in ipairs(haystack) do
            if item == needle then return end
        end
        error(message or ("expected list to contain " .. fmt(needle)), 2)
    end
    error("contains() requires a string or list", 2)
end

-- Fixture: create a driver, run fn, always quit.
function M.with_driver(opts, fn)
    if type(opts) == "function" then
        fn = opts
        opts = nil
    end
    opts = opts or {}
    if opts.headless == nil then
        opts.headless = true
    end
    local WebDriver = require("webdriver")
    local driver = WebDriver.new(opts)
    local ok, result = xpcall(function()
        return fn(driver)
    end, debug.traceback)
    pcall(function() driver:quit() end)
    if not ok then
        error(result, 0)
    end
    return result
end

-- Optional busted integration: register a before_each/after_each driver.
function M.install_busted(busted_assert, opts)
    local WebDriver = require("webdriver")
    opts = opts or { headless = true }
    local driver
    local helpers = {
        driver = function()
            return driver
        end
    }
    if type(before_each) == "function" then
        before_each(function()
            driver = WebDriver.new(opts)
        end)
    end
    if type(after_each) == "function" then
        after_each(function()
            if driver then
                pcall(function() driver:quit() end)
                driver = nil
            end
        end)
    end
    helpers.assert = busted_assert or M
    return helpers
end

M.assert_equal = M.equal
M.assert_true = M.is_true
M.assert_false = M.is_false

return M
