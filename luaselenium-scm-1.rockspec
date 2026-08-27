package = "luaselenium"
version = "scm-1"
source = {
   url = "git+https://github.com/eadaradhiraj/lua-selenium.git"
}
description = {
   summary = "W3C WebDriver client for Lua",
   detailed = [[
A Lua client for the W3C WebDriver protocol: sessions, locators, actions,
cookies, frames, alerts, managed chromedriver/geckodriver lifecycle,
and WebDriver BiDi over WebSockets.

This is an unreleased SCM rockspec; no version has been cut yet.
]],
   homepage = "https://github.com/eadaradhiraj/lua-selenium",
   license = "MIT"
}
dependencies = {
   "lua >= 5.3",
   "luasocket",
   "lunajson",
   "luasec"
}
build = {
   type = "builtin",
   modules = {
      webdriver = "webdriver.lua",
      webdriver_ws = "webdriver_ws.lua",
      webdriver_bidi = "webdriver_bidi.lua",
      webdriver_test = "webdriver_test.lua"
   }
}
