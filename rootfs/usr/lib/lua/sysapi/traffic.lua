local base = _G
local posix = require("Posix")
local json = require("json")
local net_tools = require("net_tools")
local socket = require("socket")
local string = require("string")
local io = require("io")
local os = require("os")
local ubus = require ("ubus")
local libtraffic = require("libtraffic")
local nixio  = require "nixio"
local fs     = require "nixio.fs"
local iwinfo = require "iwinfo"

module("sysapi.traffic", package.seeall)

local g = {}
local sys = { ['arp'] = {}, ['br'] = {}, ['iwinfo'] = {}, ['tr'] = {}}
local now_time = {}
local now_uptime = 0
local next_uptime = 0
local last_uptime = 0
local save_next_uptime = {}
local cfg = {
	['host'] = "127.0.0.1",
	['port'] = 1034,
	['debug'] = 0,
	['daemon'] = 0,
	['time_step'] = 2,
	['time_step_ten_minutes'] = 600,
	['time_step_hour'] = 3600,
	['time_step_day'] = 86400,
	['systime_offset'] = 3600*8,  -- 系统时区
	['points_offset'] = 1800,     --提前半小时统计
	['time_step_save_file'] = 3600,
	['data_timeout'] = 2*7*86400, --两周
	['online_timeout'] = 600,
	['save_patch'] = "/tmp/data/sysapi",
	['save_filename'] = "/tmp/data/sysapi/traffic.json",
	['read_patch'] = "/data/sysapi",
	['read_filename'] = "/data/sysapi/traffic.json",
	--uci get network.wan.ifname
	['cmd_get_wan_dev'] = "ip route list 0/0 | grep -v tap | awk '{print $5}'",
	['cmd_get_wl_dev'] = "ifconfig | grep wl | awk '{print $1}'",
	['cmd_get_model'] = "nvram  get model",
	['load_cfg'] = 1,
	['version'] = 1.01,
}
local HAVE_IWINFO = false
local HAVE_IPACC = false
local HAVE_POINT = false
local HAVE_HWNAT = false

function read_line(filename)
	local fd = io.open(filename)
	local line = fd:read("*line")
	fd:close()
	return line
end

function up2time(uptime)
	return now_time.sec - now_uptime + uptime
end

function get_uptime()
	local _, _, uptime, idle = string.find(read_line("/proc/uptime"),'^([0-9.]+)%s+([0-9.]+)$')
	return tonumber(uptime)
end

function dlog(fmt, ...)
	if (cfg.debug == 1) then
		posix.syslog(posix.LOG_WARNING, string.format(fmt, unpack(arg)))
	elseif (cfg.debug == 2) then
		print(string.format(fmt, unpack(arg)))
	end

end

function ilog(fmt, ...)
	if (cfg.debug == 2) then
		print(string.format(fmt, unpack(arg)))
	else
		posix.syslog(posix.LOG_WARNING, string.format(fmt, unpack(arg)))
	end
end

function elog(fmt, ...)
	if (cfg.debug == 2) then
		print(string.format(fmt, unpack(arg)))
	else
		posix.syslog(posix.LOG_ERR, string.format(fmt, unpack(arg)))
	end
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

function flush_wl_dev()
	g.iw = {}
	local pp = io.popen(cfg.cmd_get_wl_dev)
	local dev, api
	dev = pp:read("*line")
	while dev do
		api = iwinfo.type(dev)
		table.insert(g.iw, {['api'] = api, ['dev'] = dev})
		dev = pp:read("*line")
	end
	pp:close()
end

function wan_device()
	local conn = ubus.connect()
	if not conn then
		elog("Failed to connect to ubusd")
	end
	local status = conn:call("network.interface.wan", "status",{})
	conn:close()
	return (status.l3_device and status.l3_device) or status.device
end

function flush_wan_dev()
	g.wandev_name = wan_device()
	g.points.wan_device = g.wandev_name
end

function get_iwinfo()
	local info = {}
	if HAVE_IWINFO then
		for _, d in ipairs(g.iw) do
			local iw = iwinfo[d.api]
			local al = iw.assoclist(d.dev)
			if al and next(al) then
				for mac, _ in pairs(al) do
					info[string.upper(mac)] = d.dev
					--dlog("dev %s, mac %s", d.dev, string.upper(mac))
				end
			end
		end
	else
		local pp
		local data
		for k, v in ipairs(g.iw) do
			pp = io.popen(string.format("wl -i %s assoclist | awk '{print $2}'", v.dev))
			data = pp:read("*line")
			while data do
				data = string.upper(data)
				info[data] = v.dev
				data = pp:read("*line")
			end
			pp:close()
		end
	end
	return info
end

function save_file(file_name, content)
	dlog("save_file begin", file_name)
	local fd = io.open(file_name, "w+")
	fd:write(content)
	fd:close()
end

function read_file(file_name)
	local fd = io.open(file_name, "r")
	local content = fd:read("*all")
	fd:close()
	return content
end


function init_hw_node(ip)

	local node =  {
		['hw'] = sys.arp[ip]['hw'],
		['ip'] = ip,
		['dev'] = nil,
		['onlinets'] = now_uptime,
		['activets'] = now_uptime,
		['br_activets'] = now_time.sec,
		['upload'] = 0,
		['upspeed'] = 0,
		['download'] = 0,
		['downspeed'] = 0,
		['online'] = 0,
		['idle'] = 0,
		['initail'] = now_uptime,
		['maxuploadspeed'] = 0,
		['maxdownloadspeed'] = 0,

		['points_time'] = 0,
		['points_tx'] = 0,
		['points_rx'] = 0,
		['points_dev'] = 0,
	}
	return node
end


function update_arp()
	--更新有流量的ip
	local ip, tr_node
	for _, tr_node in pairs(sys.tr) do
		ip = tr_node['ip']

		if(not sys.arp[ip]) then
			-- mac不存在
			for k, v in pairs(g.arp) do
				if ip == v.ip then
					sys.arp[ip] = {['hw'] = v.hw}
					break
				end
			end
		end
		if(sys.arp[ip]) then
			if (g.arp[sys.arp[ip]['hw']] ~= nil) then
				local hw = sys.arp[ip]['hw']
				-- mac存在
				-- dlog("ip %s", ip)
				-- ip改变,计数器重置
				if(g.arp[hw]['ip'] ~= ip) then
					dlog("mac[%s] ip change %s -> %s", hw, g.arp[hw]['ip'], ip)
					g.arp[hw] = init_hw_node(ip)
				else
					g.arp[hw]['upload'] = g.arp[hw]['upload'] + tr_node.t_bytes
					g.arp[hw]['upspeed'] = math.floor(tr_node.t_bytes / (now_uptime - last_uptime))
					g.arp[hw]['maxuploadspeed'] = ((g.arp[hw]['maxuploadspeed'] > g.arp[hw]['upspeed'])
					and  g.arp[hw]['maxuploadspeed'] ) or g.arp[hw]['upspeed']

					g.arp[hw]['download'] = g.arp[hw]['download'] + tr_node.r_bytes
					g.arp[hw]['downspeed'] = math.floor(tr_node.r_bytes / (now_uptime - last_uptime))
					g.arp[hw]['maxdownloadspeed'] = ((g.arp[hw]['maxdownloadspeed'] > g.arp[hw]['downspeed'])
					and  g.arp[hw]['maxdownloadspeed'] ) or g.arp[hw]['downspeed']

					g.arp[hw]['activets'] = now_uptime

					if not g.arp[hw]['points_tx'] then g.arp[hw]['points_tx'] = 0 end
					if not g.arp[hw]['points_rx'] then g.arp[hw]['points_rx'] = 0 end
					g.arp[hw]['points_tx'] = g.arp[hw]['points_tx'] + tr_node.t_bytes
					g.arp[hw]['points_rx'] = g.arp[hw]['points_rx'] + tr_node.r_bytes

				end
			else
				-- new ip
				ilog("new hw add %s", sys.arp[ip]['hw'])
				--os.execute(string.format("/usr/sbin/sysapi macfilter set 'mac=%s'",sys.arp[ip]['hw']))
				g.arp[sys.arp[ip]['hw']] = init_hw_node(ip)
			end
		end
	end
end

function update_br()
	--posix.var_dump(g)
	local ip, tr_node

	local count = 0
	for hw, mac in pairs(sys.br.macs) do
		if mac.is_local == 0 then
			count = count + 1
			local idle = mac.ageing_timer_sec
			ip = sys.arp[hw] and sys.arp[hw] or "0.0.0.0"

			if(not g.arp[hw]) then
				-- mac不存在, 创建
				dlog("mac[%s] is not exist in history arp", hw)
				g.arp[hw] = {
					['hw'] = hw,
					['ip'] = ip,
					['dev'] = "br-lan",
					['onlinets'] = now_uptime,
					['activets'] = 0,
					['br_activets'] = now_time.sec - idle,
					['upload'] = 0,
					['upspeed'] = 0,
					['download'] = 0,
					['downspeed'] = 0,
					['online'] = 0,
					['idle'] = idle,
					['initail'] = now_uptime,
					['maxuploadspeed'] = 0,
					['maxdownloadspeed'] = 0,
					['points_time'] = 0,
					['points_tx'] = 0,
					['points_rx'] = 0,
					['points_dev'] = 0,
				}
			else
				if(g.arp[hw]['ip'] ~= ip and ip ~= "0.0.0.0") then
					dlog("mac[%s] ip change %s -> %s", hw, g.arp[hw]['ip'], ip)
					g.arp[hw] = {
						['hw'] = hw,
						['ip'] = ip,
						['dev'] = "br-lan",
						['onlinets'] = 0,
						['activets'] = 0,
						['br_activets'] = 0,
						['upload'] = 0,
						['upspeed'] = 0,
						['download'] = 0,
						['downspeed'] = 0,
						['online'] = 0,
						['idle'] = 0,
						['initail'] = now_uptime,
						['maxuploadspeed'] = 0,
						['maxdownloadspeed'] = 0,
						['points_time'] = 0,
						['points_tx'] = 0,
						['points_rx'] = 0,
						['points_dev'] = 0,
					}
				end
				if(now_time.sec - cfg.online_timeout > g.arp[hw]['br_activets']) then
					-- 超过online_timeout在线时间重新统计
					dlog("hw[%s] ip[%s] time out[%f] is_local[%d]", hw, ip, now_uptime - g.arp[hw]['br_activets'], mac.is_local)
					g.arp[hw]['onlinets'] = now_uptime
				end
				if( sys.br.ports[mac.port]:match("wl") and not sys.iwinfo_old[hw] ) then
					g.arp[hw]['onlinets'] = now_uptime
				end
				g.arp[hw]['idle'] = idle
				g.arp[hw]['br_activets'] = now_time.sec - idle
				g.arp[hw]['dev'] = sys.br.ports[mac.port]
				if not g.arp[hw]['points_time'] then g.arp[hw]['points_time'] = 0 end
				g.arp[hw]['points_time'] = g.arp[hw]['points_time'] + cfg.time_step
			end
		end
	end
	if count > g.points.network_max_mac then
		g.points.network_max_mac = count
	end
