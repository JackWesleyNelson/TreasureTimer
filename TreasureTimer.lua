addon.name    = 'TreasureTimer';
addon.author  = 'Apples_mmmmmmmm';
addon.version = '1.0';
addon.desc    = 'Displays expected maximum respawn timers for chests/coffers based on last open attempt';
addon.link    = '';


require('common');

local imgui = require('imgui');
local data = require('Data');
local hidden = require('Hidden');
local helper = require('Helpers');
local settingsPath = string.format('%saddons\\%s\\WindowSettings.lua', AshitaCore:GetInstallPath(), addon.name);
local settings = require('WindowSettings');

local lastFrameTime = 0
local tick = 0
local startingGilAmount = 0
local currentGilAmount = 0
local startingGilTime = 0
local gilPerHour = 0
local config = false

local entityManager = AshitaCore:GetMemoryManager():GetEntity();
local playerManager = AshitaCore:GetMemoryManager():GetPlayer();
local partyManager = AshitaCore:GetMemoryManager():GetParty();

local function CheckPointInRangeOfTable(treasurePoints, playerPos, openMaxRangeSq)
    for _, p in ipairs(treasurePoints) do
        --Input data is in X,Z,Y format, playerPos is X,Y,Z
        local distanceSq = helper.DistanceSquaredXZY_XYZ(p, playerPos)
        if distanceSq <= openMaxRangeSq then
            return true
        end
    end
    return false
end

local function GetZoneChestTypeAsString(zoneID, playerPos, openingRange)
    local cofferAtKey = data.coffer[zoneID]
    local chestAtKey = data.chest[zoneID]
    local openingRangeSq = openingRange^2
    if (cofferAtKey) then
        if (CheckPointInRangeOfTable(cofferAtKey.points, playerPos, openingRangeSq)) then
            return "Coffer"
        end
    end
    if (chestAtKey) then
        if (CheckPointInRangeOfTable(chestAtKey.points, playerPos, openingRangeSq)) then
            return "Chest"
        end
    end
    return "Unknown"
end

local function CalculateElapsedTimeAsHours(start, current)
    local elapsedTime = current - start
    local hours = elapsedTime / 3600
    return hours
end

local function UpdateGilPerHour()
    local timeInHours = CalculateElapsedTimeAsHours(startingGilTime, os.clock())
    local gil = AshitaCore:GetMemoryManager():GetInventory():GetContainerItem(0, 0);
    if (gil) then
        currentGilAmount = gil.Count
        gilPerHour = math.floor((currentGilAmount - startingGilAmount) / timeInHours)
    end
end

local function ResetGilPerHour()
    local gil = AshitaCore:GetMemoryManager():GetInventory():GetContainerItem(0, 0);
    if (gil) then
        startingGilAmount = gil.Count        
        startingGilTime = os.clock()
    end
end

ashita.events.register('load', 'load_callback1', function()
    lastFrameTime = os.time()

end);

