# Syncing with Upstream (roll-for-vanilla)

This repo maintains a WotLK 3.3.5a port of obszczymucha's
[roll-for-vanilla](https://github.com/obszczymucha/roll-for-vanilla).
The `wotlk` branch is the active development branch; `master` tracks
the upstream vanilla codebase with a flattened directory layout.

## Remotes

| Remote | Points to | Purpose |
|--------|-----------|---------|
| `origin` | `NoaF-Guild/RollFor-WotLK` | Our fork (push here) |
| `upstream` | `obszczymucha/roll-for-vanilla` | Canonical upstream |
| `thezephyrsong` | `thezephyrsong/RollFor-WotLK` | Original WotLK port |

## Branch Strategy

```
master  ← tracks upstream vanilla (flattened layout)
  └── wotlk  ← active WotLK development (merges master periodically)
```

## Periodic Sync Workflow

### 1. Fetch upstream

```bash
git fetch upstream
```

### 2. Update master

```bash
git checkout master
git merge upstream/master
```

Note: If upstream still uses the `RollFor/` subfolder layout, you'll need
to flatten the new files the same way (move `RollFor/*` to root). If
upstream adopts flat layout, this step becomes a simple fast-forward.

### 3. Merge master into wotlk

```bash
git checkout wotlk
git merge master --no-commit
```

### 4. Resolve conflicts

Conflicts are expected in files where WotLK has API-specific changes.
General strategy:

| File category | Resolution |
|--------------|------------|
| **Shared core files** (`src/*.lua`) | Take ours (`git checkout --ours`), then cherry-pick specific upstream fixes if needed |
| **`main.lua`** | Manual merge — WotLK wiring + upstream features adapted |
| **WotLK-only** (`src/wotlk/`, `GameApi.lua`, `SrListener.lua`) | Keep ours |
| **Vanilla-only** (`GargulBridge.lua`, `RollForBroadcast.lua`) | Keep theirs (not loaded by WotLK TOC) |
| **Tests** | Take theirs, update `IntegrationTestBuilder` to mock `GameApi` if needed |
| **Libs** | Take theirs (version upgrades) |

Quick resolution for most `src/` conflicts:
```bash
# Take our WotLK version for all conflicted src files
for f in $(git diff --name-only --diff-filter=U | grep '^src/'); do
  git checkout --ours "$f"
  git add "$f"
done
```

### 5. Test

```bash
./test.sh
```

### 6. Commit

```bash
git commit -m "merge: sync upstream roll-for-vanilla vX.Y.Z"
```

### 7. Push

```bash
git push origin wotlk
```

## Architecture Notes

### Multi-Version Compat

The codebase uses per-version directories for API differences:

```
src/vanilla/   ← vanilla 1.12 compat (backport.lua, compat.lua, Json.lua)
src/bcc/       ← BCC 2.5.x compat
src/wotlk/    ← WotLK 3.3.5a compat
```

Each version's TOC loads only its own compat layer. The `GameApi.lua`
adapter normalizes WoW API calls behind a clean interface, making the
shared core code version-agnostic.

### Client Communication

Two systems exist side-by-side:
- **Vanilla**: `RollForBroadcast.lua` / `RollForReceiver.lua` (AceComm + LibSerialize)
- **WotLK**: `Client.lua` / `ClientBroadcast.lua` (manual chunking, from sica fork)

The WotLK TOC loads Client/ClientBroadcast. Consider migrating to
vanilla's AceComm approach long-term for better reliability.

### Known Gaps

- Integration tests need `IntegrationTestBuilder` updated to mock `GameApi`
- Unit tests (non-integration) work fine
- Some vanilla-specific features (Gargul integration) are present but
  not wired in the WotLK TOC
