# RollFor-WotLK 3.3.5a Porting Fixes Implementation Plan

> **REQUIRED SUB-SKILL:** Use the executing-plans skill to implement this plan task-by-task.

**Goal:** Fix all Vanilla-specific `this`/`arg1` global patterns, incorrect API arity assumptions, dead code, and side-effect bugs to work correctly on WotLK 3.3.5a, following conventions used by ElvUI, DBM, and HealBot.

**Architecture:**
1. Replace global `this` with explicit `self` parameters in SetScript callbacks.
2. Replace `arg1` global with named parameters.
3. Change `create_config()` to accept `parent` explicitly instead of relying on global `this`; update all callers in `OptionsPopup.lua`.
4. Fix `GetMasterLootCandidate` arity: Vanilla = 1-arg, WotLK = 2-arg (slot, index).
5. Fix `GetLootMethod` return-value handling: Vanilla = 2 returns, WotLK = 3 returns (method, partyMaster, raidMaster).
6. Fix `is_leader()` for WotLK raid context (no `UnitIsGroupLeader` in 3.3.5a).
7. Clean up dead code, side-effect mutations, and dead event registrations.

**Tech Stack:** WoW 3.3.5a Lua 5.1, RollFor-WotLK addon

---

## Context: What We're Fixing

On Vanilla 1.12, FrameXML sets a global `this` to the frame and `arg1`, `arg2`… to event arguments before calling script handlers. On WotLK 3.3.5a (Lua 5.1), the frame is passed as the first parameter `self` and arguments are passed as subsequent parameters. Addons like ElvUI and DBM always declare explicit parameters:

```lua
-- ElvUI pattern
frame:SetScript("OnMouseWheel", function(_, delta)
    self:Scroll(delta)
end)

-- DBM pattern
frame:SetScript("OnEvent", function(self, event, ...)
    -- handle event
end)
```

Additionally, several WoW API functions changed signatures between Vanilla and WotLK. The most impactful is `GetMasterLootCandidate` (1-arg → 2-arg) and `GetLootMethod` (2 returns → 3 returns), which break master-loot candidate resolution and master-looter self-detection in raids.

---

### Task 0: Verify Expansion Flag Detection (`m.wotlk` / `m.vanilla`)

**Severity:** 🔴 Critical — if flags are wrong, every expansion-gated fix takes the wrong branch.

**Files to inspect:**
- `RollFor-WotLK/RollFor-WotLK.toc` (load order)
- `RollFor-WotLK/src/wotlk/compat.lua` (WotLK flag + SOUNDKIT shim)
- `RollFor-WotLK/src/vanilla/compat.lua` (Vanilla flag — **NOT loaded by this TOC**)

**Step 1: Confirm `m.wotlk = true` is set**

In `wotlk/compat.lua` line 3:
```lua
M.wotlk = true
```
Verify:
```bash
grep -n "wotlk\s*=\s*true" RollFor-WotLK/src/wotlk/compat.lua
```
Expected: one match.

**Step 2: Confirm `m.vanilla` is NEVER set in the loaded file set**

```bash
grep -rn "vanilla\s*=\s*true" RollFor-WotLK/src/wotlk/
grep -n "vanilla" RollFor-WotLK/RollFor-WotLK.toc
```
Expected: no matches. The TOC only loads `src\wotlk\*.lua`; `vanilla/compat.lua` is present in the repo but never loaded.

**Step 3: Confirm `m.bcc` is NEVER set**
```bash
grep -rn "bcc\s*=\s*true" RollFor-WotLK/src/
```
Expected: no matches.

**Step 4: Confirm SOUNDKIT shim exists for WotLK path**

In `wotlk/compat.lua`:
```lua
_G.SOUNDKIT = _G.SOUNDKIT or { IG_MAINMENU_OPEN = 850, ... }
```
And the PlaySound polyfill maps numeric IDs to strings. This means `m.api.SOUNDKIT.IG_MAINMENU_OPEN` (used in `RollingPopup.lua` and `FrameBuilder.lua`) resolves to `850`, which the polyfill converts to `"igMainMenuOpen"` before calling native `PlaySound`.

Verify:
```bash
grep -n "_G.SOUNDKIT" RollFor-WotLK/src/wotlk/compat.lua
grep -n "PlaySound.*function" RollFor-WotLK/src/wotlk/compat.lua
```
Expected: both match.

**Step 5: Confirm all `m.vanilla`-only branches are dead code on this TOC**

Search for `if m.vanilla then` without a matching `m.wotlk`:
```bash
grep -rn "if m\.vanilla then" RollFor-WotLK/src/ | grep -v "m\.wotlk"
```
These branches are no-ops on WotLK (`m.vanilla` is nil → false). They do not cause errors.

**Step 6: Commit (documentation only)**

```bash
git add docs/plans/2026-05-25-wotlk-porting-fixes.md
git commit -m "docs: verify m.wotlk detection before API fixes"
```

---

### Task 1: Fix `main.lua` `unpack(arg)` — Lua 5.1 Varargs

**Files:**
- Modify: `RollFor-WotLK/main.lua` (~line 357)

**Step 1: Replace `unpack(arg)` with `...`**

In the `is_rolling_check` function, replace:

```lua
local function is_rolling_check( f )
  return function( ... )
    if not M.rolling_logic.is_rolling() then
      M.chat.info( "Rolling not in progress." )
      return
    end

    f( unpack( arg ) )
  end
end
```

With:

```lua
local function is_rolling_check( f )
  return function( ... )
    if not M.rolling_logic.is_rolling() then
      M.chat.info( "Rolling not in progress." )
      return
    end

    f( ... )
  end
end
```

In Lua 5.1, `...` is the vararg list. `arg` is not an implicit table (that was Lua 5.0). Passing `f(...)` forwards all varargs directly — this is the idiomatic 5.1 pattern.

**Step 2: Verify no `unpack(arg)` remains**

Run:
```bash
grep -n "unpack\s*(\s*arg\s*)" RollFor-WotLK/main.lua
```
Expected: No output.

**Step 3: Commit**

```bash
git add RollFor-WotLK/main.lua
git commit -m "fix(wotlk): replace unpack(arg) with ... for Lua 5.1 compat"
```

---

### Task 2: Fix `WinnersPopupGui.lua` — `arg1` and `this` in SetScript Callbacks

**Files:**
- Modify: `RollFor-WotLK/src/WinnersPopupGui.lua`

**Step 1: Fix `arg1` in `onMouseUp` handler**

Replace (~line 139-146):
```lua
  roll_type:SetScript( "onMouseUp", function()
    if arg1 == "RightButton" then
```

With:
```lua
  roll_type:SetScript( "onMouseUp", function( self, button )
    if button == "RightButton" then
```

**Step 2: Fix `this` in `M.roll_type_dropdown()` function**

The `M.roll_type_dropdown()` function references the global `this` expecting it to be the `roll_type` frame. Change the function to accept the frame as a parameter.

Replace (~line 78-95):
```lua
function M.roll_type_dropdown()
  ...
  local row = this:GetParent()
  ...
  local on_update_item = this.inner.on_update_item
  for _, cb in ipairs( M.roll_type_dropdown_frame.items ) do
    cb.checkbox:SetChecked( cb.value == this.inner.value )
```

With:
```lua
function M.roll_type_dropdown( frame )
  ...
  local row = frame:GetParent()
  ...
  local on_update_item = frame.inner.on_update_item
  for _, cb in ipairs( M.roll_type_dropdown_frame.items ) do
    cb.checkbox:SetChecked( cb.value == frame.inner.value )
```

And update the call site in the same file (~line 140):
```lua
  roll_type:SetScript( "onMouseUp", function( self, button )
    if button == "RightButton" then
      ...
      M.roll_type_dropdown( self )
      ...
```

**Step 3: Fix `this` in scroll bar button OnEnter/OnLeave**

Replace (~line 255-261):
```lua
      button:SetScript( "OnEnter", function()
        this:SetBackdropBorderColor( .125, .624, .976, .5 )
      end )
      button:SetScript( "OnLeave", function()
        this:SetBackdropBorderColor( .2, .2, .2, 1 )
      end )
```

With:
```lua
      button:SetScript( "OnEnter", function( self )
        self:SetBackdropBorderColor( .125, .624, .976, .5 )
      end )
      button:SetScript( "OnLeave", function( self )
        self:SetBackdropBorderColor( .2, .2, .2, 1 )
      end )
```

**Step 4: Verify no `this` or `arg1` remain**

Run:
```bash
grep -n "\bthis\b" RollFor-WotLK/src/WinnersPopupGui.lua | grep -v "this item\|this unique\|wtf is this\|TODO"
grep -n "\barg1\b" RollFor-WotLK/src/WinnersPopupGui.lua
```
Expected: Only comment/string matches for `this`; no `arg1` matches.

**Step 5: Commit**

```bash
git add RollFor-WotLK/src/WinnersPopupGui.lua
git commit -m "fix(wotlk): replace this/arg1 globals with self/button in WinnersPopupGui"
```

---

### Task 3: Fix `GuiElements.lua` — `this` in Callbacks and `arg1` in OnMouseUp

**Files:**
- Modify: `RollFor-WotLK/src/GuiElements.lua`

**Step 1: Fix `this` in checkbox on_select callback**

In `M.dropdown()`, the checkbox callback uses `this` which is the global set by the enclosing OnClick handler on Vanilla. On WotLK, capture the `item` frame in the closure instead.

Replace (~line 516-520):
```lua
      item = m.GuiElements.checkbox( dropdown, item_data.text, function( is_checked )
        if this.on_select then
          this.on_select( this.value, is_checked )
        end
        if on_select then
          on_select( this.value, is_checked )
        end
      end )
```

With:
```lua
      item = m.GuiElements.checkbox( dropdown, item_data.text, function( is_checked )
        if item.on_select then
          item.on_select( item.value, is_checked )
        end
        if on_select then
          on_select( item.value, is_checked )
        end
      end )
```

**Step 2: Fix `this` in item OnClick handler**

Replace (~line 536-542):
```lua
      item:SetScript( "OnClick", function()
        dropdown:Hide()
        if on_select then
          on_select( this.value, this.label:GetText() )
        end
      end )
```

With:
```lua
      item:SetScript( "OnClick", function()
        dropdown:Hide()
        if on_select then
          on_select( item.value, item.label:GetText() )
        end
      end )
```

**Step 3: Fix `arg1` in anchor_frame OnMouseUp**

Replace (~line 564-572):
```lua
    anchor_frame:SetScript( "OnMouseUp", function()
      if arg1 == button then
        if dropdown:IsVisible() then
          dropdown:Hide()
        else
          dropdown:Show()
        end
      end
    end )
```

With:
```lua
    anchor_frame:SetScript( "OnMouseUp", function( self, mouse_button )
      if mouse_button == button then
        if dropdown:IsVisible() then
          dropdown:Hide()
        else
          dropdown:Show()
        end
      end
    end )
```

**Step 4: Verify no `this` or `arg1` remain in SetScript callbacks**

Run:
```bash
grep -n "\bthis\b" RollFor-WotLK/src/GuiElements.lua | grep -v "if m.vanilla then self = this end\|-- this\|this took\|this table\|this item\|wtf is this\|TODO"
grep -n "\barg1\b" RollFor-WotLK/src/GuiElements.lua
```
Expected: Only the `m.vanilla then self = this end` guards (which are correct compatibility patterns); no `arg1`.

**Step 5: Commit**

```bash
git add RollFor-WotLK/src/GuiElements.lua
git commit -m "fix(wotlk): replace this/arg1 with closure captures and self in GuiElements"
```

---

### Task 4: Fix `OptionsGuiElements.lua` — `entry_update()` and Scroll/Tab/Area SetScript Handlers

**Files:**
- Modify: `RollFor-WotLK/src/OptionsGuiElements.lua`

**Step 1: Fix `M.entry_update()` — add `self` parameter**

Replace (~line 56-77):
```lua
function M.entry_update()
  local focus = m.api.GetMouseFocus()
  if (focus and focus.value) then
    return
  end

  if m.api.MouseIsOver( this ) and not this.over then
    this.tex:Show()
    this.over = true
    if this:GetParent():GetParent():GetParent():GetParent():GetParent().show_help then
      if this.tooltip then
        this:GetParent().tooltip = this
        m.api.GameTooltip:SetOwner( this, "ANCHOR_TOPLEFT" )
        m.api.GameTooltip:SetText( this.tooltip )
        m.api.GameTooltip:Show()
      end
    end
  elseif not m.api.MouseIsOver( this ) and this.over then
    this.tex:Hide()
    this.over = nil
    if m.api.GameTooltip:IsShown() and this:GetParent().tooltip == this then
      m.api.GameTooltip:Hide()
    end
  end
end
```

With:
```lua
function M.entry_update( self )
  if m.vanilla then self = this end
  local focus = m.api.GetMouseFocus()
  if (focus and focus.value) then
    return
  end

  if m.api.MouseIsOver( self ) and not self.over then
    self.tex:Show()
    self.over = true
    if self:GetParent():GetParent():GetParent():GetParent():GetParent().show_help then
      if self.tooltip then
        self:GetParent().tooltip = self
        m.api.GameTooltip:SetOwner( self, "ANCHOR_TOPLEFT" )
        m.api.GameTooltip:SetText( self.tooltip )
        m.api.GameTooltip:Show()
      end
    end
  elseif not m.api.MouseIsOver( self ) and self.over then
    self.tex:Hide()
    self.over = nil
    if m.api.GameTooltip:IsShown() and self:GetParent().tooltip == self then
      m.api.GameTooltip:Hide()
    end
  end
end
```

**Step 2: Fix `create_scroll_frame` — OnValueChanged and OnMouseWheel**

Replace (~line 160-164):
```lua
  f.slider:SetScript( "OnValueChanged", function()
    if is_updating then return end
    is_updating = true
    f:SetVerticalScroll( this:GetValue() )
```

With:
```lua
  f.slider:SetScript( "OnValueChanged", function( self )
    if is_updating then return end
    is_updating = true
    f:SetVerticalScroll( self:GetValue() )
```

Replace (~line 213-215):
```lua
  f:SetScript( "OnMouseWheel", function()
    this:scroll( arg1 * 10 )
  end )
```

With:
```lua
  f:SetScript( "OnMouseWheel", function( self, delta )
    self:scroll( delta * 10 )
  end )
```

**Step 3: Fix `create_scroll_child` — OnUpdate**

Replace (~line 230-232):
```lua
  f:SetScript( "OnUpdate", function()
    this:GetParent():update_scroll_state()
  end )
```

With:
```lua
  f:SetScript( "OnUpdate", function( self )
    self:GetParent():update_scroll_state()
  end )
```

**Step 4: Fix `create_tab_frame` — OnClick**

Replace (~line 245-254):
```lua
  f:SetScript( "OnClick", function()
    if this.area:IsShown() then
      return
    else
      for id, name in pairs( this.parent ) do
        if type( name ) == "table" and name.area and id ~= "parent" then
          name.area:Hide()
        end
      end
      this.area:Show()
    end
  end )
```

With:
```lua
  f:SetScript( "OnClick", function( self )
    if self.area:IsShown() then
      return
    else
      for id, name in pairs( self.parent ) do
        if type( name ) == "table" and name.area and id ~= "parent" then
          name.area:Hide()
        end
      end
      self.area:Show()
    end
  end )
```

**Step 5: Fix `create_area` — OnShow, OnHide, and scroll content OnShow**

Replace (~line 282-291):
```lua
  f:SetScript( "OnShow", function()
    parent.active_area = title
    this.indexed = true
    this.button.text:SetTextColor( 0.1254, 0.6235, 0.9764, 1 )
    this.button.bg:SetTexture( 1, 1, 1, 1 )
    this.button.bg:SetGradientAlpha( "VERTICAL", 1, 1, 1, .05, 0, 0, 0, 0 )
  end )

  f:SetScript( "OnHide", function()
    this.button.text:SetTextColor( 1, 1, 1, 1 )
    this.button.bg:SetTexture( 0, 0, 0, 0 )
  end )
```

With:
```lua
  f:SetScript( "OnShow", function( self )
    parent.active_area = title
    self.indexed = true
    self.button.text:SetTextColor( 0.1254, 0.6235, 0.9764, 1 )
    self.button.bg:SetTexture( 1, 1, 1, 1 )
    self.button.bg:SetGradientAlpha( "VERTICAL", 1, 1, 1, .05, 0, 0, 0, 0 )
  end )

  f:SetScript( "OnHide", function( self )
    self.button.text:SetTextColor( 1, 1, 1, 1 )
    self.button.bg:SetTexture( 0, 0, 0, 0 )
  end )
```

Replace (~line 301-306):
```lua
    f.scroll.content:SetScript( "OnShow", function()
      this.parent:UpdateScrollChildRect()
      if not this.setup then
        func()
        this.setup = true
      end
    end )
```

With:
```lua
    f.scroll.content:SetScript( "OnShow", function( self )
      self.parent:UpdateScrollChildRect()
      if not self.setup then
        func( self )
        self.setup = true
      end
    end )
```

Note: `func(self)` passes the content frame to the populate callback. This is required so `OptionsPopup.lua` callbacks have access to the parent frame.

**Step 6: Verify no `this` or `arg1` remain in modified functions**

Run:
```bash
grep -n "\bthis\b" RollFor-WotLK/src/OptionsGuiElements.lua | grep -v "^.*--.*this\|^.*TODO.*this"
grep -n "\barg1\b" RollFor-WotLK/src/OptionsGuiElements.lua
```
Expected: Only matches in `create_config` (Task 5) and comments.

**Step 7: Commit**

```bash
git add RollFor-WotLK/src/OptionsGuiElements.lua
git commit -m "fix(wotlk): replace this/arg1 with self in entry_update and scroll/tab/area handlers"
```

---

### Task 5: Fix `OptionsGuiElements.lua` — `create_config()` Signature and SetScript Callbacks

**Files:**
- Modify: `RollFor-WotLK/src/OptionsGuiElements.lua`

**Step 1: Change function signature — add `parent` parameter**

Replace (~line 313):
```lua
function M.create_config( caption, setting, widget, tooltip, ufunc, options )
```

With:
```lua
function M.create_config( parent, caption, setting, widget, tooltip, ufunc, options )
```

**Step 2: Replace function-level `this` with `parent`**

Replace (~line 324-360):
```lua
  this.object_count = this.object_count == nil and 0 or this.object_count + 1

  local config_db = this:GetParent():GetParent():GetParent().config_db
  local frame = m.api.CreateFrame( "Frame", nil, this )
  frame:SetWidth( this:GetParent():GetWidth() - 22 )
  frame:SetHeight( 22 )
  frame:SetPoint( "TOPLEFT", this, "TOPLEFT", 5, (this.object_count * -23) - 5 )
  ...
  if not this.first_header then
    this.first_header = true
    ...
  else
    ...
    this.object_count = this.object_count + 1
  end
```

With:
```lua
  parent.object_count = parent.object_count == nil and 0 or parent.object_count + 1

  local config_db = parent:GetParent():GetParent():GetParent().config_db
  local frame = m.api.CreateFrame( "Frame", nil, parent )
  frame:SetWidth( parent:GetParent():GetWidth() - 22 )
  frame:SetHeight( 22 )
  frame:SetPoint( "TOPLEFT", parent, "TOPLEFT", 5, (parent.object_count * -23) - 5 )
  ...
  if not parent.first_header then
    parent.first_header = true
    ...
  else
    ...
    parent.object_count = parent.object_count + 1
  end
```

**Step 3: Fix button SetPoint that uses `this:GetParent()`**

Replace (~line 491):
```lua
    frame.button:SetPoint( "TOPLEFT", (this:GetParent():GetWidth() / 2 - w / 2 - 10), -5 )
```

With:
```lua
    frame.button:SetPoint( "TOPLEFT", (parent:GetParent():GetWidth() / 2 - w / 2 - 10), -5 )
```

**Step 4: Fix EditBox OnEscapePressed**

Replace (~line 381-383):
```lua
      frame.input:SetScript( "OnEscapePressed", function()
        this:ClearFocus()
      end )
```

With:
```lua
      frame.input:SetScript( "OnEscapePressed", function( self )
        self:ClearFocus()
      end )
```

**Step 5: Fix first OnTextChanged (text widget)**

