#!/usr/bin/env lua

local posix = require("Posix")
local json = require("json")
local xqf = require("xiaoqiang.common.XQFunction")
local uci = require("luci.model.uci").cursor()
local ubus = require ("ubus")

local cfg = {
        ['model_file'] = "/proc/xiaoqiang/model",
        ['debug'] = 0,
    }

function read_line(filename)
        local fd = io.open(filename)
        local line = fd:read("*line")
        fd:close()
        return line
end

function exec(cmd)
    local p = io.popen(cmd)
    ret = p:read("*line")
    p:close()
    return ret
end

function log_points(t, v, instant)
    if(type(v) ~= "string") then
            v = tostring(v)
    end

    if(instant) then
        if (cfg.debug == 1) then
            posix.syslog(posix.LOG_DEBUG, string.format("log_points %s=%s", t, v))
        elseif(cfg.debug == 2) then
            print(string.format("stat_points_instant %s=%s", t, v))
        else
            posix.syslog(posix.LOG_INFO, string.format("stat_points_instant %s=%s", t, v))
        end
    else
        if (cfg.debug == 1) then
                posix.syslog(posix.LOG_DEBUG, string.format("log_points %s=%s", t, v))
        elseif(cfg.debug == 2) then
            print(string.format("stat_points_none %s=%s", t, v))
        else
            posix.syslog(posix.LOG_INFO, string.format("stat_points_none %s=%s", t, v))
        end
    end
end



function function_appqos()
    local enable = uci:get("app-tc", "config", "enable") or 0
    log_points("function_appqos", enable == 0 and 0 or 1)
end

function function_clone()
    local wan = require("xiaoqiang.util.XQLanWanUtil")
    local defaultMac = wan.getDefaultMacAddress() or ""
    local wanMac = wan.getWanMac()
    log_points("function_clone", wanMac == defaultMac and 1 or 0)
end

function fuction_qos()
    local enable = uci:get("miqos", "settings", "enabled") or 0
    log_points("fuction_qos", enable == 0 and 0 or 1)
end

function function_upnp()
    log_points("function_upnp", exec("/etc/init.d/miniupnpd enabled && echo 1 || echo 0"))
end

function function_pptp()
    local proto = uci:get("network", "vpn", "proto")
    local enable
    local status
    if proto and proto == 'pptp' then
        status = json.decode(exec("vpn.lua status"))
        if status and status.up then
            enable = 1
        else
            enable = 0
        end
    else
        enable = 0
    end
    log_points("function_pptp", enable)
end

function function_l2tp()
    local proto = uci:get("network", "vpn", "proto")
    local enable
    local status
    if proto and proto == 'l2tp' then
        status = json.decode(exec("vpn.lua status"))
        if status and status.up then
            enable = 1
        else
            enable = 0
        end
    else
        enable = 0
    end
    log_points("function_l2tp", enable)
end

function function_dmz()
    local enable = uci:get("firewall", "dmz", "proto") or 0
    log_points("fuction_qos", enable == 0 and 0 or 1)
end

function function_plugin()
    local datacenter = xqf.thrift_tunnel_to_datacenter([[{"api":612}]])
    log_points("function_plugin", datacenter.status == 0 and 0 or 1)
end

function function_port_forwarding()
    log_points("function_port_forwarding", exec("iptables-save | grep reflection >/dev/null    && echo 1 || echo 0"))
end

function function_wireless_access()
    local model = uci:get_first("wireless", "wifi-iface", "macfilter", nil)
    if model and (model == 'deny' or model == 'allow') then
        log_points("function_wireless_access", 1)
    else
        log_points("function_wireless_access", 0)
    end
end

function function_wireless_access_blacklist()
    local model = uci:get_first("wireless", "wifi-iface", "macfilter", nil)
    if model and model == 'deny' then
        log_points("function_wireless_access_blacklist", table.getn(uci:get_first("wireless", "wifi-iface", "maclist", {})))
    else
        log_points("function_wireless_access_blacklist", 0)
    end
