local IconWidget = require("ui/widget/iconwidget")
local dir = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
return {
    connected = function(size)
        return IconWidget:new{ file = dir .. "../assets/icons/check.svg",
            width = size, height = size, alpha = true }
    end,
}
