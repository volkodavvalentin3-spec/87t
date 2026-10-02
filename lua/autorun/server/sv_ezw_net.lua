-- JMod EZ Workers :: network layer (server)
-- (net strings themselves are registered in lua/autorun/ezw_init.lua)

EZW = EZW or {}

local CV = EZW.CV

local function ReqText(reqs)
	local Parts = {}

	for Typ, Amt in pairs(reqs or {}) do
		if istable(Amt) then
			local Alt = {}

			for T2, A2 in pairs(Amt) do
				Alt[#Alt + 1] = T2 .. " x" .. A2
			end

			table.sort(Alt)
			Parts[#Parts + 1] = "(" .. table.concat(Alt, " / ") .. ")"
		else
			Parts[#Parts + 1] = Typ .. " x" .. Amt
		end
	end

	table.sort(Parts)

	return table.concat(Parts, ", ")
end

-- every recipe a workbench could build (same filter the workbench itself uses)
function EZW.GetRecipeList()
	local List = {}
	local C = JMod and JMod.Config and JMod.Config.Craftables
	if not C then return List end

	for Name, Info in pairs(C) do
		local CT = Info.craftingType

		if (CT == "workbench") or (istable(CT) and table.HasValue(CT, "workbench")) then
			List[#List + 1] = {
				name = Name,
				cat = tostring(Info.category or ""),
				reqs = ReqText(Info.craftingReqs)
			}
		end
	end

	table.sort(List, function(a, b)
		if a.cat ~= b.cat then return a.cat < b.cat end

		return a.name < b.name
	end)

	return List
end

function EZW.SendSync(ply, withRecipes)
	local Gold = 0

	if JMod and JMod.CountResourcesInRange then
		Gold = math.floor(JMod.CountResourcesInRange(ply:GetPos(), CV.payrange:GetInt())[EZW.GoldType] or 0)
	end

	local Info = {
		cost = CV.cost:GetInt(),
		max = CV.max:GetInt(),
		range = CV.payrange:GetInt(),
		gold = Gold,
		workers = {}
	}

	for _, Bot in ipairs(EZW.GetWorkers(ply)) do
		local W = Bot.EZW

		Info.workers[#Info.workers + 1] = {
			ent = Bot,
			name = W.name,
			job = W.job,
			status = W.status or "",
			energy = math.floor(W.energy),
			level = W.level,
			xp = math.floor(W.xp),
			nextxp = EZW.NextXP(W.level),
			recipe = W.recipe or "",
			amount = W.amount,
			made = W.made,
			mined = W.mined,
			mine = W.mineType,
			point = W.workPoint ~= nil,
			carry = W.carryAmt or 0,
			carrytype = W.carryType or ""
		}
	end

	net.Start("EZW_Sync")
	net.WriteTable(Info)
	net.WriteBool(withRecipes and true or false)

	if withRecipes then
		local Data = util.Compress(util.TableToJSON(EZW.GetRecipeList()))
		net.WriteUInt(#Data, 32)
		net.WriteData(Data, #Data)
	end

	net.Send(ply)
end

local NextReq = {}

net.Receive("EZW_Request", function(len, ply)
	local Want = net.ReadBool()
	local Now = CurTime()
	if (NextReq[ply] or 0) > Now then return end
	NextReq[ply] = Now + 0.4
	EZW.SendSync(ply, Want)
end)

local NextHire = {}

net.Receive("EZW_Hire", function(len, ply)
	local Mdl, Name = net.ReadString(), net.ReadString()
	local Now = CurTime()
	if (NextHire[ply] or 0) > Now then return end
	NextHire[ply] = Now + 1
	EZW.Hire(ply, Mdl, Name, false)
	timer.Simple(0.5, function()
		if IsValid(ply) then EZW.SendSync(ply, false) end
	end)
end)

net.Receive("EZW_Cmd", function(len, ply)
	local Bot = net.ReadEntity()
	local Act = net.ReadString()
	local Data = net.ReadTable() or {}
	if not (EZW.IsWorker(Bot) and (Bot.EZW.owner == ply)) then return end
	local W = Bot.EZW

	if Act == "job" then
		if EZW.Jobs[Data.job] then
			EZW.SetJob(Bot, W, tostring(Data.job))
		end
	elseif Act == "mine" then
		if table.HasValue(EZW.MineTypes, Data.typ) then
			W.mineType = Data.typ
			W.depKey = nil
		end
	elseif Act == "recipe" then
		local Name = tostring(Data.name or "")
		local Ok = false

		for _, R in ipairs(EZW.GetRecipeList()) do
			if R.name == Name then
				Ok = true
				break
			end
		end

		if Ok then
			W.recipe = Name
			W.amount = math.Clamp(math.floor(tonumber(Data.amount) or 0), 0, 999)
			W.made = 0
			W.bench = nil
			EZW.SetJob(Bot, W, "crafter")
			EZW.Notify(ply, W.name .. " will craft " .. ((W.amount > 0) and (W.amount .. "x ") or "unlimited ") .. Name .. " at a workbench near them.")
		end
	elseif Act == "point" then
		if Data.clear then
			W.workPoint = nil
			EZW.Notify(ply, W.name .. ": work point cleared.")
		else
			W.workPoint = ply:GetPos()
			EZW.Notify(ply, W.name .. ": work point set to where you are standing.")
		end
	elseif Act == "rename" then
		local N = string.Trim(string.sub(tostring(Data.name or ""), 1, 24))
		if N ~= "" then W.name = N end
	elseif Act == "dismiss" then
		EZW.Notify(ply, W.name .. " was dismissed.")
		EZW.Dismiss(Bot, "Dismissed")
	end

	EZW.SendSync(ply, false)
end)

hook.Add("PlayerSay", "EZW_ChatCommand", function(ply, text)
	local T = string.lower(string.Trim(text))

	if (T == "!workers") or (T == "/workers") then
		net.Start("EZW_OpenMenu")
		net.Send(ply)

		return ""
	end
end)
