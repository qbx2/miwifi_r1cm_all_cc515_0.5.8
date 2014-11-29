local cjson=require("json")
local util=require("luci.util")

function lua_string_split(str, split_char)
	local sub_str_tab = {};
	while (true) do
	local pos = string.find(str, split_char);
	if (not pos) then
		sub_str_tab[#sub_str_tab + 1] = str;
	break;
	end
	local sub_str = string.sub(str, 1, pos - 1);
	sub_str_tab[#sub_str_tab + 1] = sub_str;
	str = string.sub(str, pos + 1, #str);
end

return sub_str_tab;
end

local data={}
local list={}
local list_rom={}
local list_web={}
local data_rom={}
local data_web={}
local arr_rom={}
local arr_web={}

file = io.open("/tmp/stat_points_rom.log","r")
if file ~= nil then
	for line in file:lines() do
		table.insert(arr_rom, line)
	end
file:close()
end

table.sort(arr_rom)
table.insert(arr_rom, "end")

local count=1
local tmp_line=nil
for k,line in pairs(arr_rom) do

if tmp_line ~= nil and tmp_line ~= line then
	local item={}
	local list = lua_string_split(tmp_line, '=')
	if #list == 2 then
		item['v']=util.trim(list[2])

		local sub_list = lua_string_split(list[1], ' ')
		if #sub_list == 2 then
			item['t']=util.trim(sub_list[2])
		else
			item['t']=util.trim(list[1])
		end
		item['c'] = count

		table.insert(data_rom, item)
	end

	count = 1
else
	count = count + 1
end
tmp_line = line
end

local file_storage_percent=util.trim(util.exec("df -h /userdisk/ | awk '{print $5}' | grep -v Use | awk -F '%' '{print $1}'"))
local item={}
item['v']=file_storage_percent
item['t']="file_storage_percent"
item['c']=1
table.insert(data_rom, item)

list_rom['source']="rom"
list_rom['data']=data_rom
table.insert(data, list_rom)

file = io.open("/tmp/stat_points_web.log","r")
if file ~= nil then
	for line in file:lines() do
		table.insert(arr_web, line)
	end
file:close()
end
table.sort(arr_web)
table.insert(arr_web, "end")

count=1
tmp_line=nil

for k,line in pairs(arr_web) do

if tmp_line ~= nil and tmp_line ~= line then
	local item={}
	local list = lua_string_split(tmp_line, '=')
	if #list == 2 then
		item['v']=util.trim(list[2])

		local sub_list = lua_string_split(list[1], ' ')
		if #sub_list == 2 then
			item['t']=util.trim(sub_list[2])
		else
			item['t']=util.trim(list[1])
		end
		item['c'] = count

		table.insert(data_web, item)
	end

	count = 1
else
	count = count + 1
end
tmp_line = line
end

if table.getn(data_web) > 0 then
list_web['source']="web"
list_web['data']=data_web
table.insert(data, list_web)
end

list['serialNumber']=util.trim(util.exec("nvram get SN") or "")
list['hardware']=util.trim(util.exec("nvram get model") or "")
list['list']=data

new_str=cjson.encode(list)

file = io.open("/tmp/stat_points.json","w")
if file == nil then
return
end
file:write(new_str)
file:close()