Replace (~line 405-412):
```lua
      frame.input:SetScript( "OnTextChanged", function()
        local v = this:GetText()
        if ufunc then
          ufunc( v )
        else
          config_db[ setting ] = v
        end
      end )
```

With:
```lua
      frame.input:SetScript( "OnTextChanged", function( self )
        local v = self:GetText()
        if ufunc then
          ufunc( v, self )
        else
          config_db[ setting ] = v
        end
      end )
```

**Step 6: Fix second OnTextChanged (number widget)**

Replace (~line 416-429):
```lua
      frame.input:SetScript( "OnTextChanged", function()
        local v = tonumber( this:GetText() )
        local valid = v and ((not options.min or v >= options.min) and (not options.max or v <= options.max))

        if valid then
          if config_db[ setting ] ~= v then
            config_db[ setting ] = v
            if ufunc then ufunc( v ) end
          end
          this:SetTextColor( 0.1254, 0.6235, 0.9764, 1 )
        else
          this:SetTextColor( 1, .3, .3, 1 )
        end
      end )
```

With:
```lua
      frame.input:SetScript( "OnTextChanged", function( self )
        local v = tonumber( self:GetText() )
        local valid = v and ((not options.min or v >= options.min) and (not options.max or v <= options.max))

        if valid then
          if config_db[ setting ] ~= v then
            config_db[ setting ] = v
            if ufunc then ufunc( v, self ) end
          end
          self:SetTextColor( 0.1254, 0.6235, 0.9764, 1 )
        else
          self:SetTextColor( 1, .3, .3, 1 )
        end
      end )
```

**Step 7: Fix checkbox OnClick**

Replace (~line 457-465):
```lua
      frame.input:SetScript( "OnClick", function()
        if this:GetChecked() then
          config_db[ setting ] = true
        else
          config_db[ setting ] = false
        end

        if ufunc then ufunc( this:GetChecked() ) end
      end )
```

With:
```lua
      frame.input:SetScript( "OnClick", function( self )
        if self:GetChecked() then
          config_db[ setting ] = true
        else
          config_db[ setting ] = false
        end

        if ufunc then ufunc( self:GetChecked(), self ) end
      end )
```

**Step 8: Fix button OnEnter/OnLeave**

Replace (~line 497-508):
```lua
    frame.button:SetScript( "OnEnter", function()
      this:SetBackdropBorderColor( 0.1254, 0.6235, 0.9764, 1 )
      if this:GetParent():GetParent():GetParent():GetParent():GetParent():GetParent().show_help then
        if this:GetParent().tooltip then
          m.api.GameTooltip:SetOwner( this, "ANCHOR_TOPLEFT" )
          m.api.GameTooltip:SetText( this:GetParent().tooltip )
          m.api.GameTooltip:Show()
        end
      end
    end )
    frame.button:SetScript( "OnLeave", function()
      this:SetBackdropBorderColor( .2, .2, .2, 1 )
      if m.api.GameTooltip:IsShown() then
        m.api.GameTooltip:Hide()
      end
    end )
```

With:
```lua
    frame.button:SetScript( "OnEnter", function( self )
      self:SetBackdropBorderColor( 0.1254, 0.6235, 0.9764, 1 )
      if self:GetParent():GetParent():GetParent():GetParent():GetParent():GetParent().show_help then
        if self:GetParent().tooltip then
          m.api.GameTooltip:SetOwner( self, "ANCHOR_TOPLEFT" )
          m.api.GameTooltip:SetText( self:GetParent().tooltip )
          m.api.GameTooltip:Show()
        end
      end
    end )
    frame.button:SetScript( "OnLeave", function( self )
      self:SetBackdropBorderColor( .2, .2, .2, 1 )
      if m.api.GameTooltip:IsShown() then
        m.api.GameTooltip:Hide()
      end
    end )
```

**Step 9: Verify no `this` or `arg1` remain in the file**

Run:
```bash
grep -n "\bthis\b" RollFor-WotLK/src/OptionsGuiElements.lua | grep -v "^.*--.*this\|^.*TODO.*this"
grep -n "\barg1\b" RollFor-WotLK/src/OptionsGuiElements.lua
```
Expected: No output.

**Step 10: Sanity-check — verify sibling frame hierarchy is preserved**

The transforms in Task 6 Examples 2 and 4 replace `this:GetParent():GetParent()` with `input:GetParent():GetParent()`. In the original Vanilla code, `this` is `frame.input` (the SetScript self). In the new WotLK code, `input` is the same `frame.input` (the explicit `self` parameter). The parent chain is identical:
- `input` = `frame.input`
- `input:GetParent()` = `frame` (the config frame)
- `input:GetParent():GetParent()` = `parent` (the scroll content frame passed to `create_config`)

This must be verified at runtime for the +1/tmog sibling enable/disable callbacks:
1. Open `/rfo` → "Rolling" tab
2. Check "Handle +1's on MS rolls"
3. Verify "Always prompt for +1's" enables/disables correctly
4. Check "Enable transmog rolling" (if visible)
5. Verify "Transmog roll threshold" enables/disables correctly

If siblings don't toggle, the parent chain resolution is wrong.

**Step 11: Commit**

```bash
git add RollFor-WotLK/src/OptionsGuiElements.lua
git commit -m "fix(wotlk): add parent param to create_config, replace this/arg1 with self"
```

---

### Task 6: Update `OptionsPopup.lua` Callers — Pass `parent` and Fix Callback References

**Files:**
- Modify: `RollFor-WotLK/src/OptionsPopup.lua`

**Step 1: Update all `e.create_config(...)` calls to `e.create_config(parent, ...)`**

Every `e.create_config()` call in the file must be updated. There are ~40 calls across the "General", "Looting", "Rolling", and "Client" tabs. The pattern is:

**Before:**
```lua
e.create_config( "Setting Name", "setting_key", "widget", ... )
```

**After:**
```lua
e.create_config( parent, "Setting Name", "setting_key", "widget", ... )
```

Apply this to ALL calls. Representative examples:

```lua
e.create_config( parent, "General settings", nil, "header" )
e.create_config( parent, "Classic look", "classic_look", "checkbox", "Toggle classic look. Requires /reload", function()
  event_bus.notify( "config_change_requires_ui_reload", { key = "classic_look" } )
end )
e.create_config( parent, "Master loot warning", "show_ml_warning", "checkbox", ... )
```

**Step 2: Update all populate callbacks to accept `parent`**

Every `function()` inside `e.create_gui_entry(..., function() ... end)` must be changed to `function( parent )`.

**Before:**
```lua
e.create_gui_entry( "General", frames, function()
  e.create_config( ... )
end )
```

**After:**
```lua
e.create_gui_entry( "General", frames, function( parent )
  e.create_config( parent, ... )
end )
```

Apply this to ALL four entries: "General", "Looting", "Rolling", "Client".

**Step 3: Replace `this.xxx = e.create_config(...)` with `parent.xxx = e.create_config(...)`**

**Before:**
```lua
this.enable_quick_award_shift = e.create_config( "Enable quick award to self", ... )
```

