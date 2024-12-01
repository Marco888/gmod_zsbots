-- Bot cading handler, written by Marco
local GetPlayerTeam = GetPlayerTeam

if not file.Exists("zs_props", "DATA") then
	file.CreateDir("zs_props")
end

local CadeSerializeVer = 1
local CadeFileName = "zs_props/"..string.lower(game.GetMap())..".txt"

local MapCades = false

local CadingProps = {
	["func_physbox"]=true,
	["func_physbox_multiplayer"]=true,
	["prop_physics"]=true,
	["prop_physics_multiplayer"]=true,
	["prop_physics_override"]=true,
	["prop_door_rotating"]=true,
}

-- Shortcuts.
local BOT_MoveStuckTime = ZSBOTAI.AITable.MoveStuckTime
local BOT_AttackProp = ZSBOTAI.AITable.AttackProp
local BOT_SpecialPause = ZSBOTAI.AITable.SpecialPause

local E_GetPos = FindMetaTable("Entity").GetPos

local function BoundsOverlap( amin, amax, bmin, bmax, extent )
	if (amin.x-extent) > bmax.x or (bmin.x-extent) > amax.x or
		(amin.y-extent) > bmax.y or (bmin.y-extent) > amax.y or
		(amin.z-extent) > bmax.z or (bmin.z-extent) > amax.z then
		return false
	end
	return true
end

local function LoadMapCades()
	if MapCades then return end

	MapCades = {}

	local f = file.Open(CadeFileName,"rb","DATA")

	if f then
		local succ, err = pcall(function()
			local vertag = f:ReadByte()
			if vertag~=CadeSerializeVer then
				error("Cade data version mismatch ("..tostring(vertag).."/"..tostring(CadeSerializeVer)..")")
			end
			while f:Tell()<f:Size() do
				local cd = {}
				cd.Owner = f:ReadStr()
				cd.Bounds = {f:ReadVector(),f:ReadVector()}
				cd.Bounds[3] = ((cd.Bounds[1]+cd.Bounds[2])*0.5)
				local nump = f:ReadIndex()
				local props = {}
				cd.Props = props
				for i=1, nump do
					local p = {}
					props[i] = p
					p.Model = f:ReadStr()
					p.Pos = f:ReadVector()
					p.Ang = f:ReadAngle()
					p.Flags = f:ReadByte()
					local numn = f:ReadIndex()
					local nails = {}
					p.Nails = nails
					for j=1, numn do
						local n = {}
						nails[j] = n
						n.Pos = f:ReadVector()
						n.Ang = f:ReadAngle()
						n.Attach = f:ReadIndex()
					end
				end
				MapCades[#MapCades+1] = cd
			end
		end)
		f:Close()
		if not succ then
			DEBUG_MessageDev("WARNING: failed to load AI cade data: "..err,false,1)
			MapCades = {}
		end
	end
end

local function SaveMapCades()
	if not MapCades then return end

	local f = file.Open(CadeFileName,"wb","DATA")
	if not f then
		DEBUG_MessageDev("WARNING: failed to create AI cade data file at: "..CadeFileName,false,1)
		return
	end

	local succ, err = pcall(function()
		f:WriteByte(CadeSerializeVer) -- Write version
		for i=math.max(#MapCades-50,1), #MapCades do -- Don't save over 50 different cade types.
			local cd = MapCades[i]
			f:WriteStr(cd.Owner)
			f:WriteVector(cd.Bounds[1])
			f:WriteVector(cd.Bounds[2])
			f:WriteIndex(#cd.Props)
			for j=1, #cd.Props do
				local p = cd.Props[j]
				f:WriteStr(p.Model)
				f:WriteVector(p.Pos)
				f:WriteAngle(p.Ang)
				f:WriteByte(p.Flags)
				f:WriteIndex(#p.Nails)
				for z=1, #p.Nails do
					local n = p.Nails[z]
					f:WriteVector(n.Pos)
					f:WriteAngle(n.Ang)
					f:WriteIndex(n.Attach)
				end
			end
		end
	end)
	f:Close()
	if not succ then
		DEBUG_MessageDev("WARNING: failed to save AI cade data: "..err,false,1)
		MapCades = {}
	end
end

function ZSBOTAI.CheckActiveCades( pos )
	if not pos and not GAMEMODE.IsObjectiveMap and GAMEMODE:GetWave()<5 and math.random(1,3)~=2 then return end

	-- Grab all cading props.
	local CadeProps = {}
	local elist = ents.GetAll()
	for i=1, #elist do
		local e = elist[i]
		if CadingProps[e:GetClass()] and e:IsNailed() and e:GetNailFrozen() then
			CadeProps[#CadeProps+1] = e
			e._TagAI = nil
			e._SerialIndex = nil
		end
	end

	-- Group them into cades
	local Cades = {}
	for i=1, #CadeProps do
		local a = CadeProps[i]
		-- if a._TagAI or (CurTime()-(a._LastNailDamage or 0))>30 then continue end -- Only check unmarked props and props that been damaged by zombies within last 30s
		if a._TagAI then continue end

		local PropList = {a}
		local z = 1
		while z<=#PropList do
			local prop = PropList[z]
			z = z+1

			local amin, amax = prop:WorldSpaceAABB()
			for j=1, #CadeProps do
				local b = CadeProps[j]
				if j==i or b._TagAI then continue end

				local bmin, bmax = b:WorldSpaceAABB()
				if BoundsOverlap(amin,amax,bmin,bmax,35) then
					b._TagAI = true
					PropList[#PropList+1] = b
				end
			end
		end

		if #PropList>1 then -- Add as active cade.
			-- Do not consider if any part of this cade has already been saved this game.
			local bSaved = false
			for j=1, #PropList do
				if PropList[j]._AISerialized then
					bSaved = true
					break
				end
			end
			if not bSaved then
				Cades[#Cades+1] = PropList
			end
		end
	end

	if #Cades==0 then return "No cade in this map" end

	local acade

	if pos then
		local bestDist,bestProp
		for i=1, #CadeProps do
			local a = CadeProps[i]
			local dist = E_GetPos(a):DistToSqr(pos)
			if not bestProp or bestDist>dist then
				bestProp = a
				bestDist = dist
			end
		end
		if not bestProp then return "Found none nearby props?" end

		for i=1, #Cades do
			local c = Cades[i]
			for j=1, #c do
				if c[j]==bestProp then
					acade = c
					break
				end
			end
			if acade then break end
		end

		if not acade then return "This cade has too few props or is already saved!" end
	else
		acade = Cades[math.random(#Cades)]
	end

	-- Sort cade by nailing order (to make bots nail in proper order)
	table.sort(acade, function(a,b) return (a.m_FrozenTime or 0) < (b.m_FrozenTime or 0) end)

	-- Find out the main cader and cade bounds
	local caders = {}
	local Props = {}
	local mins,maxs

	for i=1, #acade do
		local prop = acade[i]
		prop._AISerialized = true -- Mark as saved.
		local pl = prop._FirstNailer
		if IsValid(pl) then
			caders[pl] = (caders[pl] or 0) + 1
		end
		local amin, amax = prop:WorldSpaceAABB()
		if not mins then
			mins,maxs = amin,amax
		else
			mins.x = math.min(mins.x,amin.x)
			mins.y = math.min(mins.y,amin.y)
			mins.z = math.min(mins.z,amin.z)
			maxs.x = math.max(maxs.x,amax.x)
			maxs.y = math.max(maxs.y,amax.y)
			maxs.z = math.max(maxs.z,amax.z)
		end

		Props[i] = {Model=prop:GetModel(),Pos=E_GetPos(prop),Ang=prop:GetAngles(),Flags=(prop._CreationMode or GAMEMODE.ZS_SpawnPropType.MapProp)}
		prop._SerialIndex = i
	end

	for i=1, #acade do
		local prop = acade[i]
		local pnails = {}
		local nails = prop:GetLivingNails()
		if #nails>0 then
			for j=1, #nails do
				local nail = nails[j]
				if nail.NailLinks[1]==prop then
					local oprop = nail.NailLinks[2]
					pnails[#pnails+1] = {Pos=E_GetPos(nail),Ang=nail:GetAngles(),Attach=(IsValid(oprop) and (oprop._SerialIndex or 0) or 0)}
				end
			end
		end
		Props[i].Nails = pnails
	end

	-- Find main cader (player who nailed most props)
	local bestpl = false
	local bestnum = 0
	for pl, num in pairs(caders) do
		if not bestpl or bestnum<num then
			bestpl = pl
			bestnum = num
		end
	end

	LoadMapCades() -- Make sure loaded!
	MapCades[#MapCades+1] = {Owner=(bestpl and (bestpl:Name().." ("..bestpl:SteamID()..")") or "<Someone>"),Bounds={mins,maxs,((mins+maxs)*0.5)},Props=Props}
	SaveMapCades()
	if pos then
		return true,"Saved cade with "..tostring(#Props).." props!"
	end
end

local PendingCade = false -- Pending cade to build.
local NextCheckTime = 0

local function CheckHasHammer( pl )
	-- Take electro hammer also into account?
	if not pl:HasWeapon("weapon_zs_hammer") then
		pl:Give("weapon_zs_hammer")
	end
	pl:SetUsingBuff(true)
end

local function EndPropFetch( pl )
	if pl.BOT_FetchProp then
		if IsValid(pl.BOT_FetchProp) then
			pl.BOT_FetchProp._AIReserved = nil
		end
		pl.BOT_FetchProp = nil
		pl.BOT_FetchInfo.Fetch = nil
		pl.BOT_FetchInfo = nil
		pl.BOT_CadeType = nil
	end
end

function ZSBOTAI.ShouldBuildCade( pl )
	return false
	/*
	if PendingCade then
		CheckHasHammer(pl)
		return true
	end

	if NextCheckTime>CurTime() then return false end

	LoadMapCades()
	if GAMEMODE.ZombieEscape or #MapCades<2 or GAMEMODE:GetWave()>1 then
		NextCheckTime = CurTime()+60
		return false
	end

	NextCheckTime = CurTime()+math.Rand(2,8)
	local PreferedCade

	if GAMEMODE.IsObjectiveMap then -- Pick random cade.
		PreferedCade = MapCades[math.random(#MapCades)]
	else
		-- Pick best one close to armory
		local armoryprops = ents.FindByClass("prop_defend_obj")
		local bestScore
		for i=1, #MapCades do
			local cd = MapCades[i]
			if cd.Built then continue end

			local midp = cd.Bounds[3]
			local bestDist
			for j=1, #armoryprops do
				local d = midp:DistToSqr(E_GetPos(armoryprops[j]))
				if j==1 then
					bestDist = d
				else
					bestDist = math.min(bestDist,d)
				end
			end
			bestDist = math.max(bestDist or math.random(),250000) * math.Rand(0.75,1.5) -- (500^2) Add random variation.

			if not PreferedCade or bestDist<bestScore then
				PreferedCade = cd
				bestScore = bestDist
			end
		end
	end

	if not PreferedCade then
		NextCheckTime = CurTime()+30
		return false
	end

	--print("Attempt to cade something by: "..PreferedCade.Owner)

	-- Make sure no player already caded that area.
	local boxents = ents.FindInBox(PreferedCade.Bounds[1],PreferedCade.Bounds[2])
	for i=1, #boxents do
		local e = boxents[i]
		if CadingProps[e:GetClass()] and e:IsNailed() and e:GetNailFrozen() and IsValid(e._FirstNailer) then
			--print("Cant cade, too close to cade by: "..tostring(e._FirstNailer))
			PreferedCade.Built = true
			return false -- Nope can't do it...
		end
	end

	-- Verify all required props are available
	-- Count all required map props
	local Required = {}
	for i=1, #PreferedCade.Props do
		local p = PreferedCade.Props[i]
		if p.Flags==GAMEMODE.ZS_SpawnPropType.MapProp then
			Required[p.Model] = (Required[p.Model] or 0)+1
		end
	end

	--[[for m, num in pairs(Required) do
		print("Need props '"..m.."' count: "..tostring(num))
	end]]

	local elist = ents.GetAll()
	for i=1, #elist do
		local e = elist[i]
		if CadingProps[e:GetClass()] and not e:IsNailed() then
			local m = e:GetModel()
			local req = Required[m]
			if req and req>0 then
				Required[m] = req-1
			end
		end
	end

	for m, num in pairs(Required) do
		if num>0 then
			--print("Cant cade, missing prop: "..m)
			PreferedCade.Built = true
			return false
		end
	end

	PendingCade = PreferedCade

	-- Reset temp variables.
	for i=1, #PreferedCade.Props do
		local p = PreferedCade.Props[i]
		p.Caded = nil
		p.Fetch = nil
		for j=1, #p.Nails do
			p.Nails[j].Nailed = nil
		end
	end

	timer.Simple(math.Rand(1,3), function()
		if IsValid(pl) and pl:IsBot() and PendingCade then
			pl:Say("I'm building a cade by "..PendingCade.Owner,true)
		end
	end)
	CheckHasHammer(pl)

	-- Reset data on new round.
	hook.Add("EndRound","EndRound.BotBarricade",function()
		PendingCade = false
		NextCheckTime = 0
		hook.Remove("EndRound","EndRound.BotBarricade")
		hook.Remove("ResetAI","ResetAI.BotBarricade")

		for i=1, #MapCades do
			MapCades[i].Built = nil
		end

		for i=1, #ZSBOTAI.Bots do
			local b = ZSBOTAI.Bots[i]
			if IsValid(b) then
				b.BOT_Barricader = nil
			end
		end
	end)

	hook.Add("ResetAI","ResetAI.BotBarricade",EndPropFetch)
	return true
	*/
end

local function SpawnNailAt( pl, pos, ang, ent )
	local wep = pl:GetActiveWeapon()
	if IsValid(wep) and wep:GetClass()=="weapon_zs_hammer" then
		wep:BotSwing()
	end

	ent:EmitSound("weapons/melee/crowbar/crowbar_hit-"..math.random(4)..".ogg")
	local nail = ents.Create("prop_nail")
	if IsValid(nail) then
		-- Drop carried props.
		if ent and IsValid(ent.CarriedBy) and ent.CarriedBy.status_human_holding then
			ent.CarriedBy.status_human_holding:Remove()
		end

		nail:SetActualOffset(pos, ent)
		nail:SetPos(pos)
		nail:SetAngles(ang)
		nail:SetDeployer(pl)
		nail:AttachTo(ent, game.GetWorld())
		nail:Spawn()

		gamemode.Call("OnNailCreated", ent, game.GetWorld(), nail)
		return nail
	end
end

local PendingNails = false
local ShadowParams = {secondstoarrive = 0.1, maxangular = 1000, maxangulardamp = 10000, maxspeed = 500, maxspeeddamp = 1000, dampfactor = 0.65, teleportdistance = 500}

local function NailTickFunc()
	local dt = FrameTime()

	for i=#PendingNails, 1, -1 do
		local n = PendingNails[i]
		local b = n.Bot
		local p = n.Prop
		local m = n.State
		if not IsValid(b) or GetPlayerTeam(b)~=TEAM_HUMAN or not b:Alive() or not IsValid(p) or IsValid(p.CarriedBy) or (m==0 and p:IsNailed()) then
			table.remove(PendingNails,i)
			continue
		end

		local ang = (E_GetPos(p) - b:EyePos()):Angle()
		b:SetEyeAngles(ang)

		local tm = CurTime()-n.Time
		local nfo = n.Info

		local wep = b:GetActiveWeapon()
		if IsValid(wep) and wep:GetClass()~="weapon_zs_hammer" then
			b:SelectWeapon("weapon_zs_hammer")
		end
		BOT_SpecialPause[b] = CurTime()+0.5

		if m==0 then -- Move in place.
			local objectphys = p:GetPhysicsObject()
			if p:GetMoveType() ~= MOVETYPE_VPHYSICS or not IsValid(objectphys) then
				table.remove(PendingNails,i)
				continue
			end

			if tm>3 or E_GetPos(p):DistToSqr(nfo.Pos)<2500 then -- 50^2
				objectphys:SetAngles(nfo.Ang)
				objectphys:SetPos(nfo.Pos,true)
				p._AISerialized = true -- Do not re-save AI built cade.
				p._InAICade = true
				n.State = 1
				nfo.Caded = true
				n.Time = CurTime()-1
				continue
			end
			ShadowParams.pos = nfo.Pos
			ShadowParams.angle = nfo.Ang
			ShadowParams.deltatime = dt
			objectphys:Wake()
			objectphys:ComputeShadowControl(ShadowParams)
		elseif m==1 then -- Nail it down.
			if tm>0.9 then
				n.Time = CurTime()
				local Any = false
				p:SetPos(nfo.Pos)
				p:SetAngles(nfo.Ang)

				for i=1, #nfo.Nails do
					local nail = nfo.Nails[i]
					if not nail.Nailed then
						SpawnNailAt(b,nail.Pos,nail.Ang,p)
						nail.Nailed = true
						Any = true
						break
					end
				end
				if Any then continue end

				EndPropFetch(b)
				table.remove(PendingNails,i)
				continue
			end
		end
	end

	if #PendingNails==0 then
		PendingNails = false
		hook.Remove("Think","Think.BotBarricade")
	end
end

local function SetPendingNail( pl )
	if not PendingNails then
		PendingNails = {}
		hook.Add("Think","Think.BotBarricade",NailTickFunc)
	end

	for i=1, #PendingNails do
		local n = PendingNails[i]
		if n.Bot==pl then
			table.remove(PendingNails,i)
			break
		end
	end

	PendingNails[#PendingNails+1] = {Bot=pl,Prop=pl.BOT_FetchProp,Info=pl.BOT_FetchInfo,State=0,Time=CurTime()}
end

local function ReturnToCade( pl )
	local prop = pl.BOT_FetchProp
	local info = pl.BOT_FetchInfo
	local ppos = prop:WorldSpaceCenter()

	for ipass=1, 2 do -- Try both nailed down position and then center of cade position.
		local pos = (ipass==1 and info.Pos or PendingCade.Bounds[3])
		if E_GetPos(pl):DistToSqr(pos)<40000 then -- 200^2
			pl.status_human_holding:Remove()
			SetPendingNail(pl)
			return 4
		end

		if pl:PointReachable(pos,200) then
			return pos
		end

		local path = ZSBOTAI.FindPathToward(pl,pos,true)
		if path then
			if pl.BOT_OldCadePath==path then
				pl.BOT_OldCadeCount = pl.BOT_OldCadeCount+1
				if pl.BOT_OldCadeCount>4 then
					path = nil
				end
			else
				pl.BOT_OldCadePath = path
				pl.BOT_OldCadeCount = 0
			end
			if path then
				return path
			end
		end

		if WorldVisible(ppos,pos) then
			pl.status_human_holding:Remove()
			SetPendingNail(pl)
			return 4
		end
	end

	prop._AIUnreach = CurTime()+5
	pl.status_human_holding:Remove()
	EndPropFetch(pl)
	-- FAILED.
end

local CadePropList
local NextPropTime = 0

hook.Add("AINotifyPropBuilt","AINotifyPropBuilt.BotBarricade",function(prop)
	for i=1, #ZSBOTAI.Bots do
		local b = ZSBOTAI.Bots[i]
		if b.BOT_FetchProp and (b.BOT_CadeType or not IsValid(b.BOT_FetchProp) or b.BOT_FetchProp.bIsDestroyedProp) and b.BOT_FetchInfo.Model==prop:GetModel()
			and E_GetPos(b):DistToSqr(E_GetPos(prop))<640000 and WorldVisible(b:GetPlayerOrigin(),E_GetPos(prop)) then -- 800^2
			-- Make bot instantly use this prop instead
			if BOT_SpecialPause[b] then
				BOT_SpecialPause[b] = nil
			end
			b.BOT_FetchProp = prop
			prop._AIReserved = CurTime()+16
			b.BOT_CadeType = nil
			ZSStatus:GiveStatus(b,"human_holding",prop,true)
			return
		end
	end

	if NextPropTime>CurTime() then
		CadePropList[#CadePropList+1] = prop
	end
end)

function ZSBOTAI.PickCadeMove( pl )
	/*if not PendingCade and not ZSBOTAI.ShouldBuildCade(pl) then return end

	local pprop = pl.BOT_FetchProp
	if IsValid(pprop) then
		if pl.BOT_FetchInfo.Caded then
			if pl.status_human_holding then
				pl.status_human_holding:Remove()
			end
			EndPropFetch(pl)
		elseif pl.BOT_CadeType then -- Special goal.
			if E_GetPos(pprop):DistToSqr(E_GetPos(pl))<40000 then -- 200^2
				if pl.BOT_CadeType==1 then -- Going for transponder
					local res = pprop:BotPrintProp(pl,pl.BOT_FetchInfo.Model)
					EndPropFetch(pl)
					return math.max(res+0.25,0.1) -- Check once prop has been printed.
				else -- Going for armory
					-- Quick verify that the transponder hasnt been deployed yet.
					local trlist = ents.FindByClass("prop_barricade_transponder")
					if #trlist>0 then
						EndPropFetch(pl)
						return 0.15
					end

					local wp = pl:GetWeapon("weapon_zs_barricadetrans")
					if IsValid(wp) then
						if pl:GetActiveWeapon()~=wp then
							pl:SelectWeapon("weapon_zs_barricadetrans")
							return 0.5
						end
						wp:AIDeploy(0.8)
						local pos = E_GetPos(pprop)
						pos.x = pos.x + math.Rand(-150,150)
						pos.y = pos.y + math.Rand(-150,150)
						return pos
					else
						pl:TakePoints(50)
						pl:Give("weapon_zs_barricadetrans")
						return 0.5
					end
				end
			elseif pl:PointReachable(pprop,200) then
				return pprop
			else
				local path = ZSBOTAI.FindPathToward(pl,pprop)
				if path then return path end

				pprop._AIUnreach = CurTime()+10 -- Temporary mark it as banned for being used in cade.
				EndPropFetch(pl)
				return 0.8
			end
		elseif pprop.bIsDestroyedProp then
			EndPropFetch(pl)
		elseif pprop.CarriedBy==pl then -- Carry it back to cade
			return ReturnToCade(pl)
		else
			local pos = pl:GetPlayerOrigin()
			local point = pprop:NearestPoint(pos)
			if point:DistToSqr(pos)<40000 then -- 200^2
				if pprop:GetClass()=="prop_door_rotating" then
					BOT_AttackProp[pl] = pprop
					pl.BOT_PropAttackTime = CurTime()+math.Rand(1.25,2)
					BOT_MoveStuckTime[pl] = nil
					ZSBOTAI.BotOrders(pl,10,ent,pl.BOT_PropAttackTime)
					return
				else
					ZSStatus:GiveStatus(pl,"human_holding",pprop,true)
				end
				return ReturnToCade(pl)
			elseif pl:PointReachable(pprop,200) then
				return pprop
			else
				local path = ZSBOTAI.FindPathToward(pl,pprop,true)
				if path then return path end

				if WorldVisible(pos,point) then
					if pprop:GetClass()=="prop_door_rotating" then
						BOT_AttackProp[pl] = pprop
						pl.BOT_PropAttackTime = CurTime()+math.Rand(1.25,2)
						BOT_MoveStuckTime[pl] = nil
						ZSBOTAI.BotOrders(pl,10,ent,pl.BOT_PropAttackTime)
						return
					else
						ZSStatus:GiveStatus(pl,"human_holding",pprop,true)
					end
					return pprop
				end
				pprop._AIUnreach = CurTime()+10 -- Temporary mark it as banned for being used in cade.
				EndPropFetch(pl)
			end
		end
	elseif pprop then
		EndPropFetch(pl)
	end

	if NextPropTime<CurTime() then
		CadePropList = {}
		local FetchPropList = {}
		NextPropTime = CurTime()+15

		for i=1, #PendingCade.Props do
			local p = PendingCade.Props[i]
			if p.Caded or IsValid(p.Fetch) then
				continue
			end
			FetchPropList[p.Model] = true
		end

		local elist = ents.GetAll()
		for i=1, #elist do
			local e = elist[i]
			if CadingProps[e:GetClass()] and FetchPropList[e:GetModel()] and not e._InAICade and (e._AIUnreach or 0)<CurTime() then
				CadePropList[#CadePropList+1] = e
			end
		end
	end

	local BScore,BInfo
	local BProp = false
	local AnyFound = false

	for pass=1, 2 do
		for j=1, #PendingCade.Props do
			local p = PendingCade.Props[j]
			if p.Caded then
				continue
			end
			AnyFound = true

			if IsValid(p.Fetch) and pass==1 then
				continue
			end
			BInfo = p

			for i=1, #CadePropList do
				local e = CadePropList[i]
				if not IsValid(e) or e.bIsDestroyedProp or IsValid(e.CarriedBy) or e._InAICade or e:GetModel()~=p.Model or (e._AIUnreach or 0)>CurTime() or (e._AIReserved or 0)>CurTime() then continue end

				local Score = p.Pos:Distance(E_GetPos(e))
				if e:IsNailed() then Score = Score+3000 end

				if not BProp or Score<BScore then
					BProp = e
					BScore = Score
				end
			end

			if not BProp then
				if p.Flags==GAMEMODE.ZS_SpawnPropType.JunkPack then -- Fake deploy junk pack.
					local wep = pl:GetWeapon("weapon_zs_boardpack")
					if not IsValid(wep) then
						wep = pl:Give("weapon_zs_boardpack")
						if not IsValid(wep) then
							return
						end
					end
					pl:SelectWeapon("weapon_zs_boardpack")
					wep:EmitSound("weapons/iceaxe/iceaxe_swing1.wav", 75, 75)
					wep:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
					BProp = wep:DeployItem(p.Model)
					BScore = 0
				elseif p.Flags==GAMEMODE.ZS_SpawnPropType.BarricadeTransponder then
					-- Look for a free transponder first.
					local trlist = ents.FindByClass("prop_barricade_transponder")
					local BTScore
					local BTTrp = false
					for i=1, #trlist do
						local tp = trlist[i]
						local Score = E_GetPos(tp):Distance(p.Pos)
						if not BTTrp or Score<BTScore then
							BTTrp = tp
							BTScore = Score
						end
					end

					if not BTTrp then
						-- No transponder found, look for nearest armory to buy it from.
						trlist = ents.FindByClass("prop_defend_obj")
						for i=1, #trlist do
							local tp = trlist[i]
							if tp:GetDestroyed() then continue end
							local Score = E_GetPos(tp):Distance(p.Pos)
							if not BTTrp or Score<BTScore then
								BTTrp = tp
								BTScore = Score
							end
						end

						if not BTTrp then -- Impossible to complete the cade with this prop.
							p.Caded = true
							return 0.1
						else
							pl.BOT_CadeType = 2
							BProp = BTTrp
						end
					else
						pl.BOT_CadeType = 1
						BProp = BTTrp
					end
				end
			end
			break
		end
		if BProp then break end
	end

	if BProp then
		pl.BOT_FetchProp = BProp
		pl.BOT_FetchInfo = BInfo
		BInfo.Fetch = pl

		if not pl.BOT_CadeType then
			BProp._AIReserved = CurTime()+8
			BInfo.NumTries = (BInfo.NumTries or 0) + 1
			if BInfo.NumTries>200 then -- Give up.
				BInfo.Caded = true
				return 0.1
			end
		end
	elseif not AnyFound then
		PendingCade.Built = true
		PendingCade = false
		if pl:IsBot() then
			pl:Say("Cade done!",true)
		end
		NextCheckTime = CurTime()+(GAMEMODE.IsObjectiveMap and 10000 or math.Rand(5,15))
	end
	*/
end
