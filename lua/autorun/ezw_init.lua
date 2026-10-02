-- JMod EZ Workers :: shared init
-- Loaded on both realms. Defines the EZW table, ConVars, constants and ALL network strings.
-- (Network strings are centralised here on purpose - never scatter util.AddNetworkString around.)

AddCSLuaFile()

EZW = EZW or {}
EZW.Version = "1.0.0"

-- Type strings are plain strings in JMod (JMod.EZ_RESOURCE_TYPES.X is just sugar for them)
EZW.GoldType = "gold"
EZW.NutrientType = "nutrients"
EZW.PickaxeClass = "wep_jack_gmod_ezpickaxe"

EZW.Jobs = {
	idle = {name = "Idle", desc = "Stands still and barely uses any energy."},
	follow = {name = "Follow", desc = "Follows you around."},
	miner = {name = "Miner", desc = "Walks to ore deposits and digs with a pickaxe."},
	crafter = {name = "Crafter", desc = "Crafts the assigned recipe at a nearby workbench."},
	hauler = {name = "Hauler", desc = "Collects loose resources and loads them into crates."}
}

EZW.JobOrder = {"idle", "follow", "miner", "crafter", "hauler"}

-- what a pickaxe can actually dig (water/oil/sand/geothermal are machine-only)
EZW.MineTypes = {
	"any", "coal", "iron ore", "lead ore", "aluminum ore", "copper ore", "tungsten ore",
	"titanium ore", "silver ore", "gold ore", "uranium ore", "platinum ore", "diamond"
}

-- Shared helper: horizontal distance between two vectors
function EZW.Flat(a, b)
	local dx, dy = a.x - b.x, a.y - b.y

	return math.sqrt(dx * dx + dy * dy)
end

local F = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED)

EZW.CV = {
	cost = CreateConVar("ezw_hire_cost", "50", F, "Gold needed to hire one worker.", 0),
	max = CreateConVar("ezw_max_per_player", "4", F, "Max workers one player can have at the same time.", 0),
	payrange = CreateConVar("ezw_pay_range", "250", F, "Gold must be within this range of you (floor, crates, your JMod inventory).", 50),
	drain = CreateConVar("ezw_energy_drain", "0.6", F, "Energy lost per second while working (max energy is 100).", 0),
	nutrient = CreateConVar("ezw_nutrient_energy", "3", F, "Energy restored by 1 unit of nutrients.", 0.1),
	carry = CreateConVar("ezw_carry_capacity", "100", F, "Base units of resources a worker can carry (grows with level).", 10),
	craftdelay = CreateConVar("ezw_craft_delay", "2.5", F, "Seconds between two auto-crafts (shrinks with level).", 1),
	scatter = CreateConVar("ezw_scatter_crafts", "1", F, "Scatter freshly crafted items so they do not clip into each other.", 0, 1),
	scatterforce = CreateConVar("ezw_scatter_force", "140", F, "How hard crafted items are pushed away from the bench.", 0),
	teleport = CreateConVar("ezw_teleport_when_stuck", "1", F, "Teleport a worker towards its goal if it stays stuck for too long.", 0, 1)
}

if SERVER then
	util.AddNetworkString("EZW_OpenMenu") -- S -> C  open the menu (chat command)
	util.AddNetworkString("EZW_Request") -- C -> S  ask for a state sync
	util.AddNetworkString("EZW_Sync") -- S -> C  workers / recipes / config
	util.AddNetworkString("EZW_Hire") -- C -> S  hire a worker
	util.AddNetworkString("EZW_Cmd") -- C -> S  command a worker
end
