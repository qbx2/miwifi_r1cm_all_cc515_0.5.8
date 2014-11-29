module ("xiaoqiang.util.XQDeviceUtil", package.seeall)

local XQConfigs = require("xiaoqiang.common.XQConfigs")
local XQFunction = require("xiaoqiang.common.XQFunction")
local XQEquipment = require("xiaoqiang.XQEquipment")

function getDeviceCompany(mac)
    local companyInfo = { name = "", icon = "" }
    if XQFunction.isStrNil(mac) or string.len(mac) < 8 then
        return companyInfo
    end
    return XQEquipment.identifyDevice(mac, nil)
end

function getDeviceInfoFromDB()
    local XQDBUtil = require("xiaoqiang.util.XQDBUtil")
    local result = {}
    local deviceList = XQDBUtil.fetchAllDeviceInfo()
    if #deviceList > 0 then
        for _,device in ipairs(deviceList) do
            result[device.mac] = device
        end
    end
    return result
end

function saveDeviceName(mac,name)
    local XQDBUtil = require("xiaoqiang.util.XQDBUtil")
    local code = XQDBUtil.updateDeviceNickname(XQFunction.macFormat(mac),name)
    if code == 0 then
        return true
    else
        return false
    end
end

--
--	Get DHCP list
--

function getDHCPList()
    local NixioFs = require("nixio.fs")
    local LuciUci = require("luci.model.uci")
    local uci =  LuciUci.cursor()
    local result = {}
    local leasefile = XQConfigs.DHCP_LEASE_FILEPATH
    uci:foreach("dhcp", "dnsmasq",
    function(s)
        if s.leasefile and NixioFs.access(s.leasefile) then
            leasefile = s.leasefile
            return false
        end
    end)
    local dhcp = io.open(leasefile, "r")
    if dhcp then
        for line in dhcp:lines() do
            if line then
                local ts, mac, ip, name = line:match("^(%d+) (%S+) (%S+) (%S+)")
                if name == "*" then
                    name = ""
                end
                if ts and mac and ip and name then
                    result[#result+1] = {
                        mac  = XQFunction.macFormat(mac),
                        ip   = ip,
                        name = name
                    }
                end
            end
        end
        dhcp:close()
        return result
    else
        return false
    end
end

function getDHCPDict()
    local dhcpDict = {}
    local dhcpList = getDHCPList()
    for _,value in ipairs(dhcpList) do
        dhcpDict[value.mac] = value
    end
    return dhcpDict
end

function getMacfilterInfoList()
    local LuciUtil = require("luci.util")
    local macFilterInfo = {}
    local metaData = LuciUtil.execi("/usr/sbin/sysapi macfilter get")
    for filterInfo in metaData do
        filterInfo = filterInfo..";"
        local mac = filterInfo:match('mac=(%S-);') or ""
        local wan = filterInfo:match('wan=(%S-);') or ""
        local lan = filterInfo:match('lan=(%S-);') or ""
        local admin = filterInfo:match('admin=(%S-);') or ""
        local pridisk = filterInfo:match('pridisk=(%S-);') or ""
        local entry = {}
        if (not XQFunction.isStrNil(mac)) then
            entry["mac"] = XQFunction.macFormat(mac)
            entry["wan"] = (string.upper(wan) == "YES" and true or false)
            entry["lan"] = (string.upper(lan) == "YES" and true or false)
            entry["admin"] = (string.upper(admin) == "YES" and true or false)
            entry["pridisk"] = (string.upper(pridisk) == "YES" and true or false)
            table.insert(macFilterInfo, entry)
        end
    end
    return macFilterInfo
end

function getMacfilterInfoDict()
    local macFilterDict = {}
    local macFilterList = getMacfilterInfoList()
    for _,value in ipairs(macFilterList) do
        macFilterDict[value.mac] = value
    end
    return macFilterDict
end

--
--	Device network statistics functions
--

function getWanSpeedHistory()
    local XQPreference = require("xiaoqiang.XQPreference")
    return XQPreference.get(XQConfigs.PREF_WAN_SPEED_HISTORY,"")
end

function setWanSpeedHistory(value)
    local XQPreference = require("xiaoqiang.XQPreference")
    XQPreference.set(XQConfigs.PREF_WAN_SPEED_HISTORY,value)
end

--[[
@param devName : lan/wan，其他情况 DEVNAME = DEV
]]--
function getWanLanNetworkStatistics(devName)
    local LuciUtil = require("luci.util")
    local traffic = require("sysapi.traffic")
    local device
    if devName == "lan" then
        device = "LANDEVICE"
    elseif devName == "wan" then
        device= LuciUtil.exec(XQConfigs.GET_WAN_DEV)
        if not XQFunction.isStrNil(device) then
            device = LuciUtil.trim(device)
        else
            device = "eth0.2"
        end
    end
    local statistics = {}

    statistics["onlinets"] = "0"
    statistics["activets"] = "0"
    statistics["upload"] = "0"
    statistics["upspeed"] = "0"
    statistics["download"] = "0"
    statistics["downspeed"] = "0"
    statistics["online"] = "0"
    statistics["idle"] = "0"
    statistics["devname"] = device
    statistics["initail"] = "0"
    statistics["maxuploadspeed"] = "0"
    statistics["maxdownloadspeed"] = "0"

    local nicList = traffic.get("nic")
    if nicList == nil then
        return statistics
    end
    for _,dev in ipairs(nicList) do
        if dev then
            if dev.DEVNAME == device then
                local downloadSpeed = tostring(math.floor(dev.DOWNSPEED))
                statistics["onlinets"] = tostring(dev.ONLINETS)
                statistics["activets"] = tostring(dev.ACTIVETS)
                statistics["upload"] = tostring(dev.UPLOAD)
                statistics["upspeed"] = tostring(math.floor(dev.UPSPEED))
                statistics["download"] = tostring(dev.DOWNLOAD)
                statistics["downspeed"] = tostring(math.floor(downloadSpeed))
                statistics["online"] = tostring(dev.ONELINE)
                statistics["idle"] = tostring(dev.IDLE)
                statistics["devname"] = device
                statistics["initail"] = tostring(dev.INITAIL)
                statistics["maxuploadspeed"] = tostring(math.floor(dev.MAXUPLOADSPEED))
                statistics["maxdownloadspeed"] = tostring(math.floor(dev.MAXDOWNLOADSPEED))
                if devName == "wan" then
                    local history = {}
                    local historyStr = getWanSpeedHistory()
                    if historyStr == "" then
                        historyStr = downloadSpeed
                        table.insert(history,downloadSpeed)
                    else
                        history = LuciUtil.split(historyStr,",")
                        for index, value in ipairs(history) do
                            if math.floor(dev.MAXDOWNLOADSPEED) < math.floor(value) then
                                history[index] = "0"
                            end
                        end
                        table.insert(history,downloadSpeed)
                        if #history > 10 then
                            historyStr = table.concat(history,",",#history-9,#history)
                        else
                            historyStr = table.concat(history,",")
                        end
                    end
                    statistics["history"] = history
                    setWanSpeedHistory(historyStr)
                end
            end
        end
    end
    return statistics
end

--[[
@param mac=B8:70:F4:27:0C:1B 网卡mac地址
@param ip=192.168.1.137      主机ip
@param onlinets=1374552092   主机上线时间UTC
@param activets=1374552261   主机最后活跃时间UTC
@param upload1=14475         主机5秒前累计上传数据总量（byte）
@param upload2=14745         主机当前累计上传数据总量（byte）
@param upspeed=54            主机5秒平均上传速度（byte/s）
@param download1=25173       主机5秒前累计下载数据总量（byte）
@param download2=25777       主机当前累计下载数据总量（byte）
@param downspeed=120         主机5秒平均下载速度（byte/s）
@param oneline=169           主机在线时长（秒）
@param idle=0                主机空闲时长（秒）， 当空闲时间大于10秒，认为主机离线，在线时长清零，当空闲时间大于两周，所有统计数据清零
@param devname               设备名
@param initail               第一次连接
@param maxuploadspeed        上传峰值
@param maxdownloadspeed      下载峰值
]]--
function getDevNetStatisticsList()
    local traffic = require("sysapi.traffic")
    local statList = {}
    local dhcpNameDict = getDHCPDict()
    local deviceInfoDict = getDeviceInfoFromDB()
    local arpList = traffic.get("arp")
    if arpList == nil then
        return statList
    end
    for _,dev in ipairs(arpList) do
        if dev then
            local item = {}
            local name, nickName, oriName
            local mac = XQFunction.macFormat(dev.MAC)
            if dhcpNameDict[mac] then
                oriName = dhcpNameDict[mac].name
            end
            local device = deviceInfoDict[mac]
            if device then
                if XQFunction.isStrNil(oriName) then
                    oriName = device.oName
                end
                nickName = device.nickname
            end
            local company = XQEquipment.identifyDevice(mac, oriName)
            local dtype = company["type"]
            if not XQFunction.isStrNil(nickName) then
                 name = nickName
            end
            if XQFunction.isStrNil(name) and not XQFunction.isStrNil(dtype.n) then
                name = dtype.n
            end
            if XQFunction.isStrNil(name) and not XQFunction.isStrNil(oriName) then
                name = oriName
            end
            if XQFunction.isStrNil(name) and not XQFunction.isStrNil(company.name) then
                name = company.name
            end
            if XQFunction.isStrNil(name) then
                name = mac
            end
            item["mac"] = mac
            item["ip"] = dev.IP
            item["onlinets"] = tostring(dev.ONLINETS)
            item["activets"] = tostring(dev.ACTIVETS)
            item["upload"] = tostring(dev.UPLOAD)
            item["upspeed"] = tostring(math.floor(dev.UPSPEED))
            item["download"] = tostring(dev.DOWNLOAD)
            item["downspeed"] = tostring(math.floor(dev.DOWNSPEED))
            item["online"] = tostring(dev.ONELINE)
            item["idle"] = tostring(dev.IDLE)
            item["devname"] = name
            item["initail"] = tostring(dev.INITAIL)
            item["maxuploadspeed"] = tostring(math.floor(dev.MAXUPLOADSPEED))
            item["maxdownloadspeed"] = tostring(math.floor(dev.MAXDOWNLOADSPEED))
            statList[#statList+1] = item
        end
    end
    return statList
end

function getDevNetStatisticsDict()
    local traffic = require("sysapi.traffic")
    local statDict = {}
    local arpList = traffic.get("arp")
    if arpList == nil then
        return statDict
    end
    for _,dev in ipairs(arpList) do
        if dev then
            local item = {}
            local mac = XQFunction.macFormat(dev.MAC)
            item["onlinets"] = tostring(dev.ONLINETS)
            item["activets"] = tostring(dev.ACTIVETS)
            item["upload"] = tostring(dev.UPLOAD)
            item["upspeed"] = tostring(math.floor(dev.UPSPEED))
            item["download"] = tostring(dev.DOWNLOAD)
            item["downspeed"] = tostring(math.floor(dev.DOWNSPEED))
            item["online"] = tostring(dev.ONELINE)
            item["idle"] = tostring(dev.IDLE)
            item["initail"] = tostring(dev.INITAIL)
            item["maxuploadspeed"] = tostring(math.floor(dev.MAXUPLOADSPEED))
            item["maxdownloadspeed"] = tostring(math.floor(dev.MAXDOWNLOADSPEED))
            statDict[mac] = item
        end
    end
    return statDict
end

function getConnectDeviceCount()
    local traffic = require("sysapi.traffic")
    local count = 0
    local arpList = traffic.get("arp")
    if arpList == nil then
        return count
    end
    for _,device in ipairs(arpList) do
        if device then
            local dev = device.DEVNAME
            if not XQFunction.isStrNil(dev) and (tonumber(device.ASSOC) == 1 or not dev:match("wl")) then
                count = count + 1
            end
        end
    end
    return count
end

--[[
@return online:      0 (offline) 1 (online)
@return ip:          ip address
@return mac:         mac address
@return type:        wifi/line
@return tag:         1 (normal) 2 (in denylist)
@return port:        1 (2.4G wifi) 2 (5G wifi)
@return name:        name for show
@return origin_name: origin name
@return signal:      wifi signal
@return statistics:
]]--
function getConnectDeviceList()
    local XQWifiUtil = require("xiaoqiang.util.XQWifiUtil")
    local XQDBUtil = require("xiaoqiang.util.XQDBUtil")
    local XQEquipment = require("xiaoqiang.XQEquipment")

    local traffic = require("sysapi.traffic")
    local deviceList = {}

    local arpList = traffic.get("arp")
    if arpList == nil then
        return deviceList
    end

    local macFilterDict = getMacfilterInfoDict()
    local dhcpDeviceDict = getDHCPDict()
    local deviceInfoDict = getDeviceInfoFromDB()
    local wifiDeviceDict = XQWifiUtil.getAllWifiConnetDeviceDict()

    for _,item in ipairs(arpList) do
        if item then
            local device = {}
            local statistics = {}
            local dev = item.DEVNAME
            local idle = tonumber(item.IDLE)
            local mac = XQFunction.macFormat(item.MAC)

            if not XQFunction.isStrNil(dev) and (tonumber(item.ASSOC) == 1 or not dev:match("wl")) then
                device["online"] = 1
                device["mac"] = mac

                statistics["idle"] = idle
                statistics["dev"] = dev
                statistics["mac"] = mac
                statistics["ip"] = item.IP
                statistics["onlinets"] = tostring(item.ONLINETS)
                statistics["activets"] = tostring(item.ACTIVETS)
                statistics["upload"] = tostring(item.UPLOAD)
                statistics["upspeed"] = tostring(math.floor(item.UPSPEED))
                statistics["download"] = tostring(item.DOWNLOAD)
                statistics["downspeed"] = tostring(math.floor(item.DOWNSPEED))
                statistics["online"] = tostring(item.ONELINE)
                statistics["initail"] = tostring(item.INITAIL)
                statistics["maxuploadspeed"] = tostring(math.floor(item.MAXUPLOADSPEED))
                statistics["maxdownloadspeed"] = tostring(math.floor(item.MAXDOWNLOADSPEED))
                device["ip"] = statistics.ip
                device["statistics"] = statistics

                local signal = wifiDeviceDict[mac]
                if signal and signal.signal then
                    device["signal"] = signal.signal
                else
                    device["signal"] = ""
                end
                if statistics.dev:match("eth") then
                    device["type"] = "line"
                    device["port"] = 0
                elseif statistics.dev == "wl0" then
                    device["type"] = "wifi"
                    device["port"] = 2
                elseif statistics.dev == "wl1" then
                    device["type"] = "wifi"
                    device["port"] = 1
                end

                -- 访问权限
                local authority = {}
                if (macFilterDict[mac]) then
                    authority["wan"] = macFilterDict[mac]["wan"] and 1 or 0
                    authority["lan"] = macFilterDict[mac]["lan"] and 1 or 0
                    authority["admin"] = macFilterDict[mac]["admin"] and 1 or 0
                    authority["pridisk"] = macFilterDict[mac]["pridisk"] and 1 or 0
                else 
                    authority["wan"] = 1
                    authority["lan"] = 1
                    authority["admin"] = 1
                    -- private disk deny access default
                    authority["pridisk"] = 0
                end
                device["authority"] = authority

                local name, originName, nickName, company
                if dhcpDeviceDict[mac] ~= nil then
                    originName = dhcpDeviceDict[mac].name
                end

                if originName and originName:match("^xiaomi%-ir") then -- fix miio model string
                    originName = originName:gsub("%-",".")
                end

                local deviceInfo = deviceInfoDict[mac]
                if deviceInfo then
                    if XQFunction.isStrNil(originName) then
                        originName = deviceInfo.oName
                    end
                    nickName = deviceInfo.nickname
                end
                device["origin_name"] = originName or ""
                if not XQFunction.isStrNil(nickName) then
                    name = nickName
                end
                company = XQEquipment.identifyDevice(mac, originName)

                local dtype = company["type"]
                device["ctype"] = dtype.c
                device["ptype"] = dtype.p
                if XQFunction.isStrNil(name) and not XQFunction.isStrNil(dtype.n) then
                    name = dtype.n
                end
                if XQFunction.isStrNil(name) and not XQFunction.isStrNil(originName) then
                    name = originName
                end
                if XQFunction.isStrNil(name) and not XQFunction.isStrNil(company.name) then
                    name = company.name
                end
                if XQFunction.isStrNil(name) then
                    name = mac
                end
                if dtype.c == 3 and XQFunction.isStrNil(nickName) then
                    name = dtype.n
                end
                device["name"] = name
                device["company"] = company
                if not deviceInfo then
                    XQDBUtil.saveDeviceInfo(mac,device.origin_name,"","","")
                end
                table.insert(deviceList,device)
            end
        end
    end
    if #deviceList > 0 then
        table.sort(deviceList,
            function(a, b)
                return b.statistics.onlinets < a.statistics.onlinets
            end
        )
    end
    return deviceList
end

function getConDevices(withbrlan)
    local XQDBUtil = require("xiaoqiang.util.XQDBUtil")
    local XQEquipment = require("xiaoqiang.XQEquipment")

    local traffic = require("sysapi.traffic")
    local deviceList = {}

    local arpList = traffic.get("arp")
    if arpList == nil then
        return deviceList
    end

    local dhcpDeviceDict = getDHCPDict()
    local deviceInfoDict = getDeviceInfoFromDB()

    for _,item in ipairs(arpList) do
        if item then
            local device = {}
            local statistics = {}
            local dev = item.DEVNAME
            local idle = tonumber(item.IDLE)
            local mac = XQFunction.macFormat(item.MAC)

            if not XQFunction.isStrNil(dev) and ((not dev:match("wl") and withbrlan) or (dev:match("wl") and tonumber(item.ASSOC) == 1)) then
                device["mac"] = mac
                statistics["idle"] = idle
                statistics["dev"] = dev
                statistics["mac"] = mac
                statistics["ip"] = item.IP
                statistics["onlinets"] = tostring(item.ONLINETS)
                statistics["activets"] = tostring(item.ACTIVETS)
                statistics["upload"] = tostring(item.UPLOAD)
                statistics["upspeed"] = tostring(math.floor(item.UPSPEED))
                statistics["download"] = tostring(item.DOWNLOAD)
                statistics["downspeed"] = tostring(math.floor(item.DOWNSPEED))
                statistics["online"] = tostring(item.ONELINE)
                statistics["initail"] = tostring(item.INITAIL)
                statistics["maxuploadspeed"] = tostring(math.floor(item.MAXUPLOADSPEED))
                statistics["maxdownloadspeed"] = tostring(math.floor(item.MAXDOWNLOADSPEED))
                device["ip"] = statistics.ip
                device["statistics"] = statistics

                local name, originName, nickName, company
                if dhcpDeviceDict[mac] ~= nil then
                    originName = dhcpDeviceDict[mac].name
                end

                local deviceInfo = deviceInfoDict[mac]
                if deviceInfo then
                    if XQFunction.isStrNil(originName) then
                        originName = deviceInfo.oName
                    end
                    nickName = deviceInfo.nickname
                end
                device["origin_name"] = originName or ""
                if not XQFunction.isStrNil(nickName) then
                    name = nickName
                end
                company = XQEquipment.identifyDevice(mac, originName)

                local dtype = company["type"]
                device["ctype"] = dtype.c
                device["ptype"] = dtype.p
                if XQFunction.isStrNil(name) and not XQFunction.isStrNil(dtype.n) then
                    name = dtype.n
                end
                if XQFunction.isStrNil(name) and not XQFunction.isStrNil(originName) then
                    name = originName
                end
                if XQFunction.isStrNil(name) and not XQFunction.isStrNil(company.name) then
                    name = company.name
                end
                if XQFunction.isStrNil(name) then
                    name = mac
                end
                if dtype.c == 3 and XQFunction.isStrNil(nickName) then
                    name = dtype.n
                end
                if not deviceInfo then
                    XQDBUtil.saveDeviceInfo(mac,device.origin_name,"","","")
                end
                device["name"] = name
                device["company"] = company
                table.insert(deviceList,device)
            end
        end
    end
    return deviceList
end
