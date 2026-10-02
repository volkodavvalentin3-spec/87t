-- JMod EZ Workers :: navigation + low-level bot steering (server)
--
-- Player bots have NO built-in AI. Everything they do is expressed as a CUserCmd
-- (movement, buttons, view angles) which we fill in inside GM:StartCommand.
--  * If the map has a navmesh we run A* over nav areas.
--  * If not (many sandbox maps) we walk straight at the goal, jump over obstacles,
--    side-step when stuck and finally teleport (convar-controlled).

EZW = EZW or {}

local CV = EZW.CV
local Flat = EZW.Flat

----------------------------------------------------------------------
-- Pathfinding
----------------------------------------------------------------------
function EZW.FindPath(from, to)
	if not (navmesh and navmesh.IsLoaded and navmesh.IsLoaded()) then return nil end

	local StartArea = navmesh.GetNearestNavArea(from, false, 250, false, true)
	local GoalArea = navmesh.GetNearestNavArea(to, false, 400, false, true)
	if not (StartArea and GoalArea) then return nil end
	if StartArea == GoalArea then return {to} end

	local Open, Came, G, Closed = {}, {}, {}, {}
	local StartID, GoalID = StartArea:GetID(), GoalArea:GetID()
	G[StartID] = 0
	Open[1] = {area = StartArea, f = from:Distance(to)}
	local Iter = 0

	while (#Open > 0) and (Iter < 4000) do
		Iter = Iter + 1
		local BestI, BestF = 1, Open[1].f

		for i = 2, #Open do
			if Open[i].f < BestF then
				BestI, BestF = i, Open[i].f
			end
		end

		local Cur = table.remove(Open, BestI)
		local CurArea = Cur.area
		local CurID = CurArea:GetID()

		if CurID == GoalID then
			local Areas, A = {}, GoalArea

			while A do
				table.insert(Areas, 1, A)
				A = Came[A:GetID()]
			end

			local Path = {}

			for i = 2, #Areas do
				Path[#Path + 1] = Areas[i]:GetCenter()
			end

			Path[#Path + 1] = to

			return Path
		end

		Closed[CurID] = true
		local CurCenter = CurArea:GetCenter()

		for _, Nb in ipairs(CurArea:GetAdjacentAreas()) do
			local NbID = Nb:GetID()

			if not Closed[NbID] then
				local Tentative = G[CurID] + CurCenter:Distance(Nb:GetCenter())

				if (G[NbID] == nil) or (Tentative < G[NbID]) then
					G[NbID] = Tentative
					Came[NbID] = CurArea
					Open[#Open + 1] = {area = Nb, f = Tentative + Nb:GetCenter():Distance(to)}
				end
			end
		end
	end

	return nil
end

-- Tell a worker where to go. Path is only recomputed when the goal really changed.
function EZW.SetGoal(W, bot, pos, radius)
	local Now = CurTime()
	W.goalRadius = radius or 40
	local Changed = (not W.goal) or (W.goal:DistToSqr(pos) > 50 * 50)

	if Changed or ((W.path == nil) and (Now > (W.repathT or 0))) then
		W.path = EZW.FindPath(bot:GetPos(), pos)
		W.pathIdx = 1
		W.repathT = Now + 6
		W.goal = pos
	else
		W.goal = pos
	end
end

-- A floor position `dist` units from `center`, on the side that `from` is on.
function EZW.StandNear(center, from, dist)
	local Dir = from - center
	Dir.z = 0

	if Dir:LengthSqr() < 4 then
		Dir = Vector(1, 0, 0)
	else
		Dir:Normalize()
	end

	local P = center + Dir * dist

	local Tr = util.TraceLine({
		start = P + Vector(0, 0, 80),
		endpos = P - Vector(0, 0, 200),
		mask = MASK_SOLID_BRUSHONLY
	})

	if Tr.Hit then return Tr.HitPos + Vector(0, 0, 2) end

	return P
end

function EZW.UnstickTeleport(bot, W)
	local Target = W.goal

	if W.path and (#W.path > 0) then
		Target = W.path[math.min((W.pathIdx or 1) + 1, #W.path)]
	end

	if not Target then return end
	local Eff = EffectData()
	Eff:SetOrigin(bot:GetPos() + Vector(0, 0, 30))
	util.Effect("cball_explode", Eff, true, true)
	bot:SetPos(Target + Vector(0, 0, 6))
	bot:SetLocalVelocity(Vector(0, 0, 0))
	Eff:SetOrigin(Target + Vector(0, 0, 30))
	util.Effect("cball_explode", Eff, true, true)
	W.stuck = 0
	W.path = nil
	W.repathT = 0
end

----------------------------------------------------------------------
-- Steering (runs every tick from StartCommand)
----------------------------------------------------------------------
local function AimDiff(view, wy, wp)
	return math.max(math.abs(math.AngleDifference(view.y, wy)), math.abs(math.AngleDifference(view.p, wp)))
end

function EZW.Steer(bot, W, cmd)
	local Now = CurTime()
	local Dt = engine.TickInterval()
	local Pos = bot:GetPos()
	W.view = W.view or Angle(0, bot:EyeAngles().y, 0)
	local View = W.view
	local Buttons, Fwd, Side = 0, 0, 0
	local MoveDir

	-- 1) where do we want to walk?
	if W.goal then
		local Wp = W.goal

		if W.path and (W.pathIdx or 1) <= #W.path then
			Wp = W.path[W.pathIdx]
		end

		local To = Wp - Pos
		To.z = 0
		local Dist = To:Length()
		W.arrived = (Flat(Pos, W.goal) <= (W.goalRadius or 40)) and (math.abs(W.goal.z - Pos.z) < 90)

		if not W.arrived then
			if W.path and (W.pathIdx or 1) <= #W.path and (Dist < 40) then
				W.pathIdx = W.pathIdx + 1
			end

			if Dist > 1 then
				MoveDir = To:GetNormalized()
			end
		end
	else
		W.arrived = false
	end

	-- 2) where do we want to look?
	local WantYaw, WantPitch = View.y, View.p
	W.aimed = false

	if W.lookAt then
		local V = (W.lookAt - bot:GetShootPos()):Angle()
		WantYaw, WantPitch = V.y, math.Clamp(math.NormalizeAngle(V.p), -80, 80)
	elseif MoveDir then
		WantYaw, WantPitch = MoveDir:Angle().y, 0
	end

	local Rate = 540 * Dt
	View.y = math.ApproachAngle(View.y, WantYaw, Rate)
	View.p = math.ApproachAngle(View.p, WantPitch, Rate)
	View.r = 0

	if W.lookAt then
		W.aimed = AimDiff(View, WantYaw, WantPitch) < 7
	end

	-- 3) translate the walk direction into forward/side moves (relative to the view)
	if MoveDir then
		local Diff = math.rad(math.NormalizeAngle(MoveDir:Angle().y - View.y))
		Fwd = math.cos(Diff) * 10000
		Side = -math.sin(Diff) * 10000

		-- obstacle probing: jump over things we can not simply step on
		local Low = Pos + Vector(0, 0, 20)

		local TrLow = util.TraceHull({
			start = Low,
			endpos = Low + MoveDir * 34,
			mins = Vector(-14, -14, 0),
			maxs = Vector(14, 14, 24),
			filter = bot,
			mask = MASK_PLAYERSOLID
		})

		if TrLow.Hit and bot:OnGround() then
			local High = Pos + Vector(0, 0, 50)

			local TrHigh = util.TraceHull({
				start = High,
				endpos = High + MoveDir * 34,
				mins = Vector(-14, -14, 0),
				maxs = Vector(14, 14, 10),
				filter = bot,
				mask = MASK_PLAYERSOLID
			})

			if not TrHigh.Hit then
				Buttons = bit.bor(Buttons, IN_JUMP)
			end
		end

		-- stuck detection
		if Now >= (W.stuckT or 0) then
			W.stuckT = Now + 0.6

			if W.stuckPos and (Flat(Pos, W.stuckPos) < 12) then
				W.stuck = (W.stuck or 0) + 0.6
			else
				W.stuck = 0
			end

			W.stuckPos = Pos
		end

		local St = W.stuck or 0

		if (St > 0.5) and bot:OnGround() then
			Buttons = bit.bor(Buttons, IN_JUMP)
		end

		if St > 1.8 then
			if Now > (W.sideUntil or 0) then
				W.sideDir = (math.random(1, 2) == 1) and 1 or -1
				W.sideUntil = Now + 0.8
			end

			Side = (W.sideDir or 1) * 10000
			Fwd = Fwd * 0.3
		end

		if (St > 4) and W.path then
			W.path = nil
			W.repathT = 0
		end

		if St > 7 then
			if CV.teleport:GetBool() then
				EZW.UnstickTeleport(bot, W)
			end

			W.stuck = 0
		end
	else
		W.stuck = 0
		W.stuckPos = nil
	end

	if W.duck then
		Buttons = bit.bor(Buttons, IN_DUCK)
	end

	if W.attack and ((not W.lookAt) or W.aimed) then
		Buttons = bit.bor(Buttons, IN_ATTACK)
	end

	cmd:ClearMovement()
	cmd:ClearButtons()
	cmd:SetForwardMove(Fwd)
	cmd:SetSideMove(Side)
	cmd:SetButtons(Buttons)
	cmd:SetViewAngles(View)
	bot:SetEyeAngles(View)
end
