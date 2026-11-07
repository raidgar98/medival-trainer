-- DynastyTrainer: singleplayer trainer for Medieval Dynasty (UE4SS Lua).
-- F4 (configurable in Settings) opens the in-game menu. Modules:
--   game.lua     access to the game's objects (inventory, coins, ...)
--   features.lua toggles, multipliers, discovery, diagnostics
--   menu.lua     the in-game menu (shared ModMenu library)
--   i18n.lua     translations; texts live in locales/<code>.lua

local VERSION = "1.0.1"
print("[DynastyTrainer] version " .. VERSION .. "\n")

if not package.searchpath("ModMenu.ModMenu", package.path) then
    print("[DynastyTrainer] ModMenu not found. Install ModMenu v1.4.0 into ue4ss/Mods/shared/ModMenu/ " ..
        "(https://github.com/mattdavida/ue4ss-ModMenu/releases/tag/v1.4.0) and restart the game.\n")
    return
end

local ok, err = pcall(function() require("menu").install() end)
if not ok then print("[DynastyTrainer] failed to start: " .. tostring(err) .. "\n") end
