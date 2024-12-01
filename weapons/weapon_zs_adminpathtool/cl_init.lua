include("shared.lua")

local PathEdit = ZSBOTAI.PATH_EDIT_DATA

include("cl_menu.lua")

SWEP.Author = "Marco"
SWEP.Instructions = "Create AI network."
SWEP.Contact = ""
SWEP.Purpose = ""

SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

function ZSBOTAI.ResetSelection()
	PathEdit.Pending = nil
	PathEdit.SPending = nil
end

function ZSBOTAI.EndPathEditor()
	ZSBOTAI.ResetSelection()
end

function SWEP:Deploy()
	if IsFirstTimePredicted() then
		ZSBOTAI.ResetSelection()
		ZSBOTAI.DrawAIPaths()
		chat.AddText(COLOR_WHITE,"Use '",COLOR_YELLOW,"zs_admin_purgepaths",COLOR_WHITE,"' to purge all paths")
	end
end

function PathEdit.StartMsg( code )
	net.Start("zspath_func")
	net.WriteUInt(code,3)
end

local function WriteXLVector( v )
	net.WriteFloat(v.x)
	net.WriteFloat(v.y)
	net.WriteFloat(v.z)
end

local DeployTypes = {
	[1] = ZSBOTAI.PATH_Type.Walk,
	[2] = ZSBOTAI.PATH_Type.Fly,
	[3] = ZSBOTAI.PATH_Type.Ladder,
	[4] = ZSBOTAI.PATH_Type.Objective,
	[5] = ZSBOTAI.PATH_Type.NoQuitNode,
	[6] = ZSBOTAI.PATH_Type.ZSpawn,
}

function SWEP:DeployNode( Mode )
	if not IsFirstTimePredicted() then return end

	if PathEdit.Mode==1 then
		if Mode==0 or Mode==2 then
			local v
			local bWater
			local ty = PathEdit.NodeType
			if Mode==0 and ty~=2 then
				if not PathEdit.Aim then
					chat.AddText(COLOR_RED,"Can't deploy node here: hitting nothing")
					return
				end
				if PathEdit.bError then
					chat.AddText(COLOR_RED,"Can't deploy node here: hitting a wall/ceiling")
					return
				end
				v = PathEdit.Aim
				bWater = PathEdit.bWater
			else
				v = MySelf:GetPos()
				bWater = (MySelf:WaterLevel()>=2)
			end

			PathEdit.StartMsg(0)
			net.WriteBool(false)
			if ty<=2 and bWater then
				ty = ZSBOTAI.PATH_Type.Swim
			else
				ty = DeployTypes[ty]
			end
			net.WriteUInt(ty,ZSBOTAI.PATH_TypeNetworkSize)

			ty = (PathEdit.bNoAutoPath and 1 or 0)
			if PathEdit.NodeType==3 then -- Ladder, force no auto path
				ty = 1
			end
			net.WriteUInt(ty,ZSBOTAI.PATH_ExTypeNetworkSize)
			WriteXLVector(v)
			if PathEdit.NodeType==5 then -- Z-Spawn
				net.WriteUInt(math.floor(PathEdit.AP_ZSpawn:GetValue()+0.5),8)
				net.WriteUInt(math.Round(EyeAngles().yaw * 0.7083),8)
			end
			net.SendToServer()
		elseif Mode==1 then
			local bCam = MySelf:KeyDown(IN_SPEED)
			if not bCam and not PathEdit.Aim then
				chat.AddText(COLOR_RED,"Can't delete node: Aiming at nothing!")
				return
			end
			local inode = ZSBOTAI.FindPathAt(bCam and MySelf:GetPos() or PathEdit.Aim)
			if not inode then
				chat.AddText(COLOR_RED,"Can't delete node: No nodes found nearby!")
				return
			end

			PathEdit.StartMsg(0)
			net.WriteBool(true)
			PathEdit.SendNode(inode)
			net.SendToServer()
		end
	elseif PathEdit.Mode==2 then
		if Mode==2 then return end -- ignore reload.

		if PathEdit.Pending then
			local onode
			if MySelf:KeyDown(IN_SPEED) then
				onode = ZSBOTAI.FindPathAt(MySelf:GetPos())
			else
				onode = PathEdit.Target
			end

			if not onode then
				chat.AddText(COLOR_RED,"Can't edit route: No nodes found nearby!")
				PathEdit.Pending = nil
				return
			end
			if onode==PathEdit.Pending then
				chat.AddText(COLOR_RED,"Can't edit route: Can't perform action on same node!")
				PathEdit.Pending = nil
				return
			end

			PathEdit.StartMsg(3)
			PathEdit.SendNode(PathEdit.Pending)
			PathEdit.SendNode(onode)
			if Mode==0 then
				net.WriteBool(true)
				net.WriteUInt(PathEdit.RouteFlags,ZSBOTAI.PATH_ReachNetworkSize)
			else
				net.WriteBool(false)
			end
			net.SendToServer()
			PathEdit.Pending = nil
		else
			if MySelf:KeyDown(IN_SPEED) then
				PathEdit.Pending = ZSBOTAI.FindPathAt(MySelf:GetPos())
			else
				PathEdit.Pending = PathEdit.Target
			end

			if not PathEdit.Pending then
				chat.AddText(COLOR_RED,"Can't edit route: No nodes found nearby!")
			end
		end
	elseif PathEdit.Mode==3 then
		if PathEdit.Pending then
			if Mode==1 then
				PathEdit.Pending = nil
				return
			end
			local v
			if Mode==0 then
				if PathEdit.bError then
					chat.AddText(COLOR_RED,"Can't move node: hitting a wall/ceiling")
					return
				end
				v = PathEdit.Aim
				if not v then
					chat.AddText(COLOR_RED,"Can't move node: Aiming at nothing!")
					return
				end
			else
				v = MySelf:GetPos()
			end
			PathEdit.StartMsg(2)
			PathEdit.SendNode(PathEdit.Pending)
			WriteXLVector(v)
			net.SendToServer()
			PathEdit.Pending = nil
		else
			if Mode==0 then
				PathEdit.Pending = PathEdit.Target
			elseif Mode==2 then
				PathEdit.Pending = ZSBOTAI.FindPathAt(MySelf:GetPos())
			else
				return
			end

			if not PathEdit.Pending then
				chat.AddText(COLOR_RED,"Can't select node: No nodes found nearby!")
			end
		end
	elseif PathEdit.Mode==4 then
		if PathEdit.Pending then
			if Mode==1 then
				PathEdit.Pending = nil
				return
			end
			if Mode==2 then return end

			local v
			if MySelf:KeyDown(IN_SPEED) then
				v = EyePos()
			else
				if not PathEdit.Aim then
					chat.AddText(COLOR_RED,"Can't create volume: Aiming at nothing!")
					return
				end
				v = PathEdit.Aim
			end
			PathEdit.StartMsg(4)
			net.WriteBool(false)
			WriteXLVector(PathEdit.Pending)
			WriteXLVector(v)
			if PathEdit.VolumeType==-1 then
				net.WriteBool(true)
				if PathEdit.ObjNum==0 then
					net.WriteBool(false)
				else
					net.WriteBool(true)
					net.WriteUInt(PathEdit.ObjNum-1,8)
				end
			else
				net.WriteBool(false)
				net.WriteUInt(PathEdit.VolumeType,6)
			end
			net.SendToServer()
			PathEdit.Pending = nil
		elseif Mode==0 then
			if not PathEdit.Aim then
				chat.AddText(COLOR_RED,"Can't create volume: Aiming at nothing!")
				return
			end
			PathEdit.Pending = PathEdit.Aim
		elseif Mode==2 then
			if not PathEdit.Aim then
				chat.AddText(COLOR_RED,"Can't delete volume: Aiming at nothing!")
				return
			end
			PathEdit.StartMsg(4)
			net.WriteBool(true)
			net.WriteVector(PathEdit.Aim)
			net.SendToServer()
		end
	elseif PathEdit.Mode==5 then
		if PathEdit.Pending then
			if Mode==1 then
				PathEdit.Pending = nil
				PathEdit.SPending = nil
				return
			end
			if Mode==2 then return end

			if isnumber(PathEdit.Pending) then
				if not PathEdit.Aim then
					chat.AddText(COLOR_RED,"Can't edit nav area: Aiming at nothing!")
					return
				end
				if PathEdit.bError then
					chat.AddText(COLOR_RED,"Can't edit nav area: hitting a wall/ceiling")
					return
				end

				if PathEdit.SPending then
					PathEdit.StartMsg(5)
					net.WriteUInt(2,2)
					net.WriteBool(true)
					PathEdit.SendNode(PathEdit.Pending)
					WriteXLVector(PathEdit.SPending)
					WriteXLVector(PathEdit.Aim)
					net.SendToServer()
					PathEdit.Pending = nil
					PathEdit.SPending = nil
				else
					PathEdit.SPending = PathEdit.Aim
				end
				return
			end

			if not PathEdit.Aim then
				chat.AddText(COLOR_RED,"Can't create new nav area: Aiming at nothing!")
				return
			end
			if PathEdit.bError then
				chat.AddText(COLOR_RED,"Can't create new nav area: hitting a wall/ceiling")
				return
			end

			if PathEdit.UseTris then
				if PathEdit.SPending then
					PathEdit.StartMsg(5)
					net.WriteUInt(2,2)
					net.WriteBool(false)
					net.WriteBool(true)
					net.WriteUInt(PathEdit.TriSide,2)
					WriteXLVector(PathEdit.Pending)
					WriteXLVector(PathEdit.SPending)
					net.SendToServer()
					PathEdit.Pending = nil
					PathEdit.SPending = nil
				else
					PathEdit.SPending = PathEdit.Aim
				end
				return
			end

			PathEdit.StartMsg(5)
			net.WriteUInt(2,2)
			net.WriteBool(false)
			net.WriteBool(false)
			WriteXLVector(PathEdit.Pending)
			WriteXLVector(PathEdit.Aim)
			net.SendToServer()
			PathEdit.Pending = nil
		elseif Mode==0 then
			if not PathEdit.Aim then
				chat.AddText(COLOR_RED,"Can't create new nav area: Aiming at nothing!")
				return
			end
			if PathEdit.bError then
				chat.AddText(COLOR_RED,"Can't create new nav area: hitting a wall/ceiling")
				return
			end

			PathEdit.Pending = PathEdit.Aim
		elseif Mode==1 then
			if not PathEdit.Target then
				chat.AddText(COLOR_RED,"Can't delete nav area: none found nearby!")
				return
			end

			PathEdit.StartMsg(0)
			net.WriteBool(true)
			PathEdit.SendNode(PathEdit.Target)
			net.SendToServer()
		elseif Mode==2 then
			if not PathEdit.Target then
				chat.AddText(COLOR_RED,"Can't edit nav area: none found nearby!")
				return
			end
			PathEdit.Pending = PathEdit.Target
		end
	end