**After:**
```lua
parent.enable_quick_award_shift = e.create_config( parent, "Enable quick award to self", ... )
```

Apply this to ALL assignments:
- `this.enable_quick_award_shift`
- `this.enable_quick_award_ctrl`
- `this.quick_award_ctrl`
- `this.disable_quick_award_confirm`
- `this.disable_quick_award_confirm_bop`
- `this.handle_plus_ones`
- `this.plus_one_prompt`
- `this.tmog_rolling_enabled`
- `this.tmog_roll_threshold`
- `this.auto_tmog`

**Step 4: Fix callback references inside `ufunc` callbacks**

Callbacks that previously accessed `this` now receive the input frame as the second argument (`self` from the SetScript callback). Replace `this` with the input parameter.

**Example 1 — `quick_award_ctrl` callback:**

**Before:**
```lua
this.quick_award_ctrl = e.create_config( "Award Ctrl-click to the following player", "quick_award_ctrl", "text|width=70",
  "Specify which player should receive loot when ctrl-clicking \"...\" button.", function( value )
    if this.disabled then return end
    ...
  end )
```

**After:**
```lua
parent.quick_award_ctrl = e.create_config( parent, "Award Ctrl-click to the following player", "quick_award_ctrl", "text|width=70",
  "Specify which player should receive loot when ctrl-clicking \"...\" button.", function( value, input )
    if input.disabled then return end
    ...
  end )
```

**Example 2 — `handle_plus_ones` callback:**

**Before:**
```lua
this.handle_plus_ones = e.create_config( "Handle +1's on MS rolls", "handle_plus_ones", "checkbox", nil, function( value )
  if value then
    this:GetParent():GetParent().plus_one_prompt.input.enable()
  else
    this:GetParent():GetParent().plus_one_prompt.input.disable()
  end
end )
```

**After:**
```lua
parent.handle_plus_ones = e.create_config( parent, "Handle +1's on MS rolls", "handle_plus_ones", "checkbox", nil, function( value, input )
  if value then
    input:GetParent():GetParent().plus_one_prompt.input.enable()
  else
    input:GetParent():GetParent().plus_one_prompt.input.disable()
  end
end )
```

**Example 3 — checking sibling state at function level:**

**Before:**
```lua
this.handle_plus_ones = e.create_config( ... )
...
this.plus_one_prompt = e.create_config( ... )
if not this.handle_plus_ones.input:GetChecked() then
  this.plus_one_prompt.input.disable()
end
```

**After:**
```lua
parent.handle_plus_ones = e.create_config( parent, ... )
...
parent.plus_one_prompt = e.create_config( parent, ... )
if not parent.handle_plus_ones.input:GetChecked() then
  parent.plus_one_prompt.input.disable()
end
```

**Example 4 — `tmog_rolling_enabled` callback:**

**Before:**
```lua
this.tmog_rolling_enabled = e.create_config( "Enable transmog rolling", "tmog_rolling_enabled", "checkbox", nil, function( value )
  if value then
    this:GetParent():GetParent().tmog_roll_threshold.input.enable()
  else
    this:GetParent():GetParent().tmog_roll_threshold.input.disable()
  end
end )
```

**After:**
```lua
parent.tmog_rolling_enabled = e.create_config( parent, "Enable transmog rolling", "tmog_rolling_enabled", "checkbox", nil, function( value, input )
  if value then
    input:GetParent():GetParent().tmog_roll_threshold.input.enable()
  else
    input:GetParent():GetParent().tmog_roll_threshold.input.disable()
  end
end )
```

**Example 5 — checking sibling state:**

**Before:**
```lua
if not this.tmog_rolling_enabled.input:GetChecked() then
  this.tmog_roll_threshold.input.disable()
  this.auto_tmog.input.disable()
end
```

**After:**
```lua
if not parent.tmog_rolling_enabled.input:GetChecked() then
  parent.tmog_roll_threshold.input.disable()
  parent.auto_tmog.input.disable()
end
```

Apply the same pattern to ALL remaining `this.` references in the file.

**Step 5: Verify no `this` or `arg1` remain**

Run:
```bash
grep -n "\bthis\b" RollFor-WotLK/src/OptionsPopup.lua | grep -v "^.*--.*this\|this item\|this message\|this instance\|disable this"
grep -n "\barg1\b" RollFor-WotLK/src/OptionsPopup.lua
```
Expected: Only comment/string matches for `this`; no `arg1`.

**Step 6: Commit**

```bash
git add RollFor-WotLK/src/OptionsPopup.lua
git commit -m "fix(wotlk): update create_config callers to pass parent, replace this with parent/input"
```

---

### Task 7: Verify `GetLootSlotInfo` Return Values on WotLK

**Severity:** 🟡 Medium — verify, likely no code change needed.

**File:** `RollFor-WotLK/src/LootFacade.lua`

**Step 1: Confirm 4-value capture is correct for WotLK 5-return API**

WotLK 3.3.5a `GetLootSlotInfo(slot)` returns: `texture, name, quantity, quality, locked` (5 values).

Current code:
```lua
if m.vanilla or m.wotlk then
    local texture, name, quantity, quality = api.GetLootSlotInfo( slot )
```

Lua discards excess returns, so `locked` (5th) is dropped and `quality` (4th) is captured correctly. This is safe. No code change needed.

Verify against your specific core (private-server cores sometimes deviate):
```bash
-- In-game test after all fixes:
/script for i=1,GetNumLootItems() do local a,b,c,d,e = GetLootSlotInfo(i); print(i,a,b,c,d,e) end
```
Confirm 5th return is `locked` (boolean/nil) and 4th is `quality` (number).

---

### Task 7b: Verify `getn` vs Hash-Keyed Tables

**Severity:** 🟡 Medium — verify, likely no code change needed.

**Files:** `RollFor-WotLK/src/wotlk/compat.lua`, `RollFor-WotLK/src/NameManualMatcher.lua`

**Step 1: Confirm `m.getn` is `#t` (array-length operator)**

```bash
grep -n "getn.*=.*#" RollFor-WotLK/src/wotlk/compat.lua
```
Expected: `M.getn = function( t ) return #t end`

In Lua 5.1, `#t` returns the array-part length. For string-keyed tables, `#t` = 0.

**Step 2: Confirm `db.manual_matches` uses `count_elements`, not `getn`**

```bash
grep -n "manual_matches" RollFor-WotLK/src/NameManualMatcher.lua
```
Line 120 shows: `m.count_elements( db.manual_matches )` — `count_elements` uses `pairs()` and counts all keys. This is correct for hash tables.

No code change needed.

---

### Task 7c: Final UI Verification — Grep Sweep for Remaining `this`/`arg1` Globals

**Files:**
- All modified files

**Step 1: Grep for remaining `this` as a code reference (not in comments/strings)**

Run across all source files:
```bash
cd RollFor-WotLK/src
for f in *.lua; do
  matches=$(grep -n "\bthis\b" "$f" | grep -v "^.*--.*this\|^.*TODO.*this\|this took\|this table\|this item\|this message\|this instance\|wtf is this\|disable this\|split this\|clearing this\|before this\|this software\|this permission\|this code" | wc -l)
  if [ "$matches" -gt 0 ]; then
    echo "=== $f ==="
    grep -n "\bthis\b" "$f" | grep -v "^.*--.*this\|^.*TODO.*this\|this took\|this table\|this item\|this message\|this instance\|wtf is this\|disable this\|split this\|clearing this\|before this\|this software\|this permission\|this code"
  fi
done
```

Expected: Only the `if m.vanilla then self = this end` guards in `GuiElements.lua`, `MasterLootCandidateSelectionFrame.lua`, `ModernLootFrameSkin.lua`, `OgLootFrameSkin.lua`, `MinimapButton.lua` — these are correct compatibility patterns.

**Step 2: Grep for remaining `arg1` as a global reference**

```bash
for f in *.lua; do
  matches=$(grep -n "\barg1\b" "$f" | grep -v "^.*--.*arg1\|lua50 and arg1\|fun(.*arg1" | wc -l)
  if [ "$matches" -gt 0 ]; then
    echo "=== $f ==="
    grep -n "\barg1\b" "$f" | grep -v "^.*--.*arg1\|lua50 and arg1\|fun(.*arg1"
  fi
done
```

Expected: Only `EventFrame.lua` and `EventHandler.lua` which correctly handle `arg1` through `lua50` detection.

**Step 3: Commit**

```bash
git add docs/plans/2026-05-25-wotlk-porting-fixes.md
git commit -m "docs: add WotLK porting fixes implementation plan"
```

---

## Part 2: API-Level Fixes (Not UI/FrameXML)

The following tasks fix incorrect WoW API assumptions that will silently break master-looting functionality on a real 3.3.5a client.

---

### Task 8: Fix `MasterLootCandidates.lua` — GetMasterLootCandidate Arity

**Severity:** 🔴 Critical — breaks master-loot candidate resolution on WotLK.

**Files:**
- Modify: `RollFor-WotLK/src/MasterLootCandidates.lua`

**Problem:** The code groups `m.vanilla or m.wotlk` together and calls the single-argument form `GetMasterLootCandidate(i)`. But WotLK 3.3.5a uses the **two-argument** signature `GetMasterLootCandidate(slot, index)`. `AutoLoot.lua` already handles this correctly (vanilla → 1-arg, else → 2-arg); `MasterLootCandidates.lua` is the only broken file.

**Step 1: Fix `get()` function — split vanilla and wotlk branches**

Replace (~line 52-68):
```lua
    for i = 1, 40 do
      -- Group legacy 1-argument APIs together (Vanilla and 3.3.5 WotLK)
      if m.vanilla or m.wotlk then
        ---@diagnostic disable-next-line: missing-parameter
        local name = api.GetMasterLootCandidate( i )

        for _, p in ipairs( players ) do
          if name == p.name then
            table.insert( result, make_item_candidate( name, p.class, p.online ) )
          end
        end
      else
        -- Modern clients (BCC, Retail, WotLK Classic) require the slot
        local name = api.GetMasterLootCandidate( slot, i )

        for _, p in ipairs( players ) do
          if name == p.name then
            table.insert( result, make_item_candidate( name, p.class, p.online ) )
          end
        end
      end
    end
```

With:
```lua
    for i = 1, 40 do
      if m.vanilla then
        ---@diagnostic disable-next-line: missing-parameter
        local name = api.GetMasterLootCandidate( i )

        for _, p in ipairs( players ) do
          if name == p.name then
            table.insert( result, make_item_candidate( name, p.class, p.online ) )
          end
        end
      else
        -- WotLK 3.3.5a, BCC, Retail: two-argument form (slot, index)
        local name = api.GetMasterLootCandidate( slot, i )

        for _, p in ipairs( players ) do
          if name == p.name then
            table.insert( result, make_item_candidate( name, p.class, p.online ) )
          end
        end
      end
    end
```

**Step 2: Fix `get_index()` function — same separation**

Replace (~line 99-108):
```lua
    for i = 1, 40 do
      -- Group legacy 1-argument APIs together (Vanilla and 3.3.5 WotLK)
      if m.vanilla or m.wotlk then
        ---@diagnostic disable-next-line: missing-parameter
        local name = api.GetMasterLootCandidate( i )
        if name == player_name then return i end
      else
        -- Modern clients (BCC, Retail, WotLK Classic) require the slot
        local name = api.GetMasterLootCandidate( slot, i )
        if name == player_name then return i end
      end
    end
```

With:
```lua
    for i = 1, 40 do
      if m.vanilla then
        ---@diagnostic disable-next-line: missing-parameter
        local name = api.GetMasterLootCandidate( i )
        if name == player_name then return i end
      else
        -- WotLK 3.3.5a, BCC, Retail: two-argument form (slot, index)
        local name = api.GetMasterLootCandidate( slot, i )
        if name == player_name then return i end
      end
    end
```

**Step 3: Verify `AutoLoot.lua` is already correct**

`AutoLoot.lua` already separates correctly:
```lua
if m.vanilla then
    local name = m.api.GetMasterLootCandidate( i )
else
    local name = m.api.GetMasterLootCandidate( slot, i )
end
```
No change needed.

**Step 4: Commit**

```bash
git add RollFor-WotLK/src/MasterLootCandidates.lua
git commit -m "fix(wotlk): use 2-arg GetMasterLootCandidate(slot, i) on WotLK 3.3.5a"
```

---

### Task 9: Fix `PlayerInfo.lua` — `is_master_looter()` for WotLK 3-Return `GetLootMethod`

**Severity:** 🔴 Critical — raid master looters are never detected on WotLK.

**Files:**
- Modify: `RollFor-WotLK/src/PlayerInfo.lua`

**Problem:** Vanilla `GetLootMethod()` returns `(method, id)` where `id` is the party/raid member index. WotLK 3.3.5a returns `(method, partyMaster, raidMaster)`:
- Party: `partyMaster` = 0-4 (0 = you), `raidMaster` = nil
- Raid: `partyMaster` = nil, `raidMaster` = 1-40

The current code only captures 2 returns. In a raid, `id` (=`partyMaster`) is `nil`, so `not id` → `true` and the function immediately returns `false`.

**Step 1: Rewrite `is_master_looter()` with expansion-aware branching**

Replace the entire `is_master_looter()` function:

