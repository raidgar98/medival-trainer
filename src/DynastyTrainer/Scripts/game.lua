-- Access to the game's objects. No UI here; functions raise errors with
-- translation keys ("err:<key>") so the menu can show them in any language.
--
-- Sources of names used here:
--   * PDB (native C++): UStatsComponentBase skills (FST_Skills), IHealthInterface,
--     UCheatManager / UMD_CheatManager, APlayerController::FOV.
--   * Other working mods: InventoryComponent.Inventory_New, AddItemToInventory,
--     SystemsManagerReference.TimeManagerReference.Time, BP_Marker_Village_C,
--     DT_ListOfItems, K2_SetActorLocation.
--   * Everything else is discovered at runtime (see reflect / findProp).

local UEHelpers = require("UEHelpers")

local M = {}

local COIN_ID = "Coin"
local COIN_SCALE = 10          -- the game stores coins in tenths
local INT32_MAX = 2147483647

-- EInternalObjectFlags::PendingKill | Unreachable: objects the engine is
-- destroying (e.g. NPCs streaming out). Touching them can crash inside UE4SS.
local DYING = 0x30000000

local function valid(o)
    local tp = type(o)
    if not ((tp == "userdata" or tp == "table") and o:IsValid() == true) then return false end
    if o.HasAnyInternalFlags then
        local ok, dying = pcall(o.HasAnyInternalFlags, o, DYING)
        if ok and dying then return false end
    end
    return true
end
M.valid = valid

local function fail(key) error("err:" .. key, 0) end
M.fail = fail

---------------------------------------------------------------------------
-- Reflection helpers
---------------------------------------------------------------------------
local NUMERIC = { FloatProperty = true, DoubleProperty = true, IntProperty = true, ByteProperty = true,
    Int64Property = true, UInt32Property = true, Int16Property = true, UInt16Property = true }
M.NUMERIC = NUMERIC

