std = "lua53"
max_line_length = 140
-- Colon methods often do not use the receiver (e.g. WebDriver:select).
ignore = { "212/self" }

files["spec"] = {
   std = "lua53+busted",
}

-- Optional busted hooks; only present when install_busted is used.
files["src/webdriver/test.lua"] = {
   globals = { "before_each", "after_each" },
}