```lua
  local function is_master_looter()
    if not api.IsInGroup() then return false end

    if m.vanilla then
      -- Vanilla: GetLootMethod returns (method, id)
      -- Party: id = 0-4 (0 = you)
      -- Raid: id = 1-40 (raid member index)
      local loot_method, id = api.GetLootMethod()
      if loot_method ~= "master" or not id then return false end
      if id == 0 then return true end

      if api.IsInRaid() then
        local name = api.GetRaidRosterInfo( id )
        return name == get_name()
      end

      return api.UnitName( "party" .. id ) == get_name()
    else
      -- WotLK 3.3.5a, BCC, Retail: GetLootMethod returns (method, partyMaster, raidMaster)
      -- Party: partyMaster = 0-4, raidMaster = nil
      -- Raid: partyMaster = nil, raidMaster = 1-40
      local loot_method, party_id, raid_id = api.GetLootMethod()
      if loot_method ~= "master" then return false end

      if party_id == 0 then return true end

      if raid_id then
        local name = api.GetRaidRosterInfo( raid_id )
        return name == get_name()
      end

      if party_id then
        return api.UnitName( "party" .. party_id ) == get_name()
      end

      return false
    end
  end
```

**Step 2: Verify**

Run:
```bash
grep -n "GetLootMethod" RollFor-WotLK/src/PlayerInfo.lua
```
Confirm both branches (vanilla 2-return, wotlk 3-return) are present.

**Step 3: Commit**

```bash
git add RollFor-WotLK/src/PlayerInfo.lua
git commit -m "fix(wotlk): handle 3-return GetLootMethod on WotLK 3.3.5a for raid ML detection"
```

---

### Task 10: Fix `PlayerInfo.lua` `is_leader()` + `backport.lua` Misleading Comment

**Severity:** 🔴 Critical — raid leaders report `false` in `is_leader()` on WotLK, breaking `AutoGroupLoot` boss-kill auto-switch.

**Files:**
- Modify: `RollFor-WotLK/src/PlayerInfo.lua`
- Modify: `RollFor-WotLK/src/wotlk/backport.lua`

**Problem:**
1. `wotlk/backport.lua` falsely claims "`UnitIsGroupLeader` exists in WotLK with the same signature." It does **not** exist in true 3.3.5a.
2. `PlayerInfo.lua` falls back to `UnitIsPartyLeader("player")`, which only works in party context — not raid.

**Step 1: Rewrite `is_leader()` with raid-aware fallback**

Replace (~line 41-44):
```lua
  local function is_leader()
    -- UnitIsGroupLeader was added in Cataclysm. In WotLK 3.3.5a use UnitIsPartyLeader.
    local fn = api.UnitIsGroupLeader or api.UnitIsPartyLeader
    return fn and fn( "player" ) or false
  end
```

With:
```lua
  local function is_leader()
    -- UnitIsGroupLeader was added in Cataclysm. In WotLK 3.3.5a, UnitIsPartyLeader
    -- only works in party context. For raids, check raid roster rank.
    if api.UnitIsGroupLeader then
      return api.UnitIsGroupLeader( "player" )
    end

    if api.IsInRaid() then
      local my_name = get_name()
      for i = 1, 40 do
        local name, rank = api.GetRaidRosterInfo( i )
        if name and name == my_name then
          return rank == 2
        end
      end
      return false
    end

    return api.UnitIsPartyLeader and api.UnitIsPartyLeader( "player" ) or false
  end
```

**Step 2: Fix `wotlk/backport.lua` misleading comment**

Replace (~line 17-19):
```lua
-- UnitIsGroupLeader was renamed to UnitIsGroupLeader in WotLK with the same signature.
-- UnitIsPartyLeader still exists as an alias, but the canonical name works directly.
-- No shim needed.
```

With:
```lua
-- WotLK 3.3.5a has UnitIsPartyLeader but NOT UnitIsGroupLeader.
-- UnitIsGroupLeader was added in a later expansion (Cataclysm+).
-- No shim needed — PlayerInfo.lua handles the fallback manually.
```

**Step 3: Verify**

Run:
```bash
grep -n "UnitIsGroupLeader\|UnitIsPartyLeader" RollFor-WotLK/src/PlayerInfo.lua RollFor-WotLK/src/wotlk/backport.lua
```

**Step 4: Commit**

```bash
git add RollFor-WotLK/src/PlayerInfo.lua RollFor-WotLK/src/wotlk/backport.lua
git commit -m "fix(wotlk): add raid-aware is_leader fallback; correct backport comment"
```

---

### Task 11: Fix `AutoGroupLoot.lua` — Remove Dead Code

**Severity:** 🟡 Low — unreachable guard, harmless but confusing.

**Files:**
- Modify: `RollFor-WotLK/src/AutoGroupLoot.lua`

**Problem:** After `m_item_count = m_item_count - 1`, the guard `if m_item_count > 0 then return end` already handles the case. The following line `if not m_item_count or m_item_count > 0 then return end` is unreachable dead code.

**Step 1: Remove the unreachable guard**

Replace (~line 30-35):
```lua
    m_item_count = m_item_count - 1
    if m_item_count > 0 then return end
    if not m_item_count or m_item_count > 0 then return end
```

With:
```lua
    m_item_count = m_item_count - 1
    if m_item_count > 0 then return end
```

**Step 2: Commit**

```bash
git add RollFor-WotLK/src/AutoGroupLoot.lua
git commit -m "refactor: remove unreachable guard in on_loot_slot_cleared"
```

---

### Task 12: Fix `BindingsHandler.lua` — `math.huge` Global Mutation

**Severity:** 🟡 Medium — mutates a stdlib constant during SR import; side-effect pollution.

**Files:**
- Modify: `RollFor-WotLK/src/BindingsHandler.lua`

**Problem:** `math.huge = 1e99` mutates a standard library field during JSON encoding. If the JSON library needs this workaround, the mutation should be scoped.

**Step 1: Wrap mutation in save/restore**

Replace (~line 30-32):
```lua
  local function import( data )
    math.huge = 1e99
    ---@diagnostic disable-next-line: undefined-global
    local json = LibStub( "Json-0.1.2" )
```

With:
```lua
  local function import( data )
    -- Some old JSON libraries cannot handle math.huge; temporarily substitute.
    local old_huge = math.huge
    math.huge = 1e99
    ---@diagnostic disable-next-line: undefined-global
    local json = LibStub( "Json-0.1.2" )
```

And add restore after the pcall (~line 38):

**Before:**
```lua
    local success, json_data = pcall( function() return json.encode( data ) end )

    if success then
```

**After:**
```lua
    local success, json_data = pcall( function() return json.encode( data ) end )
    math.huge = old_huge

    if success then
```

**Step 2: Commit**

```bash
git add RollFor-WotLK/src/BindingsHandler.lua
git commit -m "fix: scope math.huge mutation to prevent side-effect pollution"
```

---

### Task 13: Remove Dead `OPEN_MASTER_LOOT_LIST` Event Registration

**Severity:** 🟢 Cosmetic — registered but never handled.

**Files:**
- Modify: `RollFor-WotLK/src/EventHandler.lua`

**Problem:** The event is registered via `pcall` but there is no handler branch in `event_handler()`. When it fires, it falls through the if-elseif chain silently.

**Step 1: Remove the dead registration**

