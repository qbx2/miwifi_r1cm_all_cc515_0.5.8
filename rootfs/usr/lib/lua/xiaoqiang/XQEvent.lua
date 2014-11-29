module ("xiaoqiang.XQEvent", package.seeall)

function lanIPChange(ip)
    local DMZ = require("xiaoqiang.module.XQDMZModule")
    local MacBind = require("xiaoqiang.module.XQMacBind")
    local PortForward = require("xiaoqiang.module.XQPortForward")
    DMZ.hookLanIPChangeEvent(ip)
    MacBind.hookLanIPChangeEvent(ip)
    PortForward.hookLanIPChangeEvent(ip)
end