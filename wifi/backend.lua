-- All handles and hasharrays belong to a single call, including failure paths.
local Backend = {}

function Backend.call(_self, method, service, property, value)
    local handle, input, output
    local ok, result = pcall(function()
        if method == "hash" or method == "get_string_property" then
            handle = require("libopenlipclua").open_no_name()
        else
            handle = require("liblipclua").init("com.github.koreader.wifi.plugin")
        end
        assert(handle, "LIPC unavailable")
        if method == "hash" then
            input = handle:new_hasharray()
            if value then
                input:add_hash()
                for key, item in pairs(value) do
                    if type(item) == "number" then input:put_int(0, key, item)
                    else input:put_string(0, key, item) end
                end
            end
            output = handle:access_hash_property(service, property, input)
            assert(output, "Empty LIPC response")
            return output:to_table() or {}
        end
        return handle[method](handle, service, property, value)
    end)
    if output then pcall(output.destroy, output) end
    if input then pcall(input.destroy, input) end
    if handle then pcall(handle.close, handle) end
    if not ok then return nil, tostring(result) end
    return result
end

function Backend:hash(property, value)
    return self:call("hash", "com.lab126.wifid", property, value)
end
function Backend:get(property)
    return self:call("get_string_property", "com.lab126.wifid", property)
end
function Backend:scan()
    return self:call("set_string_property", "com.lab126.wifid", "scan", "")
end
function Backend:connect(id)
    return self:call("set_string_property", "com.lab126.cmd", "ensureConnection", "wifi:" .. tostring(id))
end
function Backend:forget(id)
    return self:call("set_int_property", "com.lab126.wifid", "deleteProfile", assert(tonumber(id)))
end

return Backend