Delete these lines (~line 101-103):
```lua
  -- OPEN_MASTER_LOOT_LIST fires when master looter right-clicks a loot slot.
  -- Wrap in pcall as some 3.3.5a private server builds may not expose this event.
  pcall( function() frame:RegisterEvent( "OPEN_MASTER_LOOT_LIST" ) end )
```

**Step 2: Commit**

```bash
git add RollFor-WotLK/src/EventHandler.lua
git commit -m "refactor: remove dead OPEN_MASTER_LOOT_LIST event registration"
```

---

### Task 14: (Optional) Extract Hardcoded Addon Path to Constant

**Severity:** 🟡 Medium — if user renames addon folder, all 13 texture references silently fail.

**Files:**
- Modify: ~6 files with hardcoded `Interface\AddOns\RollFor-WotLK\assets\...`

**Problem:** 13 texture paths across `OgLootFrameSkin.lua`, `MinimapButton.lua`, `OptionsGuiElements.lua`, `MasterLootCandidateSelectionFrame.lua`, `WinnersPopupGui.lua`, and `GuiElements.lua` hardcode the folder name `RollFor-WotLK`. If a user renames the folder, every icon/texture fails to load with no error message.

**Step 1: Define a central constant**

In a suitable early-loaded file (e.g., `RollFor-WotLK/src/modules.lua` or `main.lua`), add:

```lua
-- Addon folder name must match the TOC filename for texture paths to resolve.
RollFor.ADDON_NAME = "RollFor-WotLK"
```

**Step 2: Replace all 13 hardcoded paths**

Search for all occurrences:
```bash
grep -rn "Interface\\AddOns\\RollFor-WotLK" RollFor-WotLK/src/
```

Replace each with:
```lua
string.format( "Interface\\AddOns\\%s\\assets\\...", RollFor.ADDON_NAME )
```

Or simpler, define a path helper:
```lua
local function addon_asset( filename )
  return string.format( "Interface\\AddOns\\%s\\assets\\%s", RollFor.ADDON_NAME, filename )
end
```

**Step 3: Commit**

```bash
git add ...
git commit -m "refactor: centralize addon texture paths to support folder renaming"
```

> **Note:** This task is optional and lower priority than the API fixes above. The official release workflow packages the addon as `RollFor-WotLK`, so the paths are correct for standard installs. Only users who manually rename the folder are affected.

---

### Task 7d: (Optional) Verify RAID_ROSTER_UPDATE / PARTY_MEMBERS_CHANGED Double-Fire

**Severity:** 🟢 Cosmetic — redundant handler calls, no correctness impact.

**File:** `RollFor-WotLK/src/EventHandler.lua`

On WotLK, both `RAID_ROSTER_UPDATE` and `PARTY_MEMBERS_CHANGED` are registered and route to the same handlers (`main.on_group_changed()`, etc.). This causes redundant calls on every roster tick.

If desired, deduplicate by tracking the last event timestamp or only registering `RAID_ROSTER_UPDATE` in raid and `PARTY_MEMBERS_CHANGED` in party. However, this is a performance micro-optimization and is safe to skip.

---

## In-Game Testing Instructions

After all commits are applied:

### UI Tests (Tasks 1–6)

1. **Copy files to WoW 3.3.5a AddOns folder**:
   ```bash
   cp -r RollFor-WotLK /path/to/WoW/Interface/AddOns/
   ```

2. **Launch game and log in**

3. **Load addon**: Check that no Lua errors appear on login. If `OptionsPopup.lua` has syntax errors, the error will show immediately.

4. **Open options UI**: Type `/rfo` (or click the minimap button → Options).
   - Tabs should display: General, Looting, Rolling, Client
   - Click each tab — content should switch without errors

5. **Test scrolling**: In the "Rolling" or "Client" tab (which have many options), scroll with mouse wheel — scrollbar should move smoothly.

6. **Test hover effects**: Hover over any config entry — background should highlight in blue.

7. **Test checkboxes**: Click any checkbox — value should toggle.

8. **Test text inputs**: Click in a number field (e.g., "Default rolling time"), type a value, press Escape — value should save.

9. **Test dropdowns**: Click a dropdown (e.g., "Show roll popup" in Client tab) — dropdown should open and allow selection.

10. **Test Winners popup**: Type `/rfw`, right-click on a roll type column — dropdown should appear.

11. **Test +1/tmog sibling toggles**: In the "Rolling" tab, check "Handle +1's on MS rolls" and verify "Always prompt for +1's" enables/disables. Check "Enable transmog rolling" and verify "Transmog roll threshold" enables/disables. (Validates Task 5 Step 10 sibling frame hierarchy.)

### Master Loot Tests (Tasks 8–10)

12. **Be in a raid with master loot enabled** (you as ML). Target a boss, kill it, loot. Verify:
    - Master loot candidate list populates correctly (no empty list)
    - Auto-group-loot switch fires after boss kill (`AutoGroupLoot`)

13. **Be in a party with master loot enabled** (you as ML). Loot a mob. Verify:
    - Candidate list works in party too

14. **Have another player be ML in a raid**. Verify:
    - `is_master_looter()` returns `false` for you
    - Addon correctly defers to the actual ML

### API Verification Tests (Tasks 7, 7b, 7c)

15. **`GetLootSlotInfo` return values** (Task 7): Loot any mob. Run in chat:
   ```
   /script for i=1,GetNumLootItems() do local a,b,c,d,e = GetLootSlotInfo(i); print(i,a,b,c,d,e) end
   ```
   Verify 5th value is `locked` (boolean/nil) and 4th is `quality` (number).

16. **`getn` / hash tables** (Task 7b): No in-game test needed. Verified via grep during implementation.

17. **Grep sweep** (Task 7c): Run the grep commands from Task 7c after all edits. Confirm only `if m.vanilla then self = this end` guards and `lua50`-handled `arg1` references remain.

### Regression Tests

18. **Import softres data** (`/sr import <paste>`). Verify no Lua errors.

19. **Roll for an item** (`/rf [ItemLink]`). Verify rolling popup appears and resolves correctly.

If any step produces a Lua error, the error message will indicate which `nil` reference failed. Grep that file for any missed `this` or `arg1`.

---

## Rollback Instructions

If critical errors occur in-game and you need to revert:

```bash
git log --oneline -15  # find the commit hash before the first fix
git revert <first-fix-commit-hash>..HEAD --no-commit
git reset HEAD RollFor-WotLK/src/OptionsGuiElements.lua RollFor-WotLK/src/OptionsPopup.lua RollFor-WotLK/src/PlayerInfo.lua RollFor-WotLK/src/MasterLootCandidates.lua
git checkout -- RollFor-WotLK/src/OptionsGuiElements.lua RollFor-WotLK/src/OptionsPopup.lua RollFor-WotLK/src/PlayerInfo.lua RollFor-WotLK/src/MasterLootCandidates.lua
```

Or restore from the pre-change backup (if you made one before starting).
