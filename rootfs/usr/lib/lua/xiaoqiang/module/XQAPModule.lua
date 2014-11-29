module ("xiaoqiang.module.XQAPModule", package.seeall)

local XQFunction = require("xiaoqiang.common.XQFunction")
local XQConfigs = require("xiaoqiang.common.XQConfigs")
local LuciUtil = require("luci.util")

local CONFIGS = {
    ["lanap"] = {
        ["ports1"] = "0 2 4 5*",
        ["ports2"] = "5"
    },
    ["normal"] = {
        ["ports1"] = "0 2 5*",
        ["ports2"] = "4 5",
        ["ipaddr"] = "192.168.31.1"
    }
}

local NETWORK_LAN = {
    ["type"]    = "bridge",
    ["ifname"]  = "eth0.1",
    ["proto"]   = "static",
    ["netmask"] = "255.255.255.0",
    ["ipaddr"]  = "192.168.31.1"
}

local NETWORK_WAN = {
    ["ifname"]  = "eth0.2",
    ["proto"]   = "dhcp"
}

function setLanAPMode(ip)
    if XQFunction.isStrNil(ip) then
        return false
    end
    local uci = require("luci.model.uci").cursor()
    local ipv = LuciUtil.split(ip, ".")
    ipv[4] = 1
    ipv = table.concat(ipv, ".")
    local config = CONFIGS["lanap"]
    -- set config
    uci:set("network", "eth0_1", "ports", config.ports1)
    uci:set("network", "eth0_2", "ports", config.ports2)
    uci:set("network", "lan", "ipaddr", ip)
    uci:set("network", "lan", "gateway", ipv)
    uci:set("network", "lan", "dns", ipv)
    uci:commit("network")
    -- set nvram
    XQFunction.nvramSet("vlan1ports", config.ports1)
    XQFunction.nvramSet("vlan2ports", config.ports2)
    XQFunction.nvramSet("mode", "AP")
    XQFunction.setNetMode("lanapmode")
    XQFunction.nvramCommit()
    -- network reload
    os.execute("rmmod et;insmod et")
    os.execute("/etc/init.d/network reload")
    return true
end

function disableLanAP()
    local uci = require("luci.model.uci").cursor()
    local config = CONFIGS["normal"]
    -- set config
    uci:set("network", "eth0_1", "ports", config.ports1)
    uci:set("network", "eth0_2", "ports", config.ports2)
    uci:set("network", "lan", "ipaddr", config.ipaddr)
    uci:delete("network", "lan", "gateway")
    uci:delete("network", "lan", "dns")
    uci:commit("network")
    -- set nvram
    XQFunction.nvramSet("vlan1ports", config.ports1)
    XQFunction.nvramSet("vlan2ports", config.ports2)
    XQFunction.nvramSet("mode", "AP")
    XQFunction.setNetMode(nil)
    XQFunction.nvramCommit()
    -- network reload
    os.execute("rmmod et;insmod et")
    os.execute("/etc/init.d/network reload")
    return true
end

function connectionStatus()
    local connection = LuciUtil.exec("iwpriv apcli0 Connstatus")
    if connection:match("SSID:") then
        return true, connection
    else
        return false, connection
    end
end

function backupConfigs()
    local uci = require("luci.model.uci").cursor()
    local wifi = require("xiaoqiang.util.XQWifiUtil")
    local lan = uci:get_all("network", "lan")
    local dhcplan = uci:get_all("dhcp", "lan")
    local dhcpwan = uci:get_all("dhcp", "wan")
    uci:delete("backup", "lan")
    uci:delete("backup", "wifi1")
    uci:delete("backup", "wifi2")
    uci:delete("backup", "dhcplan")
    uci:delete("backup", "dhcpwan")
    uci:section("backup", "backup", "lan", lan)
    uci:section("backup", "backup", "dhcplan", dhcplan)
    uci:section("backup", "backup", "dhcpwan", dhcpwan)
    uci:commit("backup")
    wifi.backupWifiInfo(1)
    wifi.backupWifiInfo(2)
end

function setWanAuto(auto)
    local LuciNetwork = require("luci.model.network").init()
    local wan = LuciNetwork:get_network("wan")
    wan:set("auto", auto)
    LuciNetwork:commit("network")
end

