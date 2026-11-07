First public release of **Dynasty Trainer** - an in-game trainer menu for **Medieval Dynasty** (singleplayer), written as a plain UE4SS Lua mod. No executables, every line is readable.

Press **F4** in game (F2, F11 or End selectable in Settings).

## Downloads

| File | For whom |
|---|---|
| `DynastyTrainer-1.0.0-Bundled.zip` | New installs. Contains UE4SS (preconfigured for Medieval Dynasty), ModMenu and the trainer. Extract into the game folder and play. |
| `DynastyTrainer-1.0.0.zip` | You already use UE4SS mods. Trainer only - needs [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental) (tested `UE4SS_v3.0.1-1185-gdff435dd`) and [ModMenu v1.4.0](https://github.com/mattdavida/ue4ss-ModMenu/releases/tag/v1.4.0). |

Install: Steam > Medieval Dynasty > Manage > Browse local files, extract, merge the `Medieval_Dynasty` folder. Details in `INSTALLATION.txt` inside each archive.

**Linux / Steam Deck (Proton):** add the launch option `WINEDLLOVERRIDES="dwmapi=n,b" %command%` - see `LINUX-STEAMDECK-PROTON.txt`.

## Features

- **Player:** unlimited health and stamina, no hunger/thirst, no poison, intoxication or dirt, unlimited carry weight, temperature protection, heal, max health +25%, age, skill points and levels
- **Inventory:** coins, any item from the game's item list (searchable, names in your game language)
- **World:** set hour, skip day/season (the game rolls over midnight itself), stop time, game speed, dynasty reputation, technology points, villager limit, max skills for all villagers, max affection, king's herald now or next season
- **Movement:** speed/jump/gravity multipliers, flying, no clip, field of view, teleport to villages, saved position
- **18 languages**, the same as the game

## Notes

- Singleplayer only.
- The menu does not open during conversations or game windows (protects the dialogue UI).
- Things you add are saved with your game - back up your saves.
- Tested on Steam build 25776186 (November 2026), Windows build of the game under Proton.

Third-party: UE4SS (MIT) and ModMenu by mattdavida (MIT) are included only in the Bundled archive, unchanged except UE4SS's engine version override, with their licenses.
