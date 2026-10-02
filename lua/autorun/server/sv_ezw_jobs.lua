-- JMod EZ Workers :: jobs (server)
-- Miner / Crafter / Hauler / Follow / Idle, plus the helpers they share
-- (resource carrying, machine feeding, craft-scatter capture).

EZW = EZW or {}

local CV = EZW.CV
local Flat = EZW.Flat

----------------------------------------------------------------------
-- Shared helpers
----------------------------------------------------------------------
function EZW.EquipTool(bot, class)
	local Wep = bot:GetActiveWeapon()
	if IsValid(Wep) and (Wep:GetClass() == class) then return Wep end

	if not bot:HasWeapon(class) then
		if weapons.Get(class) then bot:Give(class) end
	end

	if bot:HasWeapon(class) then bot:SelectWeapon(class) end

	return nil
end

-- Loose JMod resource entities that a worker is allowed to take.
function EZW.FindLooseResource(bot, W, wanted, center, radius, avoidEnt, avoidRadius)
	local Best, BestD
	local BP, Now = bot:GetPos(), CurTime()

	for _, E in ipairs(ents.FindInSphere(center, radius)) do
		if IsValid(E) and E.IsJackyEZresource and E.EZsupplies and (not E.Loaded)
			and ((not wanted) or wanted[E.EZsupplies])
			and (E:GetResource() > 0)
			and (not E:IsPlayerHolding())
			and (not IsValid(E:GetParent()))
			and ((W.badEnts[E] or 0) < Now)
			and EZW.CanTouch(E, W.owner) then
			local Skip = IsValid(avoidEnt) and (E:GetPos():Distance(avoidEnt:GetPos()) < (avoidRadius or 150))

			if not Skip then
				local D = BP:DistToSqr(E:GetPos())

				if (not BestD) or (D < BestD) then
					Best, BestD = E, D
				end
			end
		end
	end

	return Best
end

local function CarryCap(W)
	return math.floor(CV.carry:GetInt() * (1 + (W.level - 1) * 0.15))
end

function EZW.PickUp(bot, W, res)
	local Typ = res.EZsupplies
	if (W.carryAmt > 0) and (W.carryType ~= Typ) then return false end
	local Room = CarryCap(W) - W.carryAmt
	if Room <= 0 then return false end
	local Have = res:GetResource()
	local Take = math.min(Have, Room)
	JMod.ResourceEffect(Typ, res:LocalToWorld(res:OBBCenter()), bot:GetShootPos(), 1, 1, 1)
	res:SetEZsupplies(Typ, Have - Take) -- removes the entity itself when it hits 0
	W.carryType = Typ
	W.carryAmt = W.carryAmt + Take

	return true
end

-- Spawn physical resource entities in a ring so they never overlap.
function EZW.DropResource(W, typ, amt, center, idx, high)
	local Class = JMod.EZ_RESOURCE_ENTITIES[typ]
	if not Class then return end
	local Chunk = math.max(1, math.floor(100 * JMod.Config.ResourceEconomy.MaxResourceMult))
	local N = 0

	while (amt > 0) and (N < 12) do
		local Give = math.min(Chunk, amt)
		local E = ents.Create(Class)
		if not IsValid(E) then break end
		local A = math.rad(((idx or 0) + N) * 137.5)
		E:SetPos(center + Vector(math.cos(A), math.sin(A), 0) * (35 + 8 * N) + Vector(0, 0, high or 30))
		E:SetAngles(Angle(0, math.random(0, 359), 0))
		E:Spawn()
		E:Activate()
		JMod.SetEZowner(E, W.owner)
		E:SetEZsupplies(typ, Give)
		amt = amt - Give
		N = N + 1
	end
end

function EZW.Deliver(bot, W, dest)
	local Typ, Amt = W.carryType, W.carryAmt
	if (not Typ) or (Amt <= 0) then return end
	local Accepted = 0
	local IsCrate = IsValid(dest) and dest.IsJackyEZcrate and dest.TryLoadResource

	if IsCrate then
		Accepted = dest:TryLoadResource(Typ, Amt) or 0

		if Accepted > 0 then
			JMod.ResourceEffect(Typ, bot:GetShootPos(), dest:LocalToWorld(dest:OBBCenter()), 1, 1, 1)
		end
	end

	local Rest = Amt - Accepted

	if Rest > 0 then
		local C = IsValid(dest) and dest:GetPos() or bot:GetPos()
		EZW.DropResource(W, Typ, Rest, C, W.dropIdx, IsCrate and 25 or 50)
		W.dropIdx = W.dropIdx + 3

		if IsCrate and (Accepted <= 0) then
			W.badEnts[dest] = CurTime() + 60 -- full or wrong type, try another one
		end
	end

	W.carryAmt, W.carryType = 0, nil
	EZW.AddXP(bot, W, 2)
end

-- One step of the "fetch loose resources -> deliver them" loop.
-- Returns true while it is busy, false when there is nothing (left) to do.
function EZW.HaulStep(bot, W, now, wanted, center, radius, destFor, avoidEnt, avoidRadius)
	local BP = bot:GetPos()

	if W.carryAmt > 0 then
		-- top up first if there is more of the same stuff right here
		if W.carryAmt < (CarryCap(W) * 0.85) then
			local More = EZW.FindLooseResource(bot, W, {[W.carryType] = true}, BP, 300, avoidEnt, avoidRadius)

			if More then
				if Flat(BP, More:GetPos()) > 80 then
					EZW.SetGoal(W, bot, More:GetPos(), 45)
					EZW.SetStatus(W, "Collecting " .. W.carryType)
				else
					EZW.PickUp(bot, W, More)
				end

				return true
			end
		end

		local Dest = destFor(W.carryType)

		if not IsValid(Dest) then
			-- nowhere to put it: drop at our feet and give up on this load
			EZW.DropResource(W, W.carryType, W.carryAmt, BP + bot:GetForward() * 40, 0, 20)
			W.carryAmt, W.carryType = 0, nil

			return false
		end

		local DP = Dest:GetPos()

		if Flat(BP, DP) > 110 then
			EZW.SetGoal(W, bot, EZW.StandNear(DP, BP, 85), 35)
			EZW.SetStatus(W, "Delivering " .. W.carryAmt .. " " .. W.carryType)

			return true
		end

		W.goal = nil
		W.lookAt = Dest:LocalToWorld(Dest:OBBCenter())
		EZW.Deliver(bot, W, Dest)

		return true
	end

	local Res = EZW.FindLooseResource(bot, W, wanted, center, radius, avoidEnt, avoidRadius)
	if not Res then return false end

	if Flat(BP, Res:GetPos()) > 80 then
		EZW.SetGoal(W, bot, Res:GetPos(), 45)
		EZW.SetStatus(W, "Fetching " .. tostring(Res.EZsupplies))

		return true
	end

	EZW.PickUp(bot, W, Res)

	return true
end

-- Top up a machine (power / gas / ...) from loose resources lying around it.
function EZW.FeedMachine(bot, W, machine)
	local Now = CurTime()
	if Now < (W.nextFeed or 0) then return end
	W.nextFeed = Now + 2.5
	if not (machine.EZconsumes and machine.TryLoadResource) then return end

	for _, Typ in ipairs(machine.EZconsumes) do
		local M = JMod.EZ_RESOURCE_TYPE_METHODS[Typ]
		local Getter = M and machine["Get" .. M]
		local MaxV = M and machine["Max" .. M]

		if Getter and isnumber(MaxV) and (Getter(machine) < (MaxV * 0.35)) then
			local Res = EZW.FindLooseResource(bot, W, {[Typ] = true}, machine:GetPos(), 350)

			if Res then
				local Amt = Res:GetResource()
				local Accepted = machine:TryLoadResource(Typ, Amt)

				if Accepted and (Accepted > 0) then
					JMod.ResourceEffect(Typ, Res:LocalToWorld(Res:OBBCenter()), machine:LocalToWorld(machine:OBBCenter()), 1, 1, 1)
					Res:SetEZsupplies(Typ, Amt - Accepted)
					EZW.SetStatus(W, "Refilling the workbench (" .. Typ .. ")")

					return
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Craft scatter: items that JMod spawns during a build are spread out
----------------------------------------------------------------------
EZW.Capture = nil

function EZW.BeginCapture(bench, owner)
	EZW.Capture = {
		bench = bench,
		owner = owner,
		origin = bench:GetPos() + bench:GetUp() * 55,
		untilT = CurTime() + 3.5,
		n = 0
	}
end

function EZW.ScatterEnt(ent, cap, idx)
	local Phys = ent:GetPhysicsObject()
	if not IsValid(Phys) then return end
	local Size = (ent:OBBMaxs() - ent:OBBMins()):Length()
	local A = math.rad(idx * 137.508 + math.random(-15, 15))
	local Dir = Vector(math.cos(A), math.sin(A), 0)
	local R = 8 + Size * 0.35 + 9 * math.sqrt(idx)
	local Ang = ent:GetAngles()
	Ang:RotateAroundAxis(vector_up, math.random(0, 359))
	ent:SetAngles(Ang)
	ent:SetPos(cap.origin + Dir * R + Vector(0, 0, Size * 0.25 + idx * 3))
	Phys = ent:GetPhysicsObject()
	if not IsValid(Phys) then return end
	Phys:Wake()
	local F = CV.scatterforce:GetFloat()
	Phys:SetVelocity(Dir * F * math.Rand(0.7, 1.3) + Vector(0, 0, F * 0.8))
	Phys:AddAngleVelocity(VectorRand() * 90)
end

hook.Add("OnEntityCreated", "EZW_CaptureCrafts", function(ent)
	local Cap = EZW.Capture
	if not Cap then return end

	if CurTime() > Cap.untilT then
		EZW.Capture = nil

		return
	end

	timer.Simple(0, function()
		if (not IsValid(ent)) or (EZW.Capture ~= Cap) then return end
		if (ent == Cap.bench) or ent:IsPlayer() or ent:IsNPC() or ent.EZW_scattered then return end
		if IsValid(ent:GetOwner()) or IsValid(ent:GetParent()) then return end
		if ent:GetMoveType() ~= MOVETYPE_VPHYSICS then return end
		if ent:GetPos():DistToSqr(Cap.origin) > (140 * 140) then return end
		ent.EZW_scattered = true

		-- crafted gear belongs to the human, not to the bot that pressed the button
		if IsValid(Cap.owner) then
			JMod.SetEZowner(ent, Cap.owner)
		end

		if CV.scatter:GetBool() then
			Cap.n = Cap.n + 1
			EZW.ScatterEnt(ent, Cap, Cap.n)
		end
	end)
end)

----------------------------------------------------------------------
-- Idle / Follow
----------------------------------------------------------------------
local function JobIdle(bot, W, now)
	W.goal = nil
	EZW.SetStatus(W, "Idle")
end

local function JobFollow(bot, W, now)
	local O = W.owner

	if not (IsValid(O) and O:Alive()) then
		W.goal = nil

		return
	end

	local D = Flat(bot:GetPos(), O:GetPos())

	if D > 140 then
		EZW.SetGoal(W, bot, O:GetPos(), 100)
		EZW.SetStatus(W, "Following " .. O:Nick())

		if (D > 2500) and CV.teleport:GetBool() then
			bot:SetPos(EZW.SpawnPosNear(O))
		end
	else
		W.goal = nil
		EZW.SetStatus(W, "Standing by")
	end
end

----------------------------------------------------------------------
-- Miner
----------------------------------------------------------------------
local NotPickaxeable = {water = true, oil = true, sand = true, geothermal = true}

local function PickDeposit(bot, W)
	local Tab = JMod.NaturalResourceTable
	if not Tab then return nil end
	local Center = W.workPoint or W.owner:GetPos()
	local MaxRange = W.workPoint and 1800 or 3500
	local BP, Now = bot:GetPos(), CurTime()
	local BestKey, BestScore

	for Key, Dep in pairs(Tab) do
		if istable(Dep) and Dep.pos and Dep.typ and (not NotPickaxeable[Dep.typ])
			and ((W.mineType == "any") or (W.mineType == Dep.typ))
			and ((W.badDeposits[Key] or 0) < Now) then
			local DC = Dep.pos:Distance(Center)

			if DC <= MaxRange then
				local Score = BP:Distance(Dep.pos) + DC * 0.3

				if (not BestScore) or (Score < BestScore) then
					BestKey, BestScore = Key, Score
				end
			end
		end
	end

	return BestKey
end

local function JobMiner(bot, W, now)
	local Dep = W.depKey and JMod.NaturalResourceTable[W.depKey]

	if not Dep then
		W.depKey = PickDeposit(bot, W)
		Dep = W.depKey and JMod.NaturalResourceTable[W.depKey]
		W.arrivedAt, W.lastProg, W.progChangeT, W.lastCycleT = nil, 0, nil, nil

		if not Dep then
			W.goal = nil
			EZW.SetStatus(W, "No deposits found (" .. W.mineType .. ")")

			return
		end

		W.spot = Dep.pos
		W.assigned = now
		-- stand a short distance from the spot, on the side we are coming from
		W.stand = EZW.StandNear(Dep.pos, bot:GetPos(), 28)
	end

	local Wep = EZW.EquipTool(bot, EZW.PickaxeClass)
	local Dist = Flat(bot:GetPos(), W.stand)

	if Dist > 45 then
		EZW.SetGoal(W, bot, W.stand, 24)
		EZW.SetStatus(W, "Walking to " .. Dep.typ .. " deposit")

		if (now - W.assigned) > 90 then
			W.badDeposits[W.depKey] = now + 180 -- unreachable, try another
			W.depKey = nil
		end

		return
	end

	-- ---- we are at the deposit: dig ----
	W.goal = nil
	W.duck = true -- crouching brings the ground within pickaxe reach
	W.lookAt = W.spot + Vector(0, 0, 2)
	W.arrivedAt = W.arrivedAt or now
	W.lastCycleT = W.lastCycleT or now
	W.progChangeT = W.progChangeT or now
	EZW.SetStatus(W, "Mining " .. Dep.typ)

	local HasPickaxe = weapons.Get(EZW.PickaxeClass) ~= nil
	if HasPickaxe and not IsValid(Wep) then return end -- still switching weapons
	W.attack = HasPickaxe

	-- progress lives on the pickaxe when it swings, on the bot when we drive mining directly
	local Prog = math.max(IsValid(Wep) and Wep:GetNW2Float("EZminingProgress", 0) or 0, bot:GetNW2Float("EZminingProgress", 0))

	if Prog < ((W.lastProg or 0) - 40) then
		-- the progress bar wrapped around: one resource cycle finished
		W.mined = W.mined + 1
		W.lastCycleT = now
		EZW.AddXP(bot, W, 6)
	end

	if Prog ~= (W.lastProg or 0) then
		W.progChangeT = now
	end

	W.lastProg = Prog

	-- Safety net: if the SWEP swing never registers progress, drive JMod's mining directly.
	local NoSwingProgress = (now - W.progChangeT) > 5

	if (NoSwingProgress or not HasPickaxe) and (now >= (W.nextDirect or 0)) then
		W.nextDirect = now + 1.2
		local Msg = JMod.EZprogressMining(bot, W.spot, bot, 1)

		if Msg then
			W.badDeposits[W.depKey] = now + 120
			W.depKey = nil
		end
	end

	if (now - W.lastCycleT) > 70 then
		W.badDeposits[W.depKey] = now + 180
		W.depKey = nil
	end
end

----------------------------------------------------------------------
-- Crafter
----------------------------------------------------------------------
local function FindBench(bot, W)
	local Center = W.workPoint or bot:GetPos()
	local Best, BestD

	for _, E in ipairs(ents.FindInSphere(Center, 700)) do
		if IsValid(E) and E.TryBuild and istable(E.Craftables) and E.Craftables[W.recipe] and EZW.CanTouch(E, W.owner) then
			local D = E:GetPos():DistToSqr(bot:GetPos())

			if (not BestD) or (D < BestD) then
				Best, BestD = E, D
			end
		end
	end

	return Best
end

local function MissingText(missing)
	local Parts = {}

	for Typ, Amt in pairs(missing or {}) do
		Parts[#Parts + 1] = math.ceil(Amt) .. " " .. Typ
	end

	return table.concat(Parts, ", ")
end

local function JobCrafter(bot, W, now)
	if not W.recipe then
		W.goal = nil
		EZW.SetStatus(W, "No recipe assigned")

		return
	end

	if (W.amount > 0) and (W.made >= W.amount) then
		EZW.Notify(W.owner, W.name .. " finished crafting " .. W.made .. "x " .. W.recipe .. ".")
		EZW.SetJob(bot, W, "idle")
		EZW.SetStatus(W, "Finished " .. W.made .. "x " .. W.recipe)

		return
	end

	local Info = JMod.Config.Craftables[W.recipe]

	if not Info then
		W.goal = nil
		EZW.SetStatus(W, "Unknown recipe")

		return
	end

	local Bench = IsValid(W.bench) and W.bench or FindBench(bot, W)
	W.bench = Bench

	if not IsValid(Bench) then
		W.goal = nil
		EZW.SetStatus(W, "No workbench nearby")

		return
	end

	local BP, BenchPos = bot:GetPos(), Bench:GetPos()

	-- finish a delivery that is already underway
	if W.carryAmt > 0 then
		EZW.HaulStep(bot, W, now, nil, BenchPos, 700, function() return Bench end, Bench, 160)

		return
	end

	if Flat(BP, BenchPos) > 120 then
		EZW.SetGoal(W, bot, EZW.StandNear(BenchPos, BP, 85), 35)
		EZW.SetStatus(W, "Heading to the workbench")

		return
	end

	W.goal = nil
	W.lookAt = Bench:LocalToWorld(Bench:OBBCenter())

	if Bench.GetState and (Bench:GetState() < 0) then
		EZW.SetStatus(W, "Workbench is broken")

		return
	end

	EZW.FeedMachine(bot, W, Bench)

	if (Bench.GetElectricity and (Bench:GetElectricity() <= 0)) or (Bench.GetGas and (Bench:GetGas() <= 0)) then
		EZW.SetStatus(W, "Workbench needs power / gas")

		return
	end

	local Ok, Missing = JMod.HaveResourcesToPerformTask(nil, nil, Info.craftingReqs, Bench)

	if not Ok then
		local Wanted = {}

		for Typ in pairs(Missing or {}) do
			Wanted[Typ] = true
		end

		if next(Wanted) and EZW.HaulStep(bot, W, now, Wanted, BenchPos, 700, function() return Bench end, Bench, 160) then
			return
		end

		EZW.SetStatus(W, "Missing: " .. MissingText(Missing))

		return
	end

	if now < (W.nextCraft or 0) then
		EZW.SetStatus(W, "Crafting " .. W.recipe)

		return
	end

	EZW.BeginCapture(Bench, W.owner)
	Bench:TryBuild(W.recipe, bot)
	W.made = W.made + 1
	W.nextCraft = now + math.max(1.5, CV.craftdelay:GetFloat() / (1 + (W.level - 1) * 0.1))
	EZW.AddXP(bot, W, 5)
	EZW.SetStatus(W, "Crafting " .. W.recipe)
end

----------------------------------------------------------------------
-- Hauler
----------------------------------------------------------------------
local function JobHauler(bot, W, now)
	local Home = W.workPoint or W.home or bot:GetPos()

	local function DestFor(typ)
		local Best, BestD

		for _, E in ipairs(ents.FindInSphere(Home, 900)) do
			if IsValid(E) and E.IsJackyEZcrate and E.TryLoadResource and ((W.badEnts[E] or 0) < now) and EZW.CanTouch(E, W.owner) then
				local CT = E.GetResourceType and E:GetResourceType()

				if (not CT) or (CT == typ) or (CT == "generic") then
					local D = E:GetPos():DistToSqr(Home)

					if (not BestD) or (D < BestD) then
						Best, BestD = E, D
					end
				end
			end
		end

		return Best
	end

	if EZW.HaulStep(bot, W, now, nil, Home, 650, DestFor) then return end

	W.goal = nil
	EZW.SetStatus(W, "Nothing to haul (need loose resources + a crate nearby)")
end

EZW.JobFuncs = {
	idle = JobIdle,
	follow = JobFollow,
	miner = JobMiner,
	crafter = JobCrafter,
	hauler = JobHauler
}