end

function function_wireless_access_whitelist()
    local model = uci:get_first("wireless", "wifi-iface", "macfilter", nil)
    if model and model == 'allow' then
        log_points("function_wireless_access_whitelist", table.getn(uci:get_first("wireless", "wifi-iface", "maclist", {})))
    else
        log_points("function_wireless_access_whitelist", 0)
    end
end

function function_channel_2g()
    local channel_2g = uci:get("wireless", "wl1", "channel") or 0
    log_points("function_channel_2g", channel_2g)
end

function function_channel_5g()
    local channel_5g = uci:get("wireless", "wl0", "channel") or 0
    log_points("function_channel_5g", channel_5g)
end

function function_channel_2g_signal()
    local channel_2g_signal = uci:get("wireless", "wl1", "txpwr") or 0
    log_points("function_channel_2g_signal", channel_2g_signal)
end

function function_channel_5g_signal()
    local channel_5g_signal = uci:get("wireless", "wl0", "txpwr") or 0
    log_points("function_channel_5g_signal", channel_5g_signal)
end


function function_channel_2g_r1c()
    local channel_2g = uci:get("wireless", "mt7620", "channel") or 0
    log_points("function_channel_2g", channel_2g)
end

function function_channel_5g_r1c()
    local channel_5g = uci:get("wireless", "mt7612", "channel") or 0
    log_points("function_channel_5g", channel_5g)
end

function function_channel_2g_signal_r1c()
    local channel_2g_signal = uci:get("wireless", "mt7620", "txpwr") or 0
    log_points("function_channel_2g_signal", channel_2g_signal)
end

function function_channel_5g_signal_r1c()
    local channel_5g_signal = uci:get("wireless", "mt7612", "txpwr") or 0
    log_points("function_channel_5g_signal", channel_5g_signal)
end

function function_hdd_hibernation()
    log_points("function_hdd_hibernation", exec("/etc/init.d/noflushd status >/dev/null && echo 1 || echo 0"))
end

function function_dhcp()
    local dhcp = uci:get("dhcp", "lan", "interface") or 'off'
    log_points("function_dhcp", dhcp == 'lan' and 1 or 0)
end

function function_ddns()
    local ddns = uci:get("ddns", "ddns", "status") or 'off'
    log_points("function_ddns", ddns == 'on' and 1 or 0)
end


------------------------------------------------------------------------------------------



local model = read_line(cfg.model_file)
posix.openlog(arg[0], "cp", posix.LOG_LOCAL7)

if model == 'R1D' then
    function_appqos()
    function_clone()
    fuction_qos()
    function_upnp()
    function_pptp()
    function_l2tp()
    function_dmz()
    function_port_forwarding()
    function_channel_2g()
    function_channel_5g()
    function_channel_2g_signal()
    function_channel_5g_signal()
    function_hdd_hibernation()
    function_dhcp()

elseif model == 'R1CM' then
    function_clone()
    function_upnp()
    function_dmz()
    function_plugin()
    function_port_forwarding()
    function_wireless_access()
    function_wireless_access_blacklist()
    function_wireless_access_whitelist()
    function_channel_2g_r1c()
    function_channel_5g_r1c()
    function_channel_2g_signal_r1c()
    function_channel_5g_signal_r1c()
    function_dhcp()
    function_ddns()
elseif model == 'R1CQ' then
    function_clone()
    function_upnp()
    function_dmz()
    function_plugin()
    function_port_forwarding()
    function_wireless_access()
    function_wireless_access_blacklist()
    function_wireless_access_whitelist()
    function_channel_2g_r1c()
    function_channel_5g_r1c()
    function_channel_2g_signal_r1c()
    function_channel_5g_signal_r1c()
    function_dhcp()
    function_ddns()
end

posix.closelog()
