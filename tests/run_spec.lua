-- Run spec/webdriver_spec.lua without requiring the busted package.
dofile("tests/env.lua")

local passed = 0
local failed = 0

function describe(name, fn)
    print("[" .. name .. "]")
    fn()
end

function it(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        passed = passed + 1
        print("  PASS  " .. name)
    else
        failed = failed + 1
        print("  FAIL  " .. name)
        print(tostring(err))
    end
end

dofile("spec/webdriver_spec.lua")

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
    os.exit(1)
end
print("[+] spec/webdriver_spec.lua completed successfully!")
