local plugin_dir = (debug.getinfo(1, "S").source:match("^@(.*/)") or "./")
local _ = dofile(plugin_dir .. "i18n/po.lua")

return {
    fullname = _("Wi-Fi management"),
    description = _("Manage Wi-Fi management networks in KOReader."),
}
