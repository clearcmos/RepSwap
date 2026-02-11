-- RepSwitcher: Auto-switch watched reputation when entering dungeons/raids
-- For WoW Classic Anniversary Edition (2.5.5)

local addonName, addon = ...;

--------------------------------------------------------------------------------
-- Configuration Defaults
--------------------------------------------------------------------------------

local DEFAULT_SETTINGS = {
    enabled = true,
    restorePrevious = true,
    previousFactionID = nil,
    verbose = true,
};

--------------------------------------------------------------------------------
-- Local References
--------------------------------------------------------------------------------

local pairs = pairs;
local format = string.format;
local strlower = string.lower;
local strtrim = strtrim;
local GetNumFactions = GetNumFactions;
local GetFactionInfo = GetFactionInfo;
local ExpandFactionHeader = ExpandFactionHeader;
local CollapseFactionHeader = CollapseFactionHeader;
local SetWatchedFactionIndex = SetWatchedFactionIndex;
local GetInstanceInfo = GetInstanceInfo;
local IsInInstance = IsInInstance;
local UnitFactionGroup = UnitFactionGroup;
local GetTime = GetTime;

local ADDON_COLOR = "|cff8080ff";
local ADDON_PREFIX = ADDON_COLOR .. "RepSwitcher|r: ";

--------------------------------------------------------------------------------
-- Instance → Faction Mapping
-- Keys are instance names returned by GetInstanceInfo()
-- Values: { faction = ID } for universal, { alliance = ID, horde = ID } for split
--------------------------------------------------------------------------------

local INSTANCE_FACTION_MAP = {
    -- TBC Dungeons: Hellfire Citadel
    ["Hellfire Ramparts"]       = { alliance = 946, horde = 947 },  -- Honor Hold / Thrallmar
    ["The Blood Furnace"]       = { alliance = 946, horde = 947 },
    ["The Shattered Halls"]     = { alliance = 946, horde = 947 },

    -- TBC Dungeons: Coilfang Reservoir
    ["The Slave Pens"]          = { faction = 942 },  -- Cenarion Expedition
    ["The Underbog"]            = { faction = 942 },
    ["The Steamvault"]          = { faction = 942 },

    -- TBC Dungeons: Auchindoun
    ["Mana-Tombs"]              = { faction = 933 },  -- The Consortium
    ["Auchenai Crypts"]         = { faction = 1011 }, -- Lower City
    ["Sethekk Halls"]           = { faction = 1011 },
    ["Shadow Labyrinth"]        = { faction = 1011 },

    -- TBC Dungeons: Tempest Keep
    ["The Mechanar"]            = { faction = 935 },  -- The Sha'tar
    ["The Botanica"]            = { faction = 935 },
    ["The Arcatraz"]            = { faction = 935 },

    -- TBC Dungeons: Caverns of Time
    ["Old Hillsbrad Foothills"] = { faction = 989 },  -- Keepers of Time
    ["The Black Morass"]        = { faction = 989 },

    -- TBC Dungeons: Sunwell Isle
    ["Magister's Terrace"]      = { faction = 1077 }, -- Shattered Sun Offensive

    -- TBC Raids
    ["Karazhan"]                = { faction = 967 },  -- The Violet Eye
    ["Hyjal Summit"]            = { faction = 990 },  -- Scale of the Sands
    ["Black Temple"]            = { faction = 1012 }, -- Ashtongue Deathsworn

    -- Vanilla Dungeons
    ["Stratholme"]              = { faction = 529 },  -- Argent Dawn
    ["Scholomance"]             = { faction = 529 },
    ["Blackrock Depths"]        = { faction = 59 },   -- Thorium Brotherhood
    ["Dire Maul"]               = { faction = 809 },  -- Shen'dralar

    -- Vanilla Raids
    ["Molten Core"]             = { faction = 749 },  -- Hydraxian Waterlords
    ["Ruins of Ahn'Qiraj"]     = { faction = 609 },  -- Cenarion Circle
    ["Temple of Ahn'Qiraj"]    = { faction = 910 },  -- Brood of Nozdormu
    ["Zul'Gurub"]               = { faction = 270 },  -- Zandalar Tribe
    ["Naxxramas"]               = { faction = 529 },  -- Argent Dawn
};

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local db;
local playerFaction;       -- "Alliance" or "Horde"
local lastProcessedTime = 0;
local lastProcessedInstance = nil;
local DEBOUNCE_INTERVAL = 2;

