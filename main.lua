-- luacheck: ignore 211/_result 213/_index
local Device = require("device")
if not Device:isKindle() then return { disabled = true } end

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local View = require("wifi.view")
local ButtonDialog = require("ui/widget/buttondialog")
local InputDialog = require("ui/widget/inputdialog")
local Networks = require("wifi.networks")
local Events = require("wifi.events")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local Event = require("ui/event")
local B = require("wifi.backend")
local _ = require("wifi.i18n")

local Plugin = WidgetContainer:extend{ name = "wifi", is_doc_only = false }

function Plugin:init()
    self.windows = {}
    self.ui.menu:registerToMainMenu(self)
end
function Plugin:show(widget)
    self.windows[widget] = true
    local close = widget.onCloseWidget
    widget.onCloseWidget = function(w, ...)
        self.windows[w] = nil
        if close then return close(w, ...) end
    end
    UIManager:show(widget)
    return widget
end
function Plugin:message(text)
    self:show(InfoMessage:new{ text = text })
end
function Plugin:result(err)
    self:message(err and (_("Operation failed:") .. "\n" .. err) or _("Done"))
end
function Plugin:addToMainMenu(items)
    -- Insert after the native Wi-Fi connection entry in both host menus.
    for _index, module in ipairs({"reader_menu_order", "filemanager_menu_order"}) do
        local order = require("ui/elements/" .. module).network
        local exists = false
        for _, id in ipairs(order) do if id == "wifi_manager" then exists = true end end
        if not exists then
            for position, id in ipairs(order) do
                if id == "network_wifi" then table.insert(order, position + 1, "wifi_manager"); break end
            end
        end
    end
    items.wifi_manager = { text = _("Wi-Fi management"), sorting_hint = "network", keep_menu_open = true,
        enabled_func = function() return NetworkMgr:isWifiOn() end,
        callback = function() self:open() end }
end
function Plugin:open()
    if not NetworkMgr:isWifiOn() then return end
    self.stopped = false
    if NetworkMgr:isWifiOn() then self:scan() else self:list() end
end
-- Only one operation per instance. Polls yield to KOReader's UI between checks.
function Plugin:cancelJob()
    if self.poll then UIManager:unschedule(self.poll); self.poll = nil end
    if self.events then self.events:close(); self.events = nil end
    if self.restore_wifi then self.restore_wifi = nil; NetworkMgr:restoreWifiAsync() end
    if self.progress then UIManager:close(self.progress); self.progress = nil end
end
function Plugin:wait(title, timeout, check, complete)
    if self.poll then self:message(_("An operation is already running.")); return end
    local elapsed = 0
    self.progress = self:show(InfoMessage:new{ text = title })
    local progress = self.progress
    local original_close = progress.onCloseWidget
    progress.onCloseWidget = function(w, ...)
        if self.poll then UIManager:unschedule(self.poll); self.poll = nil end
        self.progress = nil
        if self.restore_wifi then self.restore_wifi = nil; NetworkMgr:restoreWifiAsync() end
        if self.events then self.events:close(); self.events = nil end
        return original_close(w, ...)
    end
    self.poll = function()
        if self.stopped then self:cancelJob(); return end
        elapsed = elapsed + 0.5
        local done, value, err = check()
        if done or err or elapsed >= timeout then
            self:cancelJob()
            if err then self:result(err)
            elseif not done then self:message(_("Timed out. The system operation may still finish; check the network status."))
            else complete(value) end
        else UIManager:scheduleIn(0.5, self.poll) end
    end
    UIManager:scheduleIn(0.5, self.poll)
end
function Plugin:scan()
    if self.poll then self:message(_("An operation is already running.")); return end
    if not NetworkMgr:isWifiOn() then self:message(_("Turn Wi-Fi on first.")); return end
    local _result, err = B:scan()
    if err then self:result(err); return end
    self:wait(require("gettext")("Scanning for networks…"), 20, function()
        local state, failure = B:get("scanState")
        return state == "idle", nil, failure
    end, function() self:list(false) end)
end
function Plugin:list()
    local wifi_on = NetworkMgr:isWifiOn()
    local rows, err = B:hash("scanList")
    if not rows and wifi_on then self:result(err); return end
    local profiles, profile_err = B:hash("profileData")
    if not profiles and wifi_on then self:result(profile_err); return end
    local current_rows, current_err = B:hash("currentEssid")
    if not current_rows and wifi_on then self:result(current_err); return end
    local networks = Networks.build(rows or {}, profiles or {}, current_rows and current_rows[1], wifi_on)
    if #networks == 0 then
        networks[1] = { ssid = _("Empty"),
            flags = "", signal_quality = 0 }
    end
    if self.view then UIManager:close(self.view) end
    self.view = self:show(View:new{ owner = self, network_list = networks })
end
function Plugin:tapNetwork(network)
    if network.known == "yes" then
        self:connect(network.netid or network.essid)
    else
        self:credentials(network)
    end
