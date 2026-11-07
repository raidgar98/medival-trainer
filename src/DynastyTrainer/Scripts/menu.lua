-- In-game menu built on the shared ModMenu library (Mods/shared/ModMenu).
-- Every visible text goes through i18n; build() re-registers everything,
-- so switching language rebuilds the menu in place.

local UI = require("ModMenu.ModMenu")
local i18n = require("i18n")
local game = require("game")
local F = require("features")
local sched = require("sched")
local t = i18n.t
local S = F.state

local M = {}

local ID = "DynastyTrainer"
local store = UI.ConfigManager
local QUICK_AMOUNTS = { 100, 1000, 10000 }

-- Keys free in Medieval Dynasty + installed mods. Taken: F1 photo mode,
-- F3 Bounty Hunting, F5/F9 quick save/load, Home/PageUp/PageDown/numpad (game
-- Blueprints, PC_Player_C), F6-F8 other mods, F10 UE4SS console, F12 Steam
-- screenshot, Insert UE4SS. (UE4SS Key name, label)
local MENU_KEYS = {
    { "F4", "F4" }, { "F2", "F2" }, { "F11", "F11" }, { "END", "End" },
}
local DEFAULT_MENU_KEY = "F4"

local function log(msg) print("[" .. ID .. "] " .. msg .. "\n") end

local function keyLabel(name)
    for _, k in ipairs(MENU_KEYS) do if k[1] == name then return k[2] end end
    return name
end

local function menuKeyName()
    local name = store.Get("menuKey")
    for _, k in ipairs(MENU_KEYS) do if k[1] == name then return name end end
    return DEFAULT_MENU_KEY
end

-- Only open during free gameplay. While a dialogue or a game window
-- (inventory, trade, map, journal...) owns the mouse, closing our menu would
-- restore plain game input and leave that window unclickable.
local function canOpen()
    local ok, pawn, pc = pcall(game.player)
    if not ok then return true end -- main menu / loading: nothing to break
    if pawn.bIsInDialogue == true then
        log("menu blocked: dialogue in progress")
        return false, "dialogue in progress"
    end
    if pc.bShowMouseCursor == true then
        log("menu blocked: a game window is open")
        return false, "game window open"
    end
    return true
end

local function C(r, g, b, a) return { R = r, G = g, B = b, A = a or 1 } end

