# Changelog

## 1.0.1 - 2026-11-07

- Skip game objects the engine is destroying (PendingKill / Unreachable),
  e.g. villagers streaming out, before touching them. Hardening after a
  crash inside UE4SS during a Lua call (mod not identified from the stack).
- The background tick does nothing while no option is enabled.
- Time never moves backwards any more. Setting an hour that has already
  passed today moves on to that hour tomorrow (through a normal midnight).
  Moving the calendar back confused other mods (Bounty Hunting stops with
  "Calendar moved backwards") and is the most likely trigger of the crash.
- "Stop time" uses the game's own TimeFlowStoppedByCheat flag instead of
  rewriting the clock every 200 ms.

## 1.0.0 - 2026-11-07

First public release.

- In-game menu on F4 (F2, F11 or End selectable); blocked during conversations
  and game windows.
- Player: unlimited health and stamina, no hunger/thirst, no poison,
  intoxication or dirt, unlimited carry weight, temperature protection, heal,
  max health +25%, age, skill points and levels.
- Inventory: coins and any item from the game's item list.
- World: time, skip day/season, stop time, game speed, dynasty reputation,
  technology points, villager limit override, max villager skills, max
  affection, king's herald now / next season.
- Movement: speed/jump/gravity multipliers, flying, no clip, field of view,
  teleport to villages, saved position.
- 18 languages.
