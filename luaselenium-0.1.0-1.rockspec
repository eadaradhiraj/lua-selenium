package = "luaselenium"
version = "0.1.0-1"
source = {
   url = "git+https://github.com/eadaradhiraj/lua-selenium.git",
   tag = "v0.1.0"
}
description = {
   summary = "W3C WebDriver client for Lua",
   detailed = [[
A Lua client for the W3C WebDriver protocol: sessions, locators, actions,
cookies, frames, alerts, managed chromedriver/geckodriver lifecycle,
and WebDriver BiDi over WebSockets.
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
      webdriver = "src/webdriver.lua",
      ["webdriver.ws"] = "src/webdriver/ws.lua",
      ["webdriver.bidi"] = "src/webdriver/bidi.lua",
      ["webdriver.test"] = "src/webdriver/test.lua"
   }
}