local THEME = {
    theme = "light", fontHint = 22, fontItem = 23, fontTitle = 30, fontSection = 26, fontDropdown = 22,
    colors = {
        panelBg = C(0.68, 0.57, 0.40, 0.97), panelBorder = C(0.14, 0.085, 0.035),
        textPrimary = C(0.07, 0.045, 0.02), textMuted = C(0.22, 0.15, 0.07),
        textAccent = C(0.30, 0.10, 0.03), textStatus = C(0.12, 0.07, 0.03),
        sectionHeaderBg = C(0.42, 0.30, 0.15), sectionMark = C(0.85, 0.68, 0.38),
        buttonBg = C(0.26, 0.16, 0.07), buttonText = C(0.97, 0.88, 0.66),
        buttonBgPrimary = C(0.36, 0.20, 0.05), buttonTextPrimary = C(1, 0.90, 0.62),
        buttonBgSuccess = C(0.20, 0.25, 0.10), buttonTextSuccess = C(0.98, 0.92, 0.72),
        buttonBgDanger = C(0.33, 0.07, 0.04), buttonTextDanger = C(1, 0.87, 0.69),
        dropdownHeaderBg = C(0.38, 0.26, 0.13), dropdownHeaderText = C(0.98, 0.90, 0.70),
        dropdownOptionBg = C(0.70, 0.57, 0.38), dropdownOptionText = C(0.07, 0.035, 0.015),
        fieldBg = C(0.96, 0.92, 0.82), fieldText = C(0.05, 0.03, 0.01), fieldHint = C(0.40, 0.30, 0.18),
    },
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function describe(err)
    local key = type(err) == "string" and err:match("^err:([%w_]+)$")
    if key then return t(key) end
    log("ERROR: " .. tostring(err))
    return t("error_see_log")
end

local function status(sectionId, text) pcall(UI.SetLabel, sectionId, "status", text or "") end

-- Run on the game thread; on failure show the message in the section's status label.
local function run(sectionId, fn)
    sched.run(function()
        local ok, err = pcall(fn)
        if not ok then status(sectionId, describe(err)) end
    end)
end

local function button(id, label, fn, variant) return { type = "button", id = id, label = label, variant = variant, onClick = fn } end
local function check(id, label, default, fn) return { type = "checkbox", id = id, label = label, default = default, showState = false, onChange = fn } end
local function number(id, label, default, min, max, integer, fn, width)
    return { type = "number", id = id, label = label, default = default, min = min, max = max, integer = integer,
        fieldWidth = width or 120, onChange = fn }
end

-- A simple on/off feature bound to F.state[name].
local function toggle(sectionId, name, label)
    return check(name, label, S[name], function(on)
        S[name] = on == true
        if not S[name] then sched.run(function() F.off(name) end) end
        status(sectionId, "")
    end)
end

---------------------------------------------------------------------------
-- Live labels refreshed when the menu opens
---------------------------------------------------------------------------
local villages, savedPosition = {}, nil
local herald_text_fn
local challengesLoaded = false
local itemsLoaded = false

local function timeText()
    local tm = game.readTime()
    return t("time_now", { year = tm.year, season = t("season_" .. tm.season), day = tm.day,
        clock = string.format("%02d:%02d", tm.hour, tm.minute) })
end

local function refresh()
    local ok, coins = pcall(game.coins)
    pcall(UI.SetLabel, "coins", "balance", ok and t("coins_balance", { total = coins }) or describe(coins))
    local okT, tt = pcall(timeText)
    pcall(UI.SetLabel, "time", "now", okT and tt or describe(tt))

    if not itemsLoaded then
        local okI, list = pcall(game.items)
        if okI and #list > 0 then
            local opts = {}
            for _, it in ipairs(list) do
                opts[#opts + 1] = { label = it.name == it.id and it.id or (it.name .. "  (" .. it.id .. ")"), value = it.id }
            end
            UI.SetOptions("items", "item", opts)
            itemsLoaded = true
            log("item list loaded: " .. #list .. " items")
        end
    end

    local okV, list = pcall(game.villages)
    if okV and #list > 0 and #list ~= #villages then
        villages = list
        local opts = {}
        for _, v in ipairs(list) do opts[#opts + 1] = { label = v.name, value = v.name } end
        UI.SetOptions("teleport", "village", opts)
    end

    -- Show which features have their variables in this game version.
    local okD, found = pcall(F.availability)
    if okD then
        local missing = {}
        for _, k in ipairs({ "stamina", "hunger", "thirst", "debuffs", "weight", "temperature" }) do
            if found[k] == false then missing[#missing + 1] = t("feat_" .. k) end
        end
        pcall(UI.SetLabel, "survival", "found", #missing > 0 and t("not_found", { list = table.concat(missing, ", ") }) or "")
    end
    local okR, rep = pcall(game.reputation)
    pcall(UI.SetLabel, "village", "reputation", okR and t("reputation_now", { value = rep }) or describe(rep))
    if herald_text_fn then
        local okH, txt = pcall(herald_text_fn)
        pcall(UI.SetLabel, "herald", "state", okH and txt or describe(txt))
    end
    if not challengesLoaded then
        local okC, list = pcall(game.challenges)
        if okC and #list > 0 then
            local opts = {}
            for _, c in ipairs(list) do opts[#opts + 1] = { label = c.name == c.id and c.id or (c.name .. "  (" .. c.id .. ")"), value = c.id } end
            UI.SetOptions("herald", "challenge", opts)
            challengesLoaded = true
            log("challenge list loaded: " .. #list)
        end
    end
    local okB, broken = pcall(game.brokenNPCs)
    if okB then
        if #broken > 0 then log("NPCs without a model: " .. table.concat(broken, ", ")) end
        pcall(UI.SetLabel, "recruit", "broken", #broken > 0 and t("broken_npcs", { count = #broken }) or "")
    end
    local okA, age = pcall(game.age)
    if okA then pcall(UI.SetLabel, "health", "age", t("age_now", { value = math.floor(age) })) end
end

local font
local function applyFont()
    if not (font and font:IsValid()) then font = LoadAsset("/Game/Fonts/F_Medieval.F_Medieval") end
    if not (font and font:IsValid()) then return end
    for _, text in ipairs(FindAllOf("TextBlock") or {}) do
        if text:IsValid() and text:GetFullName():find(ID, 1, true) then
            text:SetFont({ FontObject = font, TypefaceFontName = FName("Regular"), Size = text.Font.Size,
                LetterSpacing = 0, OutlineSettings = { OutlineSize = 0 } })
        end
    end
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
local function addItem(sectionId, id, amount)
    run(sectionId, function()
        local added, total = game.addItem(id, amount)
        log(string.format("added %d x %s (total %d)", added, id, total))
        if id == "Coin" then pcall(UI.SetLabel, "coins", "balance", t("coins_balance", { total = total })) end
        if added == amount then
            status(sectionId, id == "Coin" and t("coins_added", { amount = amount, count = amount })
                or t("item_added", { amount = amount, total = total }))
        else
            status(sectionId, t("item_mismatch", { added = added, amount = amount }))
        end
    end)
end

local function skillTargets()
    local sel = UI.Get("skills", "skill")
    if sel == nil or sel == "all" then return game.SKILLS end
    return { sel }
end

local function addSkillPoints(n)
    run("skills", function()
        local parts = {}
        for _, s in ipairs(skillTargets()) do parts[#parts + 1] = t("skill_" .. s) .. ": " .. game.addSkillPoints(s, n) end
        status("skills", t("skill_points_now", { list = table.concat(parts, ", ") }))
    end)
end

local function maxSkills()
    run("skills", function()
        for _, s in ipairs(skillTargets()) do game.maxSkillLevel(s) end
        status("skills", t("skills_maxed"))
    end)
end

---------------------------------------------------------------------------
-- Menu
---------------------------------------------------------------------------
local build -- forward

local function languageOptions()
    local out = {}
    for _, code in ipairs(i18n.LANGUAGES) do out[#out + 1] = { label = i18n.name(code), value = code } end
    return out
end

function build()
    local tab = { player = t("tab_player"), inventory = t("tab_inventory"), world = t("tab_world"),
        movement = t("tab_movement"), settings = t("tab_settings") }

    local keyName = menuKeyName()
    local opts = { instanceId = ID, key = Key[keyName], keyHint = keyLabel(keyName), dock = "left", ignoreLook = true,
        cursorMode = "modmenu", title = t("menu_title"), canOpen = canOpen,
        tabs = { tab.player, tab.inventory, tab.world, tab.movement, tab.settings } }
    for k, v in pairs(THEME) do opts[k] = v end
    UI.Init(opts)

    -- Player ---------------------------------------------------------------
    UI.Register({ id = "survival", tab = tab.player, title = t("section_survival"), items = {
        toggle("survival", "god", t("feat_god")),
        toggle("survival", "stamina", t("feat_stamina")),
        toggle("survival", "hunger", t("feat_hunger")),
        toggle("survival", "thirst", t("feat_thirst")),
        toggle("survival", "debuffs", t("feat_debuffs")),
        toggle("survival", "weight", t("feat_weight")),
        toggle("survival", "temperature", t("feat_temperature")),
        { type = "label", id = "found", label = "" },
        { type = "label", id = "status", label = "" },
    } })

    UI.Register({ id = "health", tab = tab.player, title = t("section_health"), items = {
        { type = "row", items = {
            button("heal", t("heal"), function()
                run("health", function() local _, m = game.health(); game.setHealth(m); status("health", t("healed")) end)
            end),
            button("maxhp", t("max_health_25"), function()
                run("health", function()
                    local _, m = game.health(); game.setMaxHealth(m * 1.25); game.setHealth(m * 1.25)
                    status("health", t("max_health_now", { value = math.floor(m * 1.25) }))
                end)
            end),
        } },
        { type = "label", id = "age", label = "" },
        { type = "row", items = {
            number("ageValue", t("age"), 25, 14, 59, true, nil, 90),
            button("setAge", t("set"), function()
                run("health", function()
                    game.setAge(UI.Get("health", "ageValue"))
                    UI.SetLabel("health", "age", t("age_now", { value = math.floor(game.age()) }))
                end)
            end),
        } },
        { type = "label", id = "status", label = "" },
    } })

    local skillOpts = { { label = t("skill_all"), value = "all" } }
    for _, s in ipairs(game.SKILLS) do skillOpts[#skillOpts + 1] = { label = t("skill_" .. s), value = s } end
    UI.Register({ id = "skills", tab = tab.player, title = t("section_skills"), items = {
        { type = "dropdown", id = "skill", label = t("skill"), options = skillOpts, default = "all" },
        { type = "row", items = {
            button("sp10", t("skill_points_add", { n = 10 }), function() addSkillPoints(10) end),
            button("sp100", t("skill_points_add", { n = 100 }), function() addSkillPoints(100) end),
            button("spmax", t("skill_max_level"), maxSkills, "primary"),
        } },
        { type = "label", id = "status", label = "" },
    } })

    -- Inventory ------------------------------------------------------------
    local quick = {}
    for _, amount in ipairs(QUICK_AMOUNTS) do
        quick[#quick + 1] = button("add" .. amount, "+" .. i18n.number(amount), function() addItem("coins", "Coin", amount) end)
    end
    UI.Register({ id = "coins", tab = tab.inventory, title = t("section_coins"), items = {
        { type = "label", id = "balance", label = "" },
        { type = "row", items = quick },
        { type = "row", items = {
            number("amount", t("amount"), 1000, 1, 1000000, true, nil, 200),
            button("addCustom", t("add"), function() addItem("coins", "Coin", tonumber(UI.Get("coins", "amount")) or 0) end, "primary"),
        } },
        { type = "label", id = "status", label = "" },
    } })

    UI.Register({ id = "items", tab = tab.inventory, title = t("section_items"), items = {
        { type = "dropdown", id = "item", label = t("item"), searchable = true, placeholder = t("item_search"),
            maxVisible = 12, options = { { label = t("loading"), value = "" } } },
        { type = "row", items = {
            number("count", t("amount"), 10, 1, 100000, true, nil, 200),
            button("addItem", t("add"), function()
                addItem("items", UI.Get("items", "item"), tonumber(UI.Get("items", "count")) or 0)
            end, "primary"),
        } },
        { type = "label", id = "status", label = "" },
    } })

    -- World ----------------------------------------------------------------
    UI.Register({ id = "time", tab = tab.world, title = t("section_time"), items = {
        { type = "label", id = "now", label = "" },
        { type = "row", items = {
            number("hour", t("hour"), 8, 0, 23, true, nil, 90),
            button("setHour", t("set"), function()
                run("time", function()
                    local when = F.setHour(UI.Get("time", "hour"))
                    UI.Set("time", "freezeTime", S.freezeTime)
                    if when == "tomorrow" then
                        status("time", t("hour_tomorrow", { hour = string.format("%02d:00", math.floor(tonumber(UI.Get("time", "hour")) or 0)) }))
                    else
                        UI.SetLabel("time", "now", timeText())
                    end
                end)
            end, "primary"),
        } },
        { type = "row", items = {
            button("skipDay", t("skip_day"), function()
                run("time", function() F.skipDays(1); UI.Set("time", "freezeTime", S.freezeTime); status("time", t("skipping", { count = 1 })) end)
            end),
            button("skipSeason", t("skip_season"), function()
                run("time", function() local n = F.skipSeason(); UI.Set("time", "freezeTime", S.freezeTime); status("time", t("skipping", { count = n })) end)
            end),
        } },
        check("freezeTime", t("freeze_time"), S.freezeTime, function(on)
            run("time", function()
                F.setFreezeTime(on == true)
                status("time", on and t("time_stopped") or t("time_resumed"))
            end)
        end),
        number("gameSpeed", t("game_speed"), 1, 0.1, 10, false, function(v)
            run("time", function() game.setGameSpeed(tonumber(v) or 1) end)
        end),
        { type = "label", id = "status", label = "" },
    } })

    local techOpts = { { label = t("tech_all"), value = "all" } }
    for _, k in ipairs(game.TECHNOLOGIES) do techOpts[#techOpts + 1] = { label = t("tech_" .. k), value = k } end
    local function addTech(n)
        run("village", function()
            local sel = UI.Get("village", "tech")
            local kinds = (sel == nil or sel == "all") and game.TECHNOLOGIES or { sel }
            local parts = {}
            for _, k in ipairs(kinds) do parts[#parts + 1] = t("tech_" .. k) .. ": " .. i18n.number(game.addTechnology(k, n)) end
            status("village", table.concat(parts, ", "))
        end)
    end
    local function addRep(n)
        run("village", function()
            local v = game.addReputation(n)
            UI.SetLabel("village", "reputation", t("reputation_now", { value = v }))
        end)
    end
    local function applyLimits()
        run("village", function()
            local n, total = F.applyLimits()
            status("village", total > 0 and t("limits_applied", { count = n }) or t("limits_missing"))
        end)
    end
    UI.Register({ id = "village", tab = tab.world, title = t("section_village"), items = {
        { type = "label", id = "reputation", label = "" },
        { type = "row", items = {
            button("rep1k", t("reputation_add", { n = i18n.number(1000) }), function() addRep(1000) end),
            button("rep10k", t("reputation_add", { n = i18n.number(10000) }), function() addRep(10000) end),
        } },
        { type = "dropdown", id = "tech", label = t("technology"), options = techOpts, default = "all" },
        { type = "row", items = {
            button("tech100", t("tech_add", { n = 100 }), function() addTech(100) end),
            button("tech1000", t("tech_add", { n = i18n.number(1000) }), function() addTech(1000) end),
        } },
        check("limits", t("override_limits"), S.limits, function(on)
            S.limits = on == true
            if S.limits then applyLimits()
            else sched.run(function() F.off("limits"); status("village", t("limits_restored")) end) end
        end),
        number("villagerLimit", t("villager_limit"), S.villagerLimit, 1, 150, true, function(v)
            S.villagerLimit = tonumber(v) or S.villagerLimit
            if S.limits then applyLimits() end
        end),
        { type = "label", id = "status", label = "" },
    } })

    UI.Register({ id = "recruit", tab = tab.world, title = t("section_recruit"), items = {
        button("befriend", t("befriend_nearest"), function()
            run("recruit", function()
                local name, before, after = game.befriendNearest()
                log(string.format("affection %s: %s -> %s", name, tostring(before), tostring(after)))
                status("recruit", t("befriended", { name = name }))
            end)
        end, "primary"),
        button("maxSkills", t("max_villager_skills"), function()
            run("recruit", function()
                local people, raised = game.maxVillagerSkills()
                log(string.format("villager skills maxed: %d people, %d skills raised", people, raised))
                status("recruit", t("villager_skills_maxed", { count = people }))
            end)
        end, "primary"),
        { type = "label", label = t("new_villagers_hint") },
        { type = "label", label = t("recruit_hint") },
        { type = "label", id = "broken", label = "" },
        { type = "label", id = "status", label = "" },
    } })

    local function heraldText()
        local st = game.challengeState()
        if st == game.CHALLENGE_OFFERED then return t("herald_waiting") end
        if st == game.CHALLENGE_IN_PROGRESS then return t("herald_busy") end
        return S.heraldNext and t("herald_scheduled") or t("herald_idle")
    end
    UI.Register({ id = "herald", tab = tab.world, title = t("section_herald"), items = {
        { type = "label", id = "state", label = "" },
        { type = "dropdown", id = "challenge", label = t("challenge"), searchable = true, placeholder = t("item_search"),
            maxVisible = 10, options = { { label = t("loading"), value = "" } } },
        button("heraldNow", t("herald_now"), function()
            run("herald", function()
                local id = UI.Get("herald", "challenge")
                local before, after = game.startChallenge(id)
                log(string.format("GetChallengeCheat(%s): state %s -> %s", tostring(id), tostring(before), tostring(after)))
                status("herald", game.challengeActive(after) and t("herald_called") or t("herald_maybe", { state = tostring(after) }))
                UI.SetLabel("herald", "state", heraldText())
            end)
        end, "primary"),
        check("heraldNext", t("herald_next_season"), S.heraldNext, function(on)
            run("herald", function()
                if on and game.challengeActive(game.challengeState()) then
                    UI.Set("herald", "heraldNext", false); game.fail("challenge_running")
                end
                S.heraldNext = on == true
                if not S.heraldNext then F.off("herald") end
                UI.SetLabel("herald", "state", heraldText())
            end)
        end),
        { type = "label", id = "status", label = "" },
    } })
    herald_text_fn = heraldText

    -- Movement -------------------------------------------------------------
    local function multiplier(id, label, key, min, max)
        return number(id, label, S[key], min, max, false, function(v)
            S[key] = tonumber(v) or 1
            if S.speed == 1 and S.jump == 1 and S.gravity == 1 then sched.run(F.resetMovement) end
        end)
    end
    UI.Register({ id = "movement", tab = tab.movement, title = t("section_movement"), items = {
        multiplier("speed", t("speed_mult"), "speed", 0.5, 20),
        multiplier("jump", t("jump_mult"), "jump", 0.5, 10),
        multiplier("gravity", t("gravity_mult"), "gravity", 0.1, 3),
        check("fly", t("feat_fly"), S.fly, function(on)
            run("movement", function() F.setFly(on and "fly" or nil); if on then UI.Set("movement", "noclip", false) end end)
        end),
        check("noclip", t("feat_noclip"), S.noclip, function(on)
            run("movement", function() F.setFly(on and "noclip" or nil); if on then UI.Set("movement", "fly", false) end end)
        end),
        { type = "label", label = t("fly_hint") },
        { type = "row", items = {
            number("fov", t("fov"), 90, 30, 150, true, nil, 90),
            button("setFov", t("set"), function()
                run("movement", function() local _, pc = game.player(); pc:FOV(tonumber(UI.Get("movement", "fov")) or 90) end)
            end),
            button("resetFov", t("reset"), function()
                run("movement", function() local _, pc = game.player(); pc:FOV(0) end)
            end),
        } },
        { type = "label", id = "status", label = "" },
    } })

    UI.Register({ id = "teleport", tab = tab.movement, title = t("section_teleport"), items = {
        { type = "dropdown", id = "village", label = t("village"), options = { { label = t("village_pick"), value = "" } }, default = "" },
        button("go", t("teleport"), function()
            run("teleport", function()
                local name = UI.Get("teleport", "village")
                for _, v in ipairs(villages) do
                    if v.name == name then
                        -- Stage 1: next to the marker (markers can sit inside wells).
                        game.teleport({ x = v.x + 600, y = v.y, z = v.z }, 250)
                        status("teleport", t("teleporting", { name = name }))
                        -- Stage 2: once the navmesh exists around us, snap to a walkable spot.
                        sched.after(1500, function()
                            local ok, spot = pcall(game.walkableNear, v, 400, 1500)
                            if ok and spot then
                                game.teleport(spot, game.capsuleHalfHeight() + 20)
                                status("teleport", t("teleported", { name = name }))
                            else
                                log("teleport: no walkable spot found near " .. name)
                                status("teleport", t("teleported_unsafe", { name = name }))
                            end
                        end)
                        return
                    end
                end
                game.fail("select_village")
            end)
        end, "primary"),
        { type = "row", items = {
            button("savePos", t("save_position"), function()
                run("teleport", function() savedPosition = game.position(); status("teleport", t("position_saved")) end)
            end),
            button("loadPos", t("load_position"), function()
                run("teleport", function()
                    if not savedPosition then game.fail("no_saved_position") end
                    game.teleport(savedPosition, 50); status("teleport", t("position_loaded"))
                end)
            end),
        } },
        { type = "label", id = "status", label = "" },
    } })

    -- Settings -------------------------------------------------------------
    UI.Register({ id = "settings", tab = tab.settings, title = t("section_settings"), items = {
        { type = "dropdown", id = "language", label = t("language"), options = languageOptions(),
            default = i18n.get(),
            onChange = function(code)
                if code == i18n.get() or not i18n.set(code) then return end
                store.Set("language", code)
                log("language: " .. code)
                sched.run(function()
                    itemsLoaded = false; villages = {}; challengesLoaded = false
                    build()
                    UI.SetTab(t("tab_settings"))
                    pcall(refresh)
                    pcall(applyFont)
                end)
            end },
        { type = "dropdown", id = "menuKey", label = t("menu_key"), default = menuKeyName(),
            options = (function()
                local out = {}
                for _, k in ipairs(MENU_KEYS) do out[#out + 1] = { label = k[2], value = k[1] } end
                return out
            end)(),
            onChange = function(name)
                if name == store.Get("menuKey") then return end
                store.Set("menuKey", name)
                log("menu key set to " .. name .. " (after restart)")
                UI.SetLabel("settings", "keyHint", t("menu_key_restart", { key = keyLabel(name) }))
            end },
        { type = "label", id = "keyHint", label = t("hint_menu_key", { key = keyLabel(keyName) }) },
        button("diag", t("write_diagnostics"), function()
            run("settings", function() F.writeDiagnostics(); status("settings", t("diagnostics_written")) end)
        end),
        { type = "label", id = "status", label = "" },
    } })
end

-- Set to true while developing: dump key bindings + diagnostics.txt on first open.
local AUTO_DIAGNOSTICS = false
local diagnosticsDone = false
local function firstOpenDiagnostics()
    if diagnosticsDone or not AUTO_DIAGNOSTICS then return end
    local okP = pcall(game.player)
    if not okP then return end -- not in a save yet
    diagnosticsDone = true
    local ok, lines = pcall(game.blueprintKeyBindings)
    if ok then
        log("game Blueprint key bindings (" .. #lines .. "):")
        for _, line in ipairs(lines) do log("  " .. line) end
    end
    local ok2, err = pcall(F.writeDiagnostics)
    if not ok2 then log("diagnostics failed: " .. tostring(err)) end
end

function M.install()
    store.Init({ id = ID, defaults = { language = i18n.DEFAULT, menuKey = DEFAULT_MENU_KEY } })
    if not i18n.set(store.Get("language") or i18n.DEFAULT) then i18n.set(i18n.DEFAULT) end
    build()
    F.start()
    UI.OnOpen(function()
        sched.run(function()
            pcall(refresh)
            for _, s in ipairs({ "coins", "items", "skills", "health", "time", "teleport", "movement", "village", "recruit", "herald" }) do status(s, "") end
            pcall(applyFont)
            firstOpenDiagnostics()
        end)
    end)
    log("menu ready (language: " .. i18n.get() .. ", key " .. menuKeyName() .. ")")
end

return M