end
function Plugin:network(network)
    local dialog
    local function action(fn) return function() UIManager:close(dialog); fn() end end
    dialog = ButtonDialog:new{ title = network.essid or _("Hidden network"), buttons = {
        {{ text = _("Delete network"), enabled = tonumber(network.netid) ~= nil,
            callback = action(function() self:forget(network) end) }},
        {{ text = _("Modify network"), callback = action(function() self:credentials(network) end) }},
    } }
    self:show(dialog)
end
function Plugin:connect(id)
    if self.poll then self:message(_("An operation is already running.")); return end
    local events, event_error = Events.open()
    if not events then self:result(event_error); return end
    self.events = events
    local started, ticks = false, 0
    self:wait(_("Connecting…"), 40, function()
        if not started then
            local _result, err = B:connect(id)
            if err then return false, nil, err end
            started = true
            return false
        end
        ticks = ticks + 1
        local log, listener_error = events:read()
        if listener_error then return false, nil, listener_error end
        if log:find("cmConnectionFailed", 1, true) then
            return false, nil, _("Connection failed. Check the password and network settings.") .. "\n" .. log
        end
        if log:find("captivePortalDetected", 1, true) then
            return false, nil, _("This network requires a web login.")
        end
        local rows, failure = B:hash("currentEssid")
        local current = rows and rows[1]
        local target = current and current.connected == "yes"
            and (tostring(current.netid) == tostring(id) or current.essid == id)
        if target and ticks >= 40 and not NetworkMgr:isConnected() then
            return false, nil, _("Connected to Wi-Fi, but no IP address was obtained.")
        end
        return current and current.connected == "yes"
            and (tostring(current.netid) == tostring(id) or current.essid == id)
            and NetworkMgr:isConnected(), nil, failure
    end, function()
        UIManager:broadcastEvent(Event:new("NetworkConnected"))
        self:list(false)
    end)
end
function Plugin:forget(network)
    self:show(ConfirmBox:new{ text = _("Delete this network from Kindle system settings?"),
        ok_callback = function()
            if self.poll then self:message(_("An operation is already running.")); return end
            local rows, err = B:hash("currentEssid")
            if not rows then self:result(err); return end
            local current = rows[1]
            local active = current and current.connected == "yes"
                and tostring(current.netid) == tostring(network.netid)
            local restore = active and NetworkMgr:isWifiOn()
            if restore then NetworkMgr:turnOffWifi() end
            local deleted = false
            self:wait(_("Deleting network…"), 20, function()
                if restore and NetworkMgr:isWifiOn() then return false end
                if not deleted then
                    local _result, failure = B:forget(network.netid)
                    if failure then return false, nil, failure end
                    deleted = true
                end
                local profiles, failure = B:hash("profileData")
                if not profiles then return false, nil, failure end
                for _index, profile in ipairs(profiles) do
                    if tostring(profile.netid) == tostring(network.netid) then return false end
                end
                if restore then
                    NetworkMgr:restoreWifiAsync()
                    restore = false
                    self.restore_wifi = nil
                end
                return NetworkMgr:isWifiOn()
            end, function() self:scan() end)
            self.restore_wifi = restore
        end })
end
function Plugin:saveCredentials(network, password)
    if self.poll then self:message(_("An operation is already running.")); return false end
    local secure = network.secured == "yes"
    if not network.essid or network.essid == "" or (secure and password == "") then
        self:message(_("Check the network name and required credentials.")); return false
    end
    local profile = { essid = network.essid, secured = secure and "yes" or "no", store_nw_user_pref = 0 }
    if secure then profile.psk = password end
    local events, event_error = Events.open()
    if not events then self:result(event_error); return false end
    self.events = events
    local started = false
    self:wait(_("Saving network…"), 15, function()
        if not started then
            local _result, err = B:hash("createProfile", profile)
            profile.psk = nil
            if err then return false, nil, err end
            started = true
            return false
        end
        local log, listener_error = events:read()
        if listener_error then return false, nil, listener_error end
        if log:find("profileUpdateFailed", 1, true) then
            return false, nil, _("Network settings were rejected:") .. "\n" .. log
        end
        local id = log:match('profileUpdateOk[^%d]*(%d+)')
        return id ~= nil, id and tonumber(id)
    end, function(id) self:connect(id) end)
    return true
end
function Plugin:credentials(network)
    if network.secured ~= "yes" then
        self:show(ConfirmBox:new{ text = network.essid, ok_text = _("Connect"),
            ok_callback = function() self:saveCredentials(network, "") end })
        return
    end
    local dialog
    dialog = InputDialog:new{
        title = network.essid or _("Hidden network"), input = "",
        input_hint = _("Password"), text_type = "password",
        description = network.known == "yes" and _("Saved network. Enter a new password.") or nil,
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Connect"), is_enter_default = true, callback = function()
                if self:saveCredentials(network, dialog:getInputText()) then UIManager:close(dialog) end
            end },
        }},
    }
    self:show(dialog)
    dialog:onShowKeyboard()
end
function Plugin:stopPlugin()
    self.stopped = true
    self:cancelJob()
    local windows = {}
    for widget in pairs(self.windows) do windows[#windows + 1] = widget end
    for _index, widget in ipairs(windows) do UIManager:close(widget) end
end
function Plugin:onCloseWidget() self:stopPlugin() end
function Plugin:onSuspend() self:cancelJob() end

return Plugin