end

function arp_data_clean()
	local arp={}
	local k,v,K
	dlog("data_clean begin")
	for k, v in pairs(g.arp) do
		--等段时间后去掉该部分
		if not g.arp[k]['br_activets'] then
			g.arp[k]['br_activets'] = 0
		end
		if(now_time.sec - g.arp[k]['br_activets'] < cfg.data_timeout) then
			K = string.upper(k)
			arp[K] = g.arp[k]
			arp[K]['hw'] = K
		end
	end
	return arp
end




function loop_main_arp()

	-- get arp
	local _arp = net_tools.arp_show()
	sys.arp = {}
	for k, v in pairs(_arp) do
		if (v['hw']) then
			v['hw'] = string.upper(v['hw'])
			sys.arp[v['ip']] = v
			sys.arp[v['hw']] = v['ip']
		end
	end

	-- get bridge
	libtraffic.br_init()
	sys.br.ports = libtraffic.br_getports("br-lan")
	sys.br.macs = libtraffic.br_getmacs("br-lan")
	libtraffic.br_shutdown()


	-- get iwinfo
	sys.iwinfo_old = sys.iwinfo and sys.iwinfo or {}
	sys.iwinfo = get_iwinfo()

	if HAVE_IPACC then
		-- 流量统计
		sys.tr = libtraffic.flush_account_table("lan")
		update_arp()
	end



	-- 刷新online，br_active时间
	update_br()

end


function get_nic()
	local line
	local face, r_bytes, r_packets, r_errs, r_drop, r_fifo, r_frame, r_compressed, r_multicast
	local t_bytes, t_packets, t_errs, t_drop, t_fifo, t_colls, t_carrier, t_compressed
	local _nic = {}
	if fs.access("/proc/net/dev") then
		for line in io.lines("/proc/net/dev") do
			_, _, face, r_bytes, r_packets, r_errs, r_drop, r_fifo, r_frame, r_compressed, r_multicast,
			t_bytes, t_packets, t_errs, t_drop, t_fifo, t_colls, t_carrier, t_compressed = string.find(line,
			'%s*(%S+):%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s*')
			if (face ~= nil) then
				_nic[face] = {
					r_bytes   = tonumber(r_bytes),
					r_packets = tonumber(r_packets),
					t_bytes   = tonumber(t_bytes),
					t_packets = tonumber(t_packets)
				}
			end
		end
	end

	if HAVE_HWNAT then
		local hwcnt = libtraffic.hw_nat_get_agcnt()
		if ( _nic['eth0.2'] ~= nil ) then
			_nic['eth0.2']['r_bytes'] = _nic['eth0.2']['r_bytes'] + hwcnt.t_bytes
			_nic['eth0.2']['t_bytes'] = _nic['eth0.2']['t_bytes'] + hwcnt.r_bytes
			_nic['eth0.2']['r_packets'] = _nic['eth0.2']['r_packets'] + hwcnt.t_packets
			_nic['eth0.2']['t_packets'] = _nic['eth0.2']['t_packets'] + hwcnt.r_packets
		end
		if ( _nic['br-lan'] ~= nil ) then
			_nic['br-lan']['r_bytes']   = _nic['br-lan']['r_bytes']   + hwcnt.r_bytes
			_nic['br-lan']['t_bytes']   = _nic['br-lan']['t_bytes']   + hwcnt.t_bytes
			_nic['br-lan']['r_packets'] = _nic['br-lan']['r_packets'] + hwcnt.r_packets
			_nic['br-lan']['t_packets'] = _nic['br-lan']['t_packets'] + hwcnt.t_packets
		end
	end
	return _nic
end


function init_nic_node( dev, data )
	local node =  {
		['dev'] = dev,
		['onlinets'] = now_uptime,
		['activets'] = now_uptime,
		['upload1'] = 0,
		['upload2'] = data.t_bytes,
		['upload3'] = data.t_bytes,
		['upspeed'] = 0,
		['download1'] = 0,
		['download2'] = data.r_bytes,
		['download3'] = data.r_bytes,
		['download4'] = data.r_bytes,
		['downspeed'] = 0,
		['online'] = 0,
		['idle'] = 0,
		['devname'] = dev,
		['initail'] = now_uptime,
		['max_upload_speed_day'] = 0,
		['max_down_speed_day'] = 0,
		['maxuploadspeed'] = 0,
		['maxdownloadspeed'] = 0
	}
	return node
end


function update_nic(nic)
	for k, v in pairs(nic) do
		if (g.nic[k]) then
			-- nic 已存在
			--dlog("ip %s", k)

			g.nic[k]['upload1'] = g.nic[k]['upload2']
			g.nic[k]['upload2'] = v.t_bytes
			g.nic[k]['download1'] = g.nic[k]['download2']
			g.nic[k]['download2'] = v.r_bytes

			if ( g.nic[k]['upload2'] < g.nic[k]['upload1'] ) then
				-- 计数器变小,将上次的计数器保存后,重置
				dlog("mac[%s] upload[%.0f] pre upload[%.0f]",
				k, g.nic[k]['upload2'], g.nic[k]['upload1'])
				g.nic[k]['upload1'] = g.nic[k]['upload2']
				g.nic[k]['upspeed'] = 0
				g.nic[k]['onlinets'] = now_uptime
				g.nic[k]['initail'] = now_uptime
			elseif(g.nic[k]['upload2'] > g.nic[k]['upload1']) then
				-- 计数器变大,刷新活动时间,更新数据
				--dlog("upload2 > upload1")
				g.nic[k]['upspeed'] = math.floor((g.nic[k]['upload2'] - g.nic[k]['upload1']) / (now_uptime - last_uptime))
				g.nic[k]['maxuploadspeed'] = ((g.nic[k]['maxuploadspeed'] > g.nic[k]['upspeed'])
				and  g.nic[k]['maxuploadspeed'] ) or g.nic[k]['upspeed']
				g.nic[k]['max_upload_speed_day'] = ((g.nic[k]['max_upload_speed_day'] and g.nic[k]['max_upload_speed_day'] > g.nic[k]['upspeed'])
				and  g.nic[k]['max_upload_speed_day'] ) or g.nic[k]['upspeed']
			end


			if ( g.nic[k]['download2'] < g.nic[k]['download1'] ) then
				dlog("mac[%s] upload[%.0f] pre upload[%.0f]",
				k, g.nic[k]['download2'], g.nic[k]['download1'])
				g.nic[k]['download1'] = g.nic[k]['download2']
				g.nic[k]['downloadspeed'] = 0
				g.nic[k]['onlinets'] = now_uptime
				g.nic[k]['initail'] = now_uptime
			elseif(g.nic[k]['download2'] > g.nic[k]['download1']) then
				--dlog("download2 > download1")
				g.nic[k]['downspeed'] = math.floor((g.nic[k]['download2'] - g.nic[k]['download1']) / (now_uptime - last_uptime))
				g.nic[k]['maxdownloadspeed'] = ((g.nic[k]['maxdownloadspeed'] > g.nic[k]['downspeed'])
				and  g.nic[k]['maxdownloadspeed'] ) or g.nic[k]['downspeed']
				g.nic[k]['max_down_speed_day'] = ((g.nic[k]['max_down_speed_day'] and g.nic[k]['max_down_speed_day'] > g.nic[k]['downspeed'])
				and  g.nic[k]['max_down_speed_day'] ) or g.nic[k]['downspeed']
			end
			g.nic[k]['activets'] = now_uptime

		else
			-- new ip
			ilog("new nic add %s", k)
			g.nic[k] = init_nic_node(k, v)
		end
	end
end



function loop_main_nic()
	nic = get_nic()
	update_nic(nic)
	--commit_nic()
end

function newset()
	local reverse = {}
	local set = {}
	return setmetatable(set, {__index = {
		insert = function(set, value)
			if not reverse[value] then
				table.insert(set, value)
				reverse[value] = table.getn(set)
			end
		end,
		remove = function(set, value)
			local index = reverse[value]
			if index then
				reverse[value] = nil
				local top = table.remove(set)
				if top ~= value then
					reverse[top] = index
					set[index] = top
				end
			end
		end
	}})
end

function init_global()
	local pp = io.popen(cfg.cmd_get_model)
	local model = pp:read("*line")
	local reset_time = false
	if model == 'R1D' then
		HAVE_IPACC = true
		HAVE_POINT = true
	elseif model == 'R1CM' then
		HAVE_IWINFO = true
		HAVE_POINT = true
		local p = io.popen("lsmod | grep hw_nat")
		if p:read("*all"):match("hw_nat") then
			HAVE_HWNAT = true
		else
			HAVE_IPACC = true
		end
		p:close()
	elseif model == 'R1CQ' then
		HAVE_IPACC = true
		HAVE_IWINFO = true
		HAVE_POINT = true
	end
	pp:close()


	if(posix.stat(cfg.read_filename) == nil) then
		os.execute("mkdir -p " .. cfg.read_patch)
	end


	if(posix.stat(cfg.save_filename) == nil) then
		-- save_filename不存在，启动后第一次运行
		reset_time = true
		os.execute("mkdir -p " .. cfg.save_patch)
	else
		cfg.read_filename = cfg.save_filename
	end

	if((posix.stat(cfg.read_filename) == nil) or (cfg.load_cfg == 0)) then
		g.arp = {}
		g.nic = {}
		g.points = {}
		g.version = cfg.version
	else
		local status, err = pcall(
		function ()
			g = json.decode(read_file(cfg.read_filename))
			dlog("read data from %s", cfg.read_filename)
		end
		)
		if (not status) or (not g.version) or (g.version ~= cfg.version) then
			elog("the data file '%s' is not available!(%f)",cfg.read_filename, cfg.version)
			g = {}
			g.version = cfg.version
		end
		if(g.nic == nil) then
			g.nic = {}
		else
			for k, v in pairs(g.nic) do
				if reset_time then
					g.nic[k]['onlinets'] = now_uptime - cfg.online_timeout
					g.nic[k]['initail'] = now_uptime - cfg.online_timeout
					g.nic[k]['activets'] = now_uptime - cfg.online_timeout
				end
			end
		end
		if(g.arp == nil) then
			g.arp = {}
		else
			for k, v in pairs(g.arp) do
				if reset_time then
					g.arp[k]['onlinets'] = now_uptime - cfg.online_timeout
					g.arp[k]['initail'] = now_uptime - cfg.online_timeout
					g.arp[k]['activets'] = now_uptime - cfg.online_timeout

					g.arp[k]['points_time'] = 0
					g.arp[k]['points_tx'] = 0
					g.arp[k]['points_rx'] = 0
				end
			end
		end
		if(g.points == nil) then  g.points = {}  end
	end

	if HAVE_IPACC then
		libtraffic.ip_acc_init()
	end

	g.model = model
	g.arp = arp_data_clean()
	flush_wl_dev()
	g.wandev_name = wan_device()
	g.day_next_time = now_time.sec - ( (now_time.sec + cfg.systime_offset + cfg.points_offset) % cfg.time_step_day ) + cfg.time_step_day
	g.day_last_time = now_time.sec
	g.hour_next_time = now_time.sec - ( (now_time.sec + cfg.points_offset) % cfg.time_step_hour ) + cfg.time_step_hour
	g.hour_last_time = now_time.sec
	g.points.network_2_4G_secs = 0
	g.points.network_5G_secs = 0
	g.points.wan_device = g.wandev_name

	g.ten_minutes_next_time = now_time.sec - ( (now_time.sec + cfg.points_offset) % cfg.time_step_ten_minutes) + cfg.time_step_ten_minutes
	g.ten_minutes_last_time = now_time.sec

	g.points.network_traffic_10min = 0
	g.points.network_max_mac = 0

	loop_main_nic()
	if (not (g.wandev_name and g.nic[g.wandev_name])) then
		elog("wan device is not exist, traffic exit")
		os.exit(1)
	end

end

function get(action)

	local c = assert(socket.connect(cfg.host, cfg.port))
	local ret = {}
	local node

	dlog("connected!")

	local sent, err = c:send(action.."\n")
	dlog("c:send %s", action)
	if err then
		dlog("connect send error[%s]", err)
		os.exit()
	end

	local lines = ''
	while 1 do
		local line, err = c:receive()
		if not line or line == '' then
			if(err == "closed") then
				c:close()
				return ret
			else
				c:close()
				return ret
			end
		else
			node, _ = json.decode(line)
			table.insert(ret, node)
			--lines = lines .. line
		end
	end
	c:close()
	return ret
end


function loop_day()

	for k, v in pairs(sys.iwinfo) do
		if(v == "wl1") then
			g.points.network_2_4G_secs = g.points.network_2_4G_secs + cfg.time_step
		elseif(v == "wl0") then
			g.points.network_5G_secs = g.points.network_5G_secs + cfg.time_step
		end
	end

	if(g.day_next_time <= now_time.sec) then
		--

		g.points.network_2_4G_use = 0
		g.points.network_5G_use = 0
		for k,v in pairs(g.arp) do
			if( v.br_activets <= now_time.sec and (v.br_activets + cfg.time_step_day) >= now_time.sec) then
				--
				if(v.dev and v.dev == "wl1") then
					g.points.network_2_4G_use = g.points.network_2_4G_use + 1
				elseif(v.dev and v.dev == "wl0") then
					g.points.network_5G_use = g.points.network_5G_use + 1
				end
			end
		end

		local wan = g.wandev_name

		log_points("network_max_traffic_internal", g.nic['br-lan']['max_down_speed_day'] + g.nic['br-lan']['max_upload_speed_day'])
		log_points("network_max_traffic_external", g.nic[wan]['max_down_speed_day'])
		log_points("network_max_traffic_external_upload", g.nic[wan]['max_upload_speed_day'])
		log_points("network_2.4G_use", g.points.network_2_4G_use)
		log_points("network_2.4G_minutes", math.floor(g.points.network_2_4G_secs / 60))
		log_points("network_5G_use", g.points.network_5G_use)
		log_points("network_5G_minutes", math.floor(g.points.network_5G_secs / 60), 1)


		g.nic['br-lan']['max_down_speed_day'] =0
		g.nic['br-lan']['max_upload_speed_day'] = 0
		g.nic[wan]['max_down_speed_day'] = 0
		g.nic[wan]['max_upload_speed_day'] = 0
		g.points.network_2_4G_secs = 0
		g.points.network_5G_secs = 0
		g.points.network_2_4G_use = 0
		g.points.network_5G_use = 0

		g.day_next_time = now_time.sec - ( (now_time.sec + cfg.systime_offset + cfg.points_offset) % cfg.time_step_day ) + cfg.time_step_day
		g.day_last_time = now_time.sec
	end
end

function loop_hour()

	if(g.points.wan_last_device ~= g.points.wan_device) then
		-- wan口设备改变，重置计数器
		g.nic[g.points.wan_device].download3 = g.nic[g.points.wan_device].download1
		g.nic[g.points.wan_device].upload3 = g.nic[g.points.wan_device].upload1
		g.points.wan_last_device = g.points.wan_device
	end

	if(g.hour_next_time <= now_time.sec) then
		if(g.nic[g.points.wan_last_device].download1 >= g.nic[g.points.wan_last_device].download3) then
			g.points.network_traffic = g.nic[g.points.wan_last_device].download1 - g.nic[g.points.wan_last_device].download3
			+ g.nic[g.points.wan_last_device].upload1 - g.nic[g.points.wan_last_device].upload3

			log_points("network_traffic", string.format("%s:%f",os.date("%H",now_time.sec), math.floor(g.points.network_traffic)))

		end
		g.nic[g.points.wan_last_device].download3 = g.nic[g.points.wan_last_device].download1
		g.nic[g.points.wan_last_device].upload3 = g.nic[g.points.wan_last_device].upload1

		g.arp = arp_data_clean()
		collectgarbage("collect")
		flush_wl_dev()

		g.hour_next_time = now_time.sec - ( (now_time.sec + cfg.points_offset) % cfg.time_step_hour ) + cfg.time_step_hour
		g.hour_last_time = now_time.sec

		log_points("network_max_mac", string.format("%d",g.points.network_max_mac))
		g.points.network_max_mac = 0

		-- foreach arp and show last hour online station
		if HAVE_IPACC then
			local dev = require("xiaoqiang.util.XQDeviceUtil")
			local equ = require("xiaoqiang.XQEquipment")
			local dbDict = dev.getDeviceInfoFromDB()
			local dhcpDict = dev.getDHCPDict()
			local hostname
			for k,v in pairs(g.arp) do
				if v.points_time and v.points_time > 0 then
					if dbDict[k] and dbDict[k]['nickname'] ~= '' then
						hostname = dbDict[k]['nickname']
					else
						local dhcpname = dhcpDict[k] and dhcpDict[k]['name'] or ''
						if dhcpname == '' then
							local t = equ.identifyDevice(k, '')
							hostname = t.name
						else
							local t = equ.identifyDevice(k, dhcpname)
							if t.type.p + t.type.c > 0 then
								hostname = t.name
							else
								hostname = dhcpname
							end
						end
					end
					--mac|time|tx|rx|device|devname|hostname
					log_points("network_device_station", string.format("%s|%f|%f|%f|%s|%s",
						k, math.floor(v.points_time),
						math.floor(v.points_tx and v.points_tx or 0),
						math.floor(v.points_rx and v.points_rx or 0),
						v.dev, hostname))
					g.arp[k]['points_tx'] = 0
					g.arp[k]['points_rx'] = 0
					g.arp[k]['points_time'] = 0
				end
			end
		end
	end
end

function loop_ten_minutes()
	if(g.points.wan_last_device ~= g.points.wan_device) then
		-- wan口设备改变，重置计数器
		g.nic[g.points.wan_device].download4 = g.nic[g.points.wan_device].download1
		g.points.wan_last_device = g.points.wan_device
	end
	if(g.ten_minutes_next_time <= now_time.sec) then
		if g.nic[g.points.wan_last_device].download4
			and (g.nic[g.points.wan_last_device].download1 > g.nic[g.points.wan_last_device].download4) then
			g.points.network_traffic_10min = g.nic[g.points.wan_last_device].download1 - g.nic[g.points.wan_last_device].download4
			log_points("network_traffic_10min", string.format("%f", math.floor(g.points.network_traffic_10min)))
		end

		g.nic[g.points.wan_last_device].download4 = g.nic[g.points.wan_last_device].download1
		g.ten_minutes_next_time = now_time.sec - ( (now_time.sec + cfg.points_offset) % cfg.time_step_ten_minutes ) + cfg.time_step_ten_minutes
		g.ten_minutes_last_time = now_time.sec
	end
