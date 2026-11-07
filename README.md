# Dynasty Trainer

In-game trainer menu for Medieval Dynasty (singleplayer), written as a UE4SS
Lua mod. Player-facing docs live in `docs/`.

## Layout

```
src/DynastyTrainer/Scripts/   the mod (copied to ue4ss/Mods/DynastyTrainer)
  main.lua        entry point, VERSION
  game.lua        access to game objects (player, inventory, managers, tables)
  features.lua    toggles, multipliers, overrides with restore, diagnostics
  menu.lua        in-game menu (ModMenu), key handling, canOpen guard
  sched.lua       pinned game-thread scheduling (avoids UE4SS GC crashes)
  i18n.lua        translations, plural forms, number formatting
  locales/*.lua   one file per language (18, same as the game)
vendor/ModMenu/   ModMenu v1.4.0 (MIT) - used by deploy.sh and the Bundled archive
docs/             INSTALLATION / README / THIRD_PARTY for the archive, Nexus page
tools/deploy.sh   copy to the local game install (MD_GAME_DIR overrides the path)
tools/package.sh  build dist/DynastyTrainer-<version>.zip for Nexus
                  (--bundled: also UE4SS + ModMenu, downloaded and SHA-checked)
```

Player docs: `docs/INSTALLATION.txt` (regular), `docs/INSTALLATION-Bundled.txt`,
`docs/PROTON.txt` (Linux / Steam Deck), `docs/nexus-page.md` (upload form).

## Install from source

```sh
./tools/deploy.sh          # needs UE4SS installed; MD_GAME_DIR=... for a custom path
```

## Rules learned the hard way

- Every callback passed to UE4SS (`ExecuteInGameThread`, delayed or looping
  calls) must be pinned (`sched.lua`), otherwise Lua GC frees it and the game
  crashes with "Ref was not function".
- Loops run on the game thread (`LoopInGameThreadWithDelay`), not `LoopAsync`.
- Never call single steps of the game's NPC manager (e.g. `SpawnRandomNPC`):
  it creates villagers without a body model. Prefer the developers' own cheat
  functions (`GetChallengeCheat`) or plain variables.
- ALS rebuilds `MaxWalkSpeed` every frame - scale `walkingSpeed`,
  `runningSpeed`, `sprintingSpeed`, `crouchingSpeed` on the character instead.
- Player stats are 0..1 (Food, water, Stamina, health).

## Adding a language

Copy `locales/en.lua`, translate (keep keys and `{placeholders}`), set
`name`, `thousands` and `plural`, add the code to `M.LANGUAGES` in `i18n.lua`.
