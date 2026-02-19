-- RepSync: Auto-switch watched reputation in dungeons, raids, and cities
-- For WoW Classic Anniversary Edition (2.5.5)

local addonName, addon = ...;

--------------------------------------------------------------------------------
-- Configuration Defaults
--------------------------------------------------------------------------------

local DEFAULT_SETTINGS = {
    enabled = true,
    restorePrevious = true,
    enableCities = true,
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
local GetSubZoneText = GetSubZoneText;
local GetTime = GetTime;

local ADDON_COLOR = "|cff8080ff";
local ADDON_PREFIX = ADDON_COLOR .. "RepSync|r: ";

--------------------------------------------------------------------------------
-- Instance → Faction Mapping
-- Keys are instanceID (8th return of GetInstanceInfo(), i.e. the map ID)
-- Values: { faction = ID } for universal, { alliance = ID, horde = ID } for split
--------------------------------------------------------------------------------

local INSTANCE_FACTION_MAP = {
    -- TBC Dungeons: Hellfire Citadel
    [543]  = { alliance = 946, horde = 947 },  -- Hellfire Ramparts → Honor Hold / Thrallmar
    [542]  = { alliance = 946, horde = 947 },  -- The Blood Furnace
    [540]  = { alliance = 946, horde = 947 },  -- The Shattered Halls

    -- TBC Dungeons: Coilfang Reservoir
    [547]  = { faction = 942 },   -- The Slave Pens → Cenarion Expedition
    [546]  = { faction = 942 },   -- The Underbog
    [545]  = { faction = 942 },   -- The Steamvault

    -- TBC Dungeons: Auchindoun
    [557]  = { faction = 933 },   -- Mana-Tombs → The Consortium
    [558]  = { faction = 1011 },  -- Auchenai Crypts → Lower City
    [556]  = { faction = 1011 },  -- Sethekk Halls
    [555]  = { faction = 1011 },  -- Shadow Labyrinth

    -- TBC Dungeons: Tempest Keep
    [554]  = { faction = 935 },   -- The Mechanar → The Sha'tar
    [553]  = { faction = 935 },   -- The Botanica
    [552]  = { faction = 935 },   -- The Arcatraz

    -- TBC Dungeons: Caverns of Time
    [560]  = { faction = 989 },   -- Old Hillsbrad Foothills → Keepers of Time
    [269]  = { faction = 989 },   -- The Black Morass

    -- TBC Dungeons: Sunwell Isle
    [585]  = { faction = 1077 },  -- Magister's Terrace → Shattered Sun Offensive

    -- TBC Raids
    [532]  = { faction = 967 },   -- Karazhan → The Violet Eye
    [534]  = { faction = 990 },   -- Hyjal Summit → Scale of the Sands
    [564]  = { faction = 1012 },  -- Black Temple → Ashtongue Deathsworn

    -- Vanilla Dungeons
    [329]  = { faction = 529 },   -- Stratholme → Argent Dawn
    [289]  = { faction = 529 },   -- Scholomance → Argent Dawn
    [230]  = { faction = 59 },    -- Blackrock Depths → Thorium Brotherhood
    [429]  = { faction = 809 },   -- Dire Maul → Shen'dralar

    -- Vanilla Raids
    [409]  = { faction = 749 },   -- Molten Core → Hydraxian Waterlords
    [509]  = { faction = 609 },   -- Ruins of Ahn'Qiraj → Cenarion Circle
    [531]  = { faction = 910 },   -- Temple of Ahn'Qiraj → Brood of Nozdormu
    [309]  = { faction = 270 },   -- Zul'Gurub → Zandalar Tribe
    [533]  = { faction = 529 },   -- Naxxramas → Argent Dawn
};

--------------------------------------------------------------------------------
-- City → Faction Mapping
-- Keys are uiMapID from C_Map.GetBestMapForUnit("player")
-- Values: { alliance = ID } or { horde = ID } (only triggers for matching faction)
--------------------------------------------------------------------------------

local CITY_FACTION_MAP = {
    -- Alliance Capitals (Classic Anniversary uiMapIDs)
    [1453] = { alliance = 72 },   -- Stormwind City → Stormwind
    [1455] = { alliance = 47 },   -- Ironforge → Ironforge
    [1457] = { alliance = 69 },   -- Darnassus → Darnassus
    [1947] = { alliance = 930 },  -- The Exodar → Exodar

    -- Horde Capitals (Classic Anniversary uiMapIDs)
    [1454] = { horde = 76 },      -- Orgrimmar → Orgrimmar
    [1456] = { horde = 81 },      -- Thunder Bluff → Thunder Bluff
    [1458] = { horde = 68 },      -- Undercity → Undercity
    [1954] = { horde = 911 },     -- Silvermoon City → Silvermoon City
};

--------------------------------------------------------------------------------
-- Sub-zone → Faction Mapping (Aldor Rise / Scryer's Tier)
-- Built from all locale names so GetSubZoneText() matches any client language
--------------------------------------------------------------------------------

local SUBZONE_FACTION_MAP = {};

local SUBZONE_LOCALE_DATA = {
    { factionID = 932, names = {  -- The Aldor
        "Aldor Rise",                    -- enUS
        "Aldorhöhe",                     -- deDE
        "Alto Aldor",                    -- esES / esMX
        "Éminence de l'Aldor",           -- frFR
        "Poggio degli Aldor",            -- itIT
        "Terraço dos Aldor",             -- ptBR
        "Возвышенность Алдоров",         -- ruRU
        "알도르 마루",                      -- koKR
        "奥尔多高地",                       -- zhCN
        "奧多爾高地",                       -- zhTW
    }},
    { factionID = 934, names = {  -- The Scryers
        "Scryer's Tier",                 -- enUS
        "Sehertreppe",                   -- deDE
        "Grada del Arúspice",            -- esES / esMX
        "Degré des Clairvoyants",        -- frFR
        "Loggia dei Veggenti",           -- itIT
        "Terraço dos Áugures",           -- ptBR
        "Ярус Провидцев",                -- ruRU
        "점술가 언덕",                      -- koKR
        "占星者之台",                       -- zhCN
        "占卜者階梯",                       -- zhTW
    }},
    { factionID = 54, names = {   -- Gnomeregan Exiles (Tinker Town in Ironforge)
        "Tinker Town",                   -- enUS
        "Tüftlerstadt",                  -- deDE
        "Ciudad Manitas",                -- esES / esMX
        "Brikabrok",                     -- frFR
        "Rabberciopoli",                 -- itIT
        "Beco da Gambiarra",             -- ptBR
        "Город Механиков",               -- ruRU
        "땜장이 마을",                      -- koKR
        "侏儒区",                          -- zhCN
        "地精區",                          -- zhTW
    }},
    { factionID = 530, names = {  -- Darkspear Trolls (Valley of Spirits in Orgrimmar)
        "Valley of Spirits",             -- enUS
        "Tal der Geister",               -- deDE
        "Valle de los Espíritus",        -- esES / esMX
        "Vallée des Esprits",            -- frFR
        "Valle degli Spiriti",           -- itIT
        "Vale dos Espíritos",            -- ptBR
        "Аллея Духов",                   -- ruRU
        "정기의 골짜기",                    -- koKR
        "精神谷",                          -- zhCN / zhTW
    }},

    -- Steamwheedle Cartel goblin towns
    { factionID = 21, names = {   -- Booty Bay
        "Booty Bay",                     -- enUS
        "Beutebucht",                    -- deDE
        "Bahía del Botín",               -- esES / esMX
        "Baie-du-Butin",                 -- frFR
        "Baia del Bottino",              -- itIT
        "Angra do Butim",                -- ptBR
        "Пиратская Бухта",               -- ruRU
        "무법항",                           -- koKR
        "藏宝海湾",                         -- zhCN
        "藏寶海灣",                         -- zhTW
    }},
    { factionID = 577, names = {  -- Everlook
        "Everlook",                      -- enUS
        "Ewige Warte",                   -- deDE
        "Vista Eterna",                  -- esES / esMX
        "Long-Guet",                     -- frFR
        "Lungavista",                    -- itIT
        "Visteterna",                    -- ptBR
        "Круговзор",                     -- ruRU
        "눈망루 마을",                      -- koKR
        "永望镇",                          -- zhCN
        "永望鎮",                          -- zhTW
    }},
    { factionID = 369, names = {  -- Gadgetzan
        "Gadgetzan",                     -- enUS / deDE / esES / esMX / frFR
        "Meccania",                      -- itIT
        "Geringontzan",                  -- ptBR
        "Прибамбасск",                   -- ruRU
        "가젯잔",                          -- koKR
        "加基森",                          -- zhCN / zhTW
    }},
    { factionID = 470, names = {  -- Ratchet
        "Ratchet",                       -- enUS
        "Ratschet",                      -- deDE
        "Trinquete",                     -- esES / esMX
        "Cabestan",                      -- frFR
        "Porto Paranco",                 -- itIT
        "Vila Catraca",                  -- ptBR
        "Кабестан",                      -- ruRU
        "톱니항",                           -- koKR
        "棘齿城",                          -- zhCN
        "棘齒城",                          -- zhTW
    }},

    -- TBC sub-zones
    { factionID = 970, names = {  -- Sporeggar
        "Sporeggar",                     -- enUS / deDE / frFR / itIT / ptBR
        "Esporaggar",                    -- esES / esMX
        "Спореггар",                     -- ruRU
        "스포어가르",                       -- koKR
        "孢子村",                          -- zhCN
        "斯博格爾",                         -- zhTW
    }},
    { factionID = 978, names = {  -- Kurenai (Telaar - Alliance town in Nagrand)
        "Telaar",                        -- enUS / deDE / esES / esMX / frFR / itIT / ptBR
        "Телаар",                        -- ruRU
        "텔라아르",                         -- koKR
        "塔拉",                            -- zhCN
        "泰拉",                            -- zhTW
    }},
    { factionID = 941, names = {  -- The Mag'har (Garadar - Horde town in Nagrand)
        "Garadar",                       -- enUS / deDE / esES / esMX / frFR / itIT / ptBR
        "Гарадар",                       -- ruRU
        "가라다르",                         -- koKR
        "加拉达尔",                         -- zhCN
        "卡拉達爾",                         -- zhTW
    }},

    -- Vanilla sub-zones
    { factionID = 609, names = {  -- Cenarion Circle (Cenarion Hold in Silithus)
        "Cenarion Hold",                 -- enUS
        "Burg Cenarius",                 -- deDE
        "Fuerte Cenarion",               -- esES / esMX
        "Fort Cénarien",                 -- frFR
        "Fortezza Cenariana",            -- itIT
        "Forte Cenariano",               -- ptBR
        "Крепость Кенария",              -- ruRU
        "세나리온 요새",                    -- koKR
        "塞纳里奥要塞",                     -- zhCN
        "塞納里奧城堡",                     -- zhTW
    }},
    { factionID = 529, names = {  -- Argent Dawn (Light's Hope Chapel in EPL)
        "Light's Hope Chapel",           -- enUS
        "Kapelle des Hoffnungsvollen Lichts", -- deDE
        "Capilla de la Esperanza de la Luz",  -- esES / esMX
        "Chapelle de l'Espoir de Lumière",    -- frFR
        "Cappella della Luce",           -- itIT
        "Capela Esperança da Luz",       -- ptBR
        "Часовня Последней Надежды",     -- ruRU
        "희망의 빛 예배당",                  -- koKR
        "圣光之愿礼拜堂",                   -- zhCN
        "聖光之願禮拜堂",                   -- zhTW
    }},
};

for _, entry in ipairs(SUBZONE_LOCALE_DATA) do
    for _, name in ipairs(entry.names) do
        SUBZONE_FACTION_MAP[name] = entry.factionID;
    end
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local db;
local playerFaction;       -- "Alliance" or "Horde"
local lastProcessedTime = 0;
local lastProcessedTarget = nil;
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

--- Get the target faction ID from an entry table based on player faction
local function GetFactionIDFromEntry(entry)
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

local FACTION_NAMES = {
    [946]  = "Honor Hold",              [947]  = "Thrallmar",
    [942]  = "Cenarion Expedition",     [933]  = "The Consortium",
    [1011] = "Lower City",              [935]  = "The Sha'tar",
    [989]  = "Keepers of Time",         [1077] = "Shattered Sun Offensive",
    [967]  = "The Violet Eye",          [990]  = "Scale of the Sands",
    [1012] = "Ashtongue Deathsworn",    [529]  = "Argent Dawn",
    [59]   = "Thorium Brotherhood",     [809]  = "Shen'dralar",
    [749]  = "Hydraxian Waterlords",    [609]  = "Cenarion Circle",
    [910]  = "Brood of Nozdormu",       [270]  = "Zandalar Tribe",
    [932]  = "The Aldor",              [934]  = "The Scryers",
    [54]   = "Gnomeregan Exiles",      [530]  = "Darkspear Trolls",
    [21]   = "Booty Bay",              [577]  = "Everlook",
    [369]  = "Gadgetzan",              [470]  = "Ratchet",
    [970]  = "Sporeggar",              [978]  = "Kurenai",
    [941]  = "The Mag'har",
    [72]   = "Stormwind",              [47]   = "Ironforge",
    [69]   = "Darnassus",              [930]  = "Exodar",
    [76]   = "Orgrimmar",              [81]   = "Thunder Bluff",
    [68]   = "Undercity",              [911]  = "Silvermoon City",
};

--- Get faction name by ID (tries rep panel first, falls back to static table)
local function GetFactionNameByID(targetFactionID)
    if not targetFactionID then return nil; end
    local numFactions = GetNumFactions();
    for i = 1, numFactions do
        local name, _, _, _, _, _, _, _, isHeader, _, _, _, _, factionID = GetFactionInfo(i);
        if factionID == targetFactionID then
            return name;
        end
    end
    return FACTION_NAMES[targetFactionID];
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

    local targetFactionID = nil;
    local contextLabel = nil;

    -- Priority 1: Instance detection
    local inInstance, instanceType = IsInInstance();
    if inInstance and (instanceType == "party" or instanceType == "raid") then
        local instanceName, _, _, _, _, _, _, instanceID = GetInstanceInfo();
        if instanceID then
            targetFactionID = GetFactionIDFromEntry(INSTANCE_FACTION_MAP[instanceID]);
            contextLabel = instanceName;
        end
    end

    -- Priority 2: Sub-zone detection (Aldor Rise / Scryer's Tier)
    if not targetFactionID and db.enableCities then
        local subZone = GetSubZoneText();
        if subZone and subZone ~= "" then
            targetFactionID = SUBZONE_FACTION_MAP[subZone];
            if targetFactionID then
                contextLabel = subZone;
            end
        end
    end

    -- Priority 3: Capital city detection
    if not targetFactionID and db.enableCities then
        local mapID = C_Map.GetBestMapForUnit("player");
        if mapID then
            local entry = CITY_FACTION_MAP[mapID];
            if entry then
                targetFactionID = GetFactionIDFromEntry(entry);
                if targetFactionID then
                    local mapInfo = C_Map.GetMapInfo(mapID);
                    contextLabel = mapInfo and mapInfo.name or tostring(mapID);
                end
            end
        end
    end

    -- Debounce
    local now = GetTime();

    if targetFactionID then
        if targetFactionID == lastProcessedTarget and (now - lastProcessedTime) < DEBOUNCE_INTERVAL then
            return;
        end

        local currentFactionID = GetCurrentWatchedFactionID();
        if currentFactionID == targetFactionID then
            lastProcessedTarget = targetFactionID;
            lastProcessedTime = now;
            return;
        end

        -- Only save previous if we don't already have one (preserves original across transitions)
        if db.restorePrevious and currentFactionID and not db.previousFactionID then
            db.previousFactionID = currentFactionID;
        end

        if FindAndWatchFactionByID(targetFactionID) then
            local factionName = GetFactionNameByID(targetFactionID) or tostring(targetFactionID);
            Print("Switched to |cffffd200" .. factionName .. "|r for " .. (contextLabel or ""));
        end

        lastProcessedTarget = targetFactionID;
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

        lastProcessedTarget = nil;
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
eventFrame:RegisterEvent("ZONE_CHANGED");

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...;
        if loaded ~= addonName then return; end

        if not RepSyncDB then
            RepSyncDB = {};
        end
        for k, v in pairs(DEFAULT_SETTINGS) do
            if RepSyncDB[k] == nil then
                RepSyncDB[k] = v;
            end
        end
        db = RepSyncDB;

        self:UnregisterEvent("ADDON_LOADED");

    elseif event == "PLAYER_LOGIN" then
        playerFaction = UnitFactionGroup("player");
        C_Timer.After(1, ProcessZoneChange);

    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, ProcessZoneChange);

    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" then
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

    local frame = CreateFrame("Frame", "RepSyncOptionsFrame", UIParent, "BackdropTemplate");
    frame:SetSize(280, 192);
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
    titleText:SetText("RepSync");

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
    content:SetPoint("TOPLEFT", 20, -40);
    content:SetPoint("BOTTOMRIGHT", -20, 15);

    local y = 0;

    -- Enabled checkbox
    local enabledCb = CreateCheckbox(content, "Enable auto-switching", 240);
    enabledCb:SetPoint("TOPLEFT", 0, y);
    enabledCb:SetValue(db.enabled);
    enabledCb:EnableMouse(true);
    enabledCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText("Enable Auto-Switching", 1, 1, 1);
        GameTooltip:AddLine("Automatically switch your reputation bar when entering a mapped dungeon, raid, or city.", 1, 0.82, 0, true);
        GameTooltip:Show();
    end);
    enabledCb:SetScript("OnLeave", function() GameTooltip:Hide(); end);
    enabledCb.OnValueChanged = function(self, value)
        db.enabled = value;
    end;
    y = y - 32;

    -- Restore previous checkbox
    local restoreCb = CreateCheckbox(content, "Restore previous rep on exit", 240);
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
    y = y - 32;

    -- Enable cities checkbox
    local citiesCb = CreateCheckbox(content, "Switch in cities & sub-zones", 240);
    citiesCb:SetPoint("TOPLEFT", 0, y);
    citiesCb:SetValue(db.enableCities);
    citiesCb:EnableMouse(true);
    citiesCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText("Cities & Sub-Zones", 1, 1, 1);
        GameTooltip:AddLine("Switch reputation when entering capital cities (Stormwind, Orgrimmar, etc.) and faction sub-zones (Aldor Rise, Scryer's Tier).", 1, 0.82, 0, true);
        GameTooltip:Show();
    end);
    citiesCb:SetScript("OnLeave", function() GameTooltip:Hide(); end);
    citiesCb.OnValueChanged = function(self, value)
        db.enableCities = value;
    end;

    -- ESC to close
    tinsert(UISpecialFrames, "RepSyncOptionsFrame");

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
    PrintAlways("  |cffffd200/rs clear|r - Clear saved previous faction");
    PrintAlways("  |cffffd200/rs list|r - List all mapped instances in chat");
    PrintAlways("  |cffffd200/rs help|r - Show this help");
end

local INSTANCE_NAMES = {
    [543] = "Hellfire Ramparts",    [542] = "The Blood Furnace",    [540] = "The Shattered Halls",
    [547] = "The Slave Pens",       [546] = "The Underbog",         [545] = "The Steamvault",
    [557] = "Mana-Tombs",           [558] = "Auchenai Crypts",      [556] = "Sethekk Halls",
    [555] = "Shadow Labyrinth",     [554] = "The Mechanar",         [553] = "The Botanica",
    [552] = "The Arcatraz",         [560] = "Old Hillsbrad",        [269] = "The Black Morass",
    [585] = "Magister's Terrace",   [532] = "Karazhan",             [534] = "Hyjal Summit",
    [564] = "Black Temple",         [329] = "Stratholme",           [289] = "Scholomance",
    [230] = "Blackrock Depths",     [429] = "Dire Maul",            [409] = "Molten Core",
    [509] = "Ruins of Ahn'Qiraj",  [531] = "Temple of Ahn'Qiraj",  [309] = "Zul'Gurub",
    [533] = "Naxxramas",
};

local CITY_NAMES = {
    [1453] = "Stormwind City",      [1455] = "Ironforge",
    [1457] = "Darnassus",           [1947] = "The Exodar",
    [1454] = "Orgrimmar",           [1456] = "Thunder Bluff",
    [1458] = "Undercity",           [1954] = "Silvermoon City",
};

local function ShowList()
    PrintAlways("Mapped locations:");

    local entries = {};

    -- Instances
    for instanceID, entry in pairs(INSTANCE_FACTION_MAP) do
        local factionID = GetFactionIDFromEntry(entry);
        if factionID then
            local factionName = GetFactionNameByID(factionID) or tostring(factionID);
            local instanceName = INSTANCE_NAMES[instanceID] or tostring(instanceID);
            entries[#entries + 1] = { location = instanceName, faction = factionName };
        end
    end

    -- Cities
    for mapID, entry in pairs(CITY_FACTION_MAP) do
        local factionID = GetFactionIDFromEntry(entry);
        if factionID then
            local factionName = GetFactionNameByID(factionID) or tostring(factionID);
            local cityName = CITY_NAMES[mapID] or tostring(mapID);
            entries[#entries + 1] = { location = cityName, faction = factionName };
        end
    end

    -- Sub-zones (show English names only)
    for _, data in ipairs(SUBZONE_LOCALE_DATA) do
        local factionName = GetFactionNameByID(data.factionID) or tostring(data.factionID);
        entries[#entries + 1] = { location = data.names[1], faction = factionName };
    end

    table.sort(entries, function(a, b) return a.location < b.location; end);

    for _, e in ipairs(entries) do
        PrintAlways("  |cffffd200" .. e.location .. "|r -> " .. e.faction);
    end
end

local function SlashHandler(msg)
    if not db then return; end

    msg = strtrim(msg or "");
    local cmd = msg:match("^(%S+)") or "";
    cmd = strlower(cmd);

    if cmd == "" then
        ToggleOptionsFrame();
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

SLASH_REPSYNC1 = "/repsync";
SLASH_REPSYNC2 = "/rs";
SlashCmdList["REPSYNC"] = SlashHandler;