end

function main()

	local status, err = pcall(
	function ()
		if (cfg.daemon == 1) then
			posix.daemonize()
		end

		posix.openlog(arg[0], "cp", posix.LOG_LOCAL7)
		now_time = posix.gettimeofday()
		now_uptime = get_uptime()
		next_uptime = now_uptime - ( now_uptime % cfg.time_step ) + cfg.time_step
		save_next_time = {sec = now_time.sec - ( now_time.sec % cfg.time_step_save_file ) + cfg.time_step_save_file, usec = 0}
		init_global()
		g.proc = arg[0]

		dlog("Servers bound %s:%d", cfg.host, cfg.port)

		g.server = socket.bind(cfg.host, cfg.port)
		while (g.server == nil) do
			dlog("Servers bound %s:%d failed, sleep...", cfg.host, cfg.port)
			posix.sleep(2)
			g.server = socket.bind(cfg.host, cfg.port)
		end
		g.server:settimeout(1) -- make sure we don't block in accept

		dlog("Inserting servers in set")
		g.set = newset()
		g.set:insert(g.server)

	end
	)
	if not status then
		posix.syslog(posix.LOG_ERR, err)
	end

	while 1 do
		now_time = posix.gettimeofday()
		now_uptime = get_uptime()

		if (now_uptime >= next_uptime) then

			status, err = pcall(
			function ()
				--dlog("last_uptime %f now_uptime %f", last_uptime, now_uptime)
				loop_main_arp()
				loop_main_nic()
				if(now_time.sec >= save_next_time.sec ) then
					save_next_time = {sec = now_time.sec - ( now_time.sec % cfg.time_step_save_file ) + cfg.time_step_save_file, usec = 0}
					--if HAVE_IPACC then
					save_file(cfg.save_filename, json.encode(g))
					--end
					--flush_wl_dev()
				end
				--if HAVE_POINT then
				loop_ten_minutes()
				loop_hour()
				loop_day()
				--end
				last_uptime = now_uptime
			end
			)
			if not status then
				posix.syslog(posix.LOG_ERR, err)
			end
			--设置下一个采集点时间
			next_uptime = get_uptime() + cfg.time_step
		end

		local readable, _, error = socket.select(g.set, nil, next_uptime - now_uptime)
		for _, input in ipairs(readable) do
			-- server socket?
			if input == g.server then
				dlog("Waiting for clients")
				local new = input:accept()
				if new then
					new:settimeout(1)
					dlog("Inserting client in set")
					g.set:insert(new)
				end
				-- client socket
			else
				local line, error = input:receive()
				dlog("input receive [%s]", line)
				if error then
					input:close()
					dlog("Removing client from set[%s]", error)
					g.set:remove(input)
				else
					if(line == "arp")then
						output_arp(input)
					elseif (line == "nic") then
						output_nic(input)
					elseif (line == "wan") then
						output_wan(input)
					elseif (line == "lan") then
						output_lan(input)
					elseif (line == "client") then
						output_client(input)
					elseif (line == "flush_wl_dev") then
						flush_wl_dev()
						input:send(json.encode("done"))
					elseif (line == "flush_wan_dev") then
						flush_wan_dev()
						input:send(json.encode("done"))
					else
						input:send(json.encode("error command"))
					end
					input:send("\n")
					input:close()
					g.set:remove(input)
				end
			end
		end
	end
end


---------------------------- api

function output_arp(output)
	for k, v in pairs(g.arp) do
		local mac = sys.br.macs and sys.br.macs[v.hw] or nil
		output:send(json.encode({
			['MAC']              = v.hw,
			['IP']               = v.ip,
			['ONLINETS']         = math.floor(v.onlinets),
			['ACTIVETS']         = math.floor(v.activets),
			['UPLOAD']           = v.upload,
			['UPSPEED']          = v.activets + cfg.time_step >= now_uptime and v.upspeed or 0,
			['DOWNLOAD']         = v.download,
			['DOWNSPEED']        = v.activets + cfg.time_step >= now_uptime and v.downspeed or 0,
			['ONELINE']          = mac and math.floor(now_uptime - v.onlinets) or 0,
			['IDLE']             = mac and math.floor(mac.ageing_timer_sec) or 999,
			['DEVNAME']          = mac and sys.br.ports[mac.port] or '',
			['INITAIL']          = math.floor(v.initail),
			['MAXUPLOADSPEED']   = v.maxuploadspeed,
			['MAXDOWNLOADSPEED'] = v.maxdownloadspeed,
			['ASSOC']            = sys.iwinfo[v.hw] and 1 or 0
		}).."\n")
	end
end

