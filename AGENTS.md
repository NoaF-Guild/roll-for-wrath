# Agent Instructions — RollFor-WotLK

A WoW 3.3.5a (WotLK) addon written in Lua 5.1. This fork is **WotLK-only**; the `src/vanilla/` and `src/bcc/` directories exist only for reference and are **not** loaded by the active TOC.

---

## Critical Architecture Facts

- **Module system:** Every file starts with `RollFor = RollFor or {}` and registers on the global `RollFor` table (`m = RollFor`). There is no `require()` in the addon runtime; the TOC load order defines dependencies.
- **`m.api = getfenv()`** (`src/modules.lua:11`) — `m.api` IS the raw WoW global table `_G`. `main.lua` wraps it as `M.api = function() return m.api end`.
- **Dependency injection:** Components receive dependencies in constructors (`M.new(dep1, dep2, ...)`). Constructors validate injected objects with `interface.validate(impl, interface_table)` (`src/Interface.lua`).
- **Boundary rule:** `src/GameApi.lua` is the **single** place where WoW API version differences are normalized. Business logic never branches on `m.vanilla` / `m.wotlk` / `m.bcc`. If you need a new API call, add it to `GameApi` first.
- **Interface validation limitation:** `interface.validate` checks key presence and `type(v) == expected_type`. It does **NOT** check function arity or return shapes. This is why API bugs (wrong arg count, wrong return count) are invisible to tests — mocks encode the same wrong assumptions the code does.

---

## Developer Commands

### Run tests
```bash
./test.sh
```
Runs every `*_test.lua` file under `test/` with `lua5.1` and exits non-zero on first failure. CI (`./github/workflows/test.yml`) does exactly this.

### Run a single test file
```bash
cd test && lua5.1 GameApi_test.lua -v -T Spec -m should -o text
```
The flags are mandatory for the bundled luaunit runner. Test tables follow the pattern `GameApiSpec = {}` with `function GameApiSpec:should_do_something()`.

### Watch mode (requires `inotifywait`)
```bash
./test.sh listen
```
Runs the relevant test(s) on every `.lua` save.

### In-game self-test (after loading addon)
```
/rf apicheck   -- validates GameApi return shapes, library presence, Lua build
/rf commtest   -- broadcasts RF_PING over AceComm to verify comms round-trip
```

---

## Test Infrastructure

- **Framework:** Bundled luaunit at `test/luaunit.lua`.
- **Mocking:** `test/mocking.lua` provides `M.mock(name, value)`, `M.smart_table(map)`, `M.packed_value(array)` for injecting fake globals.
- **Addon bootstrap:** `test/utils.lua:923` — `M.load_real_stuff(req)` loads the entire addon into the test process in TOC order, mocks `_G` via `M.mock_api()`, and sets `m.wotlk = true`. Call this before constructing real components.
- **Test compat layer:** `load_real_stuff` loads `src/wotlk/compat` which provides `getn` / `mod` polyfills the test harness depends on. `m.wotlk = true` is set automatically by the compat layer.
- **Integration tests:** `test/IntegrationTestBuilder.lua` wires real components together with selective mock substitution via `M.load_real_stuff_and_inject(module_registry, target_table)`.
- **Standard mocks:**
  - `test/mocks/GameApi.lua` — use `GameApiMock.new(overrides)` for any test constructing `MasterLootCandidates`, `LootFacade`, `PlayerInfo`, or `AutoLoot`.
  - `M.mock_libraries()` — sets up mocked `AceTimer`, `AceComm`, `LibSerialize`, and `LibDeflate` for comms-related tests.
- **Test setup helpers:** `M.player(name, config)` bootstraps a full addon instance with mocked APIs and fires login events. `M.init()` resets state between tests.
- **Running order:** `lua5.1` must be used, not plain `lua` (Ubuntu package `lua5.1`).

---

## Repo Conventions & Style

- **Line length:** 160 (`.editorconfig`).
- **Spacing:** Spaces inside function call parens, param list parens, and square brackets (`space_inside_function_call_parentheses = true`).
- **Lua LS globals:** `RollForDb`, `RollForCharDb`, `LibStub` (`.luarc.json`).
- **Expansion flag:** `m.wotlk = true` is set by `src/wotlk/compat.lua`. `m.vanilla` is **never** true in this fork. Do not add new `m.vanilla` branches — they are dead code.
- **TOC load order:** `RollFor-WotLK.toc` is the source of truth. `src/GameApi.lua` must load before `src/LootFacade.lua`, `src/MasterLootCandidates.lua`, `src/PlayerInfo.lua`, and `src/AutoLoot.lua`.

---

## Build & Release

- **No package manager.** Libraries are vendored under `libs/wotlk/` (AceComm-3.0, LibSerialize, LibDeflate, LibStub, AceTimer, CallbackHandler).
- **CI:** `./test.sh` on every push/PR to `master`. Release workflow triggers on tags matching `[0-9]*`, updates TOC version, builds `RollFor-WotLK.zip`, and creates a GitHub release plus force-updates the `latest` tag.
- **Local release:** `release.sh <tag>` pushes the tag and copies to `$HOME/Dropbox` (the Dropbox path is author-specific; ignore for CI).

---

## Directory Ownership

| Path | What it is |
|------|-----------|
| `main.lua` | Addon entry point. Wires all components via `create_components()`. |
| `src/*.lua` | Shared core modules (rolled through `RollFor` global table). |
| `src/wotlk/` | WotLK 3.3.5a compat shims (`compat.lua`, `backport.lua`, `Json.lua`). Loaded first by TOC. |
| `src/vanilla/`, `src/bcc/` | Reference-only compat layers. **Not loaded** by `RollFor-WotLK.toc`. |
| `test/` | luaunit tests, mocks, fixtures, `utils.lua` bootstrap. |
| `docs/plans/` | Implementation plans (architecture decisions, migration sequences). |
| `libs/wotlk/` | Vendored Ace3 / LibStub / LibSerialize / LibDeflate / ChatThrottleLib. |
| `assets/` | Texture files referenced by relative `Interface\AddOns\RollFor-WotLK\assets\...` paths. |

---

## Common Gotchas

- **Do NOT use `getfenv()`** in new code. It was replaced with `_G` everywhere. It is deprecated and confusing.
- **Do NOT use `this` or `arg1` globals** in `SetScript` callbacks. WotLK Lua 5.1 passes `self` as the first parameter and subsequent args positionally. Existing code was fully migrated; grep should return zero hits.
- **`UnitIsGroupLeader` does not exist in 3.3.5a.** It was added in Cataclysm. Use `GameApi.is_party_leader()` or scan the raid roster for `rank == 2`.
- **AzerothCore private-server quirks:** Some 3.3.5a private-server cores return `nil` for `UnitIsPartyLeader` or use 1-arg `GetMasterLootCandidate`. The `GameApi` adapter has runtime fallbacks for these; check there before adding core-specific hacks elsewhere.
- **`next` file at repo root:** An untracked engineering handoff document. Read it when starting a fresh session — it contains cold-start context about recent work.
