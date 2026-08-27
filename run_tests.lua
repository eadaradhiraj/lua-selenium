-- Run local suite (no Wikipedia / external network).
local tests = {
    "test_api.lua",
    "test_phase1.lua",
    "test_phase2.lua",
    "test_phase3.lua",
    "test_pom.lua",
    "example.lua",
}

for _, name in ipairs(tests) do
    print("======== " .. name)
    local ok, why, code = os.execute("lua " .. name)
    if not ok then
        io.stderr:write(name .. " failed (" .. tostring(why) .. " " .. tostring(code) .. ")\n")
        os.exit(code or 1)
    end
end
print("======== all local tests passed")
