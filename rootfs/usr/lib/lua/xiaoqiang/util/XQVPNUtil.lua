module ("xiaoqiang.util.XQVPNUtil", package.seeall)

local XQFunction = require("xiaoqiang.common.XQFunction")
local XQConfigs = require("xiaoqiang.common.XQConfigs")
local XQCryptoUtil = require("xiaoqiang.util.XQCryptoUtil")

local Network = require("luci.model.network")
local Firewall = require("luci.model.firewall")
local uci = require("luci.model.uci").cursor()

-- @param proto pptp/l2tp
-- @param auto  0/1
function setVpn(interface, server, username, password, proto, id, auto)
    if XQFunction.isStrNil(interface) or XQFunction.isStrNil(server) or XQFunction.isStrNil(username) or XQFunction.isStrNil(password) or XQFunction.isStrNil(proto) or XQFunction.isStrNil(auto) then
        return false
    end
    local protocal = string.lower(proto)
    local network = Network.init()
    network:del_network(interface)
    local vpnNetwork = network:add_network(interface, {
        proto = protocal,
        server = server,
        username = username,
        password = password,
        auth = 'auto',
        id = id,
        auto = auto
    })
    if vpnNetwork then
        network:save("network")
        network:commit("network")
        local firewall = Firewall.init()
        local zoneWan = firewall:get_zone("wan")
        zoneWan:add_network(interface)
        firewall:save("firewall")
        firewall:commit("firewall")
        return true
    end
    return false
end

-- del vpn config in /etc/config/network
function _delNetworkVpn(id)
    local oldVpn = getVPNInfo("vpn")
    local oldId = oldVpn["id"]
    if oldId == id then
        local network = Network.init()
        network:del_network("vpn")
        network:save("network")
        network:commit("network")
    end
end

-- edit vpn config in /etc/config/network
function _editNetworkVpn(server, username, password, proto, id)
    local oldVpn = getVPNInfo("vpn")
    local oldId = oldVpn["id"]
    if oldId == id then
        local interface = "vpn"
        local protocal = string.lower(proto)
        local newId = XQCryptoUtil.md5Str(server .. username .. proto)
        uci:set("network", interface, "proto", protocal)
        uci:set("network", interface, "server", server)
        uci:set("network", interface, "username", username)
        uci:set("network", interface, "password", password)
        uci:set("network", interface, "id", newId)
        uci:commit("network")
    end
end

-- set vpn auto start in /etc/config/network
function setVpnAuto(auto)
    auto = tonumber(auto)
    local interface = "vpn"
    local autoinit = (auto and auto == 0) and "0" or "1"
    uci:set("network", interface, "auto", autoinit)
    uci:commit("network")
    return true
end

-- get vpn info in /etc/config/network
function getVPNInfo(interface)
    local network = Network.init()
    local info = {
        proto = "",
        server = "",
        username = "",
        password = "",
        auto = "0",
        id = ""
    }
    if XQFunction.isStrNil(interface) then
        return info
    end
    local vpn = network:get_network(interface)
    if vpn then
        info.proto = vpn:get_option_value("proto")
        info.server = vpn:get_option_value("server")
        info.username = vpn:get_option_value("username")
        info.password = vpn:get_option_value("password")
        info.auto = vpn:get_option_value("auto")
        info.id = vpn:get_option_value("id")
    end
    return info
end

-- enabled a vpn config
function vpnSwitch(enable, id)
    if XQFunction.isStrNil(id) then
        return false
    end
    if enable then
        local oldVpn = getVPNInfo("vpn")
        local oldId = oldVpn["id"]
        local autoinit = oldVpn["auto"]
        if XQFunction.isStrNil(autoinit) then
            autoinit = "0"
        end
        if oldId ~= id then
            local options = uci:get_all("vpnlist", id)
            if options then
                setVpn("vpn", options.server, options.username, options.password, options.proto, id, autoinit)
            end
        end
        os.execute(XQConfigs.RM_VPNSTATUS_FILE)
        os.execute(XQConfigs.VPN_DISABLE)
        return (os.execute(XQConfigs.VPN_ENABLE) == 0)
    else
        os.execute(XQConfigs.RM_VPNSTATUS_FILE)
        return (os.execute(XQConfigs.VPN_DISABLE) == 0)
    end
end

-- get vpn status
function vpnStatus()
    local LuciUtil = require("luci.util")
    local status = LuciUtil.exec(XQConfigs.VPN_STATUS)
    if not XQFunction.isStrNil(status) then
        status = LuciUtil.trim(status)
        if XQFunction.isStrNil(status) then
            return nil
        end
        local json = require("json")
        status = json.decode(status)
        if status then
            return status
        end
    end
    return nil
end

-- add vpn item in /etc/config/vpnlist
function addVPN(oname, server, username, password, proto)
    if XQFunction.isStrNil(oname) or XQFunction.isStrNil(server) or XQFunction.isStrNil(username) or XQFunction.isStrNil(password) or XQFunction.isStrNil(proto) then
        return false
    end
    local id = XQCryptoUtil.md5Str(server .. username .. proto)
    local protocal = string.lower(proto)
    local options = {
        ["oname"] = oname,
        ["server"] = server,
        ["username"] = username,
        ["password"] = password,
        ["proto"] = protocal,
        ["id"] = id
    }
    uci:section("vpnlist", "vpn", id, options)
    uci:commit("vpnlist")
    return true
end

-- edit a vpn config in /etc/config/vpnlist and /etc/config/network
function editVPN(oldId, oname, server, username, password, proto)
    if XQFunction.isStrNil(oldId) then
        return false
    end
    uci:delete("vpnlist", oldId)
    _editNetworkVpn(server, username, password, proto, oldId)
    return addVPN(oname, server, username, password, proto)
end

-- del a vpn config in /etc/config/vpnlist and /etc/config/network
function delVPN(id)
    if XQFunction.isStrNil(id) then
        return false
    end
    uci:delete("vpnlist", id)
    uci:commit("vpnlist")
    _delNetworkVpn(id)
    return true
end

-- get vpnlist in /etc/config/vpnlist
function getVPNList()
    local result = {}
    uci:foreach("vpnlist", "vpn",
        function(s)
            local item = {
                ["oname"] = s.oname,
                ["server"] = s.server,
                ["username"] = s.username,
                ["password"] = s.password,
                ["proto"] = s.proto,
                ["id"] = s.id
            }
            table.insert(result, item)
            -- result[s.id] = item
        end
    )
    return result
end