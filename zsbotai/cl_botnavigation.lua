-- Bot AI path network display, written by Marco
ZSBOTAI = {}

ZSBOTAI.PathDrawDistance = 1200
ZSBOTAI.HideAirPaths = false
ZSBOTAI.HideSubPaths = false
ZSBOTAI.PathIgnoreZ = false
ZSBOTAI.CheckpointTypes = {"No Cade","Z-God Mode","Z-God Mode wave 3","Block All","Block Humans","Block Zombies","Kill All","Hurt Humans"}

ZSBOTAI.PATH_EDIT_DATA = {Mode=1,NodeType=1,RouteFlags=0,ObjNum=0,VolumeType=0,UseTris=false}
local PathEdit = ZSBOTAI.PATH_EDIT_DATA

include("sh_botai.lua")
include("cl_botprofiler.lua")

local PathList
local DebugReachList
local ObjMarkers

local NODETYPE_Fly = ZSBOTAI.PATH_Type.Fly
local NODETYPE_Objective = ZSBOTAI.PATH_Type.Objective
local NODETYPE_NavMesh = ZSBOTAI.PATH_Type.NavMesh
local NODETYPE_NavMeshTris = ZSBOTAI.PATH_Type.NavMeshTris
local NODETYPE_ZSpawn = ZSBOTAI.PATH_Type.ZSpawn

local REACHTYPE_Walk = ZSBOTAI.PATH_ReachFlags.Walk
local REACHTYPE_Fly = ZSBOTAI.PATH_ReachFlags.Fly
local REACHTYPE_Swim = ZSBOTAI.PATH_ReachFlags.Swim
local REACHTYPE_Headcrab = ZSBOTAI.PATH_ReachFlags.Headcrab
local REACHTYPE_Leap = ZSBOTAI.PATH_ReachFlags.Leap
local REACHTYPE_Climb = ZSBOTAI.PATH_ReachFlags.Climb
local REACHTYPE_Door = ZSBOTAI.PATH_ReachFlags.Door
local REACHTYPE_Teleport = ZSBOTAI.PATH_ReachFlags.Teleport
local REACHTYPE_Zombies = ZSBOTAI.PATH_ReachFlags.Zombies
local REACHTYPE_Humans = ZSBOTAI.PATH_ReachFlags.Humans
local REACHTYPE_NoStrafeTo = ZSBOTAI.PATH_ReachFlags.NoStrafeTo

local NodeColors = {
	[ZSBOTAI.PATH_Type.Swim] = COLOR_BLUE,
	[ZSBOTAI.PATH_Type.Fly] = COLOR_CYAN,
	[ZSBOTAI.PATH_Type.Objective] = Color(255,201,14,255),
	[ZSBOTAI.PATH_Type.Ladder] = COLOR_PURPLE,
	[ZSBOTAI.PATH_Type.NavMesh] = COLOR_CYAN,
	[ZSBOTAI.PATH_Type.NoQuitNode] = COLOR_GREEN,
	[ZSBOTAI.PATH_Type.ZSpawn] = Color(255,201,14,255),
}

local matArmory = Material("materials/zombiesurvival/icon/armory.png")
local matNoAuto = Material("icon16/user_red.png")
local matSelected = Material("icon16/arrow_in.png")
local matWhite = Material( "vgui/white" )
local COLOR_NavArea = Color(64,200,38,64)
local COLOR_NavAreaHigh = Color(185,185,38,64)
local COLOR_NavEdge = Color(1,32,1,255)
local COLOR_TriSplitter = Color(36,185,36,64)

local function CalcDrawSize( e, p )
	return math.max(15 * (1 / e:Distance(p)),0.05)
end

local function TraceXHair()
	local eye = EyePos()
	local tri = ZSBOTAI.GetReachTraceInfo(eye,eye+MySelf:GetAimVector()*2000)
	local tr = util.TraceLine(tri)
	if tr.Hit then
		PathEdit.bWater = (bit.band(util.PointContents(tr.HitPos + Vector(0,0,30)), CONTENTS_WATER)~=0)
		PathEdit.bError = (tr.HitNormal.z<0.1)
		PathEdit.Aim = tr.HitPos
	else
		PathEdit.Aim = nil
	end
	return tr
