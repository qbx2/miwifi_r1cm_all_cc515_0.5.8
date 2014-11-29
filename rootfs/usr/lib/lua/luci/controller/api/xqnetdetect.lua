module("luci.controller.api.xqnetdetect", package.seeall)

function index()
    local page   = node("api","xqnetdetect")
    page.target  = firstchild()
    page.title   = ("")
    page.order   = 350
    page.sysauth = "admin"
    page.sysauth_authenticator = "jsonauth"
    page.index = true
    entry({"api", "xqnetdetect"}, firstchild(), _(""), 350)
    entry({"api", "xqnetdetect", "wan_status"}, call("getWanStatus"), _(""), 351, true)
    entry({"api", "xqnetdetect", "sys_info"}, call("getSysInfo"), (""), 352, true)
    entry({"api", "xqnetdetect", "ping_test"}, call("pingTest"), (""), 353, true)
    entry({"api", "xqnetdetect", "detect"}, call("systemDiagnostics"), (""), 354, true)
    entry({"api", "xqnetdetect", "sys_status"}, call("systemStatus"), (""), 355, true)
    entry({"api", "xqnetdetect", "netspeed"}, call("netspeed"), (""), 356)
    entry({"api", "xqnetdetect", "netupspeed"}, call("uploadSpeed"), (""), 357)

end

local LuciHttp = require("luci.http")
local XQFunction = require("xiaoqiang.common.XQFunction")
local XQErrorUtil = require("xiaoqiang.util.XQErrorUtil")

function getWanStatus()
    local XQLanWanUtil = require("xiaoqiang.util.XQLanWanUtil")
    local result = {}
    local wanType = XQLanWanUtil.getAutoWanType()
    local wanInfo = XQLanWanUtil.getLanWanInfo("wan")
    local wanMonitor = XQLanWanUtil.getWanMonitorStat()
    result["code"] = 0
    result["wanLink"] = wanType == 99 and 0 or 1
    result["wanType"] = wanType
    result["wanInfo"] = wanInfo
    result["wanMonitor"] = wanMonitor
    LuciHttp.write_json(result)
end

function getSysInfo()
    local LuciSys = require("luci.sys")
    local result = {}
    local cpu = {}
    local mem = {}
    local system, model, memtotal, memcached, membuffers, memfree, bogomips = LuciSys.sysinfo()
    cpu["info"] = system
    mem["total"] = memtotal
    mem["free"] = memfree
    result["code"] = 0
    result["cpuInfo"] = cpu
    result["memInfo"] = mem
    LuciHttp.write_json(result)
end

function pingTest()
    local LuciSys = require("luci.sys")
    local pingUrl = LuciHttp.formvalue("url")
    local ping = LuciSys.net.pingtest(pingUrl)
    local result = {}
    result["code"] = 0
    result["result"] = ping == 0 and 1 or 0
    LuciHttp.write_json(result)
end

