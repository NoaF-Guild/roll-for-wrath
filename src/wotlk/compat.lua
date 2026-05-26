RollFor = RollFor or {}
local M = RollFor

M.wotlk = true

-- WotLK Polyfill for modern GetLootSlotType
if not _G.GetLootSlotType then
    _G.LOOT_SLOT_ITEM = 1
    _G.LOOT_SLOT_MONEY = 2
    _G.LOOT_SLOT_CURRENCY = 3

    _G.GetLootSlotType = function(slot)
        if LootSlotIsCoin and LootSlotIsCoin(slot) then
            return _G.LOOT_SLOT_MONEY
        elseif LootSlotIsItem and LootSlotIsItem(slot) then
            return _G.LOOT_SLOT_ITEM
        end
        return 0 -- Unknown / Empty
    end
end

-------------------------------------------------
-- WotLK Polyfill for Modern PlaySound Numeric IDs
-------------------------------------------------
local original_PlaySound = _G.PlaySound
_G.PlaySound = function(sound, channel)
    -- If no sound was passed, do nothing to prevent a crash
    if not sound then return end
    
    -- If the addon passes a modern numeric Sound ID, translate it to WotLK strings
    if type(sound) == "number" then
        if sound == 850 then sound = "igMainMenuOpen"
        elseif sound == 851 then sound = "igMainMenuClose"
        elseif sound == 856 then sound = "igMainMenuOption"
        elseif sound == 798 then sound = "igMainMenuOptionCheckBoxOn"
        elseif sound == 799 then sound = "igMainMenuOptionCheckBoxOff"
        elseif sound == 839 then sound = "igSpellBookOpen"
        elseif sound == 840 then sound = "igSpellBookClose"
        elseif sound == 882 then sound = "igQuestListOpen"
        elseif sound == 883 then sound = "igQuestListClose"
        else
            return -- If it's an unknown number, just stay silent and don't crash
        end
    end
    
    -- Pass the valid string to the native 3.3.5 function
    return original_PlaySound(sound, channel)
end
-------------------------------------------------

-- SOUNDKIT table shim: In WotLK 3.3.5a, SOUNDKIT is not a global table.
-- FrameBuilder and RollingPopup reference m.api.SOUNDKIT.* on the non-vanilla path.
-- The PlaySound polyfill above already maps these numeric IDs to string names,
-- so we just need the table to exist so the lookup doesn't error first.
_G.SOUNDKIT = _G.SOUNDKIT or {
  IG_MAINMENU_OPEN        = 850,
  IG_MAINMENU_CLOSE       = 851,
  IG_MAINMENU_OPTION      = 856,
  IG_MAINMENU_OPTION_CHECKBOX_ON  = 798,
  IG_MAINMENU_OPTION_CHECKBOX_OFF = 799,
  SPELLBOOK_OPEN          = 839,
  SPELLBOOK_CLOSE         = 840,
  IG_QUEST_LIST_OPEN      = 882,
  IG_QUEST_LIST_CLOSE     = 883,
  -- Client sounds used by Client.lua
  RAID_WARNING            = 0,  -- "RaidWarning" is a string in 3.3.5, skip numeric
  PVP_THROUGH_QUEUE       = 0,  -- "PVPTHROUGHQUEUE" is a string in 3.3.5, skip numeric
}

-- WotLK uses Lua 5.1, so # operator works and math.mod is gone.
---@param t table
---@return number
M.getn = function( t ) return #t end

---@param a number
---@param b number
---@return number
M.mod = function( a, b ) return a % b end

-- WotLK uses ChatFrame1EditBox (same as BCC, different from Vanilla's ChatFrameEditBox).
---@param item_link string
function M.link_item_in_chat( item_link )
  if M.api.ChatEdit_InsertLink then
    M.api.ChatEdit_InsertLink( item_link )
  elseif M.api.ChatFrame1EditBox:IsVisible() then
    M.api.ChatFrame1EditBox:Insert( item_link )
  end
end

---@param slash_command RollSlashCommand
---@param item_link ItemLink
function M.slash_command_in_chat( slash_command, item_link )
  M.api.ChatFrame1EditBox:Show()
  M.api.ChatFrame1EditBox:SetText( string.format( "%s %s ", slash_command, item_link ) )
  M.api.ChatFrame1EditBox:SetFocus()
end

-- WotLK GetItemInfo returns 10 values (same layout as BCC): texture is index 10.
---@param api table
---@param item_id ItemId
---@return ItemTexture
function M.get_item_texture( api, item_id )
  local _, _, _, _, _, _, _, _, _, texture = api.GetItemInfo( item_id )
  return texture
end

---@param api table
---@param item_id ItemId
---@return ItemQuality
---@return ItemTexture
function M.get_item_quality_and_texture( api, item_id )
  local _, _, quality, _, _, _, _, _, _, texture = api.GetItemInfo( item_id )
  return quality, texture
end

-- WotLK does NOT need "BackdropTemplate" as a 4th arg to CreateFrame.
-- Backdrop is configured directly on frame objects via frame:SetBackdrop{}.
---@param api CreateFrameApi
---@param parent Frame
function M.create_loot_button( api, parent )
  return api.CreateFrame( "Button", nil, parent )
end

---@param api CreateFrameApi
---@param type string
---@param name string
---@param parent Frame
function M.create_backdrop_frame( api, type, name, parent )
  return api.CreateFrame( type, name, parent )
end

-- WotLK has UnitGUID natively (introduced in 2.4), same as BCC.
---@param api table
---@param unit_type string
---@return string
function M.UnitGUID( api, unit_type )
  return api.UnitGUID( unit_type )
end

-- WotLK uses the plain global SendAddonMessage (no C_ChatInfo namespace).
-- NOTE: RegisterAddonMessagePrefix( "RollFor" ) must be called at login
-- (see main.lua on_player_login) or CHAT_MSG_ADDON will not fire.
---@param api table
---@param prefix string
---@param message string
---@param channel string
function M.SendAddonMessage( api, prefix, message, channel )
  api.SendAddonMessage( prefix, message, channel )
end

-- WotLK has IsInGroup/IsInRaid/IsInParty natively — no backport needed.
---@param api table
---@param chat Chat
---@param f function
function M.in_group_check( api, chat, f )
  return function( ... )
    if not api.IsInGroup() then
      chat.info( "Not in a group." )
      return
    end

    f( ... )
  end
end
