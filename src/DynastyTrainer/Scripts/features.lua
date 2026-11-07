-- Trainer features: toggles kept alive by a game-thread tick, multipliers,
-- data-table overrides and the diagnostics dump.
--
-- Variable names below come from diagnostics.txt of the real game (v2.7):
--   BP_CharacterStatsComponent_C: Stamina, MaxStamina, Food, water, health,
--     MaxHealth (all 0..1), Poison, Alcohol, Dirtiness, GodMode,
--     SafeLowTemperature / SafeHighTemperature (Kelvin), Age
--   InventoryComponent_C: InitialOverloadWeight, FinalOverloadWeight
--   BP_VillageManager_C: DynastyReputation, TechnologyLevel_*

local game = require("game")
local sched = require("sched")
local valid = game.valid

local F = {}

local function log(msg) print("[DynastyTrainer] " .. msg .. "\n") end

---------------------------------------------------------------------------
-- State (session only; nothing here is saved)
---------------------------------------------------------------------------
F.state = {
    god = false, stamina = false, hunger = false, thirst = false, debuffs = false,
    weight = false, temperature = false, limits = false, freezeTime = false,
    fly = false, noclip = false,
    speed = 1, jump = 1, gravity = 1,
    villagerLimit = 100, heraldNext = false,
}
local S = F.state

---------------------------------------------------------------------------
-- Overrides with restore: remember the game's value the first time we write.
---------------------------------------------------------------------------
local originals = {} -- key -> { obj, name, value, group }

local function override(group, obj, name, value)
    local key = obj:GetFullName() .. "|" .. name
    if originals[key] == nil then originals[key] = { obj = obj, name = name, value = obj[name], group = group } end
    if obj[name] ~= value then obj[name] = value end
end

local function restore(group)
    for key, o in pairs(originals) do
        if o.group == group then
            if valid(o.obj) then pcall(function() o.obj[o.name] = o.value end) end
            originals[key] = nil
        end
    end
end

-- Which variables exist (for "not found" hints in the menu).
local present = {}
local function has(obj, name)
    local key = obj:GetClass():GetFName():ToString() .. "|" .. name
    if present[key] == nil then
        present[key] = false
        for _, p in ipairs(game.reflect(obj)) do if p.name == name then present[key] = true; break end end
        if not present[key] then log("variable not found: " .. key) end
    end
    return present[key]
end
F.has = has

