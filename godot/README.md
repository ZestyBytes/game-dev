# Gumdrop Cascade — Godot port (phase 1)

Native rewrite of the web game in Godot 4.3 / GDScript, aimed at real
app-store builds (iOS/Android/Steam) with no DOM overhead.

## Status: core game only

This phase has the actual gameplay working and verified:

- 8x8 match-3 grid, tap-to-select-and-swap
- match-3+ detection (horizontal + vertical), cascading chain reactions
- gravity/refill after clears
- stuck-board detection with auto-reshuffle
- scoring with combo multiplier (bigger chains score more)
- the speed bonus bar/timer (faster moves score more, like the web version)

**Not yet ported** from `web/index.html`: T-shape bomb specials, player
profiles, the level/map progression, sound, leaderboards. Those are
straightforward to add on top of this base once the core feel is approved.

## Running it

Godot isn't installed system-wide on this machine. Get the portable
4.3-stable binary (no root needed):

```
curl -fL -o godot.zip https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip
unzip godot.zip
chmod +x Godot_v4.3-stable_linux.x86_64
```

Then open the editor on this folder:

```
./Godot_v4.3-stable_linux.x86_64 --path godot
```

or run it directly:

```
./Godot_v4.3-stable_linux.x86_64 --path godot scenes/Main.tscn
```

## Tests

`scripts/test_headless.gd` is a headless smoke test for the pure grid logic
(not shipped in the game itself):

```
./Godot_v4.3-stable_linux.x86_64 --headless --path godot --script res://scripts/test_headless.gd
```

## Exporting to app stores

Once the gameplay is approved, exporting needs Godot's export templates
(`Editor > Manage Export Templates`) plus, for iOS, Xcode on a Mac to do the
final signed build — Godot itself just produces the Xcode project. Android
needs the Android SDK. Not set up yet in this pass.
