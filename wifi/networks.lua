-- Match saved profiles without persisting or copying their credentials.
local M = {}
local function same(a, b)
    if a.netid and b.netid and tonumber(a.netid) ~= -1 and tonumber(b.netid) ~= -1 then
        return tostring(a.netid) == tostring(b.netid)
    end
    return a.essid and a.essid ~= "" and a.essid == b.essid
end
function M.build(rows, profiles, current, wifi_on)
    local networks, found = {}, false
    local function append(source)
        local row = {}
        for _, key in ipairs({"essid", "netid", "secured", "key_mgmt", "signal", "signal_max", "known"}) do
            row[key] = source[key]
        end
        local active = wifi_on and current and current.connected == "yes" and same(row, current) or false
        found = found or active
        local known = active or row.known == "yes"
        for _, profile in ipairs(profiles) do
            if same(row, profile) then
                known = true
                row.netid = profile.netid or row.netid
                break
            end
        end
        row.known = known and "yes" or "no"
        networks[#networks + 1] = {
            ssid = row.essid, flags = row.secured == "yes" and "WPA" or "",
            signal_quality = math.min(100, math.max(0, (tonumber(row.signal) or 0) * 20)),
            connected = active, known = known, kindle = row,
        }
    end
    if wifi_on then for _, row in ipairs(rows) do append(row) end end
    if wifi_on and current and current.connected == "yes" and not found then append(current) end
    table.sort(networks, function(a, b)
        if a.connected ~= b.connected then return a.connected end
        if a.known ~= b.known then return a.known end
        if a.signal_quality ~= b.signal_quality then return a.signal_quality > b.signal_quality end
        return (a.ssid or "") < (b.ssid or "")
    end)
    for rank, network in ipairs(networks) do network.rank = rank end
    return networks
end
return M