---------------------------------------------------------------------------
-- Movement multipliers (ALS rewrites MaxWalkSpeed per gait, so track the
-- game's base value and re-apply the multiplier on top of it)
---------------------------------------------------------------------------
local move = {}
-- ALS (BP_BaseCharacter_C) rebuilds MaxWalkSpeed every frame from these.
local SPEED_VARS = { "walkingSpeed", "runningSpeed", "sprintingSpeed", "crouchingSpeed",
    "walkingAcceleration", "runningAcceleration" }

local function applyMovement(pawn)
    if S.speed ~= 1 then
        for _, n in ipairs(SPEED_VARS) do
            if has(pawn, n) then
                local key = pawn:GetFullName() .. "|" .. n
                if originals[key] == nil then originals[key] = { obj = pawn, name = n, value = pawn[n], group = "speed" } end
                local target = originals[key].value * S.speed
                if math.abs(pawn[n] - target) > 0.01 then pawn[n] = target end
            end
        end
    end
    local cm = pawn.CharacterMovement
    if not valid(cm) then return end
    move.jump = move.jump or cm.JumpZVelocity
    move.gravity = move.gravity or cm.GravityScale
    cm.JumpZVelocity = move.jump * S.jump
    cm.GravityScale = move.gravity * S.gravity
end

function F.resetMovement()
    restore("speed")
    pcall(function()
        local cm = game.player().CharacterMovement
        if move.jump then cm.JumpZVelocity = move.jump end
        if move.gravity then cm.GravityScale = move.gravity end
    end)
end

---------------------------------------------------------------------------
-- Fly / noclip (engine UCheatManager) with Space = up, C = down
---------------------------------------------------------------------------
local FLY_SPEED = 1500
local VERTICAL_STEP = 25 -- cm per fast tick

function F.setFly(mode) -- "fly" | "noclip" | nil
    local cm = game.cheatManager()
    local pawn = game.player()
    if mode == "fly" then cm:Fly()
    elseif mode == "noclip" then cm:Ghost()
    else cm:Walk() end
    S.fly, S.noclip = mode == "fly", mode == "noclip"
    pcall(function()
        local mc = pawn.CharacterMovement
        move.fly = move.fly or mc.MaxFlySpeed
        mc.MaxFlySpeed = mode and FLY_SPEED or move.fly
    end)
end

local keyUp, keyDown
local function vertical(pawn, pc)
    keyUp = keyUp or { KeyName = FName("SpaceBar") }
    keyDown = keyDown or { KeyName = FName("C") }
    local dz = 0
    if pc:IsInputKeyDown(keyUp) then dz = dz + VERTICAL_STEP end
    if pc:IsInputKeyDown(keyDown) then dz = dz - VERTICAL_STEP end
    if dz ~= 0 then pawn:K2_AddActorWorldOffset({ X = 0, Y = 0, Z = dz }, S.fly, {}, true) end
end

---------------------------------------------------------------------------
-- Time: freeze, and skipping days by letting the game roll over midnight
-- itself (runs the game's own end-of-day logic).
---------------------------------------------------------------------------
local frozenTime
function F.setFreezeTime(on)
    S.freezeTime = on
    frozenTime = on and game.readTime() or nil
end

local skip = { remaining = 0, day = nil }
local function nearMidnight() game.writeTime({ hour = 23, minute = 59, second = 55 }) end

function F.skipDays(n)
    local tm = game.readTime()
    skip.remaining = math.max(1, math.floor(n))
    skip.day = tm.day
    if S.freezeTime then F.setFreezeTime(false) end
    nearMidnight()
    return skip.remaining
end

function F.skipSeason()
    local tm = game.readTime()
    return F.skipDays((tm.seasondays and tm.seasondays >= 1) and tm.seasondays or 3)
end

function F.skipping() return skip.remaining end

local function skipTick()
    local tm = game.readTime()
    if tm.day ~= skip.day then
        skip.remaining = skip.remaining - 1
        skip.day = tm.day
        if skip.remaining > 0 then nearMidnight() end
    end
end

---------------------------------------------------------------------------
-- Villager limit: DT_ReputationLimits has one row per population slot
-- (Population_1..150) with RequiredReputation. The limit is the number of rows
-- whose requirement you meet, so we set the first N requirements to 0.
-- In memory only - restored when turned off or when the game restarts.
---------------------------------------------------------------------------
function F.applyLimits()
    local dt = game.reputationLimits()
    local rows = {}
    for _, name in ipairs(game.rowNames(dt)) do
        local n = tonumber(name:match("^Population_(%d+)$"))
        if n then rows[#rows + 1] = { name = name, n = n } end
    end
    table.sort(rows, function(x, y) return x.n < y.n end)
    local target = math.floor(S.villagerLimit)
    local changed = 0
    for _, r in ipairs(rows) do
        local row = dt:FindRow(r.name)
        local fieldName = row and game.field(row, "RequiredReputation")
        if fieldName then
            local key = "DT_ReputationLimits|" .. r.name
            if originals[key] == nil then
                local original = row[fieldName]
                originals[key] = { group = "limits", value = original,
                    restore = function() local rr = dt:FindRow(r.name); if rr then rr[fieldName] = original end end }
            end
            local wanted = r.n <= target and 0 or originals[key].value
            if row[fieldName] ~= wanted then row[fieldName] = wanted end
            if r.n <= target then changed = changed + 1 end
        end
    end
    log(string.format("villager limit: %d population slots unlocked (of %d rows)", changed, #rows))
    return changed, #rows
end

local function restoreLimits()
    for key, o in pairs(originals) do
        if o.group == "limits" then pcall(o.restore); originals[key] = nil end
    end
end

---------------------------------------------------------------------------
-- Tick
---------------------------------------------------------------------------
local lastError
local function report(where, err)
    local msg = where .. ": " .. tostring(err)
    if msg ~= lastError then log("tick error " .. msg); lastError = msg end
end

local function safe(where, fn, ...)
    local ok, e = pcall(fn, ...)
    if not ok then report(where, e) end
end

local function anythingOn()
    return S.god or S.stamina or S.hunger or S.thirst or S.debuffs or S.weight or S.temperature
        or S.freezeTime or S.heraldNext or S.speed ~= 1 or S.jump ~= 1 or S.gravity ~= 1
        or skip.remaining > 0 or next(originals) ~= nil
end

local function slowTick()
    if not anythingOn() then return end
    local okP, pawn = pcall(game.player)
    if not okP then return end
    local okS, stats = pcall(game.stats)

    if S.god then
        safe("god", function()
            if okS and has(stats, "GodMode") then override("god", stats, "GodMode", true) end
            local h, m = pawn:GetHealth(), pawn:GetMaxHealth()
            if h < m then pawn:SetHealth(m) end
        end)
    end

    if okS then
        if S.stamina and has(stats, "Stamina") then
            safe("stamina", function()
                local m = has(stats, "MaxStamina") and stats.MaxStamina or 1
                if stats.Stamina < m then stats.Stamina = m end
            end)
        end
        if S.hunger and has(stats, "Food") then safe("food", function() if stats.Food < 1 then stats.Food = 1 end end) end
        if S.thirst and has(stats, "water") then safe("water", function() if stats.water < 1 then stats.water = 1 end end) end
        if S.debuffs then
            for _, n in ipairs({ "Poison", "Alcohol", "Dirtiness" }) do
                if has(stats, n) then safe(n, function() if stats[n] > 0 then stats[n] = 0 end end) end
            end
        end
        if S.temperature then
            safe("temperature", function()
                if has(stats, "SafeLowTemperature") then override("temperature", stats, "SafeLowTemperature", 173.15) end
                if has(stats, "SafeHighTemperature") then override("temperature", stats, "SafeHighTemperature", 373.15) end
            end)
        end
    end

    if S.weight then
        safe("weight", function()
            local inv = game.inventory()
            for _, n in ipairs({ "InitialOverloadWeight", "FinalOverloadWeight" }) do
                if has(inv, n) then override("weight", inv, n, 100000) end
            end
        end)
    end

    if S.speed ~= 1 or S.jump ~= 1 or S.gravity ~= 1 then safe("movement", applyMovement, pawn)
    else
        for _, o in pairs(originals) do if o.group == "speed" then F.resetMovement(); break end end
    end
    if skip.remaining > 0 then
        local ok, e = pcall(skipTick); if not ok then report("skip", e); skip.remaining = 0 end
    end
    if S.freezeTime and frozenTime then safe("time", game.writeTime, frozenTime) end

    if S.heraldNext then
        safe("herald", function()
            local km = game.kingdom()
            S.heraldStartState = S.heraldStartState or km.ChallengeInProgress
            if km.ChallengeInProgress ~= S.heraldStartState or game.challengeActive(km.ChallengeInProgress) then
                S.heraldNext, S.heraldStartState = false, nil
                restore("herald")
                log("herald: challenge state changed to " .. tostring(km.ChallengeInProgress) .. ", chance restored")
            else
                override("herald", km, "ChallengeHappenChance", 1.0)
            end
        end)
    end
end

local function fastTick()
    if not (S.fly or S.noclip) then return end
    local ok, pawn, pc = pcall(game.player)
    if ok then safe("fly", vertical, pawn, pc) end
end

function F.start()
    sched.every(200, slowTick)
    sched.every(33, fastTick)
end

-- Turning features off: restore what we overrode.
function F.off(name)
    if name == "herald" then S.heraldStartState = nil end
    if name == "limits" then restoreLimits()
    else restore(name) end
end

-- Which features have their variables in this game version.
function F.availability()
    local out = {}
    local okS, stats = pcall(game.stats)
    if okS then
        out.stamina = has(stats, "Stamina"); out.hunger = has(stats, "Food"); out.thirst = has(stats, "water")
        out.debuffs = has(stats, "Poison") and has(stats, "Alcohol") and has(stats, "Dirtiness")
        out.temperature = has(stats, "SafeLowTemperature") and has(stats, "SafeHighTemperature")
    end
    local okI, inv = pcall(game.inventory)
    if okI then out.weight = has(inv, "FinalOverloadWeight") end
    return out
end

---------------------------------------------------------------------------
-- Diagnostics file (Mods/DynastyTrainer/diagnostics.txt)
---------------------------------------------------------------------------
local MOD_DIR = (package.searchpath("game", package.path) or ""):gsub("[/\\]Scripts[/\\]game%.lua$", "")

local function show(v)
    if type(v) == "userdata" then
        local ok, s = pcall(function() return v:ToString() end)
        return ok and tostring(s) or "<obj>"
    end
    return tostring(v)
end

function F.writeDiagnostics()
    local lines = { "DynastyTrainer diagnostics " .. os.date("%Y-%m-%d %H:%M:%S"), "" }
    local function section(title, fn)
        local ok, err = pcall(fn)
        if not ok then lines[#lines + 1] = "== " .. title .. ": ERROR " .. tostring(err) end
        lines[#lines + 1] = ""
    end
    local function table_rows(title, dt, limit)
        local names = game.rowNames(dt)
        lines[#lines + 1] = "== " .. title .. ": " .. #names .. " rows"
        for i = 1, math.min(#names, limit or #names) do
            local row = dt:FindRow(names[i])
            local parts = {}
            if row then
                row:ForEachProperty(function(p)
                    local n = p:GetFName():ToString()
                    local ok, v = pcall(function() return row[n] end)
                    parts[#parts + 1] = n .. "=" .. (ok and show(v) or "?")
                end)
            end
            lines[#lines + 1] = "  " .. names[i] .. ": " .. table.concat(parts, ", ")
        end
    end
    section("player", function()
        game.dumpObject(lines, "Player pawn (Blueprint part)", game.player(), { stopAt = "Character", functions = true })
    end)
    section("stats", function() game.dumpObject(lines, "Stats component", game.stats(), { structs = true, functions = true }) end)
    section("inventory", function()
        game.dumpObject(lines, "Inventory component", game.inventory(), { stopAt = "ActorComponent", functions = true })
    end)
    section("time", function() game.dumpObject(lines, "Time manager", game.timeManager(), { structs = true, functions = true, stopAt = "Actor" }) end)
    section("village", function() game.dumpObject(lines, "Village manager", game.villageManager(), { structs = true, functions = true, stopAt = "Actor" }) end)
    section("limits", function() table_rows("DT_ReputationLimits", game.reputationLimits()) end)
    section("npcmanager", function()
        game.dumpObject(lines, "NPC manager", game.npcManager(), { functions = true, stopAt = "Actor" })
    end)
    section("npc", function()
        local npc, d = game.nearestNPC(3000)
        if not npc then lines[#lines + 1] = "== Nearest NPC: none within 30 m (stand next to a villager)"; return end
        game.dumpObject(lines, string.format("Nearest NPC (%.0f cm)", d), npc, { stopAt = "Character" })
        for _, p in ipairs(game.reflect(npc, "Character")) do
            if p.type == "ObjectProperty" and (p.name:find("Relation") or p.name:find("Stats")) then
                local ok, comp = pcall(function() return npc[p.name] end)
                if ok and valid(comp) then game.dumpObject(lines, "NPC " .. p.name, comp, { structs = true, functions = true, stopAt = "ActorComponent" }) end
            end
        end
    end)
    for _, ref in ipairs({ "KingdomManagerReference", "QuestManagerReference", "EventManagerReference", "GameplayEventsManagerReference" }) do
        section(ref, function()
            game.dumpObject(lines, ref, game.player().SystemsManagerReference[ref], { structs = true, functions = true, stopAt = "Actor" })
        end)
    end
    section("systems", function() game.dumpObject(lines, "Systems manager", game.player().SystemsManagerReference, { stopAt = "Actor" }) end)
    section("controller", function()
        local _, pc = game.player()
        game.dumpObject(lines, "Player controller (Blueprint part)", pc, { stopAt = "MD_PlayerController", functions = true })
    end)
    section("cheats", function() game.dumpObject(lines, "Cheat manager", game.cheatManager(), { functions = true, stopAt = "Object" }) end)
    section("items", function()
        local list = game.items()
        lines[#lines + 1] = "== Items in DT_ListOfItems: " .. #list
        for i = 1, math.min(#list, 15) do lines[#lines + 1] = "  " .. list[i].id .. " = " .. list[i].name end
    end)
    local path = MOD_DIR .. "/diagnostics.txt"
    local f, err = io.open(path, "w")
    if not f then log("cannot write diagnostics: " .. tostring(err)); return end
    f:write(table.concat(lines, "\n"), "\n")
    f:close()
    log("diagnostics written to " .. path .. " (" .. #lines .. " lines)")
end

return F
