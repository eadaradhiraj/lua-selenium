std = "lua53"

-- Busted example spec; not a suppression of real issues.
files["spec"] = {
   std = "lua53+busted",
}

-- Runner assigns describe/it/assert so the spec can run without busted.
files["tests/run_spec.lua"] = {
   globals = { "describe", "it", "assert" },
}
