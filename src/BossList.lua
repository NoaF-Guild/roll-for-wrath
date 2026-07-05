RollFor = RollFor or {}
local m = RollFor

if m.BossList then return end

---@class BossList
---@field zones table<string, string[]>

local M    = {}

M.zones    = {
  [ "Durotar" ] = {
    "Elder Mottled Boar"
  },
  [ "Emerald Sanctum" ] = {
    "Erennius",
    "Solnius"
  },
  [ "Tower of Karazhan" ] = {
    "Keeper Gnarlmoon",
    "Ley-Watcher Incantagos",
    "Anomalus",
    "Echo of Medivh",
    "King",
    "Queen",
    "Bishop",
    "Rook",
    "Ima'ghaol, Herald of Desolation",
    "Sanv Tas'dal",
    "Rupturan the Broken",
    "Kruul",
    "Mephistroth"
  },
  [ "Lower Karazhan Halls" ] = {
    "Master Blacksmith Rolfen",
    "Brood Queen Araxxna",
    "Grizikil",
    "Clawlord Howlfang",
    "Lord Blackwald II",
    "Moroes"
  },
  [ "Timbermaw Hold" ] = {
    "Karrsh the Sentinel",
    "Rotgrowl",
    "Archdruid Kronn",
    "Loktanag the Vile",
    "Ormanos the Cracked",
    "Trioch the Devourer",
    "Selenaxx Foulheart",
    "Chieftain Partath",
    "Ursol",
    "Peroth'arn"
  },
  [ "Zul'Gurub" ] = {
    "High Priestess Jeklik",
    "High Priest Venoxis",
    "Witherbark Speaker",
    "High Priestess Mar'li",
    "Vilebranch Speaker",
    "Broodlord Mandokir",
    "Ohgan",
    "Gri'lek",
    "Hazza'rah",
    "Renataki",
    "Wushoolay",
    "Gahz'ranka",
    "High Priest Thekal",
    "Zealot Zath",
    "Zealot Lor'Khan",
    "High Priestess Arlokk",
    "Jin'do the Hexxer",
    "Hakkar"
  },
  [ "Ruins of Ahn'Qiraj" ] = {
    "Kurinnaxx",
    "General Rajaxx",
    "Moam",
    "Buru the Gorger",
    "Ayamiss the Hunter",
    "Ossirian the Unscarred"
  },
  [ "Molten Core" ] = {
    "Incindis",
    "Basalthar",
    "Smoldaris",
    "Sorcerer-Thane Thaurissan",
    "Lucifron",
    "Magmadar",
    "Gehennas",
    "Garr",
    "Shazzrah",
    "Baron Geddon",
    "Golemagg the Incinerator",
    "Sulfuron Harbinger",
    "Majordomo Executus",
    "Ragnaros"
  },
  [ "Blackwing Lair" ] = {
    "Ezzel Darkbrewer",
    "Razorgore the Untamed",
    "Vaelastrasz the Corrupt",
    "Broodlord Lashlayer",
    "Firemaw",
    "Ebonroc",
    "Flamegor",
    "Chromaggus",
    "Nefarian"
  },
  [ "Onyxia's Lair" ] = {
	"Onyxia",
	"Broodcommander Axelus",
	"Atressian",
	"Ortorg the Ardent"
  },
  [ "Ahn'Qiraj" ] = {
    "The Prophet Skeram",
    "Vem",
    "Lord Kri",
    "Princess Yauj",
    "Battleguard Sartura",
    "Fankriss the Unyielding",
    "Viscidus",
    "Princess Huhuran",
    "Emperor Vek'lor",
    "Emperor Vek'nilash",
    "Ouro",
    "C'Thun"
  },
  [ "Naxxramas" ] = {
    "Patchwerk",
    "Grobbulus",
    "Gluth",
    "Thaddius",
    "Anub'Rekhan",
    "Grand Widow Faerlina",
    "Maexxna",
    "Noth the Plaguebringer",
    "Heigan the Unclean",
    "Loatheb",
    "Instructor Razuvious",
    "Gothik the Harvester",
    "Thane Korth'azz",
    "Lady Blaumeux",
    "Highlord Mograine",
    "Sir Zeliek",
    "Sapphiron",
    "Kel'Thuzad"
  },
  [ "The Obsidian Sanctum" ] = {
    "Sartharion",
    "Shadron",
    "Tenebron",
    "Vesperon"
  },
  [ "Vault of Archavon" ] = {
    "Archavon the Stone Watcher",
    "Emalon the Storm Watcher",
    "Koralon the Flame Watcher",
    "Toravon the Ice Watcher"
  },
  [ "The Eye of Eternity" ] = {
    "Malygos"
  },
  [ "Ulduar" ] = {
    "Flame Leviathan",
    "Ignis the Furnace Master",
    "Razorscale",
    "XT-002 Deconstructor",
    "Steelbreaker",
    "Runemaster Molgeim",
    "Stormcaller Brundir",
    "Kologarn",
    "Auriaya",
    "Hodir",
    "Thorim",
    "Freya",
    "Mimiron",
    "General Vezax",
    "Yogg-Saron",
    "Algalon the Observer"
  },
  [ "Trial of the Crusader" ] = {
    "Gormok the Impaler",
    "Acidmaw",
    "Dreadscale",
    "Icehowl",
    "Lord Jaraxxus",
    "Eydis Darkbane",
    "Fjola Lightbane",
    "Anub'arak"
  },
  [ "Icecrown Citadel" ] = {
    "Lord Marrowgar",
    "Lady Deathwhisper",
    "Deathbringer Saurfang",
    "Festergut",
    "Rotface",
    "Professor Putricide",
    "Prince Valanar",
    "Prince Keleseth",
    "Prince Taldaram",
    "Blood-Queen Lana'thel",
    "Valithria Dreamwalker",
    "Sindragosa",
    "The Lich King"
  },
  [ "The Ruby Sanctum" ] = {
    "Saviana Ragefire",
    "Baltharus the Warborn",
    "General Zarithrian",
    "Halion"
  }
}

---@type BossList
m.BossList = M
return M
