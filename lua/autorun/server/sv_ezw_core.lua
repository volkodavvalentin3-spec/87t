-- JMod EZ Workers :: core (server)
-- Registry, hiring (gold), bot setup, energy / nutrients, XP, and the engine hooks.

EZW = EZW or {}
EZW.Workers = EZW.Workers or {} -- [botEntity] = true

local CV = EZW.CV

local FirstNames = {
	"Bolt", "Rusty", "Gizmo", "Sprocket", "Wrench", "Cobalt", "Ratchet", "Flint", "Anvil", "Piston",
	"Rivet", "Cinder", "Gasket", "Tungsten", "Ember", "Chisel", "Socket", "Torque", "Grit", "Welder"
}

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
function EZW.Notify(ply, msg)
	if IsValid(ply) and ply:IsPlayer() and not ply:IsBot() then
		ply:PrintMessage(HUD_PRINTTALK, "[EZ Workers] " .. msg)
	end
end

function EZW.IsWorker(ent)
	return IsValid(ent) and ent:IsPlayer() and (ent.EZW ~= nil)
end

function EZW.GetWorkers(owner)
	local List = {}

	for Bot in pairs(EZW.Workers) do
		if IsValid(Bot) and Bot.EZW and (Bot.EZW.owner == owner) then
			List[#List + 1] = Bot
		end
	end

	return List
end

function EZW.SetStatus(W, text)
	W.status = text
end

-- May a worker belonging to `owner` touch / take this entity?
function EZW.CanTouch(ent, owner)
	if not (IsValid(ent) and IsValid(owner)) then return false end
	local O = ent.EZowner
	if not (IsValid(O) and O:IsPlayer()) then return true end
	if O == owner then return true end
	if owner.JModFriends and table.HasValue(owner.JModFriends, O) then return true end
	if (engine.ActiveGamemode() ~= "sandbox") and (O:Team() == owner:Team()) then return true end

	return false
end

function EZW.SpawnPosNear(owner)
	local Base = owner:GetPos()

	for i = 1, 14 do
		local A = math.rad(math.random(0, 359))
		local P = Base + Vector(math.cos(A), math.sin(A), 0) * math.random(60, 120)

		local Tr = util.TraceHull({
			start = P + Vector(0, 0, 10),
			endpos = P + Vector(0, 0, 10),
			mins = Vector(-16, -16, 0),
			maxs = Vector(16, 16, 72),
			mask = MASK_PLAYERSOLID
		})

		if not (Tr.StartSolid or Tr.Hit) then return P end
	end

	return Base + Vector(0, 0, 10)
end

-- Friends in JMod: sentries/turrets will not shoot them, owner-gated machines accept them.
function EZW.EnsureFriend(owner, bot)
	if not (IsValid(owner) and IsValid(bot) and JMod and JMod.AddFriend) then return end
	owner.JModFriends = owner.JModFriends or {}

	if not table.HasValue(owner.JModFriends, bot) then
		JMod.AddFriend(owner, bot)
	end
end

----------------------------------------------------------------------
-- XP / levels
----------------------------------------------------------------------
function EZW.AddXP(bot, W, amt)
	W.xp = W.xp + amt
	local Lvl = math.Clamp(math.floor(math.sqrt(W.xp / 20)) + 1, 1, 10)

	if Lvl > W.level then
		W.level = Lvl
		EZW.Notify(W.owner, W.name .. " reached level " .. Lvl .. "! (works faster, burns less energy, carries more)")
		bot:EmitSound("buttons/button9.wav", 60, 120)
	end
end

function EZW.NextXP(level)
	return level * level * 20
end

----------------------------------------------------------------------
-- Energy / nutrients
----------------------------------------------------------------------
function EZW.TryEat(bot, W, now)
	local Typ = EZW.NutrientType
	local Pos = bot:GetPos() + Vector(0, 0, 30)
	local Range = 170
	local Have = JMod.CountResourcesInRange(Pos, Range)[Typ] or 0

	if Have < 1 then
		if (W.energy < 25) and (now > (W.nextWarn or 0)) then
			W.nextWarn = now + 45
			EZW.Notify(W.owner, W.name .. " is running out of energy - drop NUTRIENTS next to them!")
		end

		return
	end

	local Conv = CV.nutrient:GetFloat()
	local Need = math.ceil((100 - W.energy) / Conv)
	local Amt = math.floor(math.min(Have, Need, 40))
	if Amt < 1 then return end
	JMod.ConsumeResourcesInRange({[Typ] = Amt}, Pos, Range, nil, true)
	W.energy = math.min(100, W.energy + Amt * Conv)
	bot:EmitSound("npc/barnacle/barnacle_gulp1.wav", 60, math.random(95, 110))
end

function EZW.UpdateEnergy(bot, W, dt, now)
	local Activity = 1
	if W.job == "idle" then Activity = 0.15 end
	if W.job == "follow" then Activity = 0.3 end
	local Drain = CV.drain:GetFloat() * Activity * (1 - math.min(0.5, (W.level - 1) * 0.05))
	W.energy = math.max(0, W.energy - Drain * dt)

	if (W.energy < 40) and (now >= (W.nextEat or 0)) then
		W.nextEat = now + 2
		EZW.TryEat(bot, W, now)
	end

	-- fed workers slowly patch themselves up
	if now >= (W.nextHeal or 0) then
		W.nextHeal = now + 3

		if (W.energy > 0) and (bot:Health() < bot:GetMaxHealth()) then
			bot:SetHealth(math.min(bot:GetMaxHealth(), bot:Health() + 2))
		end
	end
end

----------------------------------------------------------------------
-- NW sync (for the overhead HUD)
----------------------------------------------------------------------
function EZW.SyncNW(bot, W)
	bot:SetNW2Bool("EZW_Is", true)
	bot:SetNW2Entity("EZW_Owner", W.owner)
	bot:SetNW2String("EZW_Name", W.name)
	bot:SetNW2String("EZW_Job", W.job)
	bot:SetNW2String("EZW_Status", W.status or "")
	bot:SetNW2Int("EZW_Energy", math.floor(W.energy))
	bot:SetNW2Int("EZW_Level", W.level)
	bot:SetNW2Int("EZW_Carry", W.carryAmt or 0)
end

----------------------------------------------------------------------
-- Bot setup (loadout, model, colour)
----------------------------------------------------------------------
function EZW.PickModel(wanted)
	local All = player_manager.AllValidModels()
	local Valid, List = {}, {}

	for _, Path in pairs(All) do
		Valid[string.lower(Path)] = Path
		List[#List + 1] = Path
	end

	if wanted and (wanted ~= "") and Valid[string.lower(wanted)] then return Valid[string.lower(wanted)] end
	if #List == 0 then return "models/player/kleiner.mdl" end

	return table.Random(List)
end

function EZW.SetupBot(bot)
	local W = bot.EZW
	if not (W and IsValid(bot) and bot:Alive()) then return end
	bot:StripWeapons()

	if weapons.Get(EZW.PickaxeClass) then
		bot:Give(EZW.PickaxeClass)
		bot:SelectWeapon(EZW.PickaxeClass)
	end

	bot:SetModel(W.model)
	bot.EZoriginalPlayerModel = W.model -- JMod restores this on death, keep our skin
	bot:SetPlayerColor(W.color)
	W.view = Angle(0, bot:EyeAngles().y, 0)
	W.path, W.goal = nil, nil
	EZW.EnsureFriend(W.owner, bot)
end

function EZW.SetJob(bot, W, job)
	if not EZW.Jobs[job] then return end

	-- drop anything we were carrying so it is not silently lost
	if (W.carryAmt or 0) > 0 and W.carryType then
		EZW.DropResource(W, W.carryType, W.carryAmt, bot:GetPos() + bot:GetForward() * 40, 0, 20)
	end

	W.job = job
	W.carryAmt, W.carryType = 0, nil
	W.depKey, W.bench, W.goal, W.path = nil, nil, nil, nil
	W.home = bot:GetPos()
	W.status = EZW.Jobs[job].name
end

----------------------------------------------------------------------
-- Hire / dismiss
----------------------------------------------------------------------
function EZW.Hire(ply, mdl, name, free)
	if not (IsValid(ply) and ply:IsPlayer() and ply:Alive()) then return end

	if not (JMod and JMod.EZ_RESOURCE_TYPES) then
		EZW.Notify(ply, "JMod is not installed or not loaded!")

		return
	end

	if #EZW.GetWorkers(ply) >= CV.max:GetInt() then
		EZW.Notify(ply, "Worker limit reached (" .. CV.max:GetInt() .. ").")

		return
	end

	if player.GetCount() >= game.MaxPlayers() then
		EZW.Notify(ply, "No free player slot for a bot. Workers are real player bots - start a multiplayer game with more slots.")

		return
	end

	local Cost = free and 0 or CV.cost:GetInt()
	local Range = CV.payrange:GetInt()
	local Reqs = {[EZW.GoldType] = Cost}
	local Pos = ply:GetPos()

	if Cost > 0 and not JMod.HaveResourcesToPerformTask(Pos, Range, Reqs) then
		local Have = JMod.CountResourcesInRange(Pos, Range)[EZW.GoldType] or 0
		EZW.Notify(ply, "Not enough gold nearby: " .. math.floor(Have) .. "/" .. Cost .. ". Drop gold (or a gold crate) within " .. Range .. " units, or carry it in your JMod inventory.")

		return
	end

	name = string.Trim(string.sub(tostring(name or ""), 1, 24))
	if name == "" then name = table.Random(FirstNames) end
	local Bot = player.CreateNextBot("[Worker] " .. name)

	if not IsValid(Bot) then
		EZW.Notify(ply, "The server refused to create a bot.")

		return
	end

	if Cost > 0 then
		JMod.ConsumeResourcesInRange(Reqs, Pos, Range, nil, true)
	end

	Bot.EZW = {
		owner = ply,
		name = name,
		model = EZW.PickModel(mdl),
		color = Vector(math.Rand(0, 1), math.Rand(0, 1), math.Rand(0, 1)),
		job = "idle",
		status = "Just hired",
		energy = 100,
		xp = 0,
		level = 1,
		mineType = "any",
		amount = 0,
		made = 0,
		mined = 0,
		carryAmt = 0,
		badDeposits = {},
		badEnts = {},
		dropIdx = 0
	}

	EZW.Workers[Bot] = true

	timer.Simple(0.3, function()
		if IsValid(Bot) and Bot.EZW and IsValid(ply) then
			Bot:SetPos(EZW.SpawnPosNear(ply))
			EZW.SetupBot(Bot)
			EZW.SetJob(Bot, Bot.EZW, "idle")
		end
	end)

	EZW.Notify(ply, name .. " has been hired" .. (Cost > 0 and (" for " .. Cost .. " gold") or "") .. ". Keep nutrients near them!")

	return Bot
end

function EZW.Dismiss(bot, reason)
	EZW.Workers[bot] = nil

	if IsValid(bot) then
		if bot.EZW and (bot.EZW.carryAmt or 0) > 0 and bot.EZW.carryType then
			EZW.DropResource(bot.EZW, bot.EZW.carryType, bot.EZW.carryAmt, bot:GetPos() + Vector(0, 0, 20), 0, 20)
		end

		bot.EZW = nil
		bot:Kick(reason or "Dismissed")
	end
end

----------------------------------------------------------------------
-- The per-worker brain tick
----------------------------------------------------------------------
function EZW.ThinkWorker(bot, W, dt)
	local Now = CurTime()
	EZW.UpdateEnergy(bot, W, dt, Now)
	W.attack, W.duck, W.lookAt = false, false, nil

	if W.energy <= 0 then
		W.goal = nil
		EZW.SetStatus(W, "Exhausted - place nutrients next to me")
	else
		local Func = EZW.JobFuncs and EZW.JobFuncs[W.job]
		if Func then Func(bot, W, Now) end
	end

	EZW.SyncNW(bot, W)
end

timer.Create("EZW_Think", 0.2, 0, function()
	local Now = CurTime()

	for Bot in pairs(EZW.Workers) do
		if not IsValid(Bot) then
			EZW.Workers[Bot] = nil
		else
			local W = Bot.EZW

			if not W then
				EZW.Workers[Bot] = nil
			elseif not IsValid(W.owner) then
				EZW.Dismiss(Bot, "Owner left")
			elseif Bot:Alive() then
				W.deadSince = nil
				local Ok, Err = pcall(EZW.ThinkWorker, Bot, W, 0.2)

				if not Ok then
					ErrorNoHalt("[EZ Workers] " .. tostring(Err) .. "\n")
				end

				-- forget stale "bad entity" marks now and then
				if Now > (W.nextPrune or 0) then
					W.nextPrune = Now + 30

					for E, T in pairs(W.badEnts) do
						if (not IsValid(E)) or (T < Now) then
							W.badEnts[E] = nil
						end
					end
				end
			else
				W.deadSince = W.deadSince or Now

				-- bots normally respawn on their own, this is just a safety net
				if (Now - W.deadSince) > 8 then
					Bot:Spawn()
					W.deadSince = nil
				end
			end
		end
	end
end)

----------------------------------------------------------------------
-- Engine hooks
----------------------------------------------------------------------
hook.Add("StartCommand", "EZW_Control", function(ply, cmd)
	if not (ply:IsBot() and ply.EZW) then return end
	if not ply:Alive() then return end
	EZW.Steer(ply, ply.EZW, cmd)
end)

hook.Add("PlayerSpawn", "EZW_Respawn", function(ply)
	if not (ply:IsBot() and ply.EZW) then return end

	timer.Simple(0.25, function()
		if IsValid(ply) and ply.EZW and IsValid(ply.EZW.owner) then
			ply:SetPos(EZW.SpawnPosNear(ply.EZW.owner))
			EZW.SetupBot(ply)
		end
	end)
end)

-- Workers never get the default sandbox loadout
hook.Add("PlayerLoadout", "EZW_Loadout", function(ply)
	if ply:IsBot() and ply.EZW then return true end
end)

hook.Add("PlayerDisconnected", "EZW_Disconnect", function(ply)
	EZW.Workers[ply] = nil

	for Bot in pairs(EZW.Workers) do
		if IsValid(Bot) and Bot.EZW and (Bot.EZW.owner == ply) then
			EZW.Dismiss(Bot, "Owner left")
		end
	end
end)

-- The owner's own JMod friend list can be rewritten from the JMod menu: keep workers on it.
timer.Create("EZW_Friends", 10, 0, function()
	for Bot in pairs(EZW.Workers) do
		if IsValid(Bot) and Bot.EZW then
			EZW.EnsureFriend(Bot.EZW.owner, Bot)
		end
	end
end)

-- Admin test helper: free worker (superadmin / console only)
concommand.Add("ezw_hire_free", function(ply, cmd, args)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	if not IsValid(ply) then return end
	EZW.Hire(ply, args[1], args[2], true)
end, nil, "Superadmin: hire a worker without paying gold.")

concommand.Add("ezw_dismiss_all", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end

	for Bot in pairs(EZW.Workers) do
		EZW.Dismiss(Bot, "Dismissed")
	end
end, nil, "Superadmin: dismiss every worker.")