function output_client(output)
	for k, v in pairs(g.arp) do
		local mac = sys.br.macs and sys.br.macs[v.hw] or nil
		if sys.iwinfo[v.hw] or (mac and sys.br.ports[mac.port]:match("eth")) then
			output:send(json.encode({
				['MAC']              = v.hw,
				['IP']               = v.ip,
				['ONLINETS']         = math.floor(v.onlinets),
				['ACTIVETS']         = math.floor(v.activets),
				['UPLOAD']           = v.upload,
				['UPSPEED']          = v.activets + cfg.time_step >= now_uptime and v.upspeed or 0,
				['DOWNLOAD']         = v.download,
				['DOWNSPEED']        = v.activets + cfg.time_step >= now_uptime and v.downspeed or 0,
				['ONELINE']          = mac and math.floor(now_uptime - v.onlinets) or 0,
				['IDLE']             = mac and math.floor(mac.ageing_timer_sec) or 999,
				['DEVNAME']          = mac and sys.br.ports[mac.port] or '',
				['INITAIL']          = math.floor(v.initail),
				['MAXUPLOADSPEED']   = v.maxuploadspeed,
				['MAXDOWNLOADSPEED'] = v.maxdownloadspeed,
				['ASSOC']            = sys.iwinfo[v.hw] and 1 or 0
			}).."\n")
		end
	end
end

--function output_client(output)
--	for _, tr_node in pairs(sys.tr) do
--		local ip = tr_node
--		if (sys.arp[tr_node.ip] and g.arp[sys.arp[tr_node.ip]['hw']]) then
--			local v = g.arp[sys.arp[tr_node.ip]['hw']]
--			local mac = sys.br.macs[v.hw]
--			output:send(json.encode({
--				['MAC']              = v.hw,
--				['IP']               = v.ip,
--				['ONLINETS']         = math.floor(v.onlinets),
--				['ACTIVETS']         = math.floor(v.activets),
--				['UPLOAD']           = v.upload,
--				['UPSPEED']          = v.activets + cfg.time_step >= now_uptime and v.upspeed or 0,
--				['DOWNLOAD']         = v.download,
--				['DOWNSPEED']        = v.activets + cfg.time_step >= now_uptime and v.downspeed or 0,
--				['ONELINE']          = mac and math.floor(now_uptime - v.onlinets) or 0,
--				['IDLE']             = mac and math.floor(mac.ageing_timer_sec) or 999,
--				['DEVNAME']          = mac and sys.br.ports[mac.port] or '',
--				['INITAIL']          = math.floor(v.initail),
--				['MAXUPLOADSPEED']   = v.maxuploadspeed,
--				['MAXDOWNLOADSPEED'] = v.maxdownloadspeed,
--				['ASSOC']            = sys.iwinfo[v.hw] and 1 or 0
--			}).."\n")
--		end
--	end
--end

function output_nic(output)
	for k, v in pairs(g.nic) do
		output:send(json.encode({
			['DEV']              = v.dev,
			['ONLINETS']         = math.floor(v.onlinets),
			['ACTIVETS']         = math.floor(v.activets),
			['UPLOAD']           = v.upload2,
			['UPSPEED']          = v.upspeed,
			['DOWNLOAD']         = v.download2,
			['DOWNSPEED']        = v.downspeed,
			['ONELINE']          = math.floor(now_uptime - v.onlinets),
			['IDLE']             = math.floor(now_uptime - v.activets),
			['DEVNAME']          = v.devname,
			['INITAIL']          = math.floor(v.initail),
			['MAXUPLOADSPEED']   = v.maxuploadspeed,
			['MAXDOWNLOADSPEED'] = v.maxdownloadspeed
		}).."\n")
	end
end

function output_wan(output)
	for k, v in pairs(g.nic) do
		if(v.dev == g.wandev_name) then
			output:send(json.encode({
				['DEV']              = v.dev,
				['ONLINETS']         = math.floor(v.onlinets),
				['ACTIVETS']         = math.floor(v.activets),
				['UPLOAD']           = v.upload2,
				['UPSPEED']          = v.upspeed,
				['DOWNLOAD']         = v.download2,
				['DOWNSPEED']        = v.downspeed,
				['ONELINE']          = math.floor(now_uptime - v.onlinets),
				['IDLE']             = math.floor(now_uptime - v.activets),
				['DEVNAME']          = v.devname,
				['INITAIL']          = math.floor(v.initail),
				['MAXUPLOADSPEED']   = v.maxuploadspeed,
				['MAXDOWNLOADSPEED'] = v.maxdownloadspeed
			}).."\n")
		end
	end
end

function output_lan(output)
	for k, v in pairs(g.nic) do
		if(v.dev == "br-lan") then
			output:send(json.encode({
				['DEV']              = v.dev,
				['ONLINETS']         = math.floor(v.onlinets),
				['ACTIVETS']         = math.floor(v.activets),
				['UPLOAD']           = v.upload2,
				['UPSPEED']          = v.upspeed,
				['DOWNLOAD']         = v.download2,
				['DOWNSPEED']        = v.downspeed,
				['ONELINE']          = math.floor(now_uptime - v.onlinets),
				['IDLE']             = math.floor(now_uptime - v.activets),
				['DEVNAME']          = v.devname,
				['INITAIL']          = math.floor(v.initail),
				['MAXUPLOADSPEED']   = v.maxuploadspeed,
				['MAXDOWNLOADSPEED'] = v.maxdownloadspeed
			}).."\n")
		end
	end
end




