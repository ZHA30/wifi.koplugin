-- Reuse core network rows, signal icons, alternating backgrounds and pagination.
local CenterContainer = require("ui/widget/container/centercontainer")
local NetworkSetting = require("ui/widget/networksetting")
local ButtonTable = require("ui/widget/buttontable")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local GestureRange = require("ui/gesturerange")
local FrameContainer = require("ui/widget/container/framecontainer")
local TextWidget = require("ui/widget/textwidget")
local Font = require("ui/font")
local Icons = require("wifi.icons")
local UIManager = require("ui/uimanager")
local translate = require("wifi.i18n")
local View = NetworkSetting:extend{}

function View:init()
    NetworkSetting.init(self)
    local list = self.popup[1][2]
    table.sort(list.items, function(a, b) return (a.info.rank or 1) < (b.info.rank or 1) end)
    local items, group = {}, nil
    for _, row in ipairs(list.items) do
        local network = row.info.kindle
        if network then
            local section = row.info.known and "known" or "other"
            if section ~= group then
                group = section
                items[#items + 1] = FrameContainer:new{
                    width = self.width, height = row.height, bordersize = 0, padding = 0, margin = 0,
                    TextWidget:new{ text = section == "known" and translate("Known networks") or translate("Other networks"),
                        face = Font:getFace("cfont"), bold = true },
                }
            end
        end
        row.onTapSelect = function()
            if network and not row.info.connected then self.owner:tapNetwork(network) end
            return true
        end
        row.onHoldNetwork = function()
            if network and row.info.known then self.owner:network(network) end
            return true
        end
        if network and row.info.known then
            row.ges_events.HoldNetwork = { GestureRange:new{ ges = "hold", range = row.dimen } }
        end
        if network then
            local label = row.content_container[1][1][4]
            label:setMaxWidth(self.width - row.icon_size * 3)
            row.content_container[1][1]:resetLayout()
        end
        if row.btn_disconnect then
            row.btn_disconnect[1]:free()
            row.btn_disconnect[1] = Icons.connected(row.icon_size)
        end
        row.connect = row.onTapSelect
        row.onAddNetwork = row.onTapSelect
        row.onEditNetwork = row.onHoldNetwork
        row.disconnect = row.onTapSelect
        if network then
            items[#items + 1] = row
        else
            -- Empty state is a plain text row, without a Wi-Fi icon or actions.
            items[#items + 1] = FrameContainer:new{
                width = self.width, height = row.height, bordersize = 0, padding = 0, margin = 0,
                TextWidget:new{ text = translate("Empty"), face = Font:getFace("cfont") },
            }
            row:free()
        end
    end
    local footer = ButtonTable:new{ width = self.width, buttons = {{
        { text = translate("Close"), callback = function() UIManager:close(self) end },
        { text = translate("Refresh"), callback = function() self.owner:scan() end },
    }} }
    list.height = math.max(list.item_height, list.height - footer:getSize().h - Size.line.medium)
    list.items = items
    list:init()
    if #self.network_list == 1 and not self.network_list[1].kindle then
        list[1] = CenterContainer:new{
            dimen = { w = self.width, h = list.height },
            TextWidget:new{ text = translate("Empty"), face = Font:getFace("cfont") },
        }
    end
    table.insert(self.popup[1], LineWidget:new{ dimen = { w = self.width, h = Size.line.medium } })
    table.insert(self.popup[1], footer)
    self.popup[1]:resetLayout()
end
function View:onCloseWidget()
    if self.owner.view == self then
        self.owner.view = nil
        self.owner:cancelJob()
    end
    UIManager:setDirty(nil, "ui", self.popup.dimen)
end
return View
