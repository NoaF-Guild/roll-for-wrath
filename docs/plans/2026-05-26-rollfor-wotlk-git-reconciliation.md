# RollFor WotLK Git Reconciliation Implementation Plan

> **REQUIRED SUB-SKILL:** Use the executing-plans skill to implement this plan task-by-task.

**Goal:** Rebuild the RollFor-WotLK repository with proper git lineage rooted in obszczymucha's canonical `roll-for-vanilla` history, then apply all WotLK-specific changes as a clean branch that can merge upstream.

**Architecture:** We clone `roll-for-vanilla` as the new unified repo, restructure it to flat addon layout (matching WotLK's deployable structure), create a `wotlk` branch from the sica fork-point (`05b9640`), layer on the sica additions and WotLK port changes, then rebase onto vanilla `master` to incorporate the 14 upstream commits that happened after the fork. Going forward, the `main` branch tracks vanilla upstream and `wotlk` is a long-lived branch that periodically merges `main`.

**Tech Stack:** Git (graft/rebase/cherry-pick), Lua (WoW addon), busted/luaunit (tests)

---

## Background / Genealogy

```
obszczymucha/RollFor (TBC, 158 commits, ended 2023-09)
    └─► obszczymucha/roll-for-vanilla (177 commits, active, latest 2026-05-17)
            ├─► sica42/RollFor (16 commits, hard-forked from vanilla @ 05b9640, 2025-02-27)
            │     Squashed history. Added: WinnersPopup, OptionsPopup, ConfirmPopup,
            │     BindingsHandler, Client, ClientBroadcast. Removed GargulBridge.
            │
            └─► thezephyrsong/RollFor-WotLK (156 commits, hard-forked from sica)
                  Added: wotlk/ compat layer, SrListener, GameApi adapter,
                  Lua 5.1 compat fixes, this→self migration, WotLK API shims.
```

**Key facts:**
- Zero shared git hashes between any pair of repos (all hard forks via `git init`)
- Sica's initial commit matches vanilla `05b9640` exactly on 66 files, differs on 19, adds 5 new
- WotLK's initial commit matches sica's `fd04310` exactly (zero diff on `src/modules.lua`)
- Vanilla has 14 commits since the fork point (v4.6.5 → v4.6.17) including Gargul integration, client GUI/protocol, and bug fixes
- Vanilla uses `RollFor/` subfolder layout; WotLK/sica use flat root layout
- Vanilla independently built `RollForBroadcast`/`RollForReceiver` (AceComm+LibSerialize); WotLK has sica's `Client`/`ClientBroadcast` (manual chunking) — different implementations of the same concept

## Directory Layout Decision

**We adopt the flat layout** (WotLK/sica style) where repo root = addon directory. This is the standard WoW addon structure and matches what gets deployed. Vanilla's `RollFor/` subfolder exists because obszczymucha also keeps `test/` and sync scripts at repo root.

Our repo structure:
```
RollFor-WotLK/          ← repo root IS the addon folder
├── main.lua
├── RollFor.toc          ← vanilla TOC (for reference/multi-version future)
├── RollFor-WotLK.toc    ← WotLK TOC (Interface: 30300)
├── src/
│   ├── *.lua            ← shared core modules
│   ├── vanilla/         ← vanilla compat (kept for reference)
│   ├── bcc/             ← BCC compat (kept for reference)
│   └── wotlk/           ← WotLK compat layer
│       ├── compat.lua
│       ├── backport.lua
│       └── Json.lua
├── libs/
│   ├── vanilla/
│   ├── bcc/
│   └── wotlk/
├── assets/
├── test/                ← from vanilla upstream
└── docs/
```

---

## Phase 1: Create the Unified Repo with Real History

### Task 1: Clone vanilla upstream and set up remotes

**Context:** We start from `roll-for-vanilla` because it has the real git history (177 commits). We'll add the current WotLK repo as a remote for reference/cherry-picking.

**Step 1: Clone the vanilla repo to a new working directory**

```bash
cd /home/damon/Games/ChromieCraft_3.3.5a/Interface/AddOns/dev
git clone roll-for-vanilla RollFor-WotLK-unified
cd RollFor-WotLK-unified
```

**Step 2: Rename origin to upstream and add WotLK remote**

```bash
git remote rename origin upstream
git remote add wotlk-old ../RollFor-WotLK
git fetch wotlk-old
```

**Step 3: Verify the fork point commit exists**

```bash
git log --oneline 05b9640 -1
# Expected: 05b9640 Fix scaling issues in modern look.
```

**Step 4: Commit**

No code changes — just repo setup. Nothing to commit.

---

### Task 2: Restructure to flat addon layout

**Context:** Vanilla keeps files under `RollFor/` subfolder. We need the repo root to BE the addon directory (flat layout). This is a structural commit on master before branching.

**Files:**
- Move: `RollFor/*` → repo root
- Move: `test/` stays at root (already there)
- Delete: empty `RollFor/` directory after move
- Keep: `test.sh`, `README.md`, `docs/` at root

**Step 1: Move addon files to root**

```bash
# On master branch
git mv RollFor/main.lua ./main.lua
git mv RollFor/RollFor.toc ./RollFor.toc
git mv RollFor/RollFor-BCC.toc ./RollFor-BCC.toc 2>/dev/null || true
git mv RollFor/src ./src
git mv RollFor/libs ./libs
git mv RollFor/assets ./assets
git mv RollFor/TODO.md ./TODO.md 2>/dev/null || true
```

**Step 2: Update test paths if they reference `RollFor/src`**

```bash
grep -r "RollFor/" test/ --include='*.lua' -l
# Check each file and update paths from RollFor/src/ to src/
```

**Step 3: Run tests to verify nothing broke**

```bash
./test.sh
# Expected: all existing tests pass
```

**Step 4: Commit**

```bash
git add -A
git commit -m "refactor: flatten RollFor/ subfolder to repo root for standard addon layout"
```

---

### Task 3: Create the wotlk branch from the fork point

**Context:** The sica fork and subsequently WotLK were based on vanilla commit `05b9640`. We branch from there and will replay changes on top.

**Step 1: Create the branch**

```bash
git checkout -b wotlk 05b9640
```

**Step 2: Apply the same flattening on this branch**

```bash
git mv RollFor/main.lua ./main.lua
git mv RollFor/RollFor.toc ./RollFor.toc
git mv RollFor/src ./src
git mv RollFor/libs ./libs
git mv RollFor/assets ./assets
git mv RollFor/TODO.md ./TODO.md 2>/dev/null || true
git add -A
git commit -m "refactor: flatten RollFor/ subfolder to repo root"
```

**Step 3: Verify we're at the right point**

```bash
grep "^## Version" RollFor.toc
# Expected: ## Version: 4.6.5
```

**Step 4: No additional commit needed**

---

## Phase 2: Layer the Sica Additions

### Task 4: Apply sica's feature additions as a single commit

**Context:** Sica added 5 new files and modified 19 files on top of vanilla `05b9640`. These are: WinnersPopup, WinnersPopupGui, ConfirmPopup, BindingsHandler, Client, ClientBroadcast, OptionsPopup, OptionsGuiElements — plus modifications to modules.lua (hex_to_rgba, scale changes), GUI files, and other tweaks. We copy these from the current WotLK repo's initial commit since it preserved sica's code exactly.

**Files:**
- Create: `src/WinnersPopup.lua`, `src/WinnersPopupGui.lua`, `src/ConfirmPopup.lua`, `src/BindingsHandler.lua`, `src/Client.lua`, `src/ClientBroadcast.lua`, `src/OptionsPopup.lua`, `src/OptionsGuiElements.lua`
- Create: `Bindings.xml`
- Modify: 19 files (modules.lua, Config.lua, EventHandler.lua, FrameBuilder.lua, GuiElements.lua, ItemUtils.lua, LootAwardCallback.lua, LootFrame.lua, LootList.lua, MinimapButton.lua, ModernLootFrameSkin.lua, NonSoftResRollingLogic.lua, PopupBuilder.lua, RollController.lua, RollingLogic.lua, RollingPopup.lua, RollingPopupContentTransformer.lua, TooltipReader.lua, AwardedLoot.lua)

**Step 1: Extract sica's additions from WotLK initial commit**

For each new file, extract from the WotLK repo's initial commit:
```bash
cd /home/damon/Games/ChromieCraft_3.3.5a/Interface/AddOns/dev/RollFor-WotLK-unified

# New files from sica (via WotLK initial commit e4b10f4)
for f in src/WinnersPopup.lua src/WinnersPopupGui.lua src/ConfirmPopup.lua \
         src/BindingsHandler.lua src/Client.lua src/ClientBroadcast.lua \
         src/OptionsPopup.lua src/OptionsGuiElements.lua Bindings.xml; do
  git show wotlk-old/main~155:"$f" > "$f" 2>/dev/null && echo "Extracted: $f" || echo "SKIP: $f"
done
```

Note: `wotlk-old/main~155` = WotLK initial commit `e4b10f4`. Verify with:
```bash
git log --oneline wotlk-old/main | tail -1
```

**Step 2: Apply sica's modifications to existing files**

For the 19 modified files, extract the sica versions:
```bash
for f in src/modules.lua src/Config.lua src/EventHandler.lua src/FrameBuilder.lua \
         src/GuiElements.lua src/ItemUtils.lua src/LootAwardCallback.lua \
         src/LootFrame.lua src/LootList.lua src/MinimapButton.lua \
         src/ModernLootFrameSkin.lua src/NonSoftResRollingLogic.lua \
         src/PopupBuilder.lua src/RollController.lua src/RollingLogic.lua \
         src/RollingPopup.lua src/RollingPopupContentTransformer.lua \
         src/TooltipReader.lua src/AwardedLoot.lua; do
  git show wotlk-old/main~155:"$f" > "$f" 2>/dev/null && echo "Updated: $f" || echo "SKIP: $f"
done
```

**Step 3: Review the changes make sense**

```bash
git diff --stat
# Should show ~24 files changed (5 new + 19 modified)
```

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: add sica's TurtleWoW extensions

Adds WinnersPopup, OptionsPopup, ConfirmPopup, BindingsHandler,
Client/ClientBroadcast system, and various GUI improvements.

Based on sica42/RollFor (TurtleWoW fork)."
```

---

## Phase 3: Layer the WotLK Port

### Task 5: Add WotLK compatibility layer

**Context:** The WotLK compat layer provides API shims for 3.3.5a: GetLootSlotType polyfill, PlaySound numeric→string translation, C_Timer replacement, and Json.lua. These files are unique to WotLK and don't conflict with anything.

**Files:**
- Create: `src/wotlk/compat.lua`
- Create: `src/wotlk/backport.lua`
- Create: `src/wotlk/Json.lua`
- Create: `libs/wotlk/` (AceTimer, CallbackHandler, LibDeflate, LibStub)
- Create: `RollFor-WotLK.toc`

**Step 1: Copy WotLK compat files from current WotLK HEAD**

```bash
# WotLK-specific source files
mkdir -p src/wotlk
for f in src/wotlk/compat.lua src/wotlk/backport.lua src/wotlk/Json.lua; do
  cp ../RollFor-WotLK/"$f" "$f"
done

# WotLK-specific libs
cp -r ../RollFor-WotLK/libs/wotlk libs/wotlk

# WotLK TOC
cp ../RollFor-WotLK/RollFor-WotLK.toc ./RollFor-WotLK.toc
```

**Step 2: Verify the compat layer files look correct**

```bash
head -10 src/wotlk/compat.lua
# Expected: RollFor = RollFor or {} / local M = RollFor / M.wotlk = true
```

**Step 3: Commit**

```bash
git add -A
git commit -m "feat(wotlk): add WotLK 3.3.5a compatibility layer

- GetLootSlotType polyfill
- PlaySound numeric→string shim
- C_Timer OnUpdate replacement
- WotLK-specific AceTimer/CallbackHandler/LibDeflate/LibStub
- WotLK TOC (Interface: 30300)"
```

---

### Task 6: Apply WotLK port fixes (Lua 5.1 compat, API changes)

**Context:** The bulk of the WotLK port work was: `this`→`self`, `arg1`→explicit params, `unpack(arg)`→`...`, `GetObjectType` vs `GetFrameType`, texture path updates, and WotLK-specific API arity differences. These were done over ~20 commits in the WotLK repo. We apply them from the current WotLK HEAD state of each file.

**Files:**
- Modify: All shared `.lua` files that differ between sica's version and WotLK HEAD
- Create: `src/GameApi.lua` (your normalized adapter)
- Create: `src/SrListener.lua` (in-game SR whisper)
- Modify: `main.lua` (WotLK wiring)

**Step 1: Identify which files changed between WotLK initial and WotLK HEAD**

```bash
cd ../RollFor-WotLK
git diff --name-only e4b10f4..HEAD -- src/ main.lua | sort
```

**Step 2: For each changed file, copy from WotLK HEAD**

```bash
cd ../RollFor-WotLK-unified

# Copy all src/*.lua and main.lua from WotLK HEAD
for f in $(cd ../RollFor-WotLK && git diff --name-only e4b10f4..HEAD -- src/ main.lua); do
  mkdir -p "$(dirname "$f")"
  cp "../RollFor-WotLK/$f" "$f"
done
```

**Step 3: Copy any new files (GameApi, SrListener, docs, SoftRes)**

```bash
cp ../RollFor-WotLK/src/GameApi.lua src/GameApi.lua
cp ../RollFor-WotLK/src/SrListener.lua src/SrListener.lua
cp -r ../RollFor-WotLK/SoftRes ./SoftRes 2>/dev/null || true
cp -r ../RollFor-WotLK/docs ./docs 2>/dev/null || true
```

**Step 4: Update the WotLK TOC to match current state**

```bash
cp ../RollFor-WotLK/RollFor-WotLK.toc ./RollFor-WotLK.toc
```

**Step 5: Review the diff**

```bash
git diff --stat
# Should show 30-50 files changed
```

**Step 6: Commit as a series or single commit**

Option A — Single commit (simpler, recommended for now):
```bash
git add -A
git commit -m "feat(wotlk): port all WotLK 3.3.5a changes

- Lua 5.1 compat: this→self, arg1→explicit params, unpack(arg)→...
- WotLK API: GetLootMethod arity, GetMasterLootCandidate 2-arg
- GameApi normalized adapter for cross-version abstraction
- SrListener for in-game SR whispers
- Texture path updates for WotLK client
- Death Knight color support
- Various bug fixes from thezephyrsong and contributors"
```

Option B — If you want granular history, cherry-pick each meaningful commit from the WotLK repo (skip the CI/version-bump noise). The meaningful commits are roughly:
```
dc114b6  Add WotLK (3.3.5a) compatibility shims
ca7ca3d  fix(wotlk): replace unpack(arg) with ... for Lua 5.1 compat
f03b05a  fix(wotlk): replace this/arg1 with closure captures in GuiElements
d832c58  fix(wotlk): replace this/arg1 with self in entry_update handlers
96bf0f2  fix(wotlk): replace arg1 with explicit button param
17d3e20  fix(wotlk): add parent param to create_config
327b219  fix(wotlk): update create_config callers
efe9ca9  fix(wotlk): replace remaining this in WinnersPopupGui
00111a3  fix(wotlk): correct GetMasterLootCandidate arity
d70701c  fix(wotlk): handle 3-return GetLootMethod
601eca2  fix(wotlk): add raid-aware is_leader fallback
4f46c60  add support for death knight color
1764887  feat(api): add GameApi normalized adapter
5718710  refactor: migrate LootFacade into GameApi
0f2ecb1  refactor: migrate PlayerInfo to GameApi
d475b17  refactor: migrate AutoLoot to GameApi
```

---

## Phase 4: Merge Upstream Changes

### Task 7: Rebase/merge upstream vanilla commits onto wotlk branch

**Context:** Vanilla has 14 commits after `05b9640` that we want. These include bug fixes, Gargul integration, test fixes, client GUI, and client protocol work. Some will conflict with sica's changes (sica's Client/ClientBroadcast vs vanilla's RollForBroadcast/RollForReceiver). We use merge (not rebase) to preserve our commit identities.

**Step 1: Make sure master is up to date**

```bash
git checkout master
# master should already have the flatten commit + all vanilla history
```

**Step 2: Merge master into wotlk**

```bash
git checkout wotlk
git merge master --no-commit
```

**Step 3: Resolve conflicts**

Expected conflicts:
- **`main.lua`** — heavy conflict. Use WotLK version as base, cherry-pick vanilla's new features (GargulBridge wiring, client protocol wiring) into WotLK's main.lua.
- **`src/modules.lua`** — vanilla added `C_PartyInfo.GetLootMethod()` and `C_AddOns.GetAddOnMetadata()`; WotLK uses the old API names routed through compat. Keep WotLK version (compat layer handles the differences).
- **Client system** — vanilla added `RollForBroadcast.lua`/`RollForReceiver.lua`/`GargulBridge.lua`; WotLK has `Client.lua`/`ClientBroadcast.lua`. **Keep both** — WotLK TOC loads Client/ClientBroadcast, vanilla TOC would load RollForBroadcast/RollForReceiver. The compat layer can pick the right one.
- **Test files** — vanilla updated tests for 2.5.5 API. Take vanilla's test changes and verify they still pass.

Resolution strategy:
1. For shared core files: take vanilla's version, then re-apply WotLK-specific patches (compat shims, `self` fixes)
2. For WotLK-only files: keep as-is
3. For vanilla-only files: keep as-is (they won't be loaded by WotLK TOC)
4. For `main.lua`: manual merge — WotLK's wiring with vanilla's new features adapted

**Step 4: Run tests**

```bash
./test.sh
# Expected: all tests pass
```

**Step 5: Commit the merge**

```bash
git add -A
git commit -m "merge: incorporate vanilla upstream v4.6.5→v4.6.17

Merges 14 upstream commits including:
- Gargul integration
- Client GUI and protocol refactor
- Various bug fixes (loot awarding, rolling, scaling)
- Test updates for 2.5.5 API"
```

---

## Phase 5: Finalize and Swap

### Task 8: Update remotes and verify

**Step 1: Verify the git log looks right**

```bash
git log --oneline --graph wotlk | head -30
# Should show: your WotLK commits → merge commit → vanilla history going back to 2021
```

**Step 2: Verify the vanilla history is intact**

```bash
git log --oneline wotlk | tail -5
# Should end with: 21fc758 Initial commit.
# (obszczymucha's original 2021 commit)
```

**Step 3: Count total commits**

```bash
git rev-list --count wotlk
# Expected: 177 (vanilla) + 1 (flatten) + 1 (sica) + 1 (wotlk compat) + 1 (wotlk port) + 1 (merge) ≈ 182
# Or more if you cherry-picked individual WotLK commits
```

**Step 4: Set up remotes for going forward**

```bash
# Point to your org's repo
git remote add origin git@github-noaf:NoaF-Guild/RollFor-WotLK.git
git remote set-url upstream git@github-noaf:obszczymucha/roll-for-vanilla

# Push with force (this replaces the old broken history)
git push origin wotlk:main --force
```

---

### Task 9: Archive old repo and swap directories

**Step 1: Back up the old repo**

```bash
cd /home/damon/Games/ChromieCraft_3.3.5a/Interface/AddOns/dev
mv RollFor-WotLK RollFor-WotLK-old-$(date +%Y%m%d)
mv RollFor-WotLK-unified RollFor-WotLK
```

**Step 2: Verify the new repo works**

```bash
cd RollFor-WotLK
git log --oneline -5
git remote -v
ls src/wotlk/
```

**Step 3: Symlink or copy to AddOns directory for testing**

```bash
# If needed — check your existing setup
ls -la /home/damon/Games/ChromieCraft_3.3.5a/Interface/AddOns/RollFor-WotLK 2>/dev/null || echo "Set up addon symlink"
```

---

## Phase 6: Ongoing Maintenance Workflow

### Task 10: Document the merge-upstream workflow

**Files:**
- Create: `docs/UPSTREAM-SYNC.md`

**Step 1: Write the sync doc**

```markdown
# Syncing with Upstream (roll-for-vanilla)

## Setup (one time)
git remote add upstream git@github-noaf:obszczymucha/roll-for-vanilla

## Fetch upstream changes
git fetch upstream

## Merge into wotlk branch
git checkout main       # or wotlk, depending on branch strategy
git merge upstream/master --no-commit

## Resolve conflicts
# 1. Core shared files: take upstream version, re-apply WotLK compat patches
# 2. main.lua: manual merge (WotLK wiring + upstream features)
# 3. WotLK-only files (src/wotlk/, GameApi.lua, etc.): keep ours
# 4. Vanilla-only files (GargulBridge, etc.): keep theirs (not loaded by WotLK TOC)

## Test
./test.sh

## Commit
git commit -m "merge: sync upstream roll-for-vanilla vX.Y.Z"
```

**Step 2: Commit**

```bash
git add docs/UPSTREAM-SYNC.md
git commit -m "docs: add upstream sync workflow"
```

---

## Architecture Decision: WotLK-Only vs Multi-Version

**Recommendation: WotLK-focused branch that merges upstream.**

Rationale:
1. **Vanilla is actively maintained by obszczymucha** — don't duplicate his work
2. **The multi-version compat architecture already exists** — `src/vanilla/`, `src/bcc/`, `src/wotlk/` with per-version TOC loading
3. **Your GameApi adapter is the right pattern** — normalizes WoW API differences behind a clean interface
4. **14+ upstream changes in 3 months** — you want these for free
5. **Sica's TurtleWoW fork is dead** — don't maintain it

**Do NOT try to make one release that runs on all three versions.** Instead:
- Keep vanilla/bcc compat directories for reference and potential future use
- Focus testing and development on WotLK 3.3.5a
- Merge upstream periodically (the compat layer isolates API differences)
- If multi-version becomes valuable later, the GameApi adapter makes it straightforward

**Branch strategy:**
```
main (tracks vanilla upstream, periodically fetched)
 └── wotlk (your active development branch, merges main)
```

---

## Risk Register

| Risk | Mitigation |
|------|-----------|
| `main.lua` merge conflicts | Manual merge; this file is the wiring harness and will always need attention |
| Vanilla changes break WotLK compat | GameApi adapter insulates; run tests after every merge |
| Client/ClientBroadcast vs RollForBroadcast/RollForReceiver divergence | Keep both; TOC controls which loads. Consider migrating to vanilla's approach (AceComm+LibSerialize) long-term |
| Test suite doesn't cover WotLK paths | Add WotLK-specific test fixtures post-reconciliation |
| Force-push to NoaF-Guild remote | Coordinate with thezephyrsong and other contributors; they'll need to re-clone |

---

## Estimated Time

| Phase | Tasks | Time |
|-------|-------|------|
| Phase 1: Create unified repo | Tasks 1-3 | 15 min |
| Phase 2: Sica additions | Task 4 | 10 min |
| Phase 3: WotLK port | Tasks 5-6 | 20 min |
| Phase 4: Merge upstream | Task 7 | 30 min (conflict resolution) |
| Phase 5: Finalize | Tasks 8-9 | 10 min |
| Phase 6: Docs | Task 10 | 5 min |
| **Total** | | **~90 min** |
