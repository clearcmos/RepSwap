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
local ipairs = ipairs;
local format = string.format;
local strlower = string.lower;
local strtrim = strtrim;
local tinsert = table.insert;
local floor = math.floor;
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
local OptionsFrame;

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
    local collapsedHeaders = {};

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
                break;
            end
        end
    end

    -- Phase 2: Find the target faction index
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

    -- Phase 4: Re-collapse headers we expanded
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
                break;
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

        -- Debounce
        local now = GetTime();
        if instanceName == lastProcessedInstance and (now - lastProcessedTime) < DEBOUNCE_INTERVAL then
            return;
        end

        local targetFactionID = GetFactionIDForInstance(instanceName);
        if not targetFactionID then return; end

        local currentFactionID = GetCurrentWatchedFactionID();
        if currentFactionID == targetFactionID then
            lastProcessedInstance = instanceName;
            lastProcessedTime = now;
            return;
        end

        if db.restorePrevious and currentFactionID then
            db.previousFactionID = currentFactionID;
        end

        if FindAndWatchFactionByID(targetFactionID) then
            local factionName = GetFactionNameByID(targetFactionID) or tostring(targetFactionID);
            Print("Switched to |cffffd200" .. factionName .. "|r for " .. instanceName);
        end

        lastProcessedInstance = instanceName;
        lastProcessedTime = now;

    else
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
        C_Timer.After(1, ProcessZoneChange);

    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, ProcessZoneChange);

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        ProcessZoneChange();
    end
end);

--------------------------------------------------------------------------------
-- GUI: Widget Factories (matching MyDruid/HealerMana style)
--------------------------------------------------------------------------------

local FrameBackdrop = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
};

local function CreateCheckbox(parent, label, width)
    local container = CreateFrame("Frame", nil, parent);
    container:SetSize(width or 200, 24);

    local checkbox = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate");
    checkbox:SetPoint("LEFT");
    checkbox:SetSize(24, 24);

    local labelText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
    labelText:SetPoint("LEFT", checkbox, "RIGHT", 2, 0);
    labelText:SetText(label);

    checkbox:SetScript("OnClick", function(self)
        PlaySound(self:GetChecked() and 856 or 857);
        if container.OnValueChanged then
            container:OnValueChanged(self:GetChecked());
        end
    end);

    container.checkbox = checkbox;
    container.labelText = labelText;

    function container:SetValue(value)
        checkbox:SetChecked(value);
    end

    function container:GetValue()
        return checkbox:GetChecked();
    end

    return container;
end

--------------------------------------------------------------------------------
-- GUI: Options Frame
--------------------------------------------------------------------------------

local function CreateOptionsFrame()
    if OptionsFrame then return OptionsFrame; end

    local frame = CreateFrame("Frame", "RepSwitcherOptionsFrame", UIParent, "BackdropTemplate");
    frame:SetSize(340, 380);
    frame:SetPoint("CENTER");
    frame:SetBackdrop(FrameBackdrop);
    frame:SetBackdropColor(0, 0, 0, 1);
    frame:SetMovable(true);
    frame:EnableMouse(true);
    frame:SetToplevel(true);
    frame:SetFrameStrata("DIALOG");
    frame:SetFrameLevel(100);
    frame:Hide();

    -- Title bar
    local titleBg = frame:CreateTexture(nil, "OVERLAY");
    titleBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header");
    titleBg:SetTexCoord(0.31, 0.67, 0, 0.63);
    titleBg:SetPoint("TOP", 0, 12);
    titleBg:SetSize(180, 40);

    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    titleText:SetPoint("TOP", titleBg, "TOP", 0, -14);
    titleText:SetText("RepSwitcher");

    local titleBgL = frame:CreateTexture(nil, "OVERLAY");
    titleBgL:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header");
    titleBgL:SetTexCoord(0.21, 0.31, 0, 0.63);
    titleBgL:SetPoint("RIGHT", titleBg, "LEFT");
    titleBgL:SetSize(30, 40);

    local titleBgR = frame:CreateTexture(nil, "OVERLAY");
    titleBgR:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header");
    titleBgR:SetTexCoord(0.67, 0.77, 0, 0.63);
    titleBgR:SetPoint("LEFT", titleBg, "RIGHT");
    titleBgR:SetSize(30, 40);

    -- Title drag area
    local titleArea = CreateFrame("Frame", nil, frame);
    titleArea:SetAllPoints(titleBg);
    titleArea:EnableMouse(true);
    titleArea:SetScript("OnMouseDown", function() frame:StartMoving(); end);
    titleArea:SetScript("OnMouseUp", function() frame:StopMovingOrSizing(); end);

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton");
    closeBtn:SetPoint("TOPRIGHT", -5, -5);

    -- Content area
    local content = CreateFrame("Frame", nil, frame);
    content:SetPoint("TOPLEFT", 20, -30);
    content:SetPoint("BOTTOMRIGHT", -20, 50);

    local y = 0;

    --------------------------------
    -- Settings section
    --------------------------------
    local settingsHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    settingsHeader:SetPoint("TOPLEFT", 0, y);
    settingsHeader:SetText("Settings");
    settingsHeader:SetTextColor(1, 0.82, 0);
    y = y - 24;

    -- Enabled checkbox
    local enabledCb = CreateCheckbox(content, "Enable auto-switching", 280);
    enabledCb:SetPoint("TOPLEFT", 0, y);
    enabledCb:SetValue(db.enabled);
    enabledCb:EnableMouse(true);
    enabledCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText("Enable Auto-Switching", 1, 1, 1);
        GameTooltip:AddLine("Automatically switch your watched reputation when entering a mapped dungeon or raid.", 1, 0.82, 0, true);
        GameTooltip:Show();
    end);
    enabledCb:SetScript("OnLeave", function() GameTooltip:Hide(); end);
    enabledCb.OnValueChanged = function(self, value)
        db.enabled = value;
    end;
    y = y - 26;

    -- Restore previous checkbox
    local restoreCb = CreateCheckbox(content, "Restore previous rep on exit", 280);
    restoreCb:SetPoint("TOPLEFT", 0, y);
    restoreCb:SetValue(db.restorePrevious);
    restoreCb:EnableMouse(true);
    restoreCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText("Restore Previous", 1, 1, 1);
        GameTooltip:AddLine("When leaving a mapped instance, automatically switch back to the reputation you were tracking before.", 1, 0.82, 0, true);
        GameTooltip:Show();
    end);
    restoreCb:SetScript("OnLeave", function() GameTooltip:Hide(); end);
    restoreCb.OnValueChanged = function(self, value)
        db.restorePrevious = value;
    end;
    y = y - 26;

    -- Verbose checkbox
    local verboseCb = CreateCheckbox(content, "Show chat notifications", 280);
    verboseCb:SetPoint("TOPLEFT", 0, y);
    verboseCb:SetValue(db.verbose);
    verboseCb:EnableMouse(true);
    verboseCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText("Chat Notifications", 1, 1, 1);
        GameTooltip:AddLine("Print a message to chat when switching or restoring reputation.", 1, 0.82, 0, true);
        GameTooltip:Show();
    end);
    verboseCb:SetScript("OnLeave", function() GameTooltip:Hide(); end);
    verboseCb.OnValueChanged = function(self, value)
        db.verbose = value;
    end;
    y = y - 30;

    --------------------------------
    -- Status section
    --------------------------------
    local statusHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    statusHeader:SetPoint("TOPLEFT", 0, y);
    statusHeader:SetText("Status");
    statusHeader:SetTextColor(1, 0.82, 0);
    y = y - 20;

    local watchingLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
    watchingLabel:SetPoint("TOPLEFT", 4, y);
    watchingLabel:SetJustifyH("LEFT");
    watchingLabel:SetWidth(280);
    y = y - 16;

    local savedLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
    savedLabel:SetPoint("TOPLEFT", 4, y);
    savedLabel:SetJustifyH("LEFT");
    savedLabel:SetWidth(280);
    y = y - 16;

    local instanceLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
    instanceLabel:SetPoint("TOPLEFT", 4, y);
    instanceLabel:SetJustifyH("LEFT");
    instanceLabel:SetWidth(280);
    y = y - 24;

    local function UpdateStatus()
        -- Watching
        local currentID = GetCurrentWatchedFactionID();
        if currentID then
            local name = GetFactionNameByID(currentID) or tostring(currentID);
            watchingLabel:SetText("Watching: |cffffd200" .. name .. "|r");
        else
            watchingLabel:SetText("Watching: |cff888888none|r");
        end

        -- Saved previous
        if db.previousFactionID then
            local name = GetFactionNameByID(db.previousFactionID) or tostring(db.previousFactionID);
            savedLabel:SetText("Saved previous: |cffffd200" .. name .. "|r");
        else
            savedLabel:SetText("Saved previous: |cff888888none|r");
        end

        -- Instance
        local inInstance, instanceType = IsInInstance();
        if inInstance then
            local instanceName = GetInstanceInfo();
            local targetID = GetFactionIDForInstance(instanceName);
            if targetID then
                local targetName = GetFactionNameByID(targetID) or tostring(targetID);
                instanceLabel:SetText("Instance: |cffffd200" .. instanceName .. "|r");
            else
                instanceLabel:SetText("Instance: |cffffd200" .. instanceName .. "|r (unmapped)");
            end
        else
            instanceLabel:SetText("Instance: |cff888888not in one|r");
        end
    end

    --------------------------------
    -- Action buttons
    --------------------------------
    local checkBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate");
    checkBtn:SetSize(130, 22);
    checkBtn:SetPoint("TOPLEFT", 0, y);
    checkBtn:SetText("Check Zone Now");
    checkBtn:SetScript("OnClick", function()
        ProcessZoneChange();
        UpdateStatus();
    end);

    local clearBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate");
    clearBtn:SetSize(130, 22);
    clearBtn:SetPoint("TOPLEFT", 140, y);
    clearBtn:SetText("Clear Saved Rep");
    clearBtn:SetScript("OnClick", function()
        db.previousFactionID = nil;
        PrintAlways("Cleared saved previous faction");
        UpdateStatus();
    end);
    y = y - 34;

    --------------------------------
    -- Instance list section
    --------------------------------
    local listHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    listHeader:SetPoint("TOPLEFT", 0, y);
    listHeader:SetText("Mapped Instances");
    listHeader:SetTextColor(1, 0.82, 0);
    y = y - 4;

    -- Scrollable instance list
    local listFrame = CreateFrame("Frame", nil, content, "BackdropTemplate");
    listFrame:SetPoint("TOPLEFT", 0, y);
    listFrame:SetPoint("RIGHT", content, "RIGHT", 0, 0);
    listFrame:SetHeight(130);
    listFrame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    });
    listFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.8);
    listFrame:SetBackdropBorderColor(0.4, 0.4, 0.4);

    local scrollFrame = CreateFrame("ScrollFrame", "RepSwitcherListScroll", listFrame, "FauxScrollFrameTemplate");
    scrollFrame:SetPoint("TOPLEFT", 4, -4);
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 4);

    local ROW_HEIGHT = 14;
    local VISIBLE_ROWS = 9;
    local listRows = {};
    local sortedInstances = {};

    for i = 1, VISIBLE_ROWS do
        local row = CreateFrame("Frame", nil, listFrame);
        row:SetSize(1, ROW_HEIGHT);
        row:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT);
        row:SetPoint("RIGHT", scrollFrame, "RIGHT", 0, 0);

        row.instanceText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
        row.instanceText:SetPoint("LEFT", 2, 0);
        row.instanceText:SetJustifyH("LEFT");
        row.instanceText:SetWidth(150);

        row.factionText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
        row.factionText:SetPoint("LEFT", 158, 0);
        row.factionText:SetJustifyH("LEFT");

        listRows[i] = row;
    end

    local function BuildInstanceList()
        table.wipe(sortedInstances);
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
            tinsert(sortedInstances, { instance = instanceName, faction = factionName });
        end
        table.sort(sortedInstances, function(a, b) return a.instance < b.instance; end);
    end

    local function UpdateList()
        local offset = FauxScrollFrame_GetOffset(scrollFrame);
        FauxScrollFrame_Update(scrollFrame, #sortedInstances, VISIBLE_ROWS, ROW_HEIGHT);
        for i = 1, VISIBLE_ROWS do
            local row = listRows[i];
            local idx = offset + i;
            if idx <= #sortedInstances then
                local e = sortedInstances[idx];
                row.instanceText:SetText(e.instance);
                row.factionText:SetText("|cffaaaaaa" .. e.faction .. "|r");
                row:Show();
            else
                row:Hide();
            end
        end
    end

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UpdateList);
    end);

    -- Update status and list on show
    frame:SetScript("OnShow", function()
        UpdateStatus();
        BuildInstanceList();
        UpdateList();
    end);

    -- Bottom close button
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
    closeButton:SetSize(100, 22);
    closeButton:SetPoint("BOTTOM", 0, 15);
    closeButton:SetText("Close");
    closeButton:SetScript("OnClick", function()
        frame:Hide();
    end);

    -- ESC to close
    tinsert(UISpecialFrames, "RepSwitcherOptionsFrame");

    OptionsFrame = frame;
    return frame;
end

local function ToggleOptionsFrame()
    local frame = CreateOptionsFrame();
    if frame:IsShown() then
        frame:Hide();
    else
        frame:Show();
    end
end

--------------------------------------------------------------------------------
-- Slash Commands
--------------------------------------------------------------------------------

local function ShowHelp()
    PrintAlways("Commands:");
    PrintAlways("  |cffffd200/rs|r - Toggle options window");
    PrintAlways("  |cffffd200/rs check|r - Manually trigger zone check");
    PrintAlways("  |cffffd200/rs clear|r - Clear saved previous faction");
    PrintAlways("  |cffffd200/rs list|r - List all mapped instances in chat");
    PrintAlways("  |cffffd200/rs help|r - Show this help");
end

local function ShowList()
    PrintAlways("Mapped instances:");
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
        PrintAlways("  |cffffd200" .. e.instance .. "|r -> " .. e.faction);
    end
end

local function SlashHandler(msg)
    if not db then return; end

    msg = strtrim(msg or "");
    local cmd = msg:match("^(%S+)") or "";
    cmd = strlower(cmd);

    if cmd == "" then
        ToggleOptionsFrame();
    elseif cmd == "check" then
        ProcessZoneChange();
        PrintAlways("Zone check complete.");
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
