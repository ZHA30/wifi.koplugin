-- Run the firmware event client directly, so cancellation owns the actual PID.
local Events = {}
Events.__index = Events
function Events.open()
    local ffi = require("ffi")
    local util = require("ffi/util")
    pcall(ffi.cdef, "int execl(const char *path, const char *arg, ...);")
    local path = os.tmpname()
    local file = io.open(path, "w")
    if not file then return nil, "Cannot create event buffer" end
    file:close()
    local pid = util.runInSubProcess(function()
        local fd = ffi.C.open(path, 1)
        if fd < 0 then return end
        ffi.C.dup2(fd, 1)
        ffi.C.close(fd)
        ffi.C.execl("/usr/bin/lipc-wait-event", "lipc-wait-event", "-m", "-s", "60",
            "com.lab126.wifid", "profileUpdateOk,profileUpdateFailed,cmConnectionFailed,captivePortalDetected", ffi.cast("void*", nil))
    end)
    if not pid then os.remove(path); return nil, "Cannot start event listener" end
    return setmetatable({pid = pid, path = path, util = util}, Events)
end
function Events:read()
    local file = io.open(self.path, "r")
    if not file then return "" end
    local text = file:read("*a") or ""
    file:close()
    if self.pid and self.util.isSubProcessDone(self.pid) then
        self.pid = nil
        return text, "Wi-Fi event listener stopped unexpectedly"
    end
    return text
end
function Events:close()
    if self.pid then
        self.util.terminateSubProcess(self.pid)
        self.util.isSubProcessDone(self.pid, true)
        self.pid = nil
    end
    if self.path then os.remove(self.path); self.path = nil end
end
return Events