--[[
    simple : 0/1/2 (正常模式,时间长上传log/简单模式,时间短,不上传log/简单模式,时间短,上传log)
]]--
function systemDiagnostics()
    local XQLog = require("xiaoqiang.XQLog")
    local XQSysUtil = require("xiaoqiang.util.XQSysUtil")
    local simple = tonumber(LuciHttp.formvalue("simple") or 0)
    local target = LuciHttp.formvalue("target")
    local result = {}
    local code = 0
    local status = 0
    local count = 0
    local cpuTemperature = XQSysUtil.getCpuTemperature()
    local network = XQSysUtil.getNetworkDetectInfo(simple,target)
    if network then
        local cputemp = {}
        cputemp["temperature"] = cpuTemperature
        if cpuTemperature > 70 then
            count = count + 1
            status = 1
            cputemp["status"] = 0
        else
            cputemp["status"] = 1
        end
        local cpuavg = {}
        cpuavg["loadavg"] = network.cpu
        if tonumber(network.cpu) > 90 then
            count = count + 1
            status = 1
            cpuavg["status"] = 0
        else
            cpuavg["status"] = 1
        end
        local memeryuse = {}
        memeryuse["use"] = network.memory
        if tonumber(network.memory) > 90 then
            count = count + 1
            status = 1
            memeryuse["status"] = 0
        else
            memeryuse["status"] = 1
        end
        local link = {}
        if network.wanLink ~= 1 then
            count = count + 1
            status = 2
            link["status"] = 0
        else
            link["status"] = 1
        end
        local wan = {}
        wan["type"] = network.wanType
        if tonumber(network.wanLink) ~= 1 then
            count = count + 1
            status = 2
            wan["status"] = 0
        else
            wan["status"] = 1
        end
        local gateway = {}
        gateway["lost"] = network.gw
        if tonumber(network.gw) > 80 then
            count = count + 1
            status = 1
            gateway["status"] = 0
        else
            gateway["status"] = 1
        end
        local dnsstatus = {}
        if tonumber(network.dns) ~= 1 then
            count = count + 1
            status = 2
            dnsstatus["status"] = 0
        else
            dnsstatus["status"] = 1
        end
        local ping = {}
        ping["lost"] = network.pingLost
        if tonumber(network.pingLost) > 80 then
            count = count + 1
            status = 2
            ping["status"] = 0
        else
            ping["status"] = 1
        end
        result = network
        result["count"] = count
        result["status"] = status
        result["cpuavg"] = cpuavg
        result["memeryuse"] = memeryuse
        result["cputemp"] = cputemp
        result["link"] = link
        result["wan"] = wan
        result["gateway"] = gateway
        result["dnsstatus"] = dnsstatus
        result["ping"] = ping
        result["cpuTemperature"] = cpuTemperature
        if count > 0 then
            XQLog.check(0, XQLog.KEY_DETECT_ERROR, 1)
        end
    else
        code = 1567
    end
    if code ~= 0 then
       result["msg"] = XQErrorUtil.getErrorMessage(code)
    end
    result["code"] = code
    LuciHttp.write_json(result)
end

function systemStatus()
    local XQSysUtil = require("xiaoqiang.util.XQSysUtil")
    local count = 0
    local result = {}
    local status = XQSysUtil.checkSystemStatus()
    result["code"] = 0
    result["status"] = 0
    if (status.cpu and status.cpu > 90) then
        count = count + 1
        result["status"] = 1
    end
    if (status.mem and status.mem > 90) then
        count = count + 1
        result["status"] = 1
    end
    if (status.tmp and status.tmp > 70) then
        count = count + 1
        result["status"] = 1
    end
    if not status.wan or not status.link then
        count = count + 1
        result["status"] = 2
    end
    result["count"] = count
    LuciHttp.write_json(result)
end

function netspeed()
    local XQPreference = require("xiaoqiang.XQPreference")
    local XQNSTUtil = require("xiaoqiang.module.XQNetworkSpeedTest")
    os.execute("/etc/init.d/miqos stop")
    local code = 0
    local result = {}
    local history = LuciHttp.formvalue("history")
    if history then
        result["bandwidth"] = tonumber(XQPreference.get("BANDWIDTH", 0, "xiaoqiang"))
        result["download"] = tonumber(string.format("%.2f", 128 * result.bandwidth))
    else
        local download = XQNSTUtil.downloadSpeedTest()
        if download and download[6] then
            result["download"] = download[6]
            result["bandwidth"] = tonumber(string.format("%.2f", 8 * download[6]/1024))
            XQPreference.set("BANDWIDTH", tostring(result.bandwidth), "xiaoqiang")
        else
            code = 1588
        end
        if code ~= 0 then
           result["msg"] = XQErrorUtil.getErrorMessage(code)
        end
    end
    os.execute("/etc/init.d/miqos start")
    result["code"] = code
    LuciHttp.write_json(result)
end

function uploadSpeed()
    local XQPreference = require("xiaoqiang.XQPreference")
    local XQNSTUtil = require("xiaoqiang.module.XQNetworkSpeedTest")
    os.execute("/etc/init.d/miqos stop")
    local code = 0
    local result = {}
    local upload = XQNSTUtil.uploadSpeedTest()
    if upload and upload[6] then
        result["upload"] = upload[6]
        result["bandwidth"] = tonumber(string.format("%.2f", 8 * upload[6]/1024))
        XQPreference.set("BANDWIDTH2", tostring(result.bandwidth), "xiaoqiang")
    else
        code = 1588
    end
    if code ~= 0 then
        result["msg"] = XQErrorUtil.getErrorMessage(code)
    end
    os.execute("/etc/init.d/miqos start")
    result["code"] = code
    LuciHttp.write_json(result)
end