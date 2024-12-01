
local PathEdit = ZSBOTAI.PATH_EDIT_DATA
local PathMenu = false

local DrawDistances = {{D=300,T="Short"},{D=800,T="Medium"},{D=1200,T="Long"},{D=3500,T="Really far"},{D=false,T="Unlimited"}}
local EditModeNames = {"Create Node","Edit ReachSpecs","Edit Nodes","Volumes","Nav Mesh","Settings"}
local ReachFlags = {{"Flying",ZSBOTAI.PATH_ReachFlags.Fly},{"Headcrab jump",ZSBOTAI.PATH_ReachFlags.Headcrab},{"FastZombie leap",ZSBOTAI.PATH_ReachFlags.Leap}
	,{"FleshBeast climb",ZSBOTAI.PATH_ReachFlags.Climb},{"Door path",ZSBOTAI.PATH_ReachFlags.Door},{"Teleport hack",ZSBOTAI.PATH_ReachFlags.Teleport}
	,{"Zombies only",ZSBOTAI.PATH_ReachFlags.Zombies},{"Humans only",ZSBOTAI.PATH_ReachFlags.Humans},{"No Strafe path",ZSBOTAI.PATH_ReachFlags.NoStrafeTo}}
local PathTypes = {"Regular","Flying","Ladder","Armory Node", "No Leave Node", "Zombie Spawn"}
local PrevMX,PrevMY = 0,0

local SubRoutine = false

local function AddCheckbox( g, txt, val, f )
	local DCheckbox = vgui.Create("DCheckBoxLabel",g)
	DCheckbox:SetText(txt)
	DCheckbox:SetValue(val)
	DCheckbox:SizeToContents()
	DCheckbox.OnChange = function( chk, val )
		if not SubRoutine then
			SubRoutine = true
			f(val)
			SubRoutine = false
		end
	end
	DCheckbox:Dock(TOP)
	return DCheckbox
end

local function AddMidLabel( g, txt )
	local DLabel = vgui.Create("DLabel",g)
	DLabel:Dock(TOP)
	DLabel:SetText(txt)
	return DLabel
end

local function AddButton( g, txt, hint, f )
	local DermaButton = vgui.Create("DButton",g)
	DermaButton:SetText(txt)
	DermaButton:SetTooltip(hint)
	DermaButton:SetSize(150,20)
	DermaButton.DoClick = function()
		if not SubRoutine then
			SubRoutine = true
			f()
			SubRoutine = false
		end
	end
	DermaButton:Dock(TOP)
	return DermaButton
end

local bDidInit = false
local T_ComboList

local function MakeExportMenu( bImport )
	if not bDidInit then
		bDidInit = true
		if not file.Exists("zsbots", "DATA") then
			file.CreateDir("zsbots")
		end
	end

	local frame = vgui.Create( "DFrame" )
	frame:SetSize( 300, 250 )
	frame:SetTitle(bImport and "Import path data" or "Export path data")
	frame:SetSkin("Default")
	frame:Center()
	frame:MakePopup()

	local DComboBox = vgui.Create( "DComboBox", frame )
	DComboBox:SetSize( 200, 20 )
	DComboBox:AlignTop(32)
	DComboBox:CenterHorizontal()
	DComboBox:SetValue( "<Select a map>" )

	if bImport then
		local fl = file.Find("zsbots/AI_*.txt","DATA")
		if fl then
			for i=1, #fl do
				DComboBox:AddChoice(string.sub(fl[i],4,-5),fl[i])
			end
		end
		T_ComboList = nil
	elseif not ZSBOTAI.MapList then
		PathEdit.StartMsg(6)
		net.WriteUInt(0,2)
		net.SendToServer()
		T_ComboList = DComboBox
	else
		for i=1, #ZSBOTAI.MapList do
			DComboBox:AddChoice(ZSBOTAI.MapList[i],i)
		end
		T_ComboList = nil
	end

	local DermaButton = vgui.Create("DButton",frame)
	DermaButton:SetText("Submit")
	DermaButton:SetSize(95,20)
	DermaButton:AlignBottom(32)
	DermaButton:CenterHorizontal()
	DermaButton.DoClick = function()
		local a,b = DComboBox:GetSelected()
		if not b then return end

		if bImport then
			local str = file.Read("zsbots/"..b)
			if str then
				str = util.Compress(str)
				PathEdit.StartMsg(6)
				net.WriteUInt(1,2)
				net.WriteString(a)
				net.WriteUInt(#str,20)
				net.WriteData(str,#str)
				net.SendToServer()
			end
		else
			PathEdit.StartMsg(6)
			net.WriteUInt(2,2)
			net.WriteString(ZSBOTAI.MapList[b])
			net.SendToServer()
		end
		frame:Close()
	end
end

function PathEdit.ServerPathFilesDone()
	if IsValid(T_ComboList) then
		for i=1, #ZSBOTAI.MapList do
			T_ComboList:AddChoice(ZSBOTAI.MapList[i],i)
		end
	end
end

-- Reachflags that don't pair together!
local REACHTYPE_Teleport = ZSBOTAI.PATH_ReachFlags.Teleport
local REACHTYPE_Fly = ZSBOTAI.PATH_ReachFlags.Fly
local REACHTYPE_Humans = ZSBOTAI.PATH_ReachFlags.Humans
local REACHTYPE_Zombies = ZSBOTAI.PATH_ReachFlags.Zombies
local TP_Pairs = bit.bor(ZSBOTAI.PATH_ReachFlags.Headcrab,ZSBOTAI.PATH_ReachFlags.Leap,ZSBOTAI.PATH_ReachFlags.Climb,ZSBOTAI.PATH_ReachFlags.Door,ZSBOTAI.PATH_ReachFlags.NoStrafeTo)
local Flying_Pairs = bit.bor(ZSBOTAI.PATH_ReachFlags.Headcrab,ZSBOTAI.PATH_ReachFlags.Leap,ZSBOTAI.PATH_ReachFlags.Climb,ZSBOTAI.PATH_ReachFlags.Humans)
local Human_Pairs = bit.bor(ZSBOTAI.PATH_ReachFlags.Headcrab,ZSBOTAI.PATH_ReachFlags.Leap,ZSBOTAI.PATH_ReachFlags.Climb,ZSBOTAI.PATH_ReachFlags.Fly,ZSBOTAI.PATH_ReachFlags.Zombies)

function SWEP:HandleHumanMenu()
	if PathMenu and IsValid(PathMenu) then
		if PathMenu:IsVisible() then
			return
		end
		PathMenu:Show()
		PathMenu:CenterVertical()
		PathMenu:AlignRight()
		PathMenu.DC_Ghost:SetValue(MySelf:GetMoveType()==MOVETYPE_NOCLIP and 1 or 0)
	else
		local DermaPanel = vgui.Create( "DFrame" )
		PathMenu = DermaPanel
		DermaPanel:ShowCloseButton(false)
		DermaPanel:SetSize( 200, 400 )
		DermaPanel:CenterVertical()
		DermaPanel:AlignRight()
		DermaPanel:SetTitle("Path Edit Tool")
		DermaPanel:SetSkin("Default")
		DermaPanel:SetDeleteOnClose(false)
		DermaPanel:SetDraggable( false )
		DermaPanel.StartChecking = 0
		DermaPanel.Think = function( d )
			if RealTime() >= d.StartChecking and not MySelf:KeyDown(GAMEMODE.MenuKey) then
				d:Close()
			end
		end
		DermaPanel.OnClose = function( d )
			PrevMX,PrevMY = input.GetCursorPos()
		end

		AddMidLabel(DermaPanel,"Path edit mode:")

		local DComboBox = vgui.Create( "DComboBox", DermaPanel )
		DComboBox:SetSize( 90, 20 )
		DComboBox:Dock(TOP)
		DComboBox:SetSortItems(false)
		DComboBox:SetValue( EditModeNames[PathEdit.Mode] )
		for i=1, #EditModeNames do
			DComboBox:AddChoice( EditModeNames[i], nil, PathEdit.Mode==i )
		end
		DComboBox.OnSelect = function( panel, index, value )
			ZSBOTAI.ResetSelection()
			PathEdit.Mode = index
			for i=1, #PathMenu.Pages do
				PathMenu.Pages[i]:SetVisible(index==i)
			end
		end

		AddMidLabel(DermaPanel,"Path draw distance:")

		DComboBox = vgui.Create( "DComboBox", DermaPanel )
		DComboBox:SetSize( 90, 20 )
		DComboBox:Dock(TOP)
		DComboBox:SetSortItems(false)
		local matched = 1
		for i=1, #DrawDistances do
			local bSelected = false
			if DrawDistances[i].D==ZSBOTAI.PathDrawDistance then
				matched = i
				bSelected = true
			end
			DComboBox:AddChoice( DrawDistances[i].T, nil, bSelected )
		end
		DComboBox:SetValue( DrawDistances[matched].T )
		DComboBox.OnSelect = function( panel, index, value )
			ZSBOTAI.PathDrawDistance = DrawDistances[index].D
		end

		DermaPanel.DC_Ghost = AddCheckbox(DermaPanel,"Ghost Mode", MySelf:GetMoveType()==MOVETYPE_NOCLIP and 1 or 0, function(val)
			PathEdit.StartMsg(1)
			net.WriteBool(val)
			net.SendToServer()
		end)
		AddCheckbox(DermaPanel,"Hide Air Paths", 0, function(val)
			ZSBOTAI.HideAirPaths = val
		end)
		AddCheckbox(DermaPanel,"Hide Volumes", 0, function(val)
			ZSBOTAI.HideVolumes = val
		end)
		AddCheckbox(DermaPanel,"Hide Sublevel Paths", 0, function(val)
			ZSBOTAI.HideSubPaths = val
		end)
		AddCheckbox(DermaPanel,"Draw Through Walls", 0, function(val)
			ZSBOTAI.PathIgnoreZ = val
		end)

		local pager = vgui.Create( "DPanel", DermaPanel )
		pager:Dock(FILL)
		pager.Paint = function( p, width, height )
			draw.RoundedBox( 8, 0, 0, width, height, Color( 4, 4, 32 ) )
		end
		local pga = {}

		for i=1, #EditModeNames do
			pga[i] = vgui.Create("DPanel",pager)
			pga[i].Paint = function( p, width, height )
			end
		end
		DermaPanel.Pages = pga

		pager.PerformLayout = function( pg, width, height )
			for i=1, #pga do
				pga[i]:SetPos(3,2)
				pga[i]:SetSize(width-6,height-4)
			end
		end

		-- Create nodes submenu:
		AddMidLabel(pga[1],"Path type:")

		DComboBox = vgui.Create("DComboBox", pga[1])
		DComboBox:SetSize( 90, 20 )
		DComboBox:Dock(TOP)
		DComboBox:SetSortItems(false)
		DComboBox:SetValue( PathTypes[PathEdit.NodeType] )
		for i=1, #PathTypes do
			DComboBox:AddChoice( PathTypes[i], nil, PathEdit.NodeType==i )
		end
		local AP_Check,AP_ZSpawn
		local OLD_AP_Value = false
		DComboBox.OnSelect = function( panel, index, value )
			SubRoutine = true
			PathEdit.NodeType = index
			if index==3 then -- Ladder node
				PathEdit.bNoAutoPath = true
				AP_Check:SetValue(true)
				AP_Check:SetEnabled(false)
			else
				PathEdit.bNoAutoPath = OLD_AP_Value
				AP_Check:SetValue(OLD_AP_Value)
				AP_Check:SetEnabled(true)
			end
			AP_ZSpawn:SetMouseInputEnabled(index==5) -- Z-Spawn node
			SubRoutine = false
		end

		AddMidLabel(pga[1],"Path flags:")
		AP_Check = AddCheckbox(pga[1],"No Auto-Path", 0, function(val)
			PathEdit.bNoAutoPath = val
			OLD_AP_Value = val
		end)

		AddMidLabel(pga[1],"Z-Spawn objective/wave:")
		AP_ZSpawn = vgui.Create("DNumSlider",pga[1])
		AP_ZSpawn:SetText(GAMEMODE.IsObjectiveMap and "Obj num" or "Wave")
		AP_ZSpawn:SetMin(GAMEMODE.IsObjectiveMap and 0 or 1)
		AP_ZSpawn:SetMax(GAMEMODE.IsObjectiveMap and 128 or 10)
		AP_ZSpawn:SetDecimals(0)
		AP_ZSpawn:SetValue(GAMEMODE.IsObjectiveMap and 0 or 1)
		AP_ZSpawn:Dock(TOP)
		AP_ZSpawn:SetTooltip(GAMEMODE.IsObjectiveMap and "Objective it's enabled on\n(0 = current obj)" or "Starting from this wave its enabled!\n(it gets overridden by higher wave)")
		AP_ZSpawn:SetMouseInputEnabled(false)
		AP_ZSpawn:GetTextArea():SetTextColor(COLOR_WHITE)
		PathEdit.AP_ZSpawn = AP_ZSpawn

		-- Edit reachspecs submenu
		AddMidLabel(pga[2],"Route flags:")
		local ctab = {}
		for i=1, #ReachFlags do
			local iflag = ReachFlags[i][2]
			ctab[i] = AddCheckbox(pga[2],ReachFlags[i][1], 0, function(val)
				PathEdit.RouteFlags = (val and bit.bor(PathEdit.RouteFlags,iflag) or bit.band(PathEdit.RouteFlags,bit.bnot(iflag)))
				if val then
					if iflag==REACHTYPE_Teleport then -- Disable all other flags that don't go with this one.
						PathEdit.RouteFlags = bit.band(PathEdit.RouteFlags,bit.bnot(TP_Pairs))
						for j=1, #ReachFlags do
							if bit.band(ReachFlags[j][2],TP_Pairs)~=0 then
								ctab[j]:SetValue(false)
							end
						end
					elseif iflag==REACHTYPE_Fly then
						PathEdit.RouteFlags = bit.band(PathEdit.RouteFlags,bit.bnot(Flying_Pairs))
						for j=1, #ReachFlags do
							if bit.band(ReachFlags[j][2],Flying_Pairs)~=0 then
								ctab[j]:SetValue(false)
							end
						end
					elseif iflag==REACHTYPE_Humans then
						PathEdit.RouteFlags = bit.band(PathEdit.RouteFlags,bit.bnot(Human_Pairs))
						for j=1, #ReachFlags do
							if bit.band(ReachFlags[j][2],Human_Pairs)~=0 then
								ctab[j]:SetValue(false)
							end
						end
					elseif iflag==REACHTYPE_Zombies then
						PathEdit.RouteFlags = bit.band(PathEdit.RouteFlags,bit.bnot(REACHTYPE_Humans))
						for j=1, #ReachFlags do
							if ReachFlags[j][2]==REACHTYPE_Humans then
								ctab[j]:SetValue(false)
								break
							end
						end
					else
						if bit.band(PathEdit.RouteFlags,TP_Pairs)~=0 and bit.band(PathEdit.RouteFlags,REACHTYPE_Teleport)~=0 then -- Disable teleport flag.
							PathEdit.RouteFlags = bit.band(PathEdit.RouteFlags,bit.bnot(REACHTYPE_Teleport))
							for j=1, #ReachFlags do
								if ReachFlags[j][2]==REACHTYPE_Teleport then
									ctab[j]:SetValue(false)
									break
								end
							end
						end
						if bit.band(PathEdit.RouteFlags,Flying_Pairs)~=0 and bit.band(PathEdit.RouteFlags,REACHTYPE_Fly)~=0 then
							PathEdit.RouteFlags = bit.band(PathEdit.RouteFlags,bit.bnot(REACHTYPE_Fly))
							for j=1, #ReachFlags do
								if ReachFlags[j][2]==REACHTYPE_Fly then
									ctab[j]:SetValue(false)
									break
								end
							end
						end
						if bit.band(PathEdit.RouteFlags,Human_Pairs)~=0 and bit.band(PathEdit.RouteFlags,REACHTYPE_Humans)~=0 then
							PathEdit.RouteFlags = bit.band(PathEdit.RouteFlags,bit.bnot(REACHTYPE_Humans))
							for j=1, #ReachFlags do
								if ReachFlags[j][2]==REACHTYPE_Humans then
									ctab[j]:SetValue(false)
									break
								end
							end
						end
					end
				end
			end)
		end

		-- Volumes submenu
		AddMidLabel(pga[4],"Volume type:")

		local ObjNumSlider
		DComboBox = vgui.Create("DComboBox", pga[4])
		DComboBox:SetSize( 90, 20 )
		DComboBox:Dock(TOP)
		DComboBox:SetValue( ZSBOTAI.CheckpointTypes[PathEdit.VolumeType+1] )
		for i=1, #ZSBOTAI.CheckpointTypes do
			DComboBox:AddChoice( ZSBOTAI.CheckpointTypes[i], (i-1), PathEdit.VolumeType==(i-1) )
		end
		DComboBox.OnSelect = function( panel, index, value, data )
			PathEdit.VolumeType = data
			if ObjNumSlider then
				ObjNumSlider:SetMouseInputEnabled(data==-1)
			end
		end
		if GAMEMODE.IsObjectiveMap then
			DComboBox:AddChoice( "Objective Checkpoint", -1, PathEdit.VolumeType==-1 )

			ObjNumSlider = vgui.Create("DNumSlider",pga[4])
			ObjNumSlider:SetText("Obj num")
			ObjNumSlider:SetMin(0)
			ObjNumSlider:SetMax(128)
			ObjNumSlider:SetDecimals(0)
			ObjNumSlider:SetValue(PathEdit.ObjNum)
			ObjNumSlider:Dock(TOP)
			ObjNumSlider:SetMouseInputEnabled(PathEdit.VolumeType==-1)
			ObjNumSlider:GetTextArea():SetTextColor(COLOR_WHITE)
			ObjNumSlider.OnValueChanged = function( sl, val )
				PathEdit.ObjNum = math.floor(val+0.5)
			end
		end

		-- Navmesh submenu:
		AddButton(pga[5],"Auto-Generate NavMesh","This will generate a nav mesh for this map",function()
			ZS_Groups.ShowYesNoMenu("!!!WARNING!!!","Doing this will freeze server for\n~1 min and restart map.\nONLY do this on DEBUG server!\nContinue?",function()
				PathEdit.StartMsg(5)
				net.WriteUInt(0,2)
				net.SendToServer()
			end)
		end)
		AddButton(pga[5],"Navigate a nav area","Seek out the entire nav area starting from your crosshair location.",function()
			if not PathEdit.Aim then
				chat.AddText(COLOR_RED,"Can't navigate nav area: Aiming at nothing!")
				return
			end
			PathEdit.StartMsg(5)
			net.WriteUInt(1,2)
			net.WriteVector(PathEdit.Aim)
			net.SendToServer()
		end)
		AddCheckbox(pga[5],"Use Triangle Mesh", 0, function(val)
			PathEdit.UseTris = val
		end)
		AddCheckbox(pga[5],"Force flat Mesh", 0, function(val)
			PathEdit.ForceFlat = val
		end)

		-- Settings submenu:
		AddButton(pga[6],"Download data","Download from server map path data",function()
			MakeExportMenu(false)
		end)
		AddButton(pga[6],"Upload data","Upload to server map path data",function()
			MakeExportMenu(true)
		end)
		AddButton(pga[6],"Good Cade","Aim at a prop with a good cade to make bots remember it",function()
			PathEdit.StartMsg(6)
			net.WriteUInt(3,2)
			net.SendToServer()
		end)

		for i=2, #EditModeNames do
			pga[i]:SetVisible(false)
		end

		DermaPanel:MakePopup()

		PrevMX = ScrW()-100
		PrevMY = ScrH()*0.5
	end

	PathMenu.StartChecking = RealTime()+0.25
	input.SetCursorPos(PrevMX,PrevMY)
end