-- All properties of an object's class chain: { {name=, type=, owner=}, ... }.
-- stopAt: class name (without _C) where to stop walking up (exclusive), optional.
function M.reflect(obj, stopAt)
    local out = {}
    local cls = obj:GetClass()
    while valid(cls) do
        local cname = cls:GetFName():ToString()
        if stopAt and cname == stopAt then break end
        cls:ForEachProperty(function(p)
            out[#out + 1] = { name = p:GetFName():ToString(), type = p:GetClass():GetFName():ToString(), owner = cname }
        end)
        cls = cls:GetSuperStruct()
    end
    return out
end

-- Field name inside a Blueprint struct ("Count_12_ABC..." for prefix "Count").
local fieldCache = {}
local function field(struct, prefix)
    local found
    struct:ForEachProperty(function(p)
        local n = p:GetFName():ToString()
        if n == prefix or n:match("^" .. prefix .. "_%d+_") then found = n; return true end
    end)
    return found
end
M.field = field

local function mustField(struct, prefix)
    return assert(field(struct, prefix), "Missing struct field: " .. prefix)
end

-- Find a numeric/bool property by candidate names (exact, case-insensitive),
-- then by tokens (all tokens contained, none of the excluded words).
-- spec = { exact = {...}, tokens = {{"stamina"}}, exclude = {...}, types = {...} }
function M.findProp(props, spec)
    local types = spec.types or NUMERIC
    local lower = {}
    for _, p in ipairs(props) do
        if types[p.type] then lower[#lower + 1] = { p = p, l = p.name:lower() } end
    end
    for _, want in ipairs(spec.exact or {}) do
        local w = want:lower()
        for _, e in ipairs(lower) do if e.l == w then return e.p end end
    end
    for _, group in ipairs(spec.tokens or {}) do
        for _, e in ipairs(lower) do
            local ok = true
            for _, t in ipairs(group) do if not e.l:find(t, 1, true) then ok = false; break end end
            if ok then
                for _, x in ipairs(spec.exclude or {}) do if e.l:find(x, 1, true) then ok = false; break end end
            end
            if ok then return e.p end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Player, controller, components
---------------------------------------------------------------------------
function M.player()
    local pc = UEHelpers.GetPlayerController()
    if not valid(pc) or not valid(pc.Pawn) then fail("load_save_first") end
    local name = pc.Pawn:GetFullName()
    if not name:find("/Game/Maps/", 1, true) or name:find("P_InitPawn", 1, true) then
        fail("load_save_first")
    end
    return pc.Pawn, pc
end

function M.inventory()
    local inv = M.player().InventoryComponent
    if not valid(inv) then fail("no_inventory") end
    return inv
end

-- The player's BP_CharacterStatsComponent (subclass of native UStatsComponentBase).
local statsCache
function M.stats()
    local pawn = M.player()
    if valid(statsCache) and statsCache:GetOuter() == pawn then return statsCache end
    statsCache = nil
    local pawnName = pawn:GetFullName():match("^%S+%s+(.+)$") or pawn:GetFullName()
    for _, c in ipairs(FindAllOf("BP_CharacterStatsComponent_C") or {}) do
        if valid(c) and c:GetFullName():find(pawnName, 1, true) then statsCache = c; break end
    end
    if not statsCache then fail("no_stats") end
    return statsCache
end

function M.cheatManager()
    local _, pc = M.player()
    local cm = pc.CheatManager
    if not valid(cm) then fail("no_cheat_manager") end
    return cm
end

function M.timeManager()
    local pawn = M.player()
    local sys = pawn.SystemsManagerReference
    if not valid(sys) then fail("systems_loading") end
    local tm = sys.TimeManagerReference
    if not valid(tm) then fail("systems_loading") end
    return tm
end

function M.villageManager()
    M.player()
    for _, vm in ipairs(FindAllOf("BP_VillageManager_C") or {}) do
        if valid(vm) and not vm:GetFullName():find("Default__", 1, true) then return vm end
    end
    fail("systems_loading")
end

local gameplayStatics
function M.statics()
    if not valid(gameplayStatics) then gameplayStatics = StaticFindObject("/Script/Engine.Default__GameplayStatics") end
    return gameplayStatics
end

---------------------------------------------------------------------------
-- Health (native IHealthInterface on ACharacterBase)
---------------------------------------------------------------------------
function M.health()
    local pawn = M.player()
    return pawn:GetHealth(), pawn:GetMaxHealth()
end

function M.setHealth(v) M.player():SetHealth(v) end
function M.setMaxHealth(v) M.player():SetMaxHealth(v) end

---------------------------------------------------------------------------
-- Skills (native FST_Skills structs on UStatsComponentBase)
---------------------------------------------------------------------------
M.SKILLS = { "ExtractionSkill", "HuntingSkill", "FarmingSkill", "DiplomacySkill", "SurvivalSkill", "CraftingSkill" }

function M.skill(name)
    local s = M.stats()[name]
    if s == nil then fail("no_stats") end
    return s
end

function M.addSkillPoints(name, n)
    local s = M.skill(name)
    local v = math.max(0, math.min(255, math.floor(s.SkillPointsToSpend + n)))
    s.SkillPointsToSpend = v
    return v
end

function M.maxSkillLevel(name)
    local s = M.skill(name)
    s.ActualLevel = s.MaxLevel
    return s.MaxLevel
end

---------------------------------------------------------------------------
-- Village: dynasty reputation and technology (BP_VillageManager_C)
---------------------------------------------------------------------------
M.TECHNOLOGIES = { "Building", "Crafting", "Farming", "Survival" }

function M.reputation() return M.villageManager().DynastyReputation end

function M.addReputation(n)
    local vm = M.villageManager()
    vm.DynastyReputation = math.max(0, math.min(INT32_MAX, vm.DynastyReputation + math.floor(n)))
    return vm.DynastyReputation
end

function M.addTechnology(kind, n)
    local vm = M.villageManager()
    local name = "TechnologyLevel_" .. kind
    vm[name] = vm[name] + n
    return vm[name]
end

function M.age() return M.stats().Age end

function M.setAge(years)
    years = tonumber(years)
    if not years or years < 14 or years > 59 then fail("invalid_age") end
    M.stats().Age = years
end

---------------------------------------------------------------------------
-- Inventory / items
---------------------------------------------------------------------------
local function itemCountRaw(inv, id)
    local count = 0
    inv.Inventory_New:ForEach(function(key, value)
        if key:get():ToString() == id then
            local group = value:get()
            group[mustField(group, "Items")]:ForEach(function(_, element)
                local item = element:get()
                count = count + item[mustField(item, "Count")]
            end)
        end
    end)
    return count
end

local function scale(id) return id == COIN_ID and COIN_SCALE or 1 end

function M.itemCount(id) return itemCountRaw(M.inventory(), id) // scale(id) end
function M.coins() return M.itemCount(COIN_ID) end

-- Returns added, total (in display units).
function M.addItem(id, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then fail("invalid_amount") end
    if not id or id == "" then fail("select_item") end
    local inv = M.inventory()
    local s = scale(id)
    local raw = amount * s
    local before = itemCountRaw(inv, id)
    if before + raw > INT32_MAX then fail("item_limit") end
    inv:AddItemToInventory(FName(id), raw, false, 100, 100, 0, 1, 0, true, true, false, 0, {})
    pcall(function() inv:UpdateTotalWeightOfInventory() end)
    local after = itemCountRaw(inv, id)
    return (after - before) // s, after // s
end

function M.addCoins(amount) return M.addItem(COIN_ID, amount) end

-- Row names of a DataTable (UE4SS ForEachRow, or the engine library as fallback).
function M.rowNames(dt)
    local ids = {}
    local ok = pcall(function()
        dt:ForEachRow(function(name) ids[#ids + 1] = type(name) == "string" and name or name:ToString() end)
    end)
    if not ok or #ids == 0 then
        ids = {}
        local lib = StaticFindObject("/Script/Engine.Default__DataTableFunctionLibrary")
        local out = {}
        lib:GetDataTableRowNames(dt, out)
        local arr = out.OutRowNames or out
        if type(arr) == "table" then
            for _, n in ipairs(arr) do ids[#ids + 1] = type(n) == "string" and n or n:ToString() end
        else
            arr:ForEach(function(_, n) ids[#ids + 1] = n:get():ToString() end)
        end
    end
    return ids
end

local function dataTable(path)
    local dt = StaticFindObject(path)
    if not valid(dt) then pcall(function() dt = LoadAsset(path) end) end
    if not valid(dt) then fail("systems_loading") end
    return dt
end

function M.reputationLimits()
    return dataTable("/Game/Blueprints/DataTables/DT_ReputationLimits.DT_ReputationLimits")
end

-- Item catalogue from DT_ListOfItems: { {id=, name=}, ... } sorted by name.
local itemList
function M.items()
    if itemList then return itemList end
    local dt = StaticFindObject("/Game/Blueprints/DataTables/DT_ListOfItems.DT_ListOfItems")
    if not valid(dt) then fail("items_loading") end
    local ids = M.rowNames(dt)
    local list = {}
    local nameField, settingsField, settingsNameField
    for _, id in ipairs(ids) do
        local label = id
        pcall(function()
            local row = dt:FindRow(id)
            if not row then return end
            nameField = nameField or field(row, "Name") or false
            if nameField then
                label = row[nameField]:ToString()
            else
                settingsField = settingsField or field(row, "Settings") or false
                if settingsField then
                    local s = row[settingsField]
                    settingsNameField = settingsNameField or field(s, "Name") or false
                    if settingsNameField then label = s[settingsNameField]:ToString() end
                end
            end
        end)
        if label == "" then label = id end
        list[#list + 1] = { id = id, name = label }
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    itemList = list
    return list
end

---------------------------------------------------------------------------
-- Time (BP_TimeManager.Time = ST_Time {Year, Season, Day, Hour, Minute, Second})
---------------------------------------------------------------------------
local TIME_FIELDS = { "Year", "Season", "Day", "Hour", "Minute", "Second" }

function M.readTime()
    local tm = M.timeManager()
    local t = tm.Time
    local out = { seasonDays = tm.Timespan }
    for _, n in ipairs(TIME_FIELDS) do out[n:lower()] = t[mustField(t, n)] end
    return out
end

function M.writeTime(values)
    local t = M.timeManager().Time
    for _, n in ipairs(TIME_FIELDS) do
        local v = values[n:lower()]
        if v ~= nil then t[mustField(t, n)] = math.floor(v) end
    end
end

function M.setGameSpeed(x)
    local pawn = M.player()
    M.statics():SetGlobalTimeDilation(pawn, x)
end

---------------------------------------------------------------------------
-- Teleport
---------------------------------------------------------------------------
function M.villages()
    local out = {}
    for _, v in ipairs(FindAllOf("BP_Marker_Village_C") or {}) do
        if valid(v) and not v:GetFullName():find("Default__", 1, true) then
            local p = v:K2_GetActorLocation()
            out[#out + 1] = { name = v.Name:ToString(), x = p.X, y = p.Y, z = p.Z }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function M.position()
    local p = M.player():K2_GetActorLocation()
    return { x = p.X, y = p.Y, z = p.Z }
end

function M.teleport(pos, lift)
    local pawn = M.player()
    pawn:K2_SetActorLocation({ X = pos.x, Y = pos.y, Z = pos.z + (lift or 0) }, false, {}, true)
end

local navCache
local function navigation()
    if not valid(navCache) then navCache = StaticFindObject("/Script/NavigationSystem.Default__NavigationSystemV1") end
    return navCache
end

-- Walkable point near `center` but at least minDist away from it (markers sit
-- on wells/signs). Needs the navmesh, which the game builds around the player.
function M.walkableNear(center, minDist, radius)
    local pawn = M.player()
    local nav = navigation()
    if not valid(nav) then return nil end
    local origin = { X = center.x, Y = center.y, Z = center.z }
    local best
    for _ = 1, 16 do
        local out = {}
        local ok, found = pcall(function() return nav:K2_GetRandomReachablePointInRadius(pawn, origin, out, radius, nil, nil) end)
        if ok and found and out.X then
            local d = math.sqrt((out.X - center.x) ^ 2 + (out.Y - center.y) ^ 2)
            if d >= minDist then best = { x = out.X, y = out.Y, z = out.Z }; break end
        end
    end
    if not best then
        local out = {}
        local probe = { X = center.x + minDist, Y = center.y, Z = center.z }
        local ok, found = pcall(function() return nav:K2_ProjectPointToNavigation(pawn, probe, out, nil, nil, { X = 400, Y = 400, Z = 3000 }) end)
        if ok and found and out.X then best = { x = out.X, y = out.Y, z = out.Z } end
    end
    return best
end

function M.capsuleHalfHeight()
    local ok, h = pcall(function() return M.player().CapsuleComponent:GetScaledCapsuleHalfHeight() end)
    return ok and h or 90
end

function M.npcManager()
    local sys = M.player().SystemsManagerReference
    if not valid(sys) or not valid(sys.NPCManagerReference) then fail("systems_loading") end
    return sys.NPCManagerReference
end

-- Recruitment helpers ------------------------------------------------------
local MAX_AFFECTION = 100

local function npcName(npc)
    local ok, n = pcall(function() return npc.BP_CharacterStatsComponent.Name:ToString() end)
    return (ok and n ~= "") and n or "NPC"
end

-- Raise the nearest NPC's affection towards the player to the maximum.
function M.befriendNearest()
    local npc = M.nearestNPC(500)
    if not npc then fail("no_npc_near") end
    local rel = npc.BP_RelationsComponent
    if not valid(rel) then fail("no_npc_near") end
    local before = rel.Affection
    rel.Affection = MAX_AFFECTION
    -- Co-op bookkeeping: some dialogue checks read the per-player array.
    pcall(function()
        rel.Affections_Coop:ForEach(function(_, e)
            local v = e:get()
            if type(v) == "number" then e:set(MAX_AFFECTION) end
        end)
    end)
    return npcName(npc), before, rel.Affection
end

-- King's herald / challenges (BP_KingdomManager_C) --------------------------
-- ChallengeInProgress (E_ChallengeState), seen in game:
--   0 = none, 1 = herald arrived / waiting to be talked to, 2 = accepted, 3 = finished.
M.CHALLENGE_OFFERED = 1
M.CHALLENGE_IN_PROGRESS = 2

function M.challengeActive(state) return state == M.CHALLENGE_OFFERED or state == M.CHALLENGE_IN_PROGRESS end

function M.kingdom()
    local sys = M.player().SystemsManagerReference
    if not valid(sys) or not valid(sys.KingdomManagerReference) then fail("systems_loading") end
    return sys.KingdomManagerReference
end

function M.challengeState() return M.kingdom().ChallengeInProgress end

local challengeList
function M.challenges()
    if challengeList then return challengeList end
    local dt = dataTable("/Game/Blueprints/Quest/DT_Challenges.DT_Challenges")
    local list, labelField = {}, nil
    for _, id in ipairs(M.rowNames(dt)) do
        local label = id
        pcall(function()
            local row = dt:FindRow(id)
            if labelField == nil then
                labelField = field(row, "Title") or field(row, "Name") or field(row, "ChallengeName") or false
            end
            if labelField then
                local s = row[labelField]:ToString()
                if s ~= "" then label = s end
            end
        end)
        list[#list + 1] = { id = id, name = label }
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    challengeList = list
    return list
end

-- Start a specific challenge through the developers' own cheat function
-- (it validates the challenge with CheckChallengeCanBeAssigned first).
function M.startChallenge(id)
    if not id or id == "" then fail("select_challenge") end
    local km = M.kingdom()
    if M.challengeActive(km.ChallengeInProgress) then fail("challenge_running") end
    local before = km.ChallengeInProgress
    km:GetChallengeCheat(FName(id))
    return before, km.ChallengeInProgress
end

-- Villagers of the player's settlement (BP_BaseCharacter_C.Ownership == 0).
function M.villagers()
    local out = {}
    for _, cls in ipairs({ "BP_NPC_C", "BP_NPC_Multi_Village_C" }) do
        for _, a in ipairs(FindAllOf(cls) or {}) do
            if valid(a) and not a:GetFullName():find("Default__", 1, true) and a.Ownership == 0 then out[#out + 1] = a end
        end
    end
    return out
end

-- Set every skill of every villager to its maximum (10 in the game).
function M.maxVillagerSkills()
    local people, raised = 0, 0
    for _, npc in ipairs(M.villagers()) do
        local stats = npc.BP_CharacterStatsComponent
        if valid(stats) then
            people = people + 1
            for _, name in ipairs(M.SKILLS) do
                local s = stats[name]
                if s ~= nil and s.ActualLevel < s.MaxLevel then
                    s.ActualLevel = s.MaxLevel
                    s.ActualProgress = 0
                    raised = raised + 1
                end
            end
        end
    end
    if people == 0 then fail("no_villagers") end
    return people, raised
end

-- NPCs without a body model. Calling the NPC manager's SpawnRandomNPC alone
-- (trainer v3) created such broken villagers; this detects leftovers.
function M.brokenNPCs()
    local out = {}
    for _, cls in ipairs({ "BP_NPC_C", "BP_NPC_Multi_Village_C" }) do
        for _, a in ipairs(FindAllOf(cls) or {}) do
            if valid(a) and not a:GetFullName():find("Default__", 1, true) then
                local ok, hasMesh = pcall(function() return valid(a.Mesh) and valid(a.Mesh.SkeletalMesh) end)
                if ok and not hasMesh then out[#out + 1] = a:GetFullName():match("([^%.]+)$") end
            end
        end
    end
    return out
end

-- Nearest village NPC (for diagnostics / recruitment features).
function M.nearestNPC(maxDist)
    local p = M.position()
    local best, bestD
    for _, cls in ipairs({ "BP_NPC_C", "BP_NPC_Multi_Village_C" }) do
        for _, a in ipairs(FindAllOf(cls) or {}) do
            if valid(a) and not a:GetFullName():find("Default__", 1, true) then
                local q = a:K2_GetActorLocation()
                local d = math.sqrt((q.X - p.x) ^ 2 + (q.Y - p.y) ^ 2 + (q.Z - p.z) ^ 2)
                if d <= (maxDist or 1500) and (not bestD or d < bestD) then best, bestD = a, d end
            end
        end
    end
    return best, bestD
end

---------------------------------------------------------------------------
-- Diagnostics: keys hard-wired in the game's Blueprints + class dumps
---------------------------------------------------------------------------
function M.blueprintKeyBindings()
    local out, seen = {}, {}
    for _, binding in ipairs(FindAllOf("InputKeyDelegateBinding") or {}) do
        local outer = binding:GetOuter()
        local owner = valid(outer) and outer:GetFName():ToString() or "?"
        binding.InputKeyDelegateBindings:ForEach(function(_, element)
            local d = element:get()
            local chord = d.InputChord
            local line = string.format("%s%s%s%s -> %s (%s)",
                chord.bCtrl and "Ctrl+" or "", chord.bShift and "Shift+" or "", chord.bAlt and "Alt+" or "",
                chord.Key.KeyName:ToString(), d.FunctionNameToBind:ToString(), owner)
            if not seen[line] then seen[line] = true; out[#out + 1] = line end
        end)
    end
    table.sort(out)
    return out
end

local function show(v)
    local tv = type(v)
    if tv == "number" or tv == "boolean" or tv == "string" then return tostring(v) end
    if tv == "userdata" then
        local ok, s = pcall(function() return v:ToString() end)
        if ok and type(s) == "string" then return '"' .. s .. '"' end
        local ok2, fn = pcall(function() return v:GetFullName() end)
        if ok2 and type(fn) == "string" then return fn end
    end
    return "<" .. tv .. ">"
end

-- Text dump of an object's properties (and optionally functions with params).
function M.dumpObject(lines, title, obj, opts)
    opts = opts or {}
    lines[#lines + 1] = "== " .. title .. ": " .. (valid(obj) and obj:GetFullName() or "<invalid>")
    if not valid(obj) then return end
    for _, p in ipairs(M.reflect(obj, opts.stopAt)) do
        local value = ""
        if NUMERIC[p.type] or p.type == "BoolProperty" or p.type == "NameProperty" or p.type == "StrProperty"
            or p.type == "TextProperty" or p.type == "ObjectProperty" or p.type == "EnumProperty" then
            local ok, v = pcall(function() return obj[p.name] end)
            value = ok and (" = " .. show(v)) or " = <err>"
        elseif p.type == "StructProperty" and opts.structs then
            local ok, s = pcall(function() return obj[p.name] end)
            if ok and s ~= nil then
                local parts = {}
                pcall(function()
                    s:ForEachProperty(function(sp)
                        local n = sp:GetFName():ToString()
                        local ok2, sv = pcall(function() return s[n] end)
                        parts[#parts + 1] = n .. "=" .. (ok2 and show(sv) or "?")
                    end)
                end)
                value = " {" .. table.concat(parts, ", ") .. "}"
            end
        end
        lines[#lines + 1] = string.format("  [%s] %s %s%s", p.owner, p.type, p.name, value)
    end
    if opts.functions then
        local cls = obj:GetClass()
        while valid(cls) do
            local cname = cls:GetFName():ToString()
            if opts.stopAt and cname == opts.stopAt then break end
            pcall(function()
                cls:ForEachFunction(function(fn)
                    local params = {}
                    pcall(function()
                        fn:ForEachProperty(function(pp)
                            params[#params + 1] = pp:GetClass():GetFName():ToString() .. " " .. pp:GetFName():ToString()
                        end)
                    end)
                    lines[#lines + 1] = string.format("  [%s] fn %s(%s)", cname, fn:GetFName():ToString(), table.concat(params, ", "))
                end)
            end)
            cls = cls:GetSuperStruct()
        end
    end
end

return M