ashita.events.register('packet_in', 'packet_in_cb', function(e)
    -- Packet: Zone Leave
    if (e.id == 0x000B) then
        hidden.zoning = true;
        return;
    end

    -- Packet: Inventory Update Completed
    if (e.id == 0x001D) then
        hidden.zoning = false;
        -- if (startingGilAmount == 0 and (partyManager:GetMemberIsActive(0) ~= 0 or partyManager:GetMemberServerId(0) ~= 0)) then
        --     ResetGilPerHour()
        -- end
        return;
    end

    --[[
        -- msgBase offsets
        0 You unlock the chest!
        1 <name> fails to open the chest.
        2 The chest was trapped!
        3 You cannot open the chest when you are in a weakened state.
        4 The chest was a mimic!
        5 You cannot open the chest while participating in the moogle event.
        6 The chest was but an illusion...
        7 The chest appears to be locked. If only you had <item>, perhaps you could open it...
    --]]

    --[[
    if e.id == 0x02A then
        --I think these offsets are correct, but they might need to be +1?
        local entityId  = struct.unpack('I32', e.data, 0x04)
        local param0    = struct.unpack('I32', e.data, 0x08)
        local param1    = struct.unpack('I32', e.data, 0x0C)
        local param2    = struct.unpack('I32', e.data, 0x10)
        local param3    = struct.unpack('I32', e.data, 0x14)
        local targetID  = struct.unpack('I16', e.data, 0x18)
        local messageID = struct.unpack('I16', e.data, 0x1A)

        --We're gonna want to log these to a file to analyze the data later.
        print("Possible Chest Open Attempt, dumping data.\nValues:\nEntityID: "..entityId.."\nP0: "..param0.."\nP1: "..param1.."\nP2: "..param2.."\nP3: "..param3.."\nTargetID: "..targetID..'\nMessageID: '..messageID)
        print("Binary (least significant first):\nEntityID: "..decimalToBinary(entityId).."\nP0: "..decimalToBinary(param0).."\nP1: "..decimalToBinary(param1).."\nP2: "..decimalToBinary(param2).."\nP3: "..decimalToBinary(param3).."\nTargetID: "..decimalToBinary(targetID)..'\nMessageID: '..decimalToBinary(messageID))
        print("Hex :\nEntityID: "..decimalToHex(entityId).."\nP0: "..decimalToHex(param0).."\nP1: "..decimalToHex(param1).."\nP2: "..decimalToHex(param2).."\nP3: "..decimalToHex(param3).."\nTargetID: "..decimalToHex(targetID)..'\nMessageID: '..decimalToHex(messageID))
    end
     ]]
end);

ashita.events.register('packet_out', 'packet_out_cb', function(e)

end);

local function SetProgressData(zoneName, newCurrentValue)
    if data.progress[zoneName] then
        data.progress[zoneName].current = newCurrentValue
    else
        data.progress[zoneName] = { current = newCurrentValue }
    end
end

local function GetProgressDataCurrent(zoneName)
    if data.progress[zoneName] then
        return data.progress[zoneName].current
    end
end

local function UpdateProgressData(lastFrameTime, currentFrameTime)
    local timeElapsed = (currentFrameTime - lastFrameTime) / 60 -- Convert to minutes
    for k, v in pairs(data.progress) do
        if (v.current ~= nil) then
            v.current = math.max(v.current - timeElapsed, 0)
        end
    end
end


local function WriteWindow(settingsFile, windowName, position, size)
    local positionX, positionY = position[1], position[2]
    local sizeX, sizeY = size[1], size[2]

    settingsFile:write("M." .. windowName .. " = {\n")
    settingsFile:write("\tpositionX = " .. positionX .. ",\n")
    settingsFile:write("\tpositionY = " .. positionY .. ",\n")
    settingsFile:write("\tsizeX = " .. sizeX .. ",\n")
    settingsFile:write("\tsizeY = " .. sizeY .. ",\n")
    settingsFile:write("}\n")
end

local function SaveWindowSettings(windowNames, positions, sizes)
    local scriptPath = debug.getinfo(1, "S").source:sub(2)
    local scriptDir = scriptPath:match("(.*/)") or ""    
    local settingsFile = io.open(settingsPath, "w")
    if not settingsFile then
        print("TreasureTimer WindowSettings.lua not loaded")
        return
    end
    settingsFile:write("local M = {}\n")
    for i, name in ipairs(windowNames) do 
        WriteWindow(settingsFile, name, positions[i], sizes[i])
    end
    settingsFile:write("return M")
    settingsFile:close()  
end

local initWindows = false

local function RenderGPH(flags)
    imgui.SetNextWindowBgAlpha(0)
    if(not initWindows and settings) then
        local gphSettings = settings.gilPerHourWindow
        if gphSettings then        
            imgui.SetNextWindowPos({gphSettings.positionX, gphSettings.positionY})
            imgui.SetNextWindowSize({gphSettings.sizeX, gphSettings.sizeY})
        end
    end
    imgui.Begin("Gil Per Hour", true, flags)
    imgui.Text("Gil/H: " .. gilPerHour .. "g")
    if(settings and settings.gilPerHourWindow) then
        local windowPosX, windowPosY = imgui.GetWindowPos()
        settings.gilPerHourWindow.positionX = windowPosX
        settings.gilPerHourWindow.positionY = windowPosY

        local windowSizeX, windowSizeY = imgui.GetWindowSize()
        settings.gilPerHourWindow.sizeX = windowSizeX
        settings.gilPerHourWindow.sizeY = windowSizeY
    end
    imgui.End()

    if table.length(data.progress) <= 0 then
        return
    end
end

local function RenderTimers(flags)
    imgui.SetNextWindowBgAlpha(0)
    if(not initWindows and settings) then
        local pbSettings = settings.progressBarWindow
        if pbSettings then        
            imgui.SetNextWindowPos({pbSettings.positionX, pbSettings.positionY})
            imgui.SetNextWindowSize({pbSettings.sizeX, pbSettings.sizeY})
        end
    end  
    imgui.Begin("Progress Bars", true, flags)
    for k, v in pairs(data.progress) do
        local progressPercentage = (30 - v.current) / 30
        local sec = (v.current * 60) % 60
        local remainingTime = string.format("%02d:%02d", v.current, sec)

        imgui.Text(k)
        imgui.SameLine()
        imgui.Text(": ")
        imgui.SameLine()
        imgui.ProgressBar(progressPercentage, { -1.0, 0.0 }, remainingTime)
    end

    if(settings and settings.progressBarWindow) then
        local windowPosX, windowPosY = imgui.GetWindowPos()
        settings.progressBarWindow.positionX = windowPosX
        settings.progressBarWindow.positionY = windowPosY

        local windowSizeX, windowSizeY = imgui.GetWindowSize()
        settings.progressBarWindow.sizeX = windowSizeX
        settings.progressBarWindow.sizeY = windowSizeY
    end
    
    imgui.End()
end


local function Render()
    if (hidden.GetHidden()) then
        return
    end

    local flags = bit.bor(
        ImGuiWindowFlags_NoDecoration,
        --ImGuiWindowFlags_AlwaysAutoResize,
        ImGuiWindowFlags_NoSavedSettings,
        ImGuiWindowFlags_NoFocusOnAppearing,
        ImGuiWindowFlags_NoNav,
        ImGuiWindowFlags_NoBackground
    )

    if (config) then
        flags = 0
    end
    RenderGPH(flags)
    RenderTimers(flags)
    if(not initWindows) then
        initWindows = true
    end
end

ashita.events.register('text_in', 'text_in_cb', function(e)
    
    if (partyManager:GetMemberIsActive(0) == 0 or partyManager:GetMemberServerId(0) == 0) then
        return;
    end
    local zoneID = partyManager:GetMemberZone(0)
    local zoneName = AshitaCore:GetResourceManager():GetString('zones.names', zoneID);

    if (e.message_modified:contains("The chest was a mimic!")) then
        local myIndex = partyManager:GetMemberTargetIndex(0);
        local playerPos = { entityManager:GetLocalPositionX(myIndex), entityManager:GetLocalPositionY(myIndex),
            entityManager:GetLocalPositionZ(myIndex) }
        zoneName = zoneName .. " " .. GetZoneChestTypeAsString(zoneID, playerPos, 5.75)
        SetProgressData(zoneName, 30)
    elseif (e.message_modified:contains("You discern that the illusion will remain for ")) then
        --TODO: try to cut this code down by finding the second match of a valid number. Maybe we don't even have to do the silly check if number is 1 or 2 digits once we change to that.
        local rep = ashita.regex.replace(
        ashita.regex.replace(e.message_modified, "You discern that the illusion will remain for ", ""), " minutes.", "")
        local minutesRemaining = tonumber(helper.TrimWhiteSpace(string.sub(rep, string.len(rep) - 2)))
        if (minutesRemaining == nil) then
            minutesRemaining = tonumber(helper.TrimWhiteSpace(string.sub(rep, string.len(rep) - 1)))
        end

        local current = GetProgressDataCurrent(zoneName)
        if (current and math.floor(current) == minutesRemaining) then
            return
        end

        local myIndex = partyManager:GetMemberTargetIndex(0);
        local playerPos = { entityManager:GetLocalPositionX(myIndex), entityManager:GetLocalPositionY(myIndex),
            entityManager:GetLocalPositionZ(myIndex) }
        zoneName = zoneName .. " " .. GetZoneChestTypeAsString(zoneID, playerPos, 5.75)
        --Add 59 seconds and then set the table, so we don't open early.
        SetProgressData(zoneName, minutesRemaining + (59 / 60))
    elseif (e.message_modified:contains("You unlock the chest!")) then
        local myIndex = partyManager:GetMemberTargetIndex(0);
        local playerPos = { entityManager:GetLocalPositionX(myIndex), entityManager:GetLocalPositionY(myIndex),
            entityManager:GetLocalPositionZ(myIndex) }
        zoneName = zoneName .. " " .. GetZoneChestTypeAsString(zoneID, playerPos, 5.75)
        SetProgressData(zoneName, 30)
    elseif (e.message_modified:contains("fails to open the chest.")) then

    elseif (e.message_modified:contains("You cannot open the chest when you are in a weakened state.")) then

    elseif (e.message_modified:contains("The chest was trapped!")) then

    elseif (e.message_modified:contains("The chest appears to be locked. If only you had ")) then

    else
        return
    end
end);

ashita.events.register('d3d_present', 'mobdb_main_render', function()
    if (startingGilAmount == 0 and (partyManager:GetMemberIsActive(0) ~= 0 or partyManager:GetMemberServerId(0) ~= 0)) then
        ResetGilPerHour()
    end
    --We don't need to tick often.
    if (os.clock() - tick >= .25) then
        tick = os.clock()
        if(not hidden.GetHidden()) then
            local nowFrameTime = os.time()
            UpdateProgressData(lastFrameTime, nowFrameTime)
            lastFrameTime = nowFrameTime
            UpdateGilPerHour()
        end
    end

    Render()
end);

ashita.events.register('command', 'command_cb', function(e)
    local args = e.command:args();
    if (#args == 0) then
        return;
    end
    args[1] = string.lower(args[1]);
    if (args[1] ~= '/tt') and (args[1] ~= '/treasuretimer') then
        return;
    end
    e.blocked = true;

    if (#args > 1) then
        if (string.lower(args[2]) == "resetgil") then
            if (partyManager:GetMemberIsActive(0) ~= 0 or partyManager:GetMemberServerId(0) ~= 0) then
                ResetGilPerHour()
            end
        elseif (string.lower(args[2]) == "config") then
            config = not config
        end
    else
        print("Usage: Lockpick a chest to add or update the illusion timer for that zone.")
        print("OR /tt <\"ZoneName\"> <minutesRemaining>")
        print("to manually change the timer for an area.")
    end
    if (#args > 3) then
        if (args[2] == 'set' or args[2] == 'add') then
            local location = args[3]
            local timeInMinutes = args[4]
            SetProgressData(location, timeInMinutes)
        end
    end
end);


ashita.events.register('unload', 'unload_callback1', function ()
    local windowNames = {"gilPerHourWindow", "progressBarWindow"}
    local positions = {
        {settings.gilPerHourWindow.positionX, settings.gilPerHourWindow.positionY}, 
        {settings.progressBarWindow.positionX, settings.progressBarWindow.positionY},                     
    }
    local sizes = {
        {settings.gilPerHourWindow.sizeX, settings.gilPerHourWindow.sizeY}, 
        {settings.progressBarWindow.sizeX, settings.progressBarWindow.sizeY},
    }
    SaveWindowSettings(windowNames, positions, sizes)
end);