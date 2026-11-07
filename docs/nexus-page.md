# Nexus Mods page - Dynasty Trainer

Values to paste into the upload form. Nexus requires accurate category, tags,
requirements and a description that matches what the mod really does
(File Submission Guidelines). Check each field against the live form.

## Basic fields

- **Name:** Dynasty Trainer - In-Game Cheat Menu (UE4SS)
- **Version:** 1.0.0
- **Summary:** In-game trainer menu (F4) for Medieval Dynasty singleplayer: unlimited health, stamina, food and water, coins and items, skills, reputation, technology, time control, villager skills and limit, king's herald, flying, no clip and teleport. 18 languages. Plain UE4SS Lua mod, source on GitHub. Tested on Linux/Proton and Steam Deck setup.
- **Category:** Cheats and God items (or the closest "Cheats" category on the Medieval Dynasty page)
- **Language of the mod page:** English
- **Tags to consider:** Cheats, Gameplay, User Interface, Translation (if offered); add only tags that really apply.

## Requirements (Requirements tab)

Off-site requirements (needed for the regular file; the Bundled file has both):

- **UE4SS** - https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental
  note: "Tested with UE4SS_v3.0.1-1185-gdff435dd. Not needed with the Bundled file."
- **ModMenu v1.4.0** (MIT, by mattdavida) - https://github.com/mattdavida/ue4ss-ModMenu/releases/tag/v1.4.0
  note: "Shared menu library. Not needed with the Bundled file."

## Permissions and credits

- Credits: ModMenu by Matthew Arvidson (mattdavida), MIT -
  https://github.com/mattdavida/ue4ss-ModMenu ; UE4SS team (RE-UE4SS), MIT.
  Both are redistributed only in the Bundled file, unchanged except the
  UE4SS-settings.ini engine override, with their license files.
- Asset use / upload / modification / conversion permissions: author's choice.
- **AI disclosure:** this mod was written with an AI coding assistant. Nexus
  defines an "AI Assisted" tag in its guidelines (new AI rules start
  2 January 2027) - declare it honestly in the form.

## Files tab

- Main file 1: `DynastyTrainer-1.0.0.zip` - "Trainer only. Requires UE4SS and ModMenu."
- Main file 2: `DynastyTrainer-1.0.0-Bundled.zip` - "Everything in one: UE4SS (preconfigured), ModMenu and the trainer. Do not use if UE4SS is already installed."
- Both are built by `tools/package.sh` / `tools/package.sh --bundled`.
- The Bundled file contains UE4SS DLLs; if Nexus' virus scan quarantines it,
  contact support@nexusmods.com with the page link (do not delete the file).

## Images

At least one in-game screenshot of the menu (Nexus gallery). Use real
screenshots only (truthful-claims rule).

## Description (BBCode)

```bbcode
[size=5][b]Dynasty Trainer[/b][/size]
An in-game trainer menu for [b]Medieval Dynasty[/b] (singleplayer). Press [b]F4[/b] in game.

[size=4][b]Why this one[/b][/size]
[list]
[*]The trainer itself is plain [b]UE4SS Lua scripts[/b] - nothing compiled. Only the Bundled file adds the official UE4SS DLLs.
[*]Uses the game's own variables and functions, found in the game's debug symbols and Blueprint data.
[*]Made and tested on Linux with Proton (the same Windows build of the game), so Windows should behave the same.
[*]18 languages - the same languages as the game.
[/list]

[size=4][b]Features[/b][/size]
[b]Player[/b]
[list]
[*]Unlimited health (game's own GodMode flag), unlimited stamina
[*]Never hungry, never thirsty
[*]No poison, intoxication or dirt
[*]Unlimited carry weight
[*]Cold and heat protection (comfortable temperature range)
[*]Heal fully, max health +25%, set age
[*]Skill points (+10 / +100) and max skill level - per skill or all
[/list]
[b]Inventory[/b]
[list]
[*]Add coins (quick buttons or any amount)
[*]Add any item - searchable list with names in your game language
[/list]
[b]World[/b]
[list]
[*]Set the hour, skip a day or a season (the game rolls over midnight itself, so daily logic runs normally), stop time, game speed
[*]Dynasty reputation +1,000 / +10,000
[*]Technology points (Building, Production, Farming, Survival)
[*]Override the villager limit (until game restart)
[*]Max skills (10) for all villagers of your settlement
[*]Max affection of the nearest villager
[*]King's herald: call him now with a chosen challenge, or make him come next season
[/list]
[b]Movement[/b]
[list]
[*]Speed, jump and gravity multipliers
[*]Flying and no clip (Space = up, C = down)
[*]Field of view
[*]Teleport to any village (lands on walkable ground), save / return to a position
[/list]
[b]Settings[/b]
[list]
[*]Language, menu key (F4, F2, F11 or End), diagnostics file for bug reports
[/list]

[size=4][b]Requirements[/b][/size]
[list]
[*][url=https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental]UE4SS[/url] - tested with UE4SS_v3.0.1-1185-gdff435dd
[*][url=https://github.com/mattdavida/ue4ss-ModMenu/releases/tag/v1.4.0]ModMenu v1.4.0[/url] (MIT, by mattdavida)
[/list]
[b]Or[/b] download the [b]Bundled[/b] file - it already contains both (UE4SS preconfigured for Medieval Dynasty).

[size=4][b]Installation[/b][/size]
[b]Bundled file:[/b] extract into the game folder (Steam > Manage > Browse local files), merging folders. Done (Linux: add the launch option below).
[b]Regular file:[/b]
[list=1]
[*]Install UE4SS into [i]Medieval_Dynasty\Binaries\Win64[/i] and set [i]EngineVersionOverride[/i] 4 / 27 / false in [i]UE4SS-settings.ini[/i].
[*]Extract ModMenu.zip into [i]Win64\ue4ss\Mods[/i].
[*]Extract this archive into the game folder, merging folders.
[*]Linux / Steam Deck: launch options [code]WINEDLLOVERRIDES="dwmapi=n,b" %command%[/code]
[*]Load a save and press F4.
[/list]
Full steps are in INSTALLATION.txt inside the archive; Linux / Steam Deck details in LINUX-STEAMDECK-PROTON.txt.

[size=4][b]Good to know[/b][/size]
[list]
[*][b]Singleplayer only.[/b] Not for co-op.
[*]The menu does not open during conversations or while a game window is open (this protects the dialogue UI).
[*]Toggles reset when you restart the game. Things you add (coins, items, skills, reputation...) are saved with your game - [b]back up your saves[/b].
[*]Tested on Steam build 25776186 (November 2026).
[/list]

[size=4][b]Compatibility[/b][/size]
Works alongside other UE4SS mods (tested with Dynasty Under Siege Plus, Dynasty Bounty Hunting and Trajectory Preview). The menu key avoids keys used by the game and those mods.

[size=4][b]Bug reports[/b][/size]
Please include [i]ue4ss\UE4SS.log[/i] and, if possible, the file from Settings > "Write diagnostics file".

[size=4][b]Credits[/b][/size]
[list]
[*]ModMenu by Matthew Arvidson (mattdavida) - MIT
[*]UE4SS team
[/list]
```