end

local function Draw2SidedQuad( v1, v2, v3, v4, c )
	render.DrawQuad(v1,v2,v3,v4,c)
	render.DrawQuad(v4,v3,v2,v1,c)
end

local function Draw2SidedTris( v1, v2, v3, c )
	local v4 = (v3+v1)*0.5
	render.DrawQuad(v1,v2,v3,v4,c)
	render.DrawQuad(v4,v3,v2,v1,c)
end

local function DrawPathNetwork( bDrawingDepth, bDrawingSkybox )
	local wp = MySelf:GetActiveWeapon()
	if not IsValid(wp) or wp:GetClass()~="weapon_zs_adminpathtool" then
		hook.Remove("PostDrawOpaqueRenderables","Bot.PostDrawOpaqueRenderables")
		ZSBOTAI.EndPathEditor()
		return
	end

	if not PathList and not ObjMarkers then
		return
	end

	local closestn = nil
	local bestdist = nil
	local eye = EyePos()
	local MaxDist = ZSBOTAI.PathDrawDistance and ZSBOTAI.PathDrawDistance^2 or false
	local bHideAir = ZSBOTAI.HideAirPaths
	local bHideSub = ZSBOTAI.HideSubPaths
	local noZ = not ZSBOTAI.PathIgnoreZ
	local iHigh

	-- Draw crosshair arrow.
	if PathEdit.Mode==1 then -- Create node
		local tr = TraceXHair()
		if tr.Hit and PathEdit.NodeType~=2 then
			render.DrawLine(tr.HitPos,tr.HitPos+tr.HitNormal*30,(PathEdit.bError and COLOR_RED or (PathEdit.bWater and COLOR_CYAN or COLOR_YELLOW)),true)

			iHigh = ZSBOTAI.FindPathAt(tr.HitPos)
			if iHigh and iHigh~=PathEdit.Pending then
				render.SetMaterial(matSelected)
				render.DrawSprite(PathList[iHigh].P+Vector(0,0,16),6,6,COLOR_WHITE)
			end

			if PathEdit.NodeType==5 then -- ZSpawn directional arrow
				local ang = Angle(0,EyeAngles().yaw,0)
				local dir = ang:Forward()
				local ydir = ang:Right() * 8
				local epos = tr.HitPos+dir*28
				local mpos = tr.HitPos+(dir*17)
				render.DrawLine(tr.HitPos,epos,COLOR_CYAN,false)
				render.DrawLine(epos,mpos+ydir,COLOR_CYAN,false)
				render.DrawLine(epos,mpos-ydir,COLOR_CYAN,false)
			end
		end
	elseif PathEdit.Mode==2 or PathEdit.Mode==3 then -- Move node/Edit reachspecs
		local tr = TraceXHair()
		if tr.Hit then
			if PathEdit.Pending then
				render.SetMaterial(matSelected)
				render.DrawSprite(PathList[PathEdit.Pending].P+Vector(0,0,16),12,12,COLOR_RED)
				render.DrawLine(tr.HitPos,tr.HitPos+tr.HitNormal*30,(PathEdit.bError and COLOR_RED or (PathEdit.bWater and COLOR_CYAN or COLOR_YELLOW)),true)
			end
			if PathEdit.Mode==2 or not PathEdit.Pending then
				iHigh = ZSBOTAI.FindPathAt(tr.HitPos)
				if iHigh and iHigh~=PathEdit.Pending then
					render.SetMaterial(matSelected)
					render.DrawSprite(PathList[iHigh].P+Vector(0,0,16),6,6,COLOR_WHITE)
				end
				PathEdit.Target = iHigh
			end
		else
			PathEdit.Target = nil
		end
	elseif PathEdit.Mode==4 then -- Create checkpoint
		local tr = TraceXHair()
		if tr.Hit and PathEdit.Pending then
			render.DrawWireframeBox(Vector(0,0,0),Angle(0,0,0),PathEdit.Pending,tr.HitPos,COLOR_YELLOW,false)
		end
	elseif PathEdit.Mode==5 then -- Nav mesh
		local tr = TraceXHair()
		if tr.Hit then
			if PathEdit.Pending then
				if isnumber(PathEdit.Pending) then
					iHigh = PathEdit.Pending
					if PathEdit.SPending then
						if PathEdit.ForceFlat then
							tr.HitPos.z = PathEdit.SPending.z
						end
						render.DrawWireframeBox(Vector(0,0,0),Angle(0,0,0),PathEdit.SPending,tr.HitPos,(PathEdit.bError and COLOR_RED or COLOR_CYAN),false)
					else
						render.DrawLine(tr.HitPos,tr.HitPos+tr.HitNormal*30,(PathEdit.bError and COLOR_RED or COLOR_CYAN),true)
					end
				elseif PathEdit.SPending and PathEdit.UseTris then
					local a,b = PathEdit.Pending,PathEdit.SPending
					local v = (a-b):GetNormalized()
					local SplitNormal = Vector(v.y,-v.x,0)
					local LeftSide = tr.HitPos:Dot(SplitNormal)>a:Dot(SplitNormal)
					if (v.x*v.y)<0 then -- invert when determinant mirrored.
						LeftSide = not LeftSide
					end
					render.DrawWireframeBox(Vector(0,0,0),Angle(0,0,0),PathEdit.Pending,PathEdit.SPending,COLOR_LIMEGREEN,false)
					local halfz = (a.z+b.z)*0.5

					render.SetMaterial(matWhite)
					if LeftSide then
						v = -v
						Draw2SidedTris(a,b,Vector(a.x,b.y,halfz),COLOR_TriSplitter)
					else
						Draw2SidedTris(a,b,Vector(b.x,a.y,halfz),COLOR_TriSplitter)
					end
					PathEdit.TriSide = bit.bor((v.x>0 and 1 or 0),(v.y>0 and 2 or 0))
				else
					if PathEdit.ForceFlat then
						tr.HitPos.z = PathEdit.Pending.z
					end
					render.DrawWireframeBox(Vector(0,0,0),Angle(0,0,0),PathEdit.Pending,tr.HitPos,(PathEdit.bError and COLOR_RED or COLOR_LIMEGREEN),false)
					if PathEdit.UseTris then
						local a,b = PathEdit.Pending,tr.HitPos
						local minz = math.min(a.z,b.z)
						local maxz = math.max(a.z,b.z,minz+10)
						render.SetMaterial(matWhite)
						Draw2SidedQuad(Vector(a.x,a.y,minz),Vector(a.x,a.y,maxz),Vector(b.x,b.y,maxz),Vector(b.x,b.y,minz),COLOR_TriSplitter)
					end
				end
			else
				render.DrawLine(tr.HitPos,tr.HitPos+tr.HitNormal*30,(PathEdit.bError and COLOR_RED or COLOR_CYAN),true)
				iHigh = ZSBOTAI.FindPathAt(tr.HitPos,true)
				PathEdit.Target = iHigh
			end
		end
	end

	if noZ then
		render.OverrideDepthEnable(true,true)
	end

	if PathList then
		if bHideSub then
			local tr = util.TraceLine(ZSBOTAI.GetReachTraceInfo(eye,eye-Vector(0,0,1000)))
			if tr.Hit then
				bHideSub = tr.HitPos.z - 50
			else
				bHideSub = eye.z - 1050
			end
		end
		for i, p in pairs(PathList) do
			if (bHideAir and p.f==NODETYPE_Fly) or (bHideSub and p.P.z<bHideSub) then
				continue
			end
			local dist = eye:DistToSqr(p.P)
			if MaxDist and dist>MaxDist then
				continue
			end

			if not closestn or bestdist>dist then
				closestn = p
				bestdist = dist
			end

			local startpos = p.P+Vector(0,0,50)
			render.DrawLine(p.P,startpos,p.c,noZ)

			if p.f==NODETYPE_NavMesh then
				render.SetMaterial(matWhite)
				local e = p.e
				render.DrawQuad(e[4],e[3],e[2],e[1],iHigh==i and COLOR_NavAreaHigh or COLOR_NavArea)
				for j=1, 4 do
					render.DrawBeam(e[j],e[j==4 and 1 or (j+1)],1,0,1,COLOR_NavEdge)
				end
			elseif p.f==NODETYPE_NavMeshTris then
				render.SetMaterial(matWhite)
				local e = p.e
				render.DrawQuad(e[1],e[2],e[3],(e[1]+e[3])*0.5,iHigh==i and COLOR_NavAreaHigh or COLOR_NavArea)
				for j=1, 3 do
					render.DrawBeam(e[j],e[j==3 and 1 or (j+1)],1,0,1,COLOR_NavEdge)
				end
			end

			for _, reach in pairs(p.r) do
				if not reach.e or not PathList[reach.e] or (bHideAir and bit.band(reach.f,REACHTYPE_Fly)~=0) then
					continue
				end

				local ep = PathList[reach.e]
				local col = reach.c
				local endpos = ep.P+Vector(0,0,30)
				render.DrawLine(startpos,endpos,col,noZ)
				local ang = (endpos-startpos):Angle()
				local x = ang:Forward()*12
				local y = ang:Right()*4

				render.DrawLine(endpos-x-y,endpos,col,noZ)
				render.DrawLine(endpos-x+y,endpos,col,noZ)
				render.DrawLine(endpos-x+y,endpos-x-y,col,noZ)
			end

			if p.f==NODETYPE_Objective then -- Armory icon
				render.SetMaterial(matArmory)
				render.DrawSprite(startpos,8,8,COLOR_YELLOW)
			elseif p.f==NODETYPE_ZSpawn then
				local epos = startpos+p.yawX*28
				local mpos = startpos+(p.yawX*17)
				local ydir = p.yawY*8
				render.DrawLine(startpos,epos,COLOR_YELLOW,noZ)
				render.DrawLine(mpos+ydir,epos,COLOR_YELLOW,noZ)
				render.DrawLine(mpos-ydir,epos,COLOR_YELLOW,noZ)
				DrawWorldHint("#"..tostring(p.ObjNum), startpos, nil, CalcDrawSize(eye,startpos))
			end

			if bit.band(p.ex,1)~=0 then -- No auto-path
				render.SetMaterial(matNoAuto)
				render.DrawSprite(startpos+Vector(0,0,8),4,4,COLOR_RED)
			end
		end
		if closestn then
			render.DrawWireframeBox(Vector(0,0,0),Angle(0,0,0),closestn.m,closestn.x,COLOR_RED,false)
		end
	end

	if noZ then
		render.OverrideDepthEnable(false)
	end

	if ObjMarkers and not ZSBOTAI.HideVolumes then
		for _, p in pairs(ObjMarkers) do
			local dist = eye:DistToSqr(p[4])
			if not MaxDist or dist<MaxDist then
				render.DrawWireframeBox(Vector(0,0,0),Angle(0,0,0),p[2],p[3],COLOR_LIMEGREEN,false)
				if dist<250000 then -- 500^2
					local s
					if p[5] then
						s = ZSBOTAI.CheckpointTypes[p[1]]
						if s then
							s = "<"..s..">"
						else
							s = "#"..tostring(p[1])
						end
					else
						s = "#"..tostring(p[1])
					end
					DrawWorldHint(s, p[4], nil, CalcDrawSize(eye,p[4]))
				end
			end
		end
	end

	if DebugReachList then
		local Prev = nil
		for _, v in pairs(DebugReachList) do
			if Prev then
				render.DrawLine(Prev,v,COLOR_YELLOW,noZ)
				render.DrawLine(v,v+Vector(0,0,10),COLOR_WHITE,noZ)
			end
			Prev = v
		end
	end

	render.ModelMaterialOverride(0)
end

function ZSBOTAI.FindPathAt( pos, bNavMesh )
	local bestidx = nil
	local bestDist = nil
	for i, p in pairs(PathList) do
		local dist = pos:DistToSqr(p.P)

		if bNavMesh then
			if p.f>=NODETYPE_NavMesh and (not bestidx or bestDist>dist) and pos:WithinAABox(p.m,p.x) and (p.f==NODETYPE_NavMesh or pos:Dot(p.sn)>p.sw) then
				bestidx = i
				bestDist = dist
			end
		elseif dist<10000 and (not bestidx or bestDist>dist) then
			bestidx = i
			bestDist = dist
		end
	end
	return bestidx
end

function ZSBOTAI.DrawAIPaths()
	if not ObjMarkers then
		ObjMarkers = {}
	end
	if not PathList then
		PathList = {}
		GAMEMODE.AI_PATHLIST = PathList
	end
	hook.Add("PostDrawOpaqueRenderables","Bot.PostDrawOpaqueRenderables",DrawPathNetwork)
end

local function SetNodeColor( node )
	node.c = NodeColors[node.f] or (node.ex==1 and COLOR_RED or COLOR_WHITE)
end

local ZombieFlags = bit.bor(REACHTYPE_Headcrab,REACHTYPE_Leap,REACHTYPE_Climb)
local PCOLOR_HumansOnly = Color(25,100,255)
local PCOLOR_NoStrafeRoute = Color(128,128,128)

local function SetRouteColor( spec )
	local f = spec.f
	local c = COLOR_LIMEGREEN
	if bit.band(f,REACHTYPE_Teleport)~=0 then
		c = COLOR_WHITE
	elseif bit.band(f,REACHTYPE_Humans)~=0 then
		c = PCOLOR_HumansOnly
	elseif bit.band(f,REACHTYPE_Zombies)~=0 then
		c = COLOR_GREEN
	elseif bit.band(f,REACHTYPE_Door)~=0 then
		c = COLOR_YELLOW
	elseif bit.band(f,REACHTYPE_Fly)~=0 then
		c = COLOR_CYAN
	elseif bit.band(f,REACHTYPE_Swim)~=0 then
		c = COLOR_BLUE
	elseif bit.band(f,ZombieFlags)~=0 then
		c = COLOR_PURPLE
	elseif bit.band(f,REACHTYPE_NoStrafeTo)~=0 then
		c = PCOLOR_NoStrafeRoute
	end
	spec.c = c
end

function PathEdit.SendNode( iNode )
	net.WriteUInt(iNode,16)
	net.WriteUInt(PathList[iNode].NetID,4)
end

net.Receive("zs_ai_debugreach", function(length)
	DebugReachList = {}

	while net.ReadBool() do
		local v = net.ReadVector()
		table.insert(DebugReachList,v)
	end
end)

local function calcTrisNormal( node )
	local ndir = (node.e[3]-node.e[2])
	local snormal = Vector(ndir.y,-ndir.x,0):GetNormalized() -- Split normal
	node.sn = snormal
	node.sw = (snormal:Dot(node.e[2]))
end

net.Receive("zs_ai_recpaths", function(length)
	if not PathList then
		PathList = {}
		GAMEMODE.AI_PATHLIST = PathList
	end

	local tp = net.ReadUInt(3)

	if tp==0 then -- add pathnode
		local ix = net.ReadUInt(16)
		local netID = net.ReadUInt(4)

		local node = {NetID=netID,Index=ix}
		PathList[ix] = node
		node.P = net.ReadVector()
		node.m = net.ReadVector()
		node.x = net.ReadVector()
		node.f = net.ReadUInt(ZSBOTAI.PATH_TypeNetworkSize)
		node.ex = net.ReadUInt(ZSBOTAI.PATH_ExTypeNetworkSize)
		if node.f==NODETYPE_NavMesh then
			node.e = {net.ReadVector(),net.ReadVector(),net.ReadVector(),net.ReadVector()}
			for i=1, 4 do
				node.e[i].z = node.e[i].z+1
			end
		elseif node.f==NODETYPE_NavMeshTris then
			node.e = {net.ReadVector(),net.ReadVector(),net.ReadVector()}
			for i=1, 3 do
				node.e[i].z = node.e[i].z+1
			end
			calcTrisNormal(node)
		elseif node.f==NODETYPE_ZSpawn then
			node.ObjNum = net.ReadUInt(12)
			local ang = Angle(0,net.ReadUInt(8)*1.412,0)
			node.yawX = ang:Forward()
			node.yawY = ang:Right()
		end
		node.r = {}
		SetNodeColor(node)

		local rc = net.ReadUInt(8)
		for i=1, rc do
			local endix = net.ReadUInt(16)
			local flg = net.ReadUInt(ZSBOTAI.PATH_ReachNetworkSize)
			local rs = {e=endix,f=flg}
			node.r[i] = rs
			SetRouteColor(rs)
		end
	elseif tp==1 then -- add reachspecs
		while net.ReadBool() do
			local ix = net.ReadUInt(16)
			local node = PathList[ix]

			if not node then
				node = {P=Vector(0,0,0),m=Vector(0,0,0),x=Vector(0,0,0),f=0,ex=0,r={}}
				PathList[ix] = node
				SetNodeColor(node)
			end

			local endix = net.ReadUInt(16)
			local flg = net.ReadUInt(ZSBOTAI.PATH_ReachNetworkSize)

			-- Verify this reachspec hasn't been received yet (could happen during load time).
			for i, reach in ipairs(PathList[ix].r) do
				if reach.e==endix then
					reach.f = flg
					SetRouteColor(reach)
					endix = nil
					break
				end
			end
			if endix then
				local rs = {e=endix,f=flg}
				node.r[#node.r+1] = rs
				SetRouteColor(rs)
			end
		end
	elseif tp==2 then -- delete pathnode
		local ix = net.ReadUInt(16)
		table.remove(PathList,ix)

		if PathEdit.Pending then
			if PathEdit.Pending==ix then
				PathEdit.Pending = nil
			elseif PathEdit.Pending>ix then
				PathEdit.Pending = PathEdit.Pending-1
			end
		end

		-- cleanup references to this pathnode from reachspecs
		for i, p in pairs(PathList) do
			p.Index = i
			local delindex = nil
			for j, reach in ipairs(p.r) do
				if reach.e==ix then
					delindex = j
				elseif reach.e>ix then
					reach.e = reach.e-1
				end
			end

			if delindex then
				table.remove(p.r,delindex)
			end
		end
	elseif tp==3 then -- purge
		PathList = {}
		GAMEMODE.AI_PATHLIST = PathList
		ObjMarkers = {}
		ZSBOTAI.ResetSelection()
		chat.AddText(COLOR_RED,"All paths purged!")
	elseif tp==4 then -- delete reachspec
		local six = net.ReadUInt(16)
		local eix = net.ReadUInt(16)
		local node = PathList[six]

		if not node then
			node = {P=Vector(0,0,0),m=Vector(0,0,0),x=Vector(0,0,0),f=0,ex=0,r={}}
			PathList[six] = node
		end

		for i, reach in ipairs(node.r) do
			if reach.e==eix then
				table.remove(node.r,i)
				break
			end
		end
	elseif tp==5 then -- add obj markers
		if not ObjMarkers then
			ObjMarkers = {}
		end

		while net.ReadBool() do
			local i = net.ReadUInt(16)
			local objn = net.ReadUInt(10)+1
			local minp = net.ReadVector()
			local maxp = net.ReadVector()
			local bVol = net.ReadBool()
			local midp = (maxp+minp)*0.5
			ObjMarkers[i] = {objn,minp,maxp,midp,bVol}
		end
	elseif tp==6 then -- delete obj marker
		if ObjMarkers then
			table.remove(ObjMarkers,net.ReadUInt(16))
		end
	elseif tp==7 then -- Move node
		local node = PathList[net.ReadUInt(16)]
		if node then
			node.P = net.ReadVector()
			node.m = net.ReadVector()
			node.x = net.ReadVector()
			if net.ReadBool() then
				if net.ReadBool() then
					node.f = NODETYPE_NavMesh
					node.e = {net.ReadVector(),net.ReadVector(),net.ReadVector(),net.ReadVector()}
					for i=1, 4 do
						node.e[i].z = node.e[i].z+1
					end
				else
					node.f = NODETYPE_NavMeshTris
					node.e = {net.ReadVector(),net.ReadVector(),net.ReadVector(),net.ReadVector()}
					for i=1, 4 do
						node.e[i].z = node.e[i].z+1
					end
					calcTrisNormal(node)
				end
			end
		end
	end
end)

local meta = FindMetaTable("Player")

function meta:UseBotAI()
	return false
end
