module("luci.controller.web.index", package.seeall)

function index()
    local root = node()
    if not root.target then
        root.target = alias("web")
        root.index = true
    end
    local page   = node("web")
    page.target  = firstchild()
    page.title   = _("")
    page.order   = 10
    page.sysauth = "admin"
    page.mediaurlbase = "/xiaoqiang/web"
    page.sysauth_authenticator = "htmlauth"
    page.index = true

    local LuciUtil = require "luci.util"
    local XQSysUtil = require "xiaoqiang.util.XQSysUtil"
    local misc = XQSysUtil.getMiscHardwareInfo()

    local XQFunction = require("xiaoqiang.common.XQFunction")
    local netMode = 0
    local mode = XQFunction.getNetMode()
    if mode == "lanapmode" then
        netMode = 2
    elseif mode == "wifiapmode" then
        netMode = 1
    end

    entry({"web"}, alias("web", "home"), _("路由器状态"), 10)
    entry({"web", "logout"}, call("action_logout"), 11, true)

    if misc.recovery == 1 then
        entry({"web", "home"}, template("web/recovery"), _("路由器状态"), 12)
    else
        if netMode == 0 then
            entry({"web", "home"}, template("web/home"), _("路由器状态"), 12)
        else
            entry({"web", "home"}, template("web/aphome"), _("路由器状态"), 12)
        end
    end

    entry({"web", "init"}, alias("web", "init", "hello"), _("初始化引导"), 13)
    entry({"web", "init", "hello"}, template("web/init/hello"), _("欢迎界面"), 14,true)   --不需要登录
    entry({"web", "init", "agreement"}, template("web/init/agreement"), _("用户协议"), 14,true)   --不需要登录
    entry({"web", "init", "guide"}, template("web/init/guide"), _("引导模式"), 15, false, 0x01)

    entry({"web", "setting"}, alias("web", "setting", "upgrade"), _("路由设置"), 16)
    entry({"web", "setting", "upgrade"}, template("web/setting/upgrade"), _("路由手动升级"), 17)
    -- entry({"web", "setting", "upgrade_manual"}, template("web/setting/upgrade_manual", _("路由器手动升级"), 18))
    entry({"web", "setting", "wifi"}, call("action_wifi"), _("Wi-Fi设置"), 18)
    entry({"web", "setting", "wan"}, template("web/setting/wan"), _("外网设置"), 19)
    entry({"web", "setting", "proset"}, template("web/setting/proset"), _("高级设置"), 20)

    entry({"web", "syslock"}, template("web/syslock"), _("路由升级"), 21)
    entry({"web", "upgrading"}, template("web/syslock"), _("路由升级"), 22, true)

    entry({"web", "setting", "dhcpipmacband"}, template("web/setting/dhcp_ip_mac"), _("DHCP静态IP分配"), 23)
    entry({"web", "setting", "safe"}, template("web/setting/safe"), _("安全中心"), 24)
    entry({"web", "setting", "dmz"}, template("web/setting/dmz"), _("DMZ"), 25)
    entry({"web", "setting", "nat"}, template("web/setting/nat_dmz"), _("端口转发"), 26)
    entry({"web", "setting", "upnp"}, template("web/setting/upnp"), _("upnp"), 27)
    entry({"web", "setting", "lannetset"}, template("web/setting/lannetset"), _("局域网设置"), 28)
    entry({"web", "setting", "ddns"}, template("web/setting/ddns"), _("DDNS"), 29)
    entry({"web", "setting", "vpn"}, template("web/setting/vpn"), _("VPN"), 30)

    entry({"web", "webinitrdr"}, template("web/init/webinitrdr"), _("劫持页面"), 31,true)   --不需要登录

    entry({"web", "apsetting"}, alias("web", "apsetting", "upgrade"), _("中继设置"), 32)
    entry({"web", "apsetting", "upgrade"}, template("web/apsetting/upgrade"), _("中继系统信息"), 33)
    entry({"web", "apsetting", "wan"}, template("web/apsetting/wan"), _("中继模式切换"), 34)
    entry({"web", "apsetting", "safe"}, template("web/apsetting/safe"), _("中继密码设置"), 35)

    entry({"web", "setting", "qos"}, template("web/setting/qos"), _("智能限速QoS"), 36)

end

function action_wifi()
    local tpl = require("luci.template")
    local XQWifiUtil = require("xiaoqiang.util.XQWifiUtil")
    local tplData = {}
    tplData['tplData'] = XQWifiUtil.getAllWifiInfo()
    tpl.render("web/setting/wifi", tplData)
end

function action_logout()
    local dsp = require "luci.dispatcher"
    local sauth = require "luci.sauth"
    if dsp.context.authsession then
        sauth.kill(dsp.context.authsession)
        dsp.context.urltoken.stok = nil
    end
    luci.http.header("Set-Cookie", "sysauth=; path=" .. dsp.build_url())
    luci.http.redirect(luci.dispatcher.build_url())
end