local eventFrame = CreateFrame("Frame");

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

local function Print(msg)
    if db and db.verbose then
        print(ADDON_PREFIX .. msg);
    end
end

local function PrintAlways(msg)
    print(ADDON_PREFIX .. msg);
end

--- Get the target faction ID for the current instance based on player faction
local function GetFactionIDForInstance(instanceName)
    local entry = INSTANCE_FACTION_MAP[instanceName];
    if not entry then return nil; end

    if entry.faction then
        return entry.faction;
    end

    if playerFaction == "Alliance" then
        return entry.alliance;
    elseif playerFaction == "Horde" then
        return entry.horde;
    end

    return nil;
end

--- Get the faction ID currently being watched, or nil
local function GetCurrentWatchedFactionID()
    local data = C_Reputation.GetWatchedFactionData();
    if data and data.factionID and data.factionID ~= 0 then
        return data.factionID;
    end
    return nil;
end

--- Get faction name by ID (scans the reputation list)
local function GetFactionNameByID(targetFactionID)
    if not targetFactionID then return nil; end
    local numFactions = GetNumFactions();
    for i = 1, numFactions do
        local name, _, _, _, _, _, _, _, isHeader, _, _, _, _, factionID = GetFactionInfo(i);
        if factionID == targetFactionID then
            return name;
        end
    end
    return nil;
end

--------------------------------------------------------------------------------
-- Core: Find and Watch Faction by ID
-- Expands all collapsed headers, finds the faction index, sets watched, then
-- re-collapses previously collapsed headers.
--------------------------------------------------------------------------------

local function FindAndWatchFactionByID(targetFactionID)
    if not targetFactionID then return false; end

    -- Phase 1: Record and expand all collapsed headers
    -- Iterate backward because expanding changes indices above the expanded point
    local collapsedHeaders = {};  -- names of headers we expanded

    local expanded = true;
    while expanded do
        expanded = false;
        local numFactions = GetNumFactions();
        for i = numFactions, 1, -1 do
            local name, _, _, _, _, _, _, _, isHeader, isCollapsed = GetFactionInfo(i);
            if isHeader and isCollapsed then
                collapsedHeaders[name] = true;
                ExpandFactionHeader(i);
                expanded = true;
                break;  -- indices shifted, restart scan
            end
        end
    end

    -- Phase 2: Find the target faction index in the now fully-expanded list
    local targetIndex = nil;
    local numFactions = GetNumFactions();
    for i = 1, numFactions do
        local _, _, _, _, _, _, _, _, _, _, _, _, _, factionID = GetFactionInfo(i);
        if factionID == targetFactionID then
            targetIndex = i;
            break;
        end
    end

    -- Phase 3: Set watched faction
    local success = false;
    if targetIndex then
        SetWatchedFactionIndex(targetIndex);
        success = true;
    end

    -- Phase 4: Re-collapse headers we expanded (iterate backward)
    local recollapsed = true;
    while recollapsed do
        recollapsed = false;
        numFactions = GetNumFactions();
        for i = numFactions, 1, -1 do
            local name, _, _, _, _, _, _, _, isHeader, isCollapsed = GetFactionInfo(i);
            if isHeader and not isCollapsed and collapsedHeaders[name] then
                CollapseFactionHeader(i);
                collapsedHeaders[name] = nil;
                recollapsed = true;
                break;  -- indices shifted, restart
            end
        end
    end

    return success;
end

--------------------------------------------------------------------------------
-- Zone Change Processing
--------------------------------------------------------------------------------

local function ProcessZoneChange()
    if not db or not db.enabled then return; end

    local inInstance, instanceType = IsInInstance();

    if inInstance and (instanceType == "party" or instanceType == "raid") then
        local instanceName = GetInstanceInfo();
        if not instanceName then return; end

        -- Debounce: skip if same instance processed recently
        local now = GetTime();
        if instanceName == lastProcessedInstance and (now - lastProcessedTime) < DEBOUNCE_INTERVAL then
            return;
        end

        local targetFactionID = GetFactionIDForInstance(instanceName);
        if not targetFactionID then return; end

        -- Already watching the correct faction?
        local currentFactionID = GetCurrentWatchedFactionID();
        if currentFactionID == targetFactionID then
            lastProcessedInstance = instanceName;
            lastProcessedTime = now;
            return;
        end

        -- Save current faction before switching
        if db.restorePrevious and currentFactionID then
            db.previousFactionID = currentFactionID;
        end

        -- Switch to instance faction
        if FindAndWatchFactionByID(targetFactionID) then
            local factionName = GetFactionNameByID(targetFactionID) or tostring(targetFactionID);
            Print("Switched to |cffffd200" .. factionName .. "|r for " .. instanceName);
        end

        lastProcessedInstance = instanceName;
        lastProcessedTime = now;

    else
        -- Not in a mapped instance; restore previous if configured
        if db.restorePrevious and db.previousFactionID then
            local previousID = db.previousFactionID;
            db.previousFactionID = nil;

            if FindAndWatchFactionByID(previousID) then
                local factionName = GetFactionNameByID(previousID) or tostring(previousID);
                Print("Restored |cffffd200" .. factionName .. "|r");
            end
        end

        lastProcessedInstance = nil;
        lastProcessedTime = 0;
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

eventFrame:RegisterEvent("ADDON_LOADED");
eventFrame:RegisterEvent("PLAYER_LOGIN");
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA");

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...;
        if loaded ~= addonName then return; end

        -- Initialize SavedVariables
        if not RepSwitcherDB then
            RepSwitcherDB = {};
        end
        for k, v in pairs(DEFAULT_SETTINGS) do
            if RepSwitcherDB[k] == nil then
                RepSwitcherDB[k] = v;
            end
        end
        db = RepSwitcherDB;

        self:UnregisterEvent("ADDON_LOADED");

    elseif event == "PLAYER_LOGIN" then
        playerFaction = UnitFactionGroup("player");

        -- Delay initial check to let reputation data populate
        C_Timer.After(1, ProcessZoneChange);

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Delay slightly to ensure instance info is available
        C_Timer.After(0.5, ProcessZoneChange);

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        ProcessZoneChange();
    end
end);

--------------------------------------------------------------------------------
-- Slash Commands
--------------------------------------------------------------------------------

local function ShowStatus()
    PrintAlways("Status:");
    PrintAlways("  Enabled: " .. (db.enabled and "|cff00ff00yes|r" or "|cffff0000no|r"));
    PrintAlways("  Restore previous: " .. (db.restorePrevious and "|cff00ff00yes|r" or "|cffff0000no|r"));
    PrintAlways("  Verbose: " .. (db.verbose and "|cff00ff00yes|r" or "|cffff0000no|r"));

    local currentID = GetCurrentWatchedFactionID();
    if currentID then
        local name = GetFactionNameByID(currentID) or tostring(currentID);
        PrintAlways("  Watching: |cffffd200" .. name .. "|r");
    else
        PrintAlways("  Watching: |cff888888none|r");
    end

    if db.previousFactionID then
        local name = GetFactionNameByID(db.previousFactionID) or tostring(db.previousFactionID);
        PrintAlways("  Saved previous: |cffffd200" .. name .. "|r");
    end

    local inInstance, instanceType = IsInInstance();
    if inInstance then
        local instanceName = GetInstanceInfo();
        local targetID = GetFactionIDForInstance(instanceName);
        if targetID then
            local targetName = GetFactionNameByID(targetID) or tostring(targetID);
            PrintAlways("  Instance: |cffffd200" .. instanceName .. "|r → " .. targetName);
        else
            PrintAlways("  Instance: |cffffd200" .. instanceName .. "|r (not mapped)");
        end
    else
        PrintAlways("  Instance: not in one");
    end
end

local function ShowHelp()
    PrintAlways("Commands:");
    PrintAlways("  |cffffd200/rs|r - Show status");
    PrintAlways("  |cffffd200/rs on|off|r - Enable/disable");
    PrintAlways("  |cffffd200/rs restore on|off|r - Toggle restore previous");
    PrintAlways("  |cffffd200/rs verbose on|off|r - Toggle chat messages");
    PrintAlways("  |cffffd200/rs check|r - Manually trigger zone check");
    PrintAlways("  |cffffd200/rs clear|r - Clear saved previous faction");
    PrintAlways("  |cffffd200/rs list|r - List all mapped instances");
    PrintAlways("  |cffffd200/rs help|r - Show this help");
end

local function ShowList()
    PrintAlways("Mapped instances:");
    -- Build sorted list
    local entries = {};
    for instanceName, entry in pairs(INSTANCE_FACTION_MAP) do
        local factionID;
        if entry.faction then
            factionID = entry.faction;
        elseif playerFaction == "Alliance" then
            factionID = entry.alliance;
        else
            factionID = entry.horde;
        end
        local factionName = GetFactionNameByID(factionID) or tostring(factionID);
        entries[#entries + 1] = { instance = instanceName, faction = factionName };
    end
    table.sort(entries, function(a, b) return a.instance < b.instance; end);

    for _, e in ipairs(entries) do
        PrintAlways("  |cffffd200" .. e.instance .. "|r → " .. e.faction);
    end
end

local function SlashHandler(msg)
    if not db then return; end

    msg = strtrim(msg or "");
    local cmd, arg1 = msg:match("^(%S+)%s*(.*)$");
    cmd = cmd and strlower(cmd) or "";
    arg1 = arg1 and strtrim(strlower(arg1)) or "";

    if cmd == "" then
        ShowStatus();
    elseif cmd == "on" then
        db.enabled = true;
        PrintAlways("Enabled");
    elseif cmd == "off" then
        db.enabled = false;
        PrintAlways("Disabled");
    elseif cmd == "restore" then
        if arg1 == "on" then
            db.restorePrevious = true;
            PrintAlways("Restore previous: |cff00ff00on|r");
        elseif arg1 == "off" then
            db.restorePrevious = false;
            PrintAlways("Restore previous: |cffff0000off|r");
        else
            PrintAlways("Usage: /rs restore on|off");
        end
    elseif cmd == "verbose" then
        if arg1 == "on" then
            db.verbose = true;
            PrintAlways("Verbose: |cff00ff00on|r");
        elseif arg1 == "off" then
            db.verbose = false;
            PrintAlways("Verbose: |cffff0000off|r");
        else
            PrintAlways("Usage: /rs verbose on|off");
        end
    elseif cmd == "check" then
        PrintAlways("Checking zone...");
        ProcessZoneChange();
    elseif cmd == "clear" then
        db.previousFactionID = nil;
        PrintAlways("Cleared saved previous faction");
    elseif cmd == "list" then
        ShowList();
    elseif cmd == "help" then
        ShowHelp();
    else
        ShowHelp();
    end
end

SLASH_REPSWITCHER1 = "/repswitcher";
SLASH_REPSWITCHER2 = "/rs";
SlashCmdList["REPSWITCHER"] = SlashHandler;