function disableWifiAPMode()
    local wifi = require("xiaoqiang.util.XQWifiUtil")
    local uci = require("luci.model.uci").cursor()
    local lan = uci:get_all("backup", "lan")
    local inf = uci:get_all("backup", "wifi1")
    local inf2 = uci:get_all("backup", "wifi2")
    local dhcplan = uci:get_all("backup", "dhcplan")
    local dhcpwan = uci:get_all("backup", "dhcpwan")
    local lanip, ssid
    uci:delete("network", "lan")
    if lan then
        uci:section("network", "interface", "lan", lan)
        lanip = lan.ipaddr
    else
        uci:section("network", "interface", "lan", NETWORK_LAN)
        lanip = NETWORK_LAN.ipaddr
    end
    if dhcplan then
        uci:section("dhcp", "dhcp", "lan", dhcplan)
    end
    if dhcpwan then
        uci:section("dhcp", "dhcp", "wan", dhcpwan)
    end
    uci:commit("dhcp")
    uci:commit("network")

    setWanAuto(nil)

    wifi.deleteWifiBridgedClient(1)
    if inf then
        ssid = inf.ssid
        wifi.setWifiBasicInfo(1, inf.ssid, inf.password, inf.encryption, tostring(inf.channel), inf.txpwr, tostring(inf.hidden), tonumber(inf.on) == 1 and 0 or 1, inf.bandwidth)
    end
    if inf2 then
        wifi.setWifiBasicInfo(2, inf2.ssid, inf2.password, inf2.encryption, tostring(inf2.channel), inf2.txpwr, tostring(inf2.hidden), tonumber(inf2.on) == 1 and 0 or 1, inf2.bandwidth)
    end
    XQFunction.setNetMode(nil)
    local restore_script = [[
	  sleep 3;
	  /etc/init.d/network restart;
	  /etc/init.d/dnsmasq restart;
          /usr/sbin/dhcp_apclient.sh restart lan;
	  /etc/init.d/traffic restart
    ]]
    XQFunction.forkExec(restore_script)
    return lanip, ssid
end

function serviceRestart()
    local restart_script = [[
	  sleep 2;
	  /etc/init.d/network restart;
	  /etc/init.d/traffic restart;
	  /etc/init.d/dnsmasq restart;
	  /usr/sbin/dhcp_apclient.sh restart lan;
    ]]
    XQFunction.forkExec(restart_script)
end

function parseCmdline(str)
    if XQFunction.isStrNil(str) then
        return ""
    else
        return str:gsub("\\", "\\\\"):gsub("`", "\\`"):gsub("\"", "\\\"")
    end
end

function setWifiAPMode(ssid, encryption, enctype, password, channel, bandwidth)
    local XQWifiUtil = require("xiaoqiang.util.XQWifiUtil")
    local result = {
        ["connected"]   = false,
        ["conerrmsg"]   = "",
        ["scan"]        = true,
        ["ip"]          = ""
    }
    local cssid = ssid
    local cenctype = enctype
    local cencryption = encryption
    local cpassword = password
    local cchannel = channel
    local cbandwidth = bandwidth
    if cssid and (cpassword or cencryption == "NONE") then
        local cmdssid = parseCmdline(cssid)
        local cmdpassword = parseCmdline(cpassword)
        if XQFunction.isStrNil(cenctype) then
            local scanlist = XQWifiUtil.getWifiScanlist(cmdssid)
            local wifi
            for _, item in ipairs(scanlist) do
                if item and item.ssid == ssid then
                    wifi = item
                    break
                end
            end
            if not wifi then
                result["scan"] = false
                return result
            end
            cchannel = wifi.channel
            cenctype = wifi.enctype
            cencryption = wifi.encryption
        end
        if cenctype:match("AES") then
            -- WPA2PSK
            os.execute("iwpriv wl1 set Channel="..tostring(cchannel))
            os.execute("ifconfig apcli0 up")
            os.execute("iwpriv apcli0 set ApCliEnable=0")
            os.execute("iwpriv apcli0 set ApCliAuthMode=WPA2PSK")
            os.execute("iwpriv apcli0 set ApCliEncrypType=AES")
            os.execute("iwpriv apcli0 set ApCliSsid=\""..cmdssid.."\"")
            os.execute("iwpriv apcli0 set ApCliWPAPSK=\""..cmdpassword.."\"")
            os.execute("iwpriv apcli0 set ApCliSsid=\""..cmdssid.."\"")
            os.execute("iwpriv apcli0 set ApCliAutoConnect=1")
        elseif cenctype == "TKIP" then
            -- WPAPSK
            os.execute("iwpriv wl1 set Channel="..tostring(cchannel))
            os.execute("ifconfig apcli0 up")
            os.execute("iwpriv apcli0 set ApCliEnable=0")
            os.execute("iwpriv apcli0 set ApCliAuthMode=WPAPSK")
            os.execute("iwpriv apcli0 set ApCliEncrypType=TKIP")
            os.execute("iwpriv apcli0 set ApCliSsid=\""..cmdssid.."\"")
            os.execute("iwpriv apcli0 set ApCliWPAPSK=\""..cmdpassword.."\"")
            os.execute("iwpriv apcli0 set ApCliSsid=\""..cmdssid.."\"")
            os.execute("iwpriv apcli0 set ApCliAutoConnect=1")
        elseif cenctype == "WEP" then
            -- WEP
            os.execute("iwpriv wl1 set Channel="..tostring(cchannel))
            os.execute("ifconfig apcli0 up")
            os.execute("iwpriv apcli0 set ApCliEnable=0")
            os.execute("iwpriv apcli0 set ApCliAuthMode=OPEN")
            os.execute("iwpriv apcli0 set ApCliEncrypType=WEP")
            os.execute("iwpriv apcli0 set ApCliDefaultKeyID=1")
            os.execute("iwpriv apcli0 set ApCliKey1=\""..cmdpassword.."\"")
            os.execute("iwpriv apcli0 set ApCliSsid=\""..cmdssid.."\"")
            os.execute("iwpriv apcli0 set ApCliAutoConnect=1")
        elseif cenctype == "NONE" then
            -- NONE
            os.execute("iwpriv wl1 set Channel="..tostring(cchannel))
            os.execute("ifconfig apcli0 up")
            os.execute("iwpriv apcli0 set ApCliEnable=0")
            os.execute("iwpriv apcli0 set ApCliAuthMode=OPEN")
            os.execute("iwpriv apcli0 set ApCliEncrypType=NONE")
            os.execute("iwpriv apcli0 set ApCliSsid=\""..cmdssid.."\"")
            os.execute("iwpriv apcli0 set ApCliAutoConnect=1")
        end

        local connected = false
        for i=1, 10 do
            local succ, status = connectionStatus()
            if succ then
                connected = true
                break
            end
            os.execute("sleep 2")
            local reason = status:match("Disconnect reason = (.-)\n$")
            if reason then
                result["conerrmsg"] = reason:gsub("\n","")
            end
        end
        result["connected"] = connected
    end
    if result.connected then
        local XQLanWanUtil = require("xiaoqiang.util.XQLanWanUtil")
        backupConfigs()

        setWanAuto(0)

        -- get ip
        os.execute("sleep 2;dhcp_apclient.sh start")
        local newip = XQLanWanUtil.getLanIp()
        if newip ~= "192.168.31.1" then
            XQFunction.setNetMode("wifiapmode")
            result["ip"] = newip
            local uci = require("luci.model.uci").cursor()
            uci:delete("dhcp", "lan")
            uci:delete("dhcp", "wan")
            uci:commit("dhcp")
            local confenc
            if cenctype == "TKIPAES" then
                confenc = "mixed-psk"
            elseif cenctype == "AES" then
                confenc = "wpa2-psk"
            elseif cenctype == "TKIP" then
                confenc = "wpa-psk"
            elseif cenctype == "WEP" then
                confenc = "wep"
            elseif cenctype == "NONE" then
                confenc = "none"
            end
            XQWifiUtil.setWifiBasicInfo(1, cssid, cpassword, confenc, cchannel, nil, nil, 1, cbandwidth)
            XQWifiUtil.setWifiBasicInfo(2, cssid.."_5G", cpassword, confenc, nil, nil, nil, 1, nil)
            XQWifiUtil.setWifiBridgedClient(1, cssid, cencryption, cpassword, cchannel)
            XQWifiUtil.setWiFiMacfilterModel(false)
        else
            local uci = require("luci.model.uci").cursor()
            uci:delete("network", "lan")
            uci:section("network", "interface", "lan", NETWORK_LAN)
            uci:commit("network")
            os.execute("iwpriv apcli0 set ApCliAutoConnect=0")
            os.execute("iwpriv apcli0 set ApCliEnable=0")
        end
    else
        os.execute("iwpriv apcli0 set ApCliAutoConnect=0")
        os.execute("iwpriv apcli0 set ApCliEnable=0")
    end
    return result
end