end

function SWEP:DrawWeaponSelection(...)
	return self:BaseDrawWeaponSelection(...)
end

local yy,ys
local fnt

local function DrawStrLine( txt, col )
	draw.SimpleTextBlurry(txt, fnt, 15, yy, col or COLOR_WHITE)
	yy = yy+ys
end

function SWEP:DrawHUD()
	fnt = "ZSHUDFontTiny-"..GAMEMODE.MainFont
	yy = 120
	ys = draw.GetFontHeight(fnt)
	local bWater = MySelf:WaterLevel()>=2

	if PathEdit.Mode==1 then
		if PathEdit.NodeType<=2 and bWater then -- Ground/Air
			DrawStrLine("Forced Water Path!",COLOR_BLUE)
		end
		if PathEdit.NodeType==2 then
			DrawStrLine("[Fire] - Deploy flying node at camera location",COLOR_WHITE)
		else
			DrawStrLine("[Fire] - Deploy node",COLOR_WHITE)
			DrawStrLine("[Reload] - Deploy node at camera location",COLOR_WHITE)
		end
		DrawStrLine("[AltFire] - Delete node",COLOR_RED)
		DrawStrLine("[Sprint]+[AltFire] - Delete node at camera location",COLOR_RED)
	elseif PathEdit.Mode==2 then
		if PathEdit.Pending then
			DrawStrLine("[Fire] - Create END node route",COLOR_LIMEGREEN)
			DrawStrLine("[Sprint]+[Fire] - Create END node route at camera location",COLOR_LIMEGREEN)
			DrawStrLine("[AltFire] - Delete END node route",COLOR_RED)
			DrawStrLine("[Sprint]+[AltFire] - Delete END node route at camera location",COLOR_RED)
		else
			DrawStrLine("[Fire/AltFire] - Select START node",COLOR_WHITE)
			DrawStrLine("[Sprint]+[Fire/AltFire] - Select START node at camera location",COLOR_WHITE)
		end
	elseif PathEdit.Mode==3 then
		if PathEdit.Pending then
			DrawStrLine("[Fire] - Move node to crosshair location",COLOR_LIMEGREEN)
			DrawStrLine("[Reload] - Move node to camera location",COLOR_LIMEGREEN)
			DrawStrLine("[AltFire] - Abort selection",COLOR_RED)
		else
			DrawStrLine("[Fire] - Select node",COLOR_WHITE)
			DrawStrLine("[Reload] - Select node at camera location",COLOR_WHITE)
		end
	elseif PathEdit.Mode==4 then
		if PathEdit.Pending then
			DrawStrLine("[Fire] - Add checkpoint END point",COLOR_LIMEGREEN)
			DrawStrLine("[Sprint]+[Fire] - Add checkpoint END point at camera location",COLOR_LIMEGREEN)
			DrawStrLine("[AltFire] - Abort new checkpoint",COLOR_RED)
		else
			DrawStrLine("[Fire] - Add checkpoint START point",COLOR_WHITE)
			DrawStrLine("[Reload] - Delete checkpoint",COLOR_RED)
		end
	elseif PathEdit.Mode==5 then
		if PathEdit.Pending then
			if isnumber(PathEdit.Pending) then
				if PathEdit.SPending then
					DrawStrLine("[Fire] - Assign nav area END point",COLOR_LIMEGREEN)
				else
					DrawStrLine("[Fire] - Assign nav area START point",COLOR_LIMEGREEN)
				end
				DrawStrLine("[AltFire] - Abort edit nav area",COLOR_RED)
			else
				if PathEdit.SPending and PathEdit.UseTris then
					DrawStrLine("[Fire] - Assign which side of polygon to use",COLOR_LIMEGREEN)
				else
					DrawStrLine("[Fire] - Assign new nav area END point",COLOR_LIMEGREEN)
				end
				DrawStrLine("[AltFire] - Abort new nav area",COLOR_RED)
			end
		else
			DrawStrLine("[Fire] - Add new nav area START point",COLOR_WHITE)
			DrawStrLine("[AltFire] - Delete nav area",COLOR_RED)
			DrawStrLine("[Reload] - Edit nav area",COLOR_YELLOW)
		end
	end
end

net.Receive("zspath_func", function(length)
	local code = net.ReadUInt(3)
	if code==0 then
		notification.AddLegacy("Couldn't perform action: Invalid node", NOTIFY_ERROR, 2)
		surface.PlaySound("buttons/button15.wav")
	elseif code==1 then
		if not ZSBOTAI.MapList then
			ZSBOTAI.MapList = {}
			while net.ReadBool() do
				ZSBOTAI.MapList[#ZSBOTAI.MapList+1] = net.ReadString()
			end
			PathEdit.ServerPathFilesDone()
		end
	elseif code==2 then
		local mapname = net.ReadString()
		local num = net.ReadUInt(20)
		local data = net.ReadData(num)
		data = util.Decompress(data)
		file.Write("zsbots/AI_"..mapname..".txt",data)
		chat.AddText(COLOR_GREEN,"Received map data file from server for: "..mapname)
	end
end)
