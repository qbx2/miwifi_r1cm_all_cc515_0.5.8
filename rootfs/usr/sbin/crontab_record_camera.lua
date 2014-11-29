#!/usr/bin/lua

local XQCameraUtil = require("xiaoqiang.util.XQCameraUtil")
local XQLog = require("xiaoqiang.XQLog")

function main()
    for k,v in pairs(XQCameraUtil.getAntsCams()) do
        -- load config
        local cfg = XQCameraUtil.getConfig(v.origin_name)
        if cfg.enable == "yes" then
            if cfg.hd == "yes" then
                ANTS_HTTP_BASE = ANTS_HTTP_BASE_MAIN
            else
                ANTS_HTTP_BASE = ANTS_HTTP_BASE_SUB
            end

            -- get days to download and delete
            local days = XQCameraUtil.getDay(cfg.days)
            -- get remote cam file list 
            local files = XQCameraUtil.getFilesOnCam(v,days)
            -- get all local file
            local localFiles = XQCameraUtil.getFilesOnRouter()
            -- delete local expired file
            XQCameraUtil.doDelete(localFiles,days)
            local downloadFiles = XQCameraUtil.mergeFiles(files,XQCameraUtil.getFilesOnRouter())
            if downloadFiles then
                for k1,v1 in pairs(downloadFiles) do 
                    XQCameraUtil.doDownload(v1)
                end
            end
        end 
    end
end



if XQCameraUtil.isRunning() then
    XQLog.log(2,"XQCameraUtil:record camera is running.. exit..")
else
    XQCameraUtil.writePID()
    local space = XQCameraUtil.getCurrentDisk()
    XQLog.log(2,"XQCameraUtil:".. XQCameraUtil.getModel().. " " ..  space .. "MB")
    if space > 4096 then
        main()
    end
end






