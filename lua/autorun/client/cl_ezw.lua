-- JMod EZ Workers :: client UI
--  * Icon in the C-menu (context menu "desktop windows") + `ezw_menu` console command + `!workers` chat command
--  * Overhead HUD for your own workers

EZW = EZW or {}
EZW.State = EZW.State or {info = nil, recipes = {}}

local S = EZW.State

local Gold = Color(255, 215, 120)
local Dim = Color(190, 190, 190)

----------------------------------------------------------------------
-- Net
----------------------------------------------------------------------
net.Receive("EZW_Sync", function()
	local Info = net.ReadTable()
	local HasRecipes = net.ReadBool()

	if HasRecipes then
		local Len = net.ReadUInt(32)
		local Data = net.ReadData(Len)
		local Json = util.Decompress(Data)
		S.recipes = (Json and util.JSONToTable(Json)) or {}
	end

	S.info = Info

	if IsValid(EZW.MenuPanel) and EZW.MenuPanel.OnSync then
		EZW.MenuPanel:OnSync()
	end
end)

net.Receive("EZW_OpenMenu", function()
	EZW.OpenMenu()
end)

function EZW.SendCmd(ent, act, data)
	net.Start("EZW_Cmd")
	net.WriteEntity(ent)
	net.WriteString(act)
	net.WriteTable(data or {})
	net.SendToServer()
end

function EZW.RequestSync(withRecipes)
	net.Start("EZW_Request")
	net.WriteBool(withRecipes and true or false)
	net.SendToServer()
end

local function FindWorker(ent)
	if not (S.info and ent) then return nil end

	for _, W in ipairs(S.info.workers or {}) do
		if W.ent == ent then return W end
	end

	return nil
end

----------------------------------------------------------------------
-- Menu
----------------------------------------------------------------------
local function Label(parent, text, font, col)
	local L = vgui.Create("DLabel", parent)
	L:Dock(TOP)
	L:SetText(text)
	L:SetFont(font or "DermaDefault")
	L:SetTextColor(col or color_white)
	L:SetWrap(true)
	L:SetAutoStretchVertical(true)
	L:DockMargin(0, 4, 0, 0)

	return L
end

local function BuildWorkersTab(ui, tab)
	local List = vgui.Create("DListView", tab)
	List:Dock(LEFT)
	List:SetWide(280)
	List:SetMultiSelect(false)
	List:AddColumn("Name")
	List:AddColumn("Job"):SetFixedWidth(65)
	List:AddColumn("En"):SetFixedWidth(40)
	List:AddColumn("Lv"):SetFixedWidth(28)
	ui.list = List

	local Right = vgui.Create("DScrollPanel", tab)
	Right:Dock(FILL)
	Right:DockMargin(8, 0, 0, 0)
	ui.right = Right

	function ui.Rebuild()
		Right:Clear()
		ui.dyn = nil
		ui.built = nil
		local W = FindWorker(ui.selected)

		if not W then
			local L = Label(Right, "Select a worker on the left - or hire one in the \"Hire\" tab.", nil, Dim)
			L:DockMargin(8, 8, 8, 0)

			return
		end

		ui.built = W.ent
		local Ent = W.ent
		local Dyn = {}
		ui.dyn = Dyn

		Dyn.title = Label(Right, "", "DermaLarge", Gold)
		Dyn.status = Label(Right, "", nil, color_white)
		Dyn.stats = Label(Right, "", nil, Dim)

		local Bar = vgui.Create("DProgress", Right)
		Bar:Dock(TOP)
		Bar:SetTall(18)
		Bar:DockMargin(0, 6, 0, 0)
		Dyn.bar = Bar

		Label(Right, "Job", "DermaDefaultBold", Gold)
		local CJ = vgui.Create("DComboBox", Right)
		CJ:Dock(TOP)

		for _, Key in ipairs(EZW.JobOrder) do
			CJ:AddChoice(EZW.Jobs[Key].name .. " - " .. EZW.Jobs[Key].desc, Key, Key == W.job)
		end

		CJ.OnSelect = function(_, _, _, Data)
			EZW.SendCmd(Ent, "job", {job = Data})
		end

		Dyn.jobCombo = CJ

		Label(Right, "Mining target (Miner job)", "DermaDefaultBold", Gold)
		local CM = vgui.Create("DComboBox", Right)
		CM:Dock(TOP)

		for _, Typ in ipairs(EZW.MineTypes) do
			CM:AddChoice(Typ == "any" and "any deposit (nearest)" or Typ, Typ, Typ == W.mine)
		end

		CM.OnSelect = function(_, _, _, Data)
			EZW.SendCmd(Ent, "mine", {typ = Data})
		end

		Label(Right, "Work point", "DermaDefaultBold", Gold)
		Dyn.point = Label(Right, "", nil, Dim)
		local Row = vgui.Create("DPanel", Right)
		Row:Dock(TOP)
		Row:SetTall(26)
		Row.Paint = function() end
		local B1 = vgui.Create("DButton", Row)
		B1:Dock(LEFT)
		B1:SetWide(190)
		B1:SetText("Set work point: where I stand")
		B1.DoClick = function() EZW.SendCmd(Ent, "point", {}) end
		local B2 = vgui.Create("DButton", Row)
		B2:Dock(LEFT)
		B2:SetWide(90)
		B2:DockMargin(6, 0, 0, 0)
		B2:SetText("Clear")
		B2.DoClick = function() EZW.SendCmd(Ent, "point", {clear = true}) end

		Label(Right, "Crafting (Crafter job - needs a workbench near the worker)", "DermaDefaultBold", Gold)
		Dyn.recipe = Label(Right, "", nil, Dim)
		local B3 = vgui.Create("DButton", Right)
		B3:Dock(TOP)
		B3:SetTall(24)
		B3:SetText("Choose a recipe...")
		B3.DoClick = function() ui.sheet:SetActiveTab(ui.craftTab.Tab) end

		Label(Right, "Rename", "DermaDefaultBold", Gold)
		local Name = vgui.Create("DTextEntry", Right)
		Name:Dock(TOP)
		Name:SetText(W.name)
		Name.OnEnter = function(Self) EZW.SendCmd(Ent, "rename", {name = Self:GetValue()}) end

		local BD = vgui.Create("DButton", Right)
		BD:Dock(TOP)
		BD:DockMargin(0, 14, 0, 0)
		BD:SetTall(28)
		BD:SetText("Dismiss this worker")
		BD:SetTextColor(Color(255, 120, 120))

		BD.DoClick = function()
			Derma_Query("Dismiss " .. W.name .. "? Their XP is lost.", "Dismiss worker",
				"Dismiss", function()
					EZW.SendCmd(Ent, "dismiss", {})
					ui.selected = nil
				end, "Cancel")
		end
	end

	function ui.UpdateDetail()
		local W = FindWorker(ui.built)
		local Dyn = ui.dyn
		if not (W and Dyn) then return end
		Dyn.title:SetText(W.name .. "  (Lv " .. W.level .. ")")
		Dyn.status:SetText("Status: " .. W.status)
		local Carry = (W.carry > 0) and ("   |   Carrying: " .. W.carry .. " " .. W.carrytype) or ""
		Dyn.stats:SetText("XP " .. W.xp .. "/" .. W.nextxp .. "   |   mined: " .. W.mined .. "   |   crafted: " .. W.made .. Carry)
		Dyn.bar:SetFraction(math.Clamp(W.energy / 100, 0, 1))
		Dyn.point:SetText(W.point and "A work point is set - the worker stays around it." or "No work point - the worker operates around you / itself.")

		if W.recipe ~= "" then
			Dyn.recipe:SetText("Recipe: " .. W.recipe .. "   (" .. W.made .. " / " .. ((W.amount > 0) and W.amount or "unlimited") .. ")")
		else
			Dyn.recipe:SetText("No recipe assigned yet.")
		end
	end

	List.OnRowSelected = function(_, _, Line)
		if ui.built == Line.ent then return end
		ui.selected = Line.ent
		ui.Rebuild()
		ui.UpdateDetail()
	end
end

local function BuildHireTab(ui, tab)
	local Models = {}

	for Name, Path in pairs(player_manager.AllValidModels()) do
		Models[#Models + 1] = {name = Name, path = Path}
	end

	table.sort(Models, function(a, b) return a.name < b.name end)

	local Left = vgui.Create("DPanel", tab)
	Left:Dock(LEFT)
	Left:SetWide(300)
	Left.Paint = function() end

	local Search = vgui.Create("DTextEntry", Left)
	Search:Dock(TOP)
	Search:SetPlaceholderText("Search player models...")

	local List = vgui.Create("DListView", Left)
	List:Dock(FILL)
	List:SetMultiSelect(false)
	List:AddColumn("Player model")

	local Right = vgui.Create("DPanel", tab)
	Right:Dock(FILL)
	Right:DockMargin(8, 0, 0, 0)
	Right.Paint = function() end

	local Preview = vgui.Create("DModelPanel", Right)
	Preview:Dock(TOP)
	Preview:SetTall(250)
	Preview:SetFOV(32)
	Preview:SetCamPos(Vector(95, 40, 55))
	Preview:SetLookAt(Vector(0, 0, 36))
	Preview:SetVisible(false)

	function Preview:LayoutEntity(Ent)
		Ent:SetAngles(Angle(0, (RealTime() * 40) % 360, 0))
	end

	ui.hireModel = ""

	local function Fill()
		List:Clear()
		local F = string.lower(Search:GetValue() or "")
		local Rand = List:AddLine("[ Random model ]")
		Rand.path = ""

		for _, M in ipairs(Models) do
			if (F == "") or string.find(string.lower(M.name), F, 1, true) then
				local L = List:AddLine(M.name)
				L.path = M.path
			end
		end
	end

	Fill()
	Search.OnChange = Fill

	List.OnRowSelected = function(_, _, Line)
		ui.hireModel = Line.path

		if Line.path == "" then
			Preview:SetVisible(false)
		else
			Preview:SetVisible(true)
			Preview:SetModel(Line.path)
		end
	end

	local Info = Label(Right, "", nil, color_white)
	Info:DockMargin(0, 8, 0, 0)
	ui.hireInfo = Info

	Label(Right, "Name (optional)", "DermaDefaultBold", Gold)
	local Name = vgui.Create("DTextEntry", Right)
	Name:Dock(TOP)
	Name:SetPlaceholderText("random name")

	local Btn = vgui.Create("DButton", Right)
	Btn:Dock(TOP)
	Btn:DockMargin(0, 10, 0, 0)
	Btn:SetTall(34)
	Btn:SetText("HIRE")
	Btn:SetFont("DermaDefaultBold")

	Btn.DoClick = function()
		net.Start("EZW_Hire")
		net.WriteString(ui.hireModel or "")
		net.WriteString(Name:GetValue() or "")
		net.SendToServer()
		Name:SetText("")
	end

	Label(Right, "Workers are real player bots, so the server needs a free player slot. They need a few seconds to spawn and walk up to you.", nil, Dim)
end

local function BuildCraftTab(ui, tab)
	local Search = vgui.Create("DTextEntry", tab)
	Search:Dock(TOP)
	Search:SetPlaceholderText("Search recipes...")

	local Bottom = vgui.Create("DPanel", tab)
	Bottom:Dock(BOTTOM)
	Bottom:SetTall(34)
	Bottom:DockMargin(0, 6, 0, 0)
	Bottom.Paint = function() end

	local List = vgui.Create("DListView", tab)
	List:Dock(FILL)
	List:DockMargin(0, 6, 0, 0)
	List:SetMultiSelect(false)
	List:AddColumn("Recipe"):SetFixedWidth(210)
	List:AddColumn("Category"):SetFixedWidth(110)
	List:AddColumn("Requirements")
	ui.recipeList = List

	local Target = vgui.Create("DLabel", Bottom)
	Target:Dock(LEFT)
	Target:SetWide(220)
	Target:SetTextColor(Gold)
	ui.craftTarget = Target

	local Amt = vgui.Create("DNumberWang", Bottom)
	Amt:Dock(LEFT)
	Amt:SetWide(70)
	Amt:SetMin(0)
	Amt:SetMax(999)
	Amt:SetValue(1)

	local AmtL = vgui.Create("DLabel", Bottom)
	AmtL:Dock(LEFT)
	AmtL:SetWide(100)
	AmtL:DockMargin(6, 0, 0, 0)
	AmtL:SetText("amount (0 = endless)")
	AmtL:SetTextColor(Dim)

	local Go = vgui.Create("DButton", Bottom)
	Go:Dock(FILL)
	Go:SetText("Assign and start crafting")

	Go.DoClick = function()
		local W = FindWorker(ui.selected)
		local Line = List:GetSelectedLine() and List:GetLine(List:GetSelectedLine())

		if not W then
			notification.AddLegacy("Select a worker in the Workers tab first.", NOTIFY_ERROR, 3)

			return
		end

		if not Line then
			notification.AddLegacy("Select a recipe first.", NOTIFY_ERROR, 3)

			return
		end

		EZW.SendCmd(W.ent, "recipe", {name = Line.recipe, amount = Amt:GetValue()})
		notification.AddLegacy(W.name .. " is on it.", NOTIFY_GENERIC, 3)
	end

	function ui.FillRecipes()
		List:Clear()
		local F = string.lower(Search:GetValue() or "")

		for _, R in ipairs(S.recipes or {}) do
			if (F == "") or string.find(string.lower(R.name), F, 1, true) or string.find(string.lower(R.cat), F, 1, true) then
				local L = List:AddLine(R.name, R.cat, R.reqs)
				L.recipe = R.name
			end
		end
	end

	Search.OnChange = function() ui.FillRecipes() end
end

local HelpText = [[HOW IT WORKS

HIRING
Stand within the pay range of some GOLD (loose on the floor, in a gold crate, or in your own JMod inventory) and press HIRE. The gold is consumed.

FEEDING
Workers burn energy while they work. Drop NUTRIENTS (or a nutrients crate) within ~170 units of them and they eat on their own when low. At 0 energy they stop and wait for food. Fed workers slowly heal.

JOBS
Miner - walks to the nearest ore deposit (or one near the work point), crouches and digs with the EZ Pickaxe. Resources pop out like normal JMod mining (into a nearby crate when there is one).
Crafter - needs a JMod workbench within 700 units of the worker. Keep materials, power and gas near the bench: the worker fetches missing materials from loose resources, refills the bench from loose batteries/gas, builds, and scatters the results so they do not clip into each other.
Hauler - picks up loose resources around the work point and loads them into the nearest fitting crate.
Follow / Idle - what they say.

TIPS
Level up workers by working: they burn less energy, carry more and craft faster.
Set a WORK POINT by standing where you want them to operate. Workers respect JMod ownership and are added to your JMod friends list, so your sentries will not shoot them.
Chat: !workers    Console: ezw_menu]]

function EZW.BuildMenu(Parent)
	local UI = {}
	Parent.EZWui = UI

	local Header = vgui.Create("DLabel", Parent)
	Header:Dock(TOP)
	Header:SetTall(20)
	Header:SetFont("DermaDefaultBold")
	Header:SetTextColor(Gold)
	Header:SetText("Loading...")
	UI.header = Header

	local Sheet = vgui.Create("DPropertySheet", Parent)
	Sheet:Dock(FILL)
	UI.sheet = Sheet

	local WP = vgui.Create("DPanel", Sheet)
	WP.Paint = function() end
	local HP = vgui.Create("DPanel", Sheet)
	HP.Paint = function() end
	local CP = vgui.Create("DPanel", Sheet)
	CP.Paint = function() end
	local HelpP = vgui.Create("DScrollPanel", Sheet)

	UI.workersTab = Sheet:AddSheet("Workers", WP, "icon16/user.png")
	UI.hireTab = Sheet:AddSheet("Hire", HP, "icon16/user_add.png")
	UI.craftTab = Sheet:AddSheet("Crafting", CP, "icon16/wrench.png")
	Sheet:AddSheet("Help", HelpP, "icon16/help.png")

	local HL = vgui.Create("DLabel", HelpP)
	HL:Dock(TOP)
	HL:DockMargin(8, 8, 8, 8)
	HL:SetText(HelpText)
	HL:SetWrap(true)
	HL:SetAutoStretchVertical(true)
	HL:SetTextColor(color_white)

	BuildWorkersTab(UI, WP)
	BuildHireTab(UI, HP)
	BuildCraftTab(UI, CP)
	UI.Rebuild()

	local LastRecipeCount = -1

	Parent.OnSync = function()
		local Info = S.info
		if not Info then return end

		Header:SetText("Gold nearby: " .. Info.gold .. "   |   Hire cost: " .. Info.cost .. " gold   |   Workers: " .. #Info.workers .. "/" .. Info.max)
		UI.hireInfo:SetText("Cost: " .. Info.cost .. " gold  (you have " .. Info.gold .. " within " .. Info.range .. " units).\nGold on the floor, in a crate or in your JMod inventory counts.")
		local Sel = UI.selected
		UI.list:Clear()
		local Found = false

		for _, W in ipairs(Info.workers) do
			local Line = UI.list:AddLine(W.name, EZW.Jobs[W.job] and EZW.Jobs[W.job].name or W.job, W.energy .. "%", W.level)
			Line.ent = W.ent

			if W.ent == Sel then
				UI.list:SelectItem(Line)
				Found = true
			end
		end

		if (Sel ~= nil) and not Found then
			UI.selected = nil
			UI.Rebuild()
		end

		UI.UpdateDetail()
		local W = FindWorker(UI.selected)
		UI.craftTarget:SetText(W and ("Assign to: " .. W.name) or "Assign to: (select a worker first)")

		if #(S.recipes or {}) ~= LastRecipeCount then
			LastRecipeCount = #S.recipes
			UI.FillRecipes()
		end
	end

	EZW.RequestSync(true)

	timer.Create("EZW_MenuRefresh", 1, 0, function()
		if not IsValid(Parent) then
			timer.Remove("EZW_MenuRefresh")

			return
		end

		EZW.RequestSync(false)
	end)
end

function EZW.OpenMenu()
	if IsValid(EZW.MenuFrame) then EZW.MenuFrame:Remove() end
	local Frame = vgui.Create("DFrame")
	Frame:SetSize(math.min(ScrW() - 40, 860), math.min(ScrH() - 40, 600))
	Frame:SetTitle("JMod EZ Workers")
	Frame:Center()
	Frame:MakePopup()
	EZW.MenuFrame = Frame
	EZW.MenuPanel = Frame
	EZW.BuildMenu(Frame)
end

concommand.Add("ezw_menu", function() EZW.OpenMenu() end, nil, "Open the EZ Workers menu.")

-- The C-menu (context menu) icon
list.Set("DesktopWindows", "EZWorkers", {
	title = "EZ Workers",
	icon = "icon64/playermodel.png",
	width = 860,
	height = 600,
	onewindow = true,
	init = function(icon, window)
		EZW.MenuPanel = window
		EZW.BuildMenu(window)
	end
})

----------------------------------------------------------------------
-- Overhead HUD for your own workers
----------------------------------------------------------------------
hook.Add("HUDPaint", "EZW_Overhead", function()
	local Me = LocalPlayer()
	if not IsValid(Me) then return end
	local Eye = EyePos()

	for _, P in ipairs(player.GetAll()) do
		if (P ~= Me) and P:GetNW2Bool("EZW_Is", false) and (P:GetNW2Entity("EZW_Owner") == Me) and P:Alive() then
			local Pos = P:GetPos() + Vector(0, 0, 88)

			if Eye:DistToSqr(Pos) < (1600 * 1600) then
				local Sp = Pos:ToScreen()

				if Sp.visible then
					local Energy = P:GetNW2Int("EZW_Energy", 0)
					local Frac = math.Clamp(Energy / 100, 0, 1)
					local Job = EZW.Jobs[P:GetNW2String("EZW_Job", "idle")]
					local Carry = P:GetNW2Int("EZW_Carry", 0)
					draw.SimpleTextOutlined(P:GetNW2String("EZW_Name", "Worker") .. "  Lv" .. P:GetNW2Int("EZW_Level", 1), "DermaDefaultBold", Sp.x, Sp.y - 26, Gold, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, color_black)
					draw.SimpleTextOutlined((Job and Job.name or "?") .. " - " .. P:GetNW2String("EZW_Status", ""), "DermaDefault", Sp.x, Sp.y - 12, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, color_black)

					if Carry > 0 then
						draw.SimpleTextOutlined("carrying " .. Carry, "DermaDefault", Sp.x, Sp.y + 12, Dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
					end

					surface.SetDrawColor(0, 0, 0, 200)
					surface.DrawRect(Sp.x - 31, Sp.y - 9, 62, 8)
					surface.SetDrawColor(255 * (1 - Frac), 200 * Frac + 40, 40, 255)
					surface.DrawRect(Sp.x - 30, Sp.y - 8, 60 * Frac, 6)
				end
			end
		end
	end
end)
