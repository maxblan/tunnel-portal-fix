# Tunnel Portal Fix (Transport Fever 3)

[mod.io page](https://mod.io/g/transportfever3/m/tunnel-portal-fix)

Fixes tunnel portals that clip into each other when two parallel tracks enter the same hill at slightly different points.

## The bug

The engine groups parallel tracks into one tunnel "strip" with one wide portal. In-game tests (`spec/ingame/`) showed exactly when that happens:

- **Spacing:** tracks up to 5.2 m apart are merged; from 5.4 m on, never.
- **Same build:** the engine only merges tracks it sees together in one build command.
- **Staggered entries:** if the two tracks enter the hill at different points, the strip only starts at the second entry. The first track gets a single portal and the second entry gets a double portal, and the two clip into each other.

## The fix

The game script `tunnel_portal_fix/portal_align.*` runs after every completed build (`onPostBuildProposal`). It looks for a parallel neighbour whose portal is 1–20 m further out, 2.5–5.3 m to the side, with the same tunnel type and direction. For such a pair it sends one rebuild that:

1. moves the later track's portal level with the neighbour's (shortens its open-air edge, extends its tunnel edge, removes the old portal node), and
2. re-adds the neighbour's portal edges unchanged in the same build. Without this, the engine rejects the moved portal as a collision with the neighbour's single-track strip.

The engine then merges both tracks into one strip from the portal on, with one wide portal.

The rebuild waits until no build tool is open, because the track tool still holds the edges it just built and crashes if they disappear. Portals next to signals or waypoints are left untouched.

**Not fixed:** tracks 5.4–8 m apart. The engine never merges them, so their separate portals can still overlap. Fixing that would mean moving a track sideways.

## Layout

```
src/tunnel_portal_fix/            the mod as the game loads it (mod.json, _metadata/, content/)
  content/tunnel_portal_fix/
    portal_align.gs.lua           game script registration
    portal_align.script.lua       game script: event queue, tool gating, sending proposals
    alignment.lua                 when to align a pair, and the rebuild proposal
    portal.lua                    reading portals and neighbours from the track network
    curve.lua                     Hermite edge geometry
    logger.lua                    tagged logging
assets/preview.svg                source of the mod's preview image (_metadata/0.png, via make preview)
spec/                             Busted specs (*_spec.lua) against a mock engine
  support/                        setup.lua (Busted helper), mock_engine.lua
  ingame/                         in-game scenarios: run.sh and the dev-only testbench mod
tools/
  deploy.sh                       copy mods into / remove them from the game's staging area
  validate.sh                     run the game's own mod validation
  preview/                        SVG renderer for the preview image
  lua/                            fengari-based Lua tooling for machines without native Lua
```

Code follows the [LuaRocks style guide](https://github.com/luarocks/lua-style-guide):

- modules are `local name = {} … return name`;
- `snake_case` for own identifiers;
- `require("…")` into locals, no own globals.

Two exceptions come from the game:

- **Engine-loaded files:** files the engine loads as resources (`*.gs.lua`, `*.script.lua`, `app_script.lua`) must define the global `data()`, and engine callbacks keep the engine's names (`update`, `handleEvent`, `guiUpdate`).
- **Indentation:** tabs, like the base game and official mods.

Inside the game, `require("/x.lua")` resolves within the owning mod and `::/x.lua` within the base game.

## Development

```bash
make              # list targets
make deps         # once: fengari and the luacheck source for tools/lua
make lint         # luacheck
make test         # offline specs, a few seconds
make test-ingame  # in-game scenarios, about 7 minutes
make preview      # render assets/preview.svg to _metadata/0.png (1920x1080)
make deploy       # copy the mod into the game's staging area
make validate     # deploy, then run the game's mod validation (report in dist/validation.json)
make package      # dist/tunnel_portal_fix.zip
```

**Tools:**

- **Busted and luacheck:** `make test` and `make lint` use them when they are installed. Otherwise they run on [fengari](https://github.com/fengari-lua/fengari) (Lua 5.3 in node) through `tools/lua/`.
- **Mock engine:** `spec/support/mock_engine.lua` applies the mod's proposals to a small track network and models engine behaviour seen in-game:
  - game scripts may not pass callbacks to `sendCommand`;
  - the idle game reports `EntityDetailsTool` as the active tool;
  - `getComponent` returns copies;
  - resource files are loaded through `data()`.

**In-game tests:** `make test-ingame` deploys the mod and the testbench and launches the game with `--script tunnel_portal_fix_testbench_1::/tunnel_portal_fix_testbench/app_script.lua`. The app script starts a small test game with the official `urbangames_no_costs` mod. The testbench then builds each scenario of `scenarios.lua`, reads back the engine's portals and strips, and logs `PASS`/`FAIL`. The run ends by quitting the game and printing the results; full logs are kept in `spec/ingame/results/`.

Requirements:

- Steam is running and the game is not.
- A `steam_appid.txt` containing `3493540` exists in the game folder. Without it, Steam asks for confirmation of the custom launch argument on every start.

Game log: `<Steam userdata>/3493540/local/crash_dump/stdout.txt`. Mod lines start with `[tunnel_portal_fix]`. Set `logger.DEBUG = true` to also log queueing, tool state and the engine's strips.

## Publishing

Mods are published on [mod.io](https://mod.io/g/transportfever3) from inside the game. You need a mod.io account; logging in with a Paradox account or by email works.

1. `make check`, `make preview` and `make validate`.
2. In the game: **Main menu → Mods**, then pick "Tunnel Portal Fix" (the staging mod).
3. Check name, summary, description and tags (from `_metadata/modinfo.json`) and the logo (`_metadata/0.png`).
4. **Publish**. The game validates and cooks the mod again, then uploads it. Tick "Set Public" once it should be visible to everyone.

`_metadata/mod.io_fileid.txt` links the staging mod to the published mod.io entry; the game writes it on the first publish. Keep it in the repo, so `make deploy` preserves it and later publishes update the existing mod instead of creating a new one.

## License

[MIT](LICENSE). Transport Fever 3 is a trademark of Urban Games; this project is not affiliated with Urban Games or Paradox Interactive.
