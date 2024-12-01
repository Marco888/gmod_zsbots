AddCSLuaFile("cl_init.lua")
AddCSLuaFile("cl_menu.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

util.AddNetworkString("zspath_func")

function SWEP:Deploy()
	local owner = self:GetOwner()
	if owner and not owner:IsBot() then
		ZSBOTAI.NetworkPathList(owner)
	end
end

function SWEP:DeployNode( Mode )
end

local function ReadXLVector()
	return Vector(net.ReadFloat(),net.ReadFloat(),net.ReadFloat())
end

local function StartMessage( code )
	net.Start("zspath_func")
	net.WriteUInt(code,3)
end

local function SendNodeError( pl )
	StartMessage(0)
	net.Send(pl)
end

local function CheckAdminAccess( pl )
	if not hook.Run("PlayerIsSuperAdmin",pl) then
		pl:PrintMessage(HUD_PRINTTALK,"You don't have permission to do this!")
		return false
	end
	return true
end

local LoadedMapList = false
local NODETYPE_ZSpawn = ZSBOTAI.PATH_Type.ZSpawn

net.Receive("zspath_func", function(length, pl)
	local w = pl:GetActiveWeapon()
	if not IsValid(w) or w:GetClass()~="weapon_zs_adminpathtool" then return end
	
	local code = net.ReadUInt(3)
	if code==0 then
		if net.ReadBool() then
			local node = ZSBOTAI.ReadNode()
			if node then
				ZSBOTAI.RemovePathNode(node)
			else
				SendNodeError(pl)
			end
		else
			local ntype = net.ReadUInt(ZSBOTAI.PATH_TypeNetworkSize)
			local extype = net.ReadUInt(ZSBOTAI.PATH_ExTypeNetworkSize)
			local nodepos = ReadXLVector()
			local objnum,ydir
			if ntype==NODETYPE_ZSpawn then
				objnum = net.ReadUInt(8)
				ydir = net.ReadUInt(8)
			end
			local err = ZSBOTAI.DeployPathNode(nodepos,ntype,extype,ydir,objnum)
			
			if err and isstring(err) then
				pl:PrintMessage(HUD_PRINTTALK,"Can't deploy node: "..err)
			end
		end
	elseif code==1 then
		if net.ReadBool() then
			pl:SetMoveType(MOVETYPE_NOCLIP)
			pl:SetInvisible(true)
			pl.ULXHasGod = true
		else
			pl:SetMoveType(MOVETYPE_WALK)
			pl:SetInvisible(false)
			pl.ULXHasGod = nil
		end
	elseif code==2 then
		local node = ZSBOTAI.ReadNode()
		if not node then
			SendNodeError(pl)
			return
		end
		local nodepos = ReadXLVector()
		ZSBOTAI.MovePathNode(node,nodepos)
	elseif code==3 then
		local node = ZSBOTAI.ReadNode()
		local onode = ZSBOTAI.ReadNode()
		if not node or not onode then
			SendNodeError(pl)
			return
		end
		local err
		if net.ReadBool() then
			local rflags = net.ReadUInt(ZSBOTAI.PATH_ReachNetworkSize)
			err = ZSBOTAI.EditReachSpec(node,onode,true,rflags)
		else
			err = ZSBOTAI.EditReachSpec(node,onode,false)
		end
		
		if err then
			pl:PrintMessage(HUD_PRINTTALK,"Can't edit reachspecs: "..err)
		end
	elseif code==4 then
		if net.ReadBool() then
			local v = net.ReadVector()
			ZSBOTAI.DeleteCheckpoint(v)
		else
			local a = ReadXLVector()
			local b = ReadXLVector()
			local ix
			local bCheck = net.ReadBool()
			if bCheck then
				if net.ReadBool() then
					ix = net.ReadUInt(8)
				end
			else
				ix = net.ReadUInt(6)
			end
			ZSBOTAI.DeployVolume(a,b,ix,not bCheck)
		end
	elseif code==5 then
		local s = net.ReadUInt(2)
		if s==0 then
			if not CheckAdminAccess(pl) then return end

			DEBUG_MessageDev(pl:Name().." ("..pl:SteamID()..") generated a new navmesh for this map!",false,1,true)
			navmesh.ClearWalkableSeeds()
			navmesh.AddWalkableSeed(pl:GetPos(),Vector(0,0,1))
			navmesh.BeginGeneration()
		elseif s==1 then
			local v = net.ReadVector()
			local err = ZSBOTAI.FindNavArea(v)
			if err then
				pl:PrintMessage(HUD_PRINTTALK,"Can't navigate nav area: "..err)
			end
		elseif s==2 then
			if net.ReadBool() then
				local node = ZSBOTAI.ReadNode()
				if not node then
					SendNodeError(pl)
					return
				end
				local a = ReadXLVector()
				local b = ReadXLVector()

				ZSBOTAI.MovePathNode(node,a,b)
			else
				local TriSide
				if net.ReadBool() then
					TriSide = net.ReadUInt(2)
				end
				local a = ReadXLVector()
				local b = ReadXLVector()
				local err = ZSBOTAI.DeployNavArea(a,b,false,TriSide)
				if err then
					pl:PrintMessage(HUD_PRINTTALK,"Can't add nav area: "..err)
				end
			end
		end
	elseif code==6 then
		local s = net.ReadUInt(2)
		if s==0 then
			if not LoadedMapList then
				LoadedMapList = {}
				local fl = file.Find("AI_*.txt","DATA")
				if fl then
					for i=1, #fl do
						LoadedMapList[i] = string.sub(fl[i],4,-5)
					end
				end
			end
			StartMessage(1)
			for i=1, #LoadedMapList do
				net.WriteBool(true)
				net.WriteString(LoadedMapList[i])
			end
			net.WriteBool(false)
			net.Send(pl)
		elseif s==1 then
			if not CheckAdminAccess(pl) then return end

			local mapname = net.ReadString()
			local num = net.ReadUInt(20)
			local data = net.ReadData(num)
			data = util.Decompress(data)
			DEBUG_MessageDev(pl:Nick().." ("..pl:SteamID()..") uploaded AI data for: "..mapname,false,0,true)
			file.Write("AI_"..mapname..".txt",data)

			if mapname==string.lower(game.GetMap()) then -- reload current map
				ZSBOTAI.ReloadPaths()
			end
		elseif s==2 then
			if not CheckAdminAccess(pl) then return end

			local mapname = net.ReadString()
			local str = file.Read("AI_"..mapname..".txt")
			if str then
				DEBUG_MessageDev(pl:Nick().." ("..pl:SteamID()..") downloaded AI data for: "..mapname,false,0,true)
				str = util.Compress(str)
				StartMessage(2)
				net.WriteString(mapname)
				net.WriteUInt(#str,20)
				net.WriteData(str,#str) 
				net.Send(pl)
			end
		else
			local vStart = pl:EyePos()
			local tr = util.TraceLine({ start=vStart,endpos=vStart+(pl:GetAimVector() * 2048),filter=pl:GetMeleeFilter() })
			if not tr.Hit then
				pl:PrintMessage(HUD_PRINTTALK,"Can't save cade: Hit nothing!")
				return
			end
			local res,msg = ZSBOTAI.CheckActiveCades(tr.HitPos)
			if res==true then
				pl:PrintMessage(HUD_PRINTTALK,msg)
			else
				pl:PrintMessage(HUD_PRINTTALK,"Can't save cade: "..res)
			end
		end
	end
end)
