-- Bot AI path navigation, written by Marco
if ZSBOTAI.NAV_IS_LOADED then return end
ZSBOTAI.NAV_IS_LOADED = true

AddCSLuaFile("cl_botnavigation.lua")

GM.IsNavigationExist = false
GM.IsBotSpawned = false

local util_TraceHull = util.TraceHull
local numNavs = 0
local MapNavigationList = nil
local MapObjMarkers = nil
local navfilename = "ai/AI_"..string.lower(game.GetMap())..".txt"
local PathsDirty = false

-- Networking:
util.AddNetworkString("zs_ai_recpaths")
util.AddNetworkString("zs_ai_debugreach")

local NetworkedPlayers = false
local SendPLList = {}
local PendingNetwork = nil
local NodeIndex = -1

local FileSerialTag = 212
local FileSerialVer = 1

-- Cache for faster access.
local NODETYPE_Walk = ZSBOTAI.PATH_Type.Walk
local NODETYPE_Fly = ZSBOTAI.PATH_Type.Fly
local NODETYPE_Swim = ZSBOTAI.PATH_Type.Swim
local NODETYPE_Ladder = ZSBOTAI.PATH_Type.Ladder
local NODETYPE_Objective = ZSBOTAI.PATH_Type.Objective
local NODETYPE_NavMesh = ZSBOTAI.PATH_Type.NavMesh
local NODETYPE_NavMeshTris = ZSBOTAI.PATH_Type.NavMeshTris
local NODETYPE_NoQuitNode = ZSBOTAI.PATH_Type.NoQuitNode
local NODETYPE_ZSpawn = ZSBOTAI.PATH_Type.ZSpawn

local NavMeshNode = {[NODETYPE_NavMesh]=true,[NODETYPE_NavMeshTris]=true}

local NODEFLAGS_NoAutoPath = ZSBOTAI.PATH_ExtraType.NoAutoPath

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

local DEFROUTE_Swim = bit.bor(REACHTYPE_Walk,REACHTYPE_Swim) -- Walking units can also swim...
local ROUTE_SpecialMove = bit.bor(REACHTYPE_Headcrab,REACHTYPE_Leap,REACHTYPE_Climb,REACHTYPE_Door,REACHTYPE_Teleport,REACHTYPE_NoStrafeTo) -- These require special preparations

local NodeTypeConvert = {
	[0] = NODETYPE_Walk,
	[1] = NODETYPE_Swim, -- Water
	[2] = NODETYPE_Fly, -- Fly
	[3] = NODETYPE_Objective, -- Armory
	[5] = NODETYPE_Walk, -- Autopath
	[6] = NODETYPE_Ladder, -- Ladder
}

local E_GetPos = FindMetaTable("Entity").GetPos

local function PointAABoxCheck( b, m, x )
	return (b.x>=m.x) and (b.x<=x.x) and (b.y>=m.y) and (b.y<=x.y) and (b.z>=m.z) and (b.z<=x.z)
end

local function AABoxOverlapCheck( am, ax, bm, bx, ext )
	return  (ax.x+ext)>=bm.x and (bx.x+ext)>=am.x and
			(ax.y+ext)>=bm.y and (bx.y+ext)>=am.y and
			(ax.z+ext)>=bm.z and (bx.z+ext)>=am.z
end

local function LinePlaneIntersection( Point1, Point2, PlaneOrigin, PlaneNormal )
	local dir = (Point2-Point1)
	return
		Point1
	+	dir
	*	((PlaneOrigin - Point1):Dot(PlaneNormal) / dir:Dot(PlaneNormal))
end

local function FindNodeFloorHeight( p, node )
	if node.n.z>=0.999 then
		return node.P.z
	else
		return LinePlaneIntersection(p+Vector(0,0,100),p,node.P,node.n).z
	end
end

local function GetNextNIndex()
	NodeIndex = bit.band(NodeIndex+1,15)
	return NodeIndex
end

local function StartNavMsg( code )
	net.Start("zs_ai_recpaths")
	net.WriteUInt(code,3)
end

local function GetReachFlags( movetype )
	if movetype==NODETYPE_Fly then
		return REACHTYPE_Fly
	elseif movetype==NODETYPE_Swim then
		return DEFROUTE_Swim
	else
		return REACHTYPE_Walk
	end
end

local function CleanupRefs()
	for _, rs in ipairs(MapNavigationList) do
		for _, r in ipairs(rs) do
			if r._Door then
				r._Door = nil
			end
		end
	end
end

function ZSBOTAI.InitNavigationNetwork()
	if MapNavigationList then return end -- already loaded.

	local map = string.lower(game.GetMap())
	if file.Exists("ai/AI_" .. map .. ".txt", "DATA") then
		navfilename = "ai/AI_" .. map .. ".txt"
	elseif file.Exists("ai/ai_" .. map .. ".txt", "DATA") then
		navfilename = "ai/ai_" .. map .. ".txt"
	end

	local f = file.Open(navfilename,"rb","DATA")
	if f then
		local ConvertFlags = false
		local succ, err = pcall(function()
			local v = f:ReadByte()
			if v==FileSerialTag then
				v = f:ReadByte()
				if v==0 then -- Old format.
					ConvertFlags = true
				end

				GAMEMODE.IsNavigationExist = true

				MapNavigationList = {}
				numNavs = f:ReadIndex()

				local pos,minb,maxb,flags,nodetype,exflags,edges,nspecs,specs,enode,rflags,cost
				local numobj,ObjNum,bVol

				if v==0 then -- Convert to new version binary.
					for i=1, numNavs do
						pos = f:ReadVector()
						minb = f:ReadVector()
						maxb = f:ReadVector()
						flags = f:ReadIndex()
						nspecs = f:ReadIndex()
						specs = {}
						for j=1, nspecs do
							enode = f:ReadIndex()
							rflags = f:ReadIndex()
							cost = f:ReadLong()
							specs[j] = {e=enode,f=rflags,d=cost}
						end
						MapNavigationList[i] = {P=pos,m=minb,x=maxb,f=flags,r=specs}
					end

					numobj = f:ReadIndex()
					if numobj>0 then
						MapObjMarkers = {}
						for i=1, numobj do
							ObjNum = f:ReadIndex()
							minb = f:ReadVector()
							maxb = f:ReadVector()
							MapObjMarkers[#MapObjMarkers+1] = {ObjNum,minb,maxb}
						end
					end
				else
					for i=1, numNavs do
						pos = f:ReadVector()
						minb = f:ReadVector()
						maxb = f:ReadVector()
						nodetype = f:ReadIndex()
						exflags = f:ReadIndex()
						nspecs = f:ReadIndex()
						specs = {}
						for j=1, nspecs do
							enode = f:ReadIndex()
							rflags = f:ReadIndex()
							cost = f:ReadLong()
							specs[j] = {e=enode,f=rflags,d=cost}
							if bit.band(rflags,REACHTYPE_Door)~=0 then
								specs[j].i = f:ReadIndex()
							end
						end
						local tab = {P=pos,m=minb,x=maxb,f=nodetype,ex=exflags,rf=GetReachFlags(nodetype),r=specs}
						if nodetype==NODETYPE_NavMesh then
							edges = {}
							for j=1, 4 do
								edges[j] = f:ReadVector()
							end
							tab.e = edges
							tab.n = f:ReadVector()
							tab.w = f:ReadFloat()
						elseif nodetype==NODETYPE_NavMeshTris then
							edges = {}
							for j=1, 3 do
								edges[j] = f:ReadVector()
							end
							tab.e = edges
							tab.n = f:ReadVector()
							tab.w = f:ReadFloat()
							tab.side = f:ReadByte()
							tab.sn = f:ReadVector()
							tab.sw = f:ReadFloat()
						elseif nodetype==NODETYPE_ZSpawn then
							tab.ObjNum = f:ReadIndex()
							tab.yaw = f:ReadByte()
						end
						MapNavigationList[i] = tab
					end

					numobj = f:ReadIndex()
					if numobj>0 then
						MapObjMarkers = {}
						for i=1, numobj do
							ObjNum = f:ReadIndex()
							bVol = (bit.band(ObjNum,1)~=0)
							minb = f:ReadVector()
							maxb = f:ReadVector()
							MapObjMarkers[#MapObjMarkers+1] = {bit.rshift(ObjNum,1),minb,maxb,bVol}
						end
					end
				end
			else
				-- Old json format, convert to binary version.
				ConvertFlags = true
				DEBUG_MessageDev("Converting map pathdata version to up to date binary...",false,0,true)
				f:Seek(0)
				local s = f:Read(f:Size())
				MapNavigationList = util.JSONToTable(s)
				if MapNavigationList then
					GAMEMODE.IsNavigationExist = true
					ZSBOTAI.MarkPathsDirty()

					if MapNavigationList[0] then
						MapObjMarkers = MapNavigationList[0].O
						MapNavigationList[0] = nil
					end
				end
			end
		end)
		f:Close()

		if not succ then
			DEBUG_MessageDev("WARNING Failed to load map path data: "..err,false,1)
			MapNavigationList = nil
			MapObjMarkers = nil
		elseif ConvertFlags then
			ZSBOTAI.MarkPathsDirty()

			-- Convert nodes
			for _, n in ipairs(MapNavigationList) do
				n.f = NodeTypeConvert[n.f or 0]
				n.ex = (n.f==NODETYPE_Ladder and NODEFLAGS_NoAutoPath or 0)
				n.rf = GetReachFlags(n.f)
			end

			-- Convert reachspecs
			for _, n in ipairs(MapNavigationList) do
				local rs = n.r
				for _, r in ipairs(rs) do
					local en = MapNavigationList[r.e]
					local nf = 0
					local of = r.f or 0

					if bit.band(of,8)~=0 then
						nf = bit.bor(REACHTYPE_Walk,REACHTYPE_Teleport)
					elseif bit.band(of,7)==0 then
						if n.f==NODETYPE_Fly or en.f==NODETYPE_Fly then
							nf = REACHTYPE_Fly
						elseif n.f==NODETYPE_Swim or en.f==NODETYPE_Swim then
							nf = DEFROUTE_Swim
						else
							nf = REACHTYPE_Walk
						end
					else
						if bit.band(of,1)~=0 then
							nf = bit.bor(nf,REACHTYPE_Leap)
						end
						if bit.band(of,2)~=0 then
							nf = bit.bor(nf,REACHTYPE_Climb)
						end
						if bit.band(of,4)~=0 then
							nf = bit.bor(nf,REACHTYPE_Headcrab)
						end
					end

					r.f = nf
				end
			end
		end
	end

	if not MapNavigationList then
		MapNavigationList = {}
	end

	numNavs = #MapNavigationList

	-- Setup references
	for i=1, numNavs do
		MapNavigationList[i].Index = i
		NodeIndex = bit.band(NodeIndex+1,15)
		MapNavigationList[i].NetID = NodeIndex
		local rs = MapNavigationList[i].r
		for j=1, #rs do
			rs[j].e = MapNavigationList[rs[j].e]
		end
	end

	ZSBOTAI.CreatePathOctree()

	hook.Add("PostCleanupMap","PostCleanupMap.CleanupDoorRefs",CleanupRefs)
end

local function SaveNavigationNetwork()
	if not PathsDirty then return end

	hook.Remove("ShutDown","ShutDown.SavePathNetworks")

	PathsDirty = false
	--if true then return end -- ============DELETEME=================== DEBUG DONT SAVE ATM!
	local f = file.Open(navfilename,"wb","DATA")
	if f then
		f:WriteByte(FileSerialTag)
		f:WriteByte(FileSerialVer)
		f:WriteIndex(numNavs)
		for _, nav in ipairs(MapNavigationList) do
			f:WriteVector(nav.P)
			f:WriteVector(nav.m)
			f:WriteVector(nav.x)
			f:WriteIndex(nav.f)
			f:WriteIndex(nav.ex)
			local rl = nav.r
			f:WriteIndex(#rl)
			for _, r in ipairs(rl) do
				f:WriteIndex(r.e.Index)
				f:WriteIndex(r.f)
				f:WriteLong(r.d)
				if bit.band(r.f,REACHTYPE_Door)~=0 then
					f:WriteIndex(r.i or 0)
				end
			end
			if nav.f==NODETYPE_NavMesh then
				local e = nav.e
				for j=1, 4 do
					f:WriteVector(e[j])
				end
				f:WriteVector(nav.n)
				f:WriteFloat(nav.w)
			elseif nav.f==NODETYPE_NavMeshTris then
				local e = nav.e
				for j=1, 3 do
					f:WriteVector(e[j])
				end
				f:WriteVector(nav.n)
				f:WriteFloat(nav.w)
				f:WriteByte(nav.side)
				f:WriteVector(nav.sn)
				f:WriteFloat(nav.sw)
			elseif nav.f==NODETYPE_ZSpawn then
				f:WriteIndex(nav.ObjNum)
				f:WriteByte(nav.yaw)
			end
		end
		if MapObjMarkers then
			f:WriteIndex(#MapObjMarkers)
			for _, obj in ipairs(MapObjMarkers) do
				f:WriteIndex(bit.bor(bit.lshift(obj[1],1),obj[4] and 1 or 0))
				f:WriteVector(obj[2])
				f:WriteVector(obj[3])
			end
		else
			f:WriteIndex(0)
		end
		f:Close()
		DEBUG_MessageDev("Created new pathdata version: "..navfilename,true,0)
	else
		DEBUG_MessageDev("Error: Couldn't create pathdata file (file may be write locked)!",false,1,true)
	end
	--ZSBOTAI.CreatePathOctree()
end

function ZSBOTAI.MarkPathsDirty()
	if not PathsDirty then
		timer.Simple(30, SaveNavigationNetwork)
		PathsDirty = true
		hook.Add("ShutDown","ShutDown.SavePathNetworks",SaveNavigationNetwork)
	end
end

local OCT_MaxGridSize = 65536 -- Map maximum grid size.
local OCT_MinOctantSize = 1024 -- Minimum octant size.
local OCT_MaxNodes = 6 -- Max nodes per octant.

local function GetFilterFlags( Node, Octant )
	local p = Octant.P
	local tmin,tmax = Node.m,Node.x

	-- Filter down this node.
	local x,y,z
	if tmax.x<=p.x then
		x = 1
	elseif tmin.x>=p.x then
		x = 2
	else
		x = 3
	end

	if tmax.y<=p.y then
		y = 1
	elseif tmin.y>=p.y then
		y = 2
	else
		y = 3
	end

	if tmax.z<=p.z then
		z = 1
	elseif tmin.z>=p.z then
		z = 2
	else
		z = 3
	end
	return x,y,z
end

local function FilterNode( Node, Octant )
	local cn = Octant.N
	if cn and #cn>OCT_MaxNodes and Octant.E>OCT_MinOctantSize then
		-- Create new children.
		local chl = {}
		local ext = Octant.E/2
		local pos = Octant.P
		Octant.C = chl
		for i=0, 7 do
			local x = bit.band(i,1)==0 and (-ext) or ext
			local y = bit.band(i,2)==0 and (-ext) or ext
			local z = bit.band(i,4)==0 and (-ext) or ext
			chl[i+1] = {P=Vector(pos.x+x,pos.y+y,pos.z+z),E=ext}
		end

		-- Filter down this nodes children too.
		Octant.N = nil
		for i=1, #cn do
			FilterNode(cn[i],Octant)
		end
	end

	local on = Octant.C
	if not on then -- Has no child nodes, simply insert here.
		if not cn then
			cn = {}
			Octant.N = cn
		end
		cn[#cn+1] = Node
		return
	end

	-- Filter down this node.
	local x,y,z = GetFilterFlags(Node,Octant)
	for i=0, 7 do
		local xf = bit.band(i,1)==0 and 1 or 2
		local yf = bit.band(i,2)==0 and 1 or 2
		local zf = bit.band(i,4)==0 and 1 or 2

		if bit.band(xf,x)~=0 and bit.band(yf,y)~=0 and bit.band(zf,z)~=0 then
			FilterNode(Node,on[i+1])
		end
	end
end

local OctreeMain

local function AddToOctree( Node )
	if Node.f~=NODETYPE_Ladder then -- Skip ladders.
		FilterNode(Node,OctreeMain)
	end
end

function ZSBOTAI.CreatePathOctree()
	OctreeMain = {P=Vector(0,0,0),E=OCT_MaxGridSize}

	for i=1, numNavs do
		AddToOctree(MapNavigationList[i])
	end
end

local function RemoveNode( Node, Octant )
	local cn = Octant.N
	if cn then
		for i=1, #cn do
			if cn[i]==Node then
				table.remove(cn,i)
				break
			end
		end
	else
		cn = Octant.C
		if cn then
			-- Filter down this node.
			local x,y,z = GetFilterFlags(Node,Octant)
			for i=0, 7 do
				local xf = bit.band(i,1)==0 and 1 or 2
				local yf = bit.band(i,2)==0 and 1 or 2
				local zf = bit.band(i,4)==0 and 1 or 2

				if bit.band(xf,x)~=0 and bit.band(yf,y)~=0 and bit.band(zf,z)~=0 then
					RemoveNode(Node,cn[i+1])
				end
			end
		end
	end
end

local function RemoveFromOctree( Node )
	if OctreeMain and Node.f~=NODETYPE_Ladder then
		RemoveNode(Node,OctreeMain)
	end
end

local Test_Point
local Test_Results
local Test_Tag = 0
local BOT_MOVEMENT_FLAGS = 1

local function LookupCnodes( Octant )
	local cn = Octant.N
	if cn then
		for _, nav in ipairs(cn) do
			if nav._TTag~=Test_Tag then
				nav._TTag = Test_Tag
				if bit.band(nav.rf,BOT_MOVEMENT_FLAGS)~=0 and PointAABoxCheck(Test_Point,nav.m,nav.x) then
					nav._NextResult = Test_Results
					Test_Results = nav
				end
			end
		end
	else
		cn = Octant.C
		if cn then
			local pos = Octant.P
			local i = (Test_Point.x>pos.x) and 1 or 0
			if Test_Point.y>pos.y then
				i = bit.bor(i,2)
			end
			if Test_Point.z>pos.z then
				i = bit.bor(i,4)
			end
			LookupCnodes(cn[i+1])
		end
	end
end

function ZSBOTAI.FindNodesAt( pos, flags )
	if not OctreeMain then return end

	BOT_MOVEMENT_FLAGS = flags or REACHTYPE_Walk
	Test_Point = pos
	Test_Results = false
	Test_Tag = Test_Tag+1
	LookupCnodes(OctreeMain)
	return Test_Results
end

local function VerifyBlockedPaths( pl )
	local t = CurTime()

	for ix, et in pairs(pl.BOT_BlockedPaths) do
		if et<t then
			pl.BOT_BlockedPaths[ix] = nil
		end
	end
end

local AtFixedAnchor = false
local BT_bottom, BT_top
local DR_FilterDoor
local DR_TraceRes = {}
local DR_TraceInfo = {filter=function( e ) return e==DR_FilterDoor end,mins=Vector(-16,-16,0),maxs=Vector(16,16,16),mask=MASK_PLAYERSOLID,ignoreworld=true,output=DR_TraceRes}

local function TestDoorOpen( s, e )
	if (DR_FilterDoor._CHTime or 0)<CurTime() then
		DR_TraceInfo.start = s.P
		DR_TraceInfo.endpos = e.P
		util.TraceHull(DR_TraceInfo)

		DR_FilterDoor._DOpen = not DR_TraceRes.Hit
		DR_FilterDoor._CHTime = CurTime()+6
	end
	return DR_FilterDoor._DOpen
end

local function GetNextNode( pl, currentnode, nextnode )
	-- Handle navmesh area
	if currentnode.e then
		if not nextnode then -- reached goal?
			currentnode.nv = currentnode.P
		elseif not nextnode.e then -- Exit navmesh area.
			return nextnode
		else
			-- Find center crossing
			local ext = BT_top.x
			local bXEdge = (math.min(math.abs(currentnode.m.x-nextnode.x.x),math.abs(currentnode.x.x-nextnode.m.x))<math.min(math.abs(currentnode.m.y-nextnode.x.y),math.abs(currentnode.x.y-nextnode.m.y)))
			local midp,dir,inext,outext
			local plpos = E_GetPos(pl)
			local bInside = false
			local minedge,maxedge,cnt,plaxis

			-- Find crossing height.
			if bXEdge then -- edges along X-axis are parallel
				minedge = math.max(currentnode.m.y,nextnode.m.y)
				maxedge = math.min(currentnode.x.y,nextnode.x.y)
				plaxis = plpos.y
			else -- Y-axis
				minedge = math.max(currentnode.m.x,nextnode.m.x)
				maxedge = math.min(currentnode.x.x,nextnode.x.x)
				plaxis = plpos.x
			end

			if (minedge+ext)>=(maxedge-ext) then -- Doesn't really fit here so hack it...
				cnt = (maxedge-minedge)*0.5 + minedge
				minedge = cnt-5
				maxedge = cnt+5
			else
				minedge = minedge+ext
				maxedge = maxedge-ext
			end
			if minedge<=plaxis and maxedge>=plaxis then
				bInside = true
				cnt = plaxis
			else
				cnt = (minedge<plaxis) and maxedge or minedge
			end

			if bXEdge then
				inext = math.min(ext,currentnode.x.x-currentnode.m.x)
				outext = math.min(ext,nextnode.x.x-nextnode.m.x)

				if currentnode.P.x<nextnode.P.x then
					midp = Vector(currentnode.x.x,cnt,currentnode.P.z)
					dir = Vector(-1,0,0)
				else
					midp = Vector(currentnode.m.x,cnt,currentnode.P.z)
					dir = Vector(1,0,0)
				end
			else
				inext = math.min(ext,currentnode.x.y-currentnode.m.y)
				outext = math.min(ext,nextnode.x.y-nextnode.m.y)

				if currentnode.P.y<nextnode.P.y then
					midp = Vector(cnt,currentnode.x.y,currentnode.P.z)
					dir = Vector(0,-1,0)
				else
					midp = Vector(cnt,currentnode.m.y,currentnode.P.z)
					dir = Vector(0,1,0)
				end
			end

			local sn = midp+(dir*inext)
			if bInside or (plpos-sn):Length2DSqr()<2500 then
				currentnode = nextnode
				currentnode.nv = midp-(dir*outext)
			else
				currentnode.nv = sn
			end
			currentnode.nv.z = FindNodeFloorHeight(currentnode.nv,currentnode)

			if bit.band(BOT_MOVEMENT_FLAGS,REACHTYPE_Fly)~=0 then -- set flying height.
				local testp = Vector(currentnode.nv.x,currentnode.nv.y,(currentnode.x.z+currentnode.nv.z)*0.5)
				if ZSBOTAI.DirectReachable(testp,plpos,BT_bottom,BT_top) then
					currentnode.nv = testp
				elseif not ZSBOTAI.DirectReachable(currentnode.nv,plpos,BT_bottom,BT_top) then -- try to land to reach through.
					local flrz = FindNodeFloorHeight(plpos,currentnode)
					if (flrz+100)<plpos.z then
						currentnode.nv = Vector(plpos.x,plpos.y,FindNodeFloorHeight(plpos,currentnode))
					end
				end
			end
		end
	end
	return currentnode
end

local function breathPathTo( pl, startAnchor )
	-- Find best path towards end anchor.
	local BestDest = nil
	local currentnode = startAnchor
	local LastAdd = currentnode
	local BLCK = pl.BOT_BlockedPaths

	if not currentnode then return end

	currentnode.visitedWeight = 0
	while currentnode do
		currentnode.taken = true
		if currentnode.bEndPoint and (not BestDest or (BestDest.visitedWeight or 0)>(currentnode.visitedWeight or 0)) then
			BestDest = currentnode
		end

		if not currentnode.r then break end
		for _, reach in ipairs(currentnode.r) do
			if not reach then continue end

			local endnode = reach.e
			if not endnode then continue end

			if not endnode.taken and bit.band(reach.f,BOT_MOVEMENT_FLAGS) ~= 0 and BLCK and endnode.Index and not BLCK[endnode.Index] then
				if reach.i then -- Handle doors.
					DR_FilterDoor = reach._Door
					if DR_FilterDoor==nil then
						DR_FilterDoor = ents.GetMapCreatedEntity(reach.i)
						reach._Door = DR_FilterDoor
					end
					if DR_FilterDoor~=false then
						if IsValid(DR_FilterDoor) then
							if not TestDoorOpen(currentnode,endnode) then
								continue
							end
						else
							reach._Door = false
						end
					end
				end

				local newVisit = reach.d + currentnode.visitedWeight

				if not endnode.visitedWeight or endnode.visitedWeight > newVisit then
					-- found a better path to endnode
					endnode.previousPath = currentnode

					if endnode.prevOrdered then -- remove from old position
						endnode.prevOrdered.nextOrdered = endnode.nextOrdered
						if endnode.nextOrdered then
							endnode.nextOrdered.prevOrdered = endnode.prevOrdered
						end
						if LastAdd==endnode or (LastAdd.visitedWeight > (endnode.visitedWeight or 0)) then
							LastAdd = endnode.prevOrdered
						end
						endnode.prevOrdered = nil
						endnode.nextOrdered = nil
					end
					endnode.visitedWeight = newVisit

					-- LastAdd is a good starting point for searching the list and inserting this node
					local nextnode = LastAdd
					if not nextnode then break end

					if nextnode.visitedWeight <= newVisit then
						while nextnode.nextOrdered and nextnode.nextOrdered.visitedWeight and (nextnode.nextOrdered.visitedWeight < newVisit) do
							nextnode = nextnode.nextOrdered
						end
					else
						while nextnode.prevOrdered and nextnode.visitedWeight and nextnode.visitedWeight > newVisit do
							nextnode = nextnode.prevOrdered
						end
					end

					if nextnode.nextOrdered ~= endnode then
						if nextnode.nextOrdered then
							nextnode.nextOrdered.prevOrdered = endnode
						end
						endnode.nextOrdered = nextnode.nextOrdered
						nextnode.nextOrdered = endnode
						endnode.prevOrdered = nextnode
					end
					LastAdd = endnode
				end
			end
		end
		currentnode = currentnode.nextOrdered
	end

	if BestDest then
		-- Lookup next route.
		currentnode = startAnchor
		local NextNode, NNextNode
		local testNode = BestDest
		while testNode.previousPath and testNode~=currentnode do
			NNextNode = NextNode
			NextNode = testNode
			testNode = testNode.previousPath
		end

		-- Lookup next path thats not overlapping this one.
		if NextNode and AtFixedAnchor and not currentnode.e then
			currentnode = NextNode
			NextNode = NNextNode
		end

		-- Handle navmesh area
		currentnode = GetNextNode(pl,currentnode,NextNode)

		pl.BOT_LastDest = currentnode

		if currentnode~=startAnchor then
			-- Check route type.
			local rs = startAnchor.r
			for _, rslt in ipairs(rs) do
				if rslt.e==currentnode then
					local f = bit.band(rslt.f,ROUTE_SpecialMove)
					pl.BOT_PendingMoveFlags = (f>0 and f or nil)
					break
				end
			end
		end

		if pl.AIProfilers then
			ZSBOTAI.BotOrders(pl,2,currentnode,BestDest)
		end
	end

	-- Reset cached data
	for _, nav in ipairs(MapNavigationList) do
		nav.visitedWeight = nil
		nav.nextOrdered = nil
		nav.prevOrdered = nil
		nav.previousPath = nil
		nav.bEndPoint = nil
		nav.taken = nil
	end

	return currentnode
end

local function PointInsideNavArea( p, n )
	if not PointAABoxCheck(p,n.m,n.x) then return false end

	if n.f==NODETYPE_NavMeshTris and p:Dot(n.sn)<n.sw then return false end

	if n.n.z==1 then return true end -- Flat plane.

	return p:Dot(n.n)>(n.w-5) -- Is in top side of the plane.
end

local function OverlapsNode( plypos, node, verb )
	if node.e then
		return PointInsideNavArea(plypos,node)
	else
		local v = plypos-node.P
		return v:Length2DSqr()<2500 and math.abs(v.z-(BT_top.z*0.5))<64
	end
end

local function FindAnchor( pl, plypos, startPos )
	-- Try to use cached data if possible.
	if pl.BOT_LastDest and OverlapsNode(startPos,pl.BOT_LastDest) then
		AtFixedAnchor = true
		pl.BOT_LastAnchor = pl.BOT_LastDest
		return pl.BOT_LastDest
	elseif pl.BOT_LastAnchor and OverlapsNode(startPos,pl.BOT_LastAnchor) then
		AtFixedAnchor = true
		return pl.BOT_LastAnchor
	end

	local bestAnchor = false
	local bestDist
	local bInWater = (pl:WaterLevel()>=2)
	BOT_MOVEMENT_FLAGS = (pl.BOT_MoveFlags or REACHTYPE_Walk)
	local bFlyMove = (bit.band(BOT_MOVEMENT_FLAGS,REACHTYPE_Fly)~=0)
	local BLCK = pl.BOT_BlockedPaths

	-- Find start anchor.
	local nav
	nav = ZSBOTAI.FindNodesAt(startPos,BOT_MOVEMENT_FLAGS)
	while nav do
		if BLCK and nav.Index and not BLCK[nav.Index] then
			local dist = startPos:DistToSqr(nav.P)
			if nav.e then
				dist = dist*0.1
				if (not bestAnchor or bestDist>dist) and PointInsideNavArea(plypos,nav) then
					bestAnchor = nav
					bestDist = dist
				end
			elseif (not bestAnchor or bestDist>dist) and ((bFlyMove or (bInWater and nav.f==NODETYPE_Swim)) and ZSBOTAI.DirectReachable(nav.P, plypos, BT_bottom, BT_top) or ZSBOTAI.PointReachable(nav.P, plypos, BT_bottom, BT_top, false, true)) then
				bestAnchor = nav
				bestDist = dist
			end
		end
		nav = nav._NextResult
	end
	if bestAnchor then
		AtFixedAnchor = OverlapsNode(startPos,bestAnchor)
		pl.BOT_LastAnchor = bestAnchor
		return bestAnchor
	end
end

function ZSBOTAI.FindPathToward( pl, Destination, huntPath )
	pl.BOT_PendingMoveFlags = nil
	if pl.BOT_NextCheckRouteTime<CurTime() then
		pl.BOT_NextCheckRouteTime = CurTime()+10
		VerifyBlockedPaths(pl)
	end

	BOT_MOVEMENT_FLAGS = (pl.BOT_MoveFlags or REACHTYPE_Walk)
	local bFlyMove = (bit.band(BOT_MOVEMENT_FLAGS,REACHTYPE_Fly)~=0)

	-- Trace to floor to find start/end positions.
	if pl:Crouching() then
		BT_bottom, BT_top = pl:GetHullDuck()
	else
		BT_bottom, BT_top = pl:GetHull()
	end
	local plypos = E_GetPos(pl)
	local startPos = Vector(plypos)

	if not bFlyMove then -- Make src from ground height.
		local tr = util_TraceHull( ZSBOTAI.GetReachTraceInfo(plypos,plypos-Vector(0,0,200),BT_bottom,BT_top) )
		if tr.Hit then
			startPos = tr.HitPos
		end
	end
	startPos.z = startPos.z+(BT_top.z*0.5)

	local endPos
	local bDestWater
	if isvector(Destination) then
		endPos = Vector(Destination)
		bDestWater = (bit.band(util.PointContents(endPos),CONTENTS_WATER)~=0)
	elseif IsValid(Destination) then
		endPos = E_GetPos(Destination)
		bDestWater = (Destination:WaterLevel()>=2)
	else
		return
	end

	if not bFlyMove then -- Make destination start from floor.
		local tr = util_TraceHull( ZSBOTAI.GetReachTraceInfo(endPos,endPos-Vector(0,0,150),Vector(-8,-8,0),Vector(8,8,0)) )
		if tr.Hit then
			endPos = tr.HitPos
		end
	end

	if WorldVisible(endPos,endPos+Vector(0,0,18)) then
		endPos.z = endPos.z + 16
	end

	local startAnchor = FindAnchor(pl,plypos,startPos)
	local foundEnd = 0
	local BLCK = pl.BOT_BlockedPaths

	-- Find end anchor
	local nav = ZSBOTAI.FindNodesAt(endPos,BOT_MOVEMENT_FLAGS)
	local endnav = nav
	while nav do
		if BLCK and nav.Index and not BLCK[nav.Index] then
			if nav.e then
				if PointInsideNavArea(endPos,nav) then
					nav.bEndPoint = true
					foundEnd = foundEnd+1
					if foundEnd>=4 then break end
				end
			elseif (bFlyMove or (bDestWater and nav.f==NODETYPE_Swim)) and ZSBOTAI.DirectReachable(Destination, nav.P, BT_bottom, BT_top, 25) or ZSBOTAI.PointReachable(Destination, nav.P, BT_bottom, BT_top, 5, true, true) then
				nav.bEndPoint = true
				foundEnd = foundEnd+1
				if foundEnd>=4 then break end
			end
		end
		nav = nav._NextResult
	end

	if foundEnd==0 and not bFlyMove then -- Pick more leniant dest.
		local bestDest = nil
		local bestDist
		nav = endnav
		while nav do
			if BLCK and nav.Index and not BLCK[nav.Index] then
				local dist = endPos:DistToSqr(nav.P)
				if nav.e then
					dist = dist*0.1
					if (not bestDest or bestDist>dist) and (PointInsideNavArea(endPos,nav) or ZSBOTAI.PointReachable(Destination, nav.P, BT_bottom, BT_top, 25, false, true)) then
						bestDest = nav
						bestDist = dist
					end
				elseif (not bestDest or bestDist>dist) and (not bDestWater or nav.f~=NODETYPE_Swim) and ZSBOTAI.PointReachable(Destination, nav.P, BT_bottom, BT_top, 25, false, true) then
					bestDest = nav
					bestDist = dist
				end
			end
			nav = nav._NextResult
		end

		if bestDest then
			bestDest.bEndPoint = true
			foundEnd = foundEnd+1
		end
	end

	if foundEnd==0 and huntPath then
		-- Pick a nearby visible endpath.
		nav = endnav
		while nav do
			if BLCK and nav.Index and not BLCK[nav.Index] and WorldVisible(nav.P+Vector(0,0,16),endPos) then
				nav.bEndPoint = true
				foundEnd = foundEnd+1
				if foundEnd>=3 then
					break
				end
			end
			nav = nav._NextResult
		end
	end

	if not startAnchor or foundEnd==0 then
		return
	end

	-- Find path
	local BestDest = breathPathTo(pl,startAnchor)
	if BestDest then
		ZSBOTAI.CheckBlockedAIPath(pl,BestDest)

		if BestDest.e then -- Handle navmesh area.
			return BestDest.nv
		elseif BestDest.f == NODETYPE_Ladder then -- Handle ladder hack.
			pl.BOT_PendingLadder = true
		end

		pl.ShouldQuitNode = BestDest.f == NODETYPE_NoQuitNode

		local res = util.FindSpot(BestDest.P,BT_bottom,BT_top)
		if isvector(res) then return res end

		return BestDest.P
	end
end

function ZSBOTAI.FindRandomPath( pl, targetNode )
	pl.BOT_PendingMoveFlags = nil
	if pl.BOT_NextCheckRouteTime<CurTime() then
		pl.BOT_NextCheckRouteTime = CurTime()+10
		VerifyBlockedPaths(pl)
	end

	BOT_MOVEMENT_FLAGS = (pl.BOT_MoveFlags or REACHTYPE_Walk)
	local bFlyMove = (bit.band(BOT_MOVEMENT_FLAGS,REACHTYPE_Fly)~=0)

	-- Trace to floor to find start/end positions.
	if pl:Crouching() then
		BT_bottom, BT_top = pl:GetHullDuck()
	else
		BT_bottom, BT_top = pl:GetHull()
	end
	local plypos = E_GetPos(pl)
	local startPos = Vector(plypos)

	if not bFlyMove then -- Make src from ground height.
		local tr = util_TraceHull( ZSBOTAI.GetReachTraceInfo(plypos,plypos-Vector(0,0,200),BT_bottom,BT_top) )
		if tr.Hit then
			startPos = tr.HitPos
		end
	end
	startPos.z = startPos.z+(BT_top.z*0.5)

	local startAnchor = FindAnchor(pl,plypos,startPos)
	if not startAnchor then
		return
	end
	local BLCK = pl.BOT_BlockedPaths

	if targetNode then
		targetNode = MapNavigationList[targetNode]
	end
	local BestDest

	for iteration=1, 2 do
		if not targetNode then -- Must find a random target node first!
			-- Start with simply tagging all nodes we can walk to.
			local currentnode = startAnchor
			currentnode.taken = true
			currentnode.nextOrdered = nil
			local n = 0
			while currentnode do
				n = n+1

				if not currentnode.r then break end
				for _, reach in ipairs(currentnode.r) do
					if not reach then continue end

					local endnode = reach.e
					if not endnode then continue end

					if not endnode.taken and bit.band(reach.f,BOT_MOVEMENT_FLAGS)~=0 and BLCK and endnode.Index and not BLCK[endnode.Index] then
						if reach.i then -- Handle doors.
							DR_FilterDoor = reach._Door
							if DR_FilterDoor==nil then
								DR_FilterDoor = ents.GetMapCreatedEntity(reach.i)
								reach._Door = DR_FilterDoor
							end
							if DR_FilterDoor~=false then
								if IsValid(DR_FilterDoor) then
									if not TestDoorOpen(currentnode,endnode) then
										continue
									end
								else
									reach._Door = false
								end
							end
						end

						endnode.taken = true
						endnode.nextOrdered = currentnode.nextOrdered
						currentnode.nextOrdered = endnode
					end
				end
				currentnode = currentnode.nextOrdered
			end

			-- Pick random number.
			n = math.random(n)
			for i=1, numNavs do
				local nav = MapNavigationList[i]
				nav.nextOrdered = nil

				if nav.taken then
					nav.taken = nil
					n = n-1
					if n==0 then
						currentnode = nav
					end
				end
			end

			if not currentnode then -- WTF?
				return
			end
			targetNode = currentnode
		end

		if startAnchor==targetNode then
			if targetNode and targetNode.f==NODETYPE_Ladder then -- Handle ladder hack.
				pl.BOT_PendingLadder = true
			end

			pl.ShouldQuitNode = targetNode.f == NODETYPE_NoQuitNode

			return targetNode.P, -1
		end

		targetNode.bEndPoint = true

		-- Find path to random destination now.
		BestDest = breathPathTo(pl,startAnchor)

		-- No path found!
		if not BestDest then
			if iteration==2 then
				return
			end
			continue
		end
		break
	end

	-- Reached our goal!
	if BestDest==targetNode then
		targetNode = nil
	end
	ZSBOTAI.CheckBlockedAIPath(pl,BestDest)
	if BestDest.e then -- Handle navmesh area.
		return BestDest.nv, targetNode and targetNode.Index or -1
	elseif BestDest.f==NODETYPE_Ladder then -- Handle ladder hack.
		pl.BOT_PendingLadder = true
	end

	pl.ShouldQuitNode = BestDest.f == NODETYPE_NoQuitNode

	return BestDest.P, targetNode and targetNode.Index or -1
end

function ZSBOTAI.GetRetreatDest( pl, enemy )
	pl.BOT_PendingMoveFlags = nil
	if pl.BOT_NextCheckRouteTime<CurTime() then
		pl.BOT_NextCheckRouteTime = CurTime()+10
		VerifyBlockedPaths(pl)
	end

	BOT_MOVEMENT_FLAGS = (pl.BOT_MoveFlags or REACHTYPE_Walk)
	local bFlyMove = (bit.band(BOT_MOVEMENT_FLAGS,REACHTYPE_Fly)~=0)

	-- Trace to floor to find start/end positions.
	if pl:Crouching() then
		BT_bottom, BT_top = pl:GetHullDuck()
	else
		BT_bottom, BT_top = pl:GetHull()
	end
	local plypos = E_GetPos(pl)
	local startPos = Vector(plypos)

	if not bFlyMove then -- Make src from ground height.
		local tr = util_TraceHull( ZSBOTAI.GetReachTraceInfo(plypos,plypos-Vector(0,0,200),BT_bottom,BT_top) )
		if tr.Hit then
			startPos = tr.HitPos
		end
	end
	startPos.z = startPos.z+(BT_top.z*0.5)

	local startAnchor = FindAnchor(pl,plypos,startPos)
	if not startAnchor then
		return
	end
	local BLCK = pl.BOT_BlockedPaths
	local enemypos = E_GetPos(enemy)
	local bestRoute = false
	local bestDist

	local rs = startAnchor.r
	for _, reach in ipairs(rs) do
		local endnode = reach.e
		local dist = endnode.P:DistToSqr(enemypos)
		if dist<endnode.P:DistToSqr(startPos) then -- Avoid going past enemy!
			dist = dist*0.25
		end

		if bestRoute and bestDist>dist then continue end -- Skip already known to be too close to enemy!

		if bit.band(reach.f,BOT_MOVEMENT_FLAGS)~=0 and not BLCK[endnode.Index] then
			if reach.i then -- Handle doors.
				DR_FilterDoor = reach._Door
				if DR_FilterDoor==nil then
					DR_FilterDoor = ents.GetMapCreatedEntity(reach.i)
					reach._Door = DR_FilterDoor
				end
				if DR_FilterDoor~=false then
					if IsValid(DR_FilterDoor) then
						if not TestDoorOpen(currentnode,endnode) then
							continue
						end
					else
						reach._Door = false
					end
				end
			end

			bestRoute = endnode
			bestDist = dist
		end
	end

	if bestRoute then
		-- Handle navmesh area
		local result = startAnchor.e and GetNextNode(pl,startAnchor,bestRoute) or bestRoute

		pl.BOT_LastDest = result

		if result~=startAnchor then
			-- Check route type.
			for _, rslt in ipairs(startAnchor.r) do
				if rslt.e==result then
					local f = bit.band(rslt.f,ROUTE_SpecialMove)
					pl.BOT_PendingMoveFlags = (f>0 and f or nil)
					break
				end
			end
		end

		if result.e then -- Handle navmesh area.
			return result.nv
		elseif result.f==NODETYPE_Ladder then -- Handle ladder hack.
			pl.BOT_PendingLadder = true
		end

		pl.ShouldQuitNode = result.f == NODETYPE_NoQuitNode

		local res = util.FindSpot(result.P,BT_bottom,BT_top)
		if isvector(res) then return res end

		return result.P
	end
end

-- Cleanup recast paths
local function CleanupRecast( bnode )
	local CheckList = {bnode}

	-- Slow: Must search through entire navigation list to find all navs leading to this new path.
	for i=1, numNavs do
		local nav = MapNavigationList[i]
		if nav~=bnode and nav.f~=NODETYPE_Fly then
			local rs = nav.r
			for _, reach in ipairs(rs) do
				if reach.e==bnode and bit.band(reach.f,REACHTYPE_Walk)~=0 and reach.d<=1200 then -- Check non-special paths.
					CheckList[#CheckList+1] = nav
				end
			end
		end
	end

	local z = 1
	while z<=#CheckList do
		local nav = CheckList[z]
		local startp = nav.P
		local Found = 1

		while Found do
			Found = nil
			for i, reach in ipairs(nav.r) do
				if bit.band(reach.f,REACHTYPE_Walk)~=0 and reach.d<=1200 then -- Check non-special paths.
					local g = reach.e
					local mxd = reach.d
					local goalp = g.P

					-- Check if this goal has already an alternative similar route.
					local Dir = (goalp-startp):GetNormalized()

					local TestList = {nav}
					local j = 1
					while j<=#TestList do
						local cur = TestList[j]
						for _, rchb in pairs(cur.r) do
							if bit.band(rchb.f,REACHTYPE_Walk)~=0 and rchb.d<mxd and rchb~=reach and not table.HasValue(TestList,rchb.e) then
								if rchb.e==g then
									Found = g -- Found alt route.
									break
								end
								local testp = rchb.e.P
								if (testp-startp):GetNormalized():Dot(Dir)>0.9 and (goalp-testp):GetNormalized():Dot(Dir)>0.9 then -- Leads to a similar direction.
									TestList[#TestList+1] = rchb.e
								end
							end
						end
						if Found then break end
						j = j+1
					end

					if Found then
						table.remove(nav.r,i) -- Leave a more direct route hanging.

						if NetworkedPlayers then
							StartNavMsg(4)
								net.WriteUInt(nav.Index,16)
								net.WriteUInt(Found.Index,16)
							net.Send(SendPLList)
						end
						break
					end
				end
			end
		end

		if z==1 then
			for i, reach in ipairs(nav.r) do
				if bit.band(reach.f,REACHTYPE_Walk)~=0 and reach.d<=1200 and reach.e.f~=NODETYPE_Fly then -- Check non-special paths.
					CheckList[#CheckList+1] = reach.e
				end
			end
		end
		z = z+1
	end
end

-- To be called when a node was removed.
local function NotePathRemoved()
	for i, pl in ipairs(player.GetAllNoCopy()) do
		pl.BOT_LastDest = nil
		pl.BOT_LastAnchor = nil
	end
end

local DefaultHullMin = Vector(-16,-16,0)
local DefaultHullMax = Vector(16,16,36)

local function CalcNodeSize( node )
	local midpos = node.P+Vector(0,0,25)
	local minsize = Vector(node.P)
	local maxsize = Vector(midpos)

	if node.f~=NODETYPE_Ladder then -- Ladders dont need this
		local tri = {start=midpos, mask=MASK_PLAYERSOLID_BRUSHONLY}

		-- Then check around to figure out area bounding box size.
		for x=-1, 1 do
			for y=-1, 1 do
				for z=-1, 1 do
					if x==0 and y==0 and z==0 then
						continue
					end

					local endsize = midpos + Vector(x,y,z)*1200
					tri.endpos = endsize

					local tr = util.TraceLine(tri)
					if tr.Hit then
						endsize = tr.HitPos
					end

					minsize.x = math.min(minsize.x,endsize.x)
					minsize.y = math.min(minsize.y,endsize.y)
					minsize.z = math.min(minsize.z,endsize.z)
					maxsize.x = math.max(maxsize.x,endsize.x)
					maxsize.y = math.max(maxsize.y,endsize.y)
					maxsize.z = math.max(maxsize.z,endsize.z)
				end
			end
		end

		minsize.x = math.floor(minsize.x)-5
		minsize.y = math.floor(minsize.y)-5
		minsize.z = math.floor(minsize.z)-5
		maxsize.x = math.ceil(maxsize.x)+5
		maxsize.y = math.ceil(maxsize.y)+5
		maxsize.z = math.ceil(maxsize.z)+5
	end

	node.m = minsize
	node.x = maxsize
end

-- Check if 2 NavAreas has coplanar edges
local function navAreasCoplanar( a, b )
	if not AABoxOverlapCheck(a.m,a.x,b.m,b.x,8) then return false end
	local ea,eb = a.e,b.e
	local a1,a2,b1,b2,bn,an,xn,gap,v1,v2,t,zn

	for i=1, #ea do
		a1 = ea[i]
		a2 = ea[i==#ea and 1 or (i+1)]
		an = (a2-a1)
		xn = Vector(an.y,-an.x,0):GetNormalized()
		zn = an:Cross(xn):GetNormalized()
		an:Normalize()
		v1 = a1:Dot(an)
		v2 = a2:Dot(an)
		if v1>v2 then
			t = v2
			v2 = v1
			v1 = t
		end

		for j=1, #eb do
			b1 = eb[j]
			b2 = eb[j==#eb and 1 or (j+1)]
			bn = (b2-b1):GetNormalized()

			if math.abs(a1:Dot(xn)-b1:Dot(xn))>8 or math.abs(a1:Dot(zn)-b1:Dot(zn))>8 then continue end -- Too far apart
			if math.abs(an:Dot(bn))<0.98 then continue end -- Too huge angular difference.

			b1 = b1:Dot(an)
			b2 = b2:Dot(an)
			if b1>b2 then
				t = b2
				b2 = b1
				b1 = t
			end
			gap = math.min(v2,b2)-math.max(v1,b1)
			if gap>12 then -- Enough to fit something through.
				return true
			end
		end
	end
	return false
end

local function AutoBindReach( n )
	if bit.band(n.ex,NODEFLAGS_NoAutoPath) ~= 0 then return end
	if n.f == NODETYPE_NoQuitNode then return end

	if NetworkedPlayers then
		StartNavMsg(1)
	end

	local newRoutes
	local nodetype = n.f
	local nw = n.Index

	if NavMeshNode[nodetype] then
		local maxedge = math.max(-n.m.x,-n.m.y,-n.m.z,n.x.x,n.x.y,n.x.z)^2

		-- Check for co-planars
		for i=1, numNavs do
			local nav = MapNavigationList[i]
			local dist = n.P:DistToSqr(nav.P)

			if nav==n or bit.band(nav.ex,NODEFLAGS_NoAutoPath)~=0 then continue end

			if nav.e then
				if navAreasCoplanar(n,nav) then
					dist = math.floor(math.sqrt(dist))
					n.r[#n.r+1] = {e=nav,d=dist,f=REACHTYPE_Walk}
					nav.r[#nav.r+1] = {e=n,d=dist,f=REACHTYPE_Walk}

					if NetworkedPlayers then
						net.WriteBool(true)
						net.WriteUInt(nw,16)
						net.WriteUInt(i,16)
						net.WriteUInt(REACHTYPE_Walk,ZSBOTAI.PATH_ReachNetworkSize)
						net.WriteBool(true)
						net.WriteUInt(i,16)
						net.WriteUInt(nw,16)
						net.WriteUInt(REACHTYPE_Walk,ZSBOTAI.PATH_ReachNetworkSize)
					end
				end
				continue
			elseif dist<(40000+maxedge) and PointInsideNavArea(nav.P,n) then -- 200^2
				dist = math.floor(math.sqrt(dist))
				local rf = GetReachFlags(nav.f)
				n.r[#n.r+1] = {e=nav,d=dist,f=rf}
				nav.r[#nav.r+1] = {e=n,d=dist,f=rf}

				if NetworkedPlayers then
					net.WriteBool(true)
					net.WriteUInt(nw,16)
					net.WriteUInt(i,16)
					net.WriteUInt(rf,ZSBOTAI.PATH_ReachNetworkSize)
					net.WriteBool(true)
					net.WriteUInt(i,16)
					net.WriteUInt(nw,16)
					net.WriteUInt(rf,ZSBOTAI.PATH_ReachNetworkSize)
				end
			end
		end
	else
		newRoutes = {}
		local TestStartPos = util.FindSpot(n.P,DefaultHullMin,DefaultHullMax)
		if isnumber(TestStartPos) then
			TestStartPos = n.P
		end

		for i=1, numNavs do
			local nav = MapNavigationList[i]
			local dist = n.P:DistToSqr(nav.P)

			if nav==n or bit.band(nav.ex,NODEFLAGS_NoAutoPath)~=0 then continue end

			if nav.e then
				if PointInsideNavArea(n.P,nav) then
					dist = math.floor(math.sqrt(dist))
					local rf = GetReachFlags(n.f)
					n.r[#n.r+1] = {e=nav,d=dist,f=rf}
					nav.r[#nav.r+1] = {e=n,d=dist,f=rf}

					if NetworkedPlayers then
						net.WriteBool(true)
						net.WriteUInt(nw,16)
						net.WriteUInt(i,16)
						net.WriteUInt(rf,ZSBOTAI.PATH_ReachNetworkSize)
						net.WriteBool(true)
						net.WriteUInt(i,16)
						net.WriteUInt(nw,16)
						net.WriteUInt(rf,ZSBOTAI.PATH_ReachNetworkSize)
					end
				end
				continue
			elseif dist>1440000 then continue end -- 1200^2

			local bFlyRoute = (nodetype==NODETYPE_Fly or nav.f==NODETYPE_Fly)
			local bWaterRoute = (nodetype==NODETYPE_Swim and nav.f==NODETYPE_Swim)
			local rf = bFlyRoute and REACHTYPE_Fly or (bWaterRoute and DEFROUTE_Swim or REACHTYPE_Walk)
			local bAnyRoute = bFlyRoute or bWaterRoute -- Either points are air path, or both points are water path.

			if bFlyRoute then
				dist = dist*0.75
			end

			local TestEndPos = util.FindSpot(nav.P,DefaultHullMin,DefaultHullMax)
			if isnumber(TestEndPos) then
				TestEndPos = nav.P
			end

			dist = math.floor(math.sqrt(dist))
			if bAnyRoute and ZSBOTAI.DirectReachable(TestEndPos, TestStartPos, DefaultHullMin, DefaultHullMax) or ZSBOTAI.PointReachable(TestEndPos, TestStartPos, DefaultHullMin, DefaultHullMax) then
				n.r[#n.r+1] = {e=nav,d=dist,f=rf}

				if NetworkedPlayers then
					net.WriteBool(true)
					net.WriteUInt(nw,16)
					net.WriteUInt(i,16)
					net.WriteUInt(rf,ZSBOTAI.PATH_ReachNetworkSize)
				end
			end
			if bAnyRoute and ZSBOTAI.DirectReachable(TestStartPos, TestEndPos, DefaultHullMin, DefaultHullMax) or ZSBOTAI.PointReachable(TestStartPos, TestEndPos, DefaultHullMin, DefaultHullMax) then
				nav.r[#nav.r+1] = {e=n,d=dist,f=rf}
				newRoutes[#newRoutes+1] = nav

				if NetworkedPlayers then
					net.WriteBool(true)
					net.WriteUInt(i,16)
					net.WriteUInt(nw,16)
					net.WriteUInt(rf,ZSBOTAI.PATH_ReachNetworkSize)
				end
			end
		end
	end

	if NetworkedPlayers then
		net.WriteBool(false)
		net.Send(SendPLList)
	end

	-- Cleanup path network
	if not NavMeshNode[nodetype] then
		for _, route in ipairs(newRoutes) do
			CleanupRecast( route )
		end
	end
end

local function _GetPriority( ent )
	local objnum = ent.ObjNum

	if GAMEMODE.IsObjectiveMap then
		if (objnum-1)>(GAMEMODE:GetCurrentObjNum() or 0) then
			return -1
		end
	elseif objnum>1 then
		local wcomp = GAMEMODE.WaveNumber
		if not GAMEMODE.bWaveIsActive then
			wcomp = wcomp+1
		end
		if objnum>wcomp then
			return -1
		end
	end

	return objnum+1
end

local function SpawnZombieStart( node )
	local zspawn = node._ObjEnt
	if IsValid(zspawn) then
		zspawn:SetPos(node.P)
		return
	end

	zspawn = ents.Create("info_player_undead")
	if IsValid(zspawn) then
		zspawn:SetPos(node.P)
		zspawn:SetAngles(Angle(0,node.yaw*1.412,0))
		zspawn:Spawn()
		zspawn.ObjNum = node.ObjNum
		zspawn.GetPriority = _GetPriority
		node._ObjEnt = zspawn
		team.AddSpawnPoint(TEAM_UNDEAD,zspawn)
	end
end

function ZSBOTAI.DeployPathNode( pos, nodetype, pathexflags, yawDir, objNum )
	if NavMeshNode[nodetype] then
		return "Can't deploy navmesh here!"
	end
	ZSBOTAI.InitNavigationNetwork() -- make sure loaded!

	if nodetype==NODETYPE_ZSpawn then
		local res = util.FindSpot(pos,DefaultHullMin,DefaultHullMax)
		if isvector(res) then
			pos = res
		end
		if res==1 then return "Can't deploy this node inside a wall!" end
	end

	local nw = numNavs+1
	local netID = GetNextNIndex()
	local newNav = {P=pos,Index=nw,f=nodetype,ex=pathexflags,rf=GetReachFlags(nodetype),r={},NetID=netID}
	CalcNodeSize(newNav)
	MapNavigationList[nw] = newNav

	if nodetype==NODETYPE_ZSpawn then
		if not objNum then
			objNum = 0
		end
		if objNum<=0 then
			if GAMEMODE.IsObjectiveMap then
				objNum = (GAMEMODE:GetCurrentObjNum() or 0)+1
			else
				objNum = 1
			end
		end
		newNav.ObjNum = objNum
		newNav.yaw = yawDir
		SpawnZombieStart(newNav)
	end

	if NetworkedPlayers then
		StartNavMsg(0)
			net.WriteUInt(nw,16)
			net.WriteUInt(netID,4)
			net.WriteVector(pos)
			net.WriteVector(newNav.m)
			net.WriteVector(newNav.x)
			net.WriteUInt(nodetype,ZSBOTAI.PATH_TypeNetworkSize)
			net.WriteUInt(pathexflags,ZSBOTAI.PATH_ExTypeNetworkSize)
			if nodetype==NODETYPE_ZSpawn then
				net.WriteUInt(newNav.ObjNum,12)
				net.WriteUInt(newNav.yaw,8)
			end
			net.WriteUInt(0,8)
		net.Send(SendPLList)
	end

	-- Inform new slot and save.
	numNavs = nw

	AutoBindReach(newNav)

	AddToOctree(newNav)
	ZSBOTAI.MarkPathsDirty()

	return nw
end

function ZSBOTAI.RemovePathNode( inode )
	local delNode = MapNavigationList[inode]
	if not delNode then return false end

	table.remove(MapNavigationList,inode)
	numNavs = numNavs-1

	-- cleanup references to this pathnode from reachspecs
	for i=1, numNavs do
		local nav = MapNavigationList[i]
		nav.Index = i
		local delindex = nil
		for j, reach in ipairs(nav.r) do
			if reach.e==delNode then
				delindex = j
				break
			end
		end

		if delindex then
			table.remove(nav.r,delindex)
		end
	end

	if PendingNetwork then -- Prevent pending networkers from skipping a node
		for pl, ix in pairs(PendingNetwork) do
			if ix>inode then
				PendingNetwork[pl] = ix-1
			end
		end
	end

	StartNavMsg(2)
		net.WriteUInt(inode,16)
	net.Send(SendPLList)

	delNode._DELETED = true
	RemoveFromOctree(delNode)
	ZSBOTAI.MarkPathsDirty()
	NotePathRemoved()

	if IsValid(delNode._ObjEnt) then
		delNode._ObjEnt:Remove()
		delNode._ObjEnt = nil
	end

	return true
end

function ZSBOTAI.MovePathNode( inode, NewPos, EndPos )
	local Node = MapNavigationList[inode]
	if not Node then return false end

	if Node.e then
		if not EndPos then return end

		RemoveFromOctree(Node)
		local err = ZSBOTAI.BuildNavArea(NewPos,EndPos,Node)
		AddToOctree(Node)

		if err then
			return err
		end

		StartNavMsg(7)
			net.WriteUInt(inode,16)
			net.WriteVector(Node.P)
			net.WriteVector(Node.m)
			net.WriteVector(Node.x)
			net.WriteBool(true)
			if Node.f==NODETYPE_NavMesh then
				net.WriteBool(true)
				for i=1, 4 do
					net.WriteVector(Node.e[i])
				end
			else
				net.WriteBool(false)
				for i=1, 3 do
					net.WriteVector(Node.e[i])
				end
			end
		net.Send(SendPLList)
		return
	end

	RemoveFromOctree(Node)
	Node.P = NewPos
	CalcNodeSize(Node)
	AddToOctree(Node)

	StartNavMsg(7)
		net.WriteUInt(inode,16)
		net.WriteVector(NewPos)
		net.WriteVector(Node.m)
		net.WriteVector(Node.x)
		net.WriteBool(false)
	net.Send(SendPLList)

	ZSBOTAI.MarkPathsDirty()
	NotePathRemoved()

	if Node.f==NODETYPE_ZSpawn then
		SpawnZombieStart(Node)
	end

	return true
end

local DoorEntClasses = {
	["prop_dynamic"]=true,
	["prop_dynamic_ornament"]=true,
	["prop_dynamic_override"]=true,
	["func_wall"]=true,
	["func_brush"]=true,
	["func_wall_toggle"]=true,
	["func_door_rotating"]=true,
	["func_door"]=true,
	["func_movelinear"]=true,
	["func_breakable"]=true,
}

local function DoorTraceFilter( ent )
	return DoorEntClasses[ent:GetClass()] and ent:MapCreationID()>=0
end

local DoorTraceInfo = {filter=DoorTraceFilter,mins=Vector(-16,-16,0),maxs=Vector(16,16,16),mask=MASK_PLAYERSOLID,ignoreworld=true}

local NoLadderFlags = bit.bnot(bit.bor(REACHTYPE_Headcrab,REACHTYPE_Leap,REACHTYPE_Climb,REACHTYPE_Teleport))
local HardFlags = bit.bor(REACHTYPE_Zombies,REACHTYPE_Humans)

-- If none of these flags are added, add walk flag.
local AnyMoveFlags = bit.bor(REACHTYPE_Walk,REACHTYPE_Fly,REACHTYPE_Swim
					,REACHTYPE_Headcrab,REACHTYPE_Leap,REACHTYPE_Climb
					,REACHTYPE_Zombies,REACHTYPE_Humans)

function ZSBOTAI.EditReachSpec( StartNav, EndNav, bEditSpec, NewFlags )
	local nav = MapNavigationList[StartNav]
	local enav = MapNavigationList[EndNav]
	local bDeleted = false

	for j, reach in ipairs(nav.r) do
		if reach.e==enav then
			if bEditSpec then
				return "This path is already bound!"
			end
			table.remove(nav.r,j)

			StartNavMsg(4)
				net.WriteUInt(StartNav,16)
				net.WriteUInt(EndNav,16)
			net.Send(SendPLList)
			bDeleted = true
			break
		end
	end

	if bEditSpec then
		if nav.f==NODETYPE_Fly or enav.f==NODETYPE_Fly then
			NewFlags = bit.bor(NewFlags,REACHTYPE_Fly)
		end
		if (nav.f==NODETYPE_Swim or enav.f==NODETYPE_Swim) and bit.band(NewFlags,HardFlags)==0 then
			NewFlags = bit.bor(NewFlags,REACHTYPE_Swim)
		end
		if nav.f==NODETYPE_Ladder or enav.f==NODETYPE_Ladder then -- Don't allow some flags to ladders.
			NewFlags = bit.band(NewFlags,NoLadderFlags)
		end
		if bit.band(NewFlags,AnyMoveFlags)==0 then -- Make sure any movement flag is set!
			NewFlags = bit.bor(NewFlags,REACHTYPE_Walk)
		end

		local DoorID = false
		if bit.band(NewFlags,REACHTYPE_Door)~=0 then -- Attempt to find door entity.
			DoorTraceInfo.start = nav.P
			DoorTraceInfo.endpos = enav.P
			local tr = util.TraceHull(DoorTraceInfo)
			if not tr.Hit or not IsValid(tr.Entity) then
				return "Failed to find door entity blocking this path!"
			end
			DoorID = tr.Entity:MapCreationID()
		end

		local dist = math.floor(nav.P:Distance(enav.P))
		if bit.band(NewFlags,REACHTYPE_Teleport)~=0 then -- Teleports are shortest routes!
			dist = 100
		elseif bit.band(NewFlags,REACHTYPE_Fly)~=0 then
			dist = math.floor(dist*0.75)
		end

		local rs = {e=enav,d=dist,f=NewFlags}
		nav.r[#nav.r+1] = rs
		if DoorID then
			rs.i = DoorID
		end

		-- Send a single reachspec
		StartNavMsg(1)
			net.WriteBool(true)
			net.WriteUInt(StartNav,16)
			net.WriteUInt(EndNav,16)
			net.WriteUInt(NewFlags,ZSBOTAI.PATH_ReachNetworkSize)
			net.WriteBool(false)
		net.Send(SendPLList)
	elseif not bDeleted then
		return "No path links found!"
	end

	ZSBOTAI.MarkPathsDirty()
end

function ZSBOTAI.FindPathAt( pos )
	local bestidx = nil
	local bestDist = nil
	for i=1, numNavs do
		local nav = MapNavigationList[i]
		local dist = pos:Distance(nav.P)

		if dist<100 and (not bestidx or bestDist>dist) then
			bestidx = i
			bestDist = dist
		end
	end
	if not bestidx then
		return nil
	end
	return bestidx, MapNavigationList[bestidx].P
end

concommand.Add("zs_admin_purgepaths", function(sender, command, arguments)
	if IsValid(sender) and not GAMEMODE:PlayerIsSuperAdmin(sender) then return end

	MapNavigationList = {}
	numNavs = 0

	if MapObjMarkers then
		for _, objn in ipairs(MapObjMarkers) do
			if objn._Box then
				if objn._Box:IsValid() then
					objn._Box:Remove()
				end
				objn._Box = nil
			end
		end
		MapObjMarkers = nil
	end

	ZSBOTAI.MarkPathsDirty()
	NotePathRemoved()

	StartNavMsg(3)
	net.Send(SendPLList)

	if PendingNetwork then
		PendingNetwork = nil
		hook.Remove("Think","Bot.ThinkPaths")
	end
end)

-- ==========================================================================================================
-- Networking to admins:

local function ThinkPathNetwork()
	local bFound = false

	-- Send one pathnode info per think to prevent massive server lagspikes.
	for pl, ix in pairs(PendingNetwork) do
		if ix<=numNavs then
			bFound = true
			StartNavMsg(0)
				local node = MapNavigationList[ix]
				net.WriteUInt(ix,16)
				net.WriteUInt(node.NetID,4)
				net.WriteVector(node.P)
				net.WriteVector(node.m)
				net.WriteVector(node.x)
				net.WriteUInt(node.f,ZSBOTAI.PATH_TypeNetworkSize)
				net.WriteUInt(node.ex,ZSBOTAI.PATH_ExTypeNetworkSize)
				if node.f==NODETYPE_ZSpawn then
					net.WriteUInt(node.ObjNum,12)
					net.WriteUInt(node.yaw,8)
				elseif node.e then
					for i=1, #node.e do
						net.WriteVector(node.e[i])
					end
				end
				net.WriteUInt(#node.r,8)
				for _, reach in pairs(node.r) do
					net.WriteUInt(reach.e.Index,16)
					net.WriteUInt(reach.f,ZSBOTAI.PATH_ReachNetworkSize)
				end
			net.Send(pl)
		elseif ix==(numNavs+1) and MapObjMarkers then -- Transmit objective markers.
			StartNavMsg(5)
			for i, objn in ipairs(MapObjMarkers) do
				net.WriteBool(true)
				net.WriteUInt(i,16)
				net.WriteUInt(objn[1],10)
				net.WriteVector(objn[2])
				net.WriteVector(objn[3])
				net.WriteBool(objn[4])
			end
				net.WriteBool(false)
			net.Send(pl)
		end
		PendingNetwork[pl] = PendingNetwork[pl]+1
	end

	if not bFound then
		PendingNetwork = nil
		hook.Remove("Think","Bot.ThinkPaths")
	end
end

function ZSBOTAI.NetworkPathList( pl )
	if not NetworkedPlayers then
		NetworkedPlayers = {}

		ZSBOTAI.InitNavigationNetwork()
	end

	if NetworkedPlayers[pl] then return end

	NetworkedPlayers[pl] = true
	SendPLList[#SendPLList+1] = pl

	-- start feeding list to client.
	if not PendingNetwork then
		PendingNetwork = {}

		hook.Add("Think","Bot.ThinkPaths",ThinkPathNetwork)
	end
	PendingNetwork[pl] = 1
end

function ZSBOTAI.ReloadPaths()
	MapNavigationList = nil
	NotePathRemoved()

	if MapObjMarkers then
		for _, objn in ipairs(MapObjMarkers) do
			if objn._Box then
				if objn._Box:IsValid() then
					objn._Box:Remove()
				end
				objn._Box = nil
			end
		end
		MapObjMarkers = nil
	end

	ZSBOTAI.InitNavigationNetwork()

	if NetworkedPlayers then
		StartNavMsg(3)
		net.Send(SendPLList)

		PendingNetwork = {}
		for _, newSendPLList in ipairs(SendPLList) do
			PendingNetwork[newSendPLList] = 1
		end

		hook.Add("Think","Bot.ThinkPaths",ThinkPathNetwork)
	end
end

function ZSBOTAI.EndNetworkPathList( pl )
	if NetworkedPlayers and NetworkedPlayers[pl] then
		NetworkedPlayers[pl] = nil
		table.RemoveByValue(SendPLList,pl)
		if PendingNetwork then
			PendingNetwork[pl] = nil
		end

		if table.Count(NetworkedPlayers)==0 then
			NetworkedPlayers = false
			if PendingNetwork then
				PendingNetwork = nil
				hook.Remove("Think","Bot.ThinkPaths")
			end
		end
	end
end

function ZSBOTAI.ReadNode()
	if not MapNavigationList then return false end

	local i = net.ReadUInt(16)
	local id = net.ReadUInt(4)
	local nav = MapNavigationList[i]
	return (nav and nav.NetID==id) and i or false
end

function ZSBOTAI.PickRandomNode()
	ZSBOTAI.InitNavigationNetwork() -- make sure loaded!

	if numNavs>0 then
		local tries = 0
		while tries<25 do
			tries = tries+1
			local i = math.random(numNavs)
			if MapNavigationList[i].f~=NODETYPE_Fly then
				return MapNavigationList[i].P
			end
		end
	end
	return nil
end

function ZSBOTAI.GetMaxNodeDistance( pos )
	local mx = 0

	for i=1, numNavs do
		mx = math.max(mx,pos:DistToSqr(MapNavigationList[i].P))
	end
	return math.sqrt(mx)
end

function ZSBOTAI.GetArmoryPoints()
	ZSBOTAI.InitNavigationNetwork() -- make sure loaded!

	local Points = {}
	for i=1, numNavs do
		if MapNavigationList[i].f==NODETYPE_Objective then
			Points[#Points+1] = MapNavigationList[i]
		end
	end

	return Points
end

function ZSBOTAI.SpawnObjMarkers()
	ZSBOTAI.InitNavigationNetwork()
	if not MapObjMarkers then return end

	for _, objn in ipairs(MapObjMarkers) do
		if objn[4] then continue end

		local objmarker = ents.Create("point_objectivemarker")
		if IsValid(objmarker) then
			objmarker:SetPos(objn[2])
			objmarker:SetAngles(Angle(0,0,0))
			objmarker:Spawn()
			objmarker:InitTo(objn)
			objn._Box = objmarker
		end
	end
end

local EntClasses = {"tt_nocade","tt_godmode","tt_godmode","prop_playerblocker","prop_playerblocker","prop_playerblocker","tt_killall","tt_hurthumans"}

local function AddBoxFor( tab )
	local ty = tab[1]+1
	local cl = EntClasses[ty]
	if not cl then return end

	local e = ents.Create(cl)
	if IsValid(e) then
		if IsValid(tab._Box) then tab._Box:Remove() end
		tab._Box = e
		e:Spawn()
		e:SetMoveType(MOVETYPE_NONE)
		e:SetSolid(SOLID_BBOX)
		e:SetCollisionBoundsWS(tab[2],tab[3])
		local f = e.InitType
		if f then
			f(e,ty)
		end
	end
end

local ENT = {Type = "anim"}
local bHookAllowBC = false
local function AllowNailHere(pl, tr)
	if tr==nil then return end

	local ent = tr.Entity
	if IsValid(ent) and ent._NoBarricadeNum then
		pl:PrintTranslatedMessage(HUD_PRINTCENTER, "impossible")
		return false
	end
end
function ENT:Initialize()
	self:SetCollisionGroup(COLLISION_GROUP_DEBRIS_TRIGGER)
	self:SetTrigger(true)
	self:SetNoDraw(true)
	self:SetCustomGroupAndFlags(ZS_COLLISIONGROUP_FORCEFIELD, ZS_COLLISIONFLAGS_PROP, true)
end
function ENT:StartTouch( ent )
	if ent:IsAPhysicsProp() then
		ent._NoBarricadeNum = (ent._NoBarricadeNum or 0)+1
		if not bHookAllowBC then
			bHookAllowBC = true
			hook.Add("CanPlaceNail", "CanPlaceNail.NavBlocker",AllowNailHere)
		end
	end
end
function ENT:EndTouch( ent )
	local n = ent._NoBarricadeNum
	if n then
		n = n-1
		if n<=0 then
			ent._NoBarricadeNum = nil
		end
	end
end
function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end
scripted_ents.Register(ENT,"tt_nocade")

ENT = table.Copy(ENT)
ENT.StartTouch = nil
ENT.EndTouch = nil
function ENT:Touch( ent )
	if EntityIsPlayer(ent) then
		if ent:Alive(true) then
			ent:Kill()
		end
	elseif ent:IsAPhysicsProp() then
		ent:Fire("Break")
	end
end
scripted_ents.Register(ENT,"tt_killall")

ENT = table.Copy(ENT)
function ENT:Touch( ent )
	if EntityIsPlayer(ent) and GetPlayerTeam(ent)==TEAM_HUMAN and (ent._NextHurtTime or 0)<CurTime() then
		ent._NextHurtTime = CurTime()+0.75
		ent:TakeDamage(5,ent,self)
	end
end
scripted_ents.Register(ENT,"tt_hurthumans")

ENT = table.Copy(ENT)
function ENT:Touch( ent )
	if EntityIsPlayer(ent) and GetPlayerTeam(ent)==TEAM_UNDEAD and (not self.bLateGame or GAMEMODE:GetWave()>=3) and GAMEMODE:GetWaveActive() and not ent:GetZombieClassTable().Boss then
		ent:SetSpawnProtection(true,true)
	end
end
function ENT:InitType( ty )
	self.bLateGame = (ty==3)
end
scripted_ents.Register(ENT,"tt_godmode")

hook.AddPost("InitPostEntityMap", "InitPostEntityMap.InitNavCol", function()
	ZSBOTAI.InitNavigationNetwork()

	for i=1, numNavs do
		if MapNavigationList[i].f==NODETYPE_ZSpawn then
			SpawnZombieStart(MapNavigationList[i])
		end
	end

	if not MapObjMarkers then return end

	for i=1, #MapObjMarkers do
		if MapObjMarkers[i][4] then
			AddBoxFor(MapObjMarkers[i])
		end
	end
end)

function ZSBOTAI.DeployVolume( A, B, Index, bVolume )
	ZSBOTAI.InitNavigationNetwork()

	if not Index then
		if GAMEMODE.IsObjectiveMap then
			Index = GAMEMODE:GetCurrentObjNum()
			if not Index then return end
		else
			Index = 0
		end
	end

	local minV = Vector(math.min(A.x,B.x)-1,math.min(A.y,B.y)-1,math.min(A.z,B.z)-1)
	local maxV = Vector(math.max(A.x,B.x)+1,math.max(A.y,B.y)+1,math.max(A.z,B.z)+1)

	if not MapObjMarkers then
		MapObjMarkers = {}
	end

	local i = #MapObjMarkers+1
	local tab = {Index,minV,maxV,bVolume}
	MapObjMarkers[i] = tab
	if bVolume then
		AddBoxFor(tab)
	end
	ZSBOTAI.MarkPathsDirty()

	StartNavMsg(5)
		net.WriteBool(true)
		net.WriteUInt(i,16)
		net.WriteUInt(Index,10)
		net.WriteVector(minV)
		net.WriteVector(maxV)
		net.WriteBool(bVolume)
		net.WriteBool(false)
	net.Send(SendPLList)
end

function ZSBOTAI.DeleteCheckpoint( V )
	ZSBOTAI.InitNavigationNetwork()

	if not MapObjMarkers then return end

	for i, objn in ipairs(MapObjMarkers) do
		if PointAABoxCheck(V,objn[2]-Vector(10,10,10),objn[3]+Vector(10,10,10)) then
			if objn._Box then
				if objn._Box:IsValid() then
					objn._Box:Remove()
				end
				objn._Box = nil
			end
			table.remove(MapObjMarkers,i)
			ZSBOTAI.MarkPathsDirty()

			StartNavMsg(6)
				net.WriteUInt(i,16)
			net.Send(SendPLList)
			break
		end
	end
end

local SetupEdges = {
	function( a, b )
		return {Vector(b.x,a.y,0),Vector(a.x,a.y,0),Vector(b.x,b.y,0)}
	end,
	function( a, b )
		return {Vector(a.x,a.y,0),Vector(a.x,b.y,0),Vector(b.x,a.y,0)}
	end,
	function( a, b )
		return {Vector(b.x,b.y,0),Vector(b.x,a.y,0),Vector(a.x,b.y,0)}
	end,
	function( a, b )
		return {Vector(a.x,b.y,0),Vector(b.x,b.y,0),Vector(a.x,a.y,0)}
	end,
}

function ZSBOTAI.BuildNavArea( a, b, resultTab )
	if a:DistToSqr(b)<100 then
		return "Both points are too close to each other!"
	end
	local triside = resultTab.side
	local mins,maxs = Vector(math.min(a.x,b.x),math.min(a.y,b.y),math.min(a.z,b.z)),Vector(math.max(a.x,b.x),math.max(a.y,b.y),math.max(a.z,b.z))
	local edges,dirs,mid

	if triside then -- Handle triangle mesh
		edges = SetupEdges[triside+1](mins,maxs)

		local zdif = 0
		local tri = ZSBOTAI.GetReachTraceInfo(Vector(0,0,0),Vector(0,0,0))
		local tr
		local lowest = maxs.z+250
		if math.abs(mins.z-maxs.z)>5 then
			for i=1, 3 do
				local e = edges[i]
				tri.start.x = e.x
				tri.start.y = e.y
				tri.start.z = maxs.z+32
				tri.endpos.x = e.x
				tri.endpos.y = e.y
				tri.endpos.z = mins.z-100
				tr = util.TraceLine(tri)
				if not tr.Hit then
					return "Invalid floor normal ("..tostring(i)..")"
				end
				e.z = tr.HitPos.z
				zdif = math.max(zdif,math.abs(e.z-mins.z))

				-- Check roof height.
				tri.start.z = e.z+4
				tri.endpos.z = maxs.z+250
				tr = util.TraceLine(tri)
				if tr.Hit and tr.Fraction>0.05 then
					lowest = math.min(lowest,tr.HitPos.z)
				end
			end
		else
			for i=1, 3 do
				local e = edges[i]
				e.z = mins.z

				-- Check roof height.
				tri.start.x = e.x
				tri.start.y = e.y
				tri.start.z = e.z+4
				tri.endpos.x = e.x
				tri.endpos.y = e.y
				tri.endpos.z = maxs.z+250
				tr = util.TraceLine(tri)
				if tr.Hit and tr.Fraction>0.05 then
					lowest = math.min(lowest,tr.HitPos.z)
				end
			end
		end

		if zdif<5 then -- Even it out.
			for i=1, 3 do
				edges[i].z = maxs.z
			end
			dirs = Vector(0,0,1)
		else
			dirs = (edges[2]-edges[1]):GetNormalized():Cross((edges[3]-edges[1]):GetNormalized()):GetNormalized()
		end

		mid = (edges[1]/3) + (edges[2]/3) + (edges[3]/3)
		local ndir = (edges[3]-edges[2])
		local snormal = Vector(ndir.y,-ndir.x,0):GetNormalized() -- Split normal
		lowest = math.max(lowest-maxs.z,48)

		resultTab.P = mid
		resultTab.e = edges
		resultTab.n = dirs
		resultTab.w = (dirs:Dot(mid)-5)
		resultTab.m = mins-Vector(0,0,6)
		resultTab.x = maxs+Vector(0,0,lowest)
		resultTab.sn = snormal
		resultTab.sw = (snormal:Dot(edges[2]))
		return
	end

	-- Check bounding area normal direction
	if math.abs(mins.z-maxs.z)>5 then
		local ta,tb,tc,td
		local tri = ZSBOTAI.GetReachTraceInfo(Vector(mins.x,mins.y,maxs.z+32),Vector(mins.x,mins.y,mins.z-100))
		local tr = util.TraceLine(tri)
		if tr.Hit then
			ta = tr.HitPos
		else
			return "Invalid floor normal (A)"
		end

		tri.start.y = maxs.y
		tri.endpos.y = maxs.y
		tr = util.TraceLine(tri)
		if tr.Hit then
			tb = tr.HitPos
		else
			return "Invalid floor normal (B)"
		end

		tri.start.x = maxs.x
		tri.endpos.x = maxs.x
		tr = util.TraceLine(tri)
		if tr.Hit then
			tc = tr.HitPos
		else
			return "Invalid floor normal (C)"
		end

		tri.start.y = mins.y
		tri.endpos.y = mins.y
		tr = util.TraceLine(tri)
		if tr.Hit then
			td = tr.HitPos
		else
			return "Invalid floor normal (D)"
		end

		-- grab highest point
		local high = tb.z>ta.z and tb or ta
		if tc.z>high.z then
			high = tc
		end
		if td.z>high.z then
			high = td
		end

		dirs = (ta-tb):GetNormalized():Cross((tc-tb):GetNormalized()):GetNormalized()
		local dirb = (tc-td):GetNormalized():Cross((ta-td):GetNormalized()):GetNormalized()
		dirs = (dirs+dirb):GetNormalized()
		mid = (mins+((maxs-mins)*0.5))
		mid = LinePlaneIntersection(mid+Vector(0,0,100),mid-Vector(0,0,100),high,dirs)
		edges = {Vector(mins.x,mins.y,maxs.z),Vector(maxs.x,mins.y,maxs.z),Vector(maxs.x,maxs.y,maxs.z),Vector(mins.x,maxs.y,maxs.z)}
		for i=1, 4 do
			local v = edges[i]
			edges[i] = LinePlaneIntersection(v,Vector(v.x,v.y,mins.z),high,dirs)
		end
	else
		mins.z = maxs.z
		dirs = Vector(0,0,1)
		mid = (mins+((maxs-mins)*0.5))
		edges = {mins,Vector(maxs.x,mins.y,mins.z),maxs,Vector(mins.x,maxs.y,mins.z)}
	end

	-- Find roof height
	local tri = ZSBOTAI.GetReachTraceInfo(Vector(mins.x,mins.y,maxs.z),Vector(mins.x,mins.y,maxs.z+250))
	local lowest = maxs.z+250
	local tr = util.TraceLine(tri)
	if tr.Hit and tr.Fraction>0.05 then
		lowest = math.min(lowest,tr.HitPos.z)
	end
	tri.start.x = maxs.x
	tri.endpos.x = maxs.x
	tr = util.TraceLine(tri)
	if tr.Hit and tr.Fraction>0.05 then
		lowest = math.min(lowest,tr.HitPos.z)
	end
	tri.start.y = maxs.y
	tri.endpos.y = maxs.y
	tr = util.TraceLine(tri)
	if tr.Hit and tr.Fraction>0.05 then
		lowest = math.min(lowest,tr.HitPos.z)
	end
	tri.start.x = mins.x
	tri.endpos.x = mins.x
	tr = util.TraceLine(tri)
	if tr.Hit and tr.Fraction>0.05 then
		lowest = math.min(lowest,tr.HitPos.z)
	end
	lowest = math.max(lowest-maxs.z,48)

	resultTab.P = mid
	resultTab.e = edges
	resultTab.n = dirs
	resultTab.w = (dirs:Dot(mid)-5)
	resultTab.m = mins-Vector(0,0,6)
	resultTab.x = maxs+Vector(0,0,lowest)
end

function ZSBOTAI.DeployNavArea( a, b, bNoBind, TriSide )
	local tab = {f=NODETYPE_NavMesh}
	if TriSide~=nil then
		tab.f = NODETYPE_NavMeshTris
		tab.side = TriSide
	end
	local err = ZSBOTAI.BuildNavArea(a,b,tab)
	if err then
		return err
	end

	nw = numNavs+1
	tab.Index = nw
	tab.ex = 0
	tab.rf = REACHTYPE_Walk
	tab.r = {}
	tab.NetID = GetNextNIndex()

	if NetworkedPlayers then
		StartNavMsg(0)
			net.WriteUInt(nw,16)
			net.WriteUInt(tab.NetID,4)
			net.WriteVector(tab.P)
			net.WriteVector(tab.m)
			net.WriteVector(tab.x)
			net.WriteUInt(tab.f,ZSBOTAI.PATH_TypeNetworkSize)
			net.WriteUInt(0,ZSBOTAI.PATH_ExTypeNetworkSize)
			for _, newtab in ipairs(tab.e) do
				net.WriteVector(newtab)
			end
			net.WriteUInt(0,8)
		net.Send(SendPLList)
	end

	MapNavigationList[nw] = tab
	numNavs = nw

	if not bNoBind then
		AutoBindReach(tab)
	end

	AddToOctree(tab)
	ZSBOTAI.MarkPathsDirty()

	if bNoBind then
		return tab
	end
end

local navTable = {}

function ZSBOTAI.FindNavArea( v )
	local na = navmesh.GetNavArea(v,32)
	if not na then
		return "Couldn't find entry point!"
	end
	if na:IsUnderwater() then
		return "Entry point is underwater!"
	end
	if not na:GetID() then
		return "Invalid entry point ("..tostring(na)..")!"
	end

	local maxBindDist = 1000^2

	local org = na
	local nai = na:GetID()
	if navTable[nai] then
		navTable[nai]._Next = nil
	end

	-- First add all nodes
	while na do
		nai = na:GetID()
		local nat = navTable[nai]
		if not nat then
			nat = {}
			navTable[nai] = nat
		end
		nat._Done = true
		if not nat._Nav then
			local mins,maxs
			for i=0, 3 do
				local e = na:GetCorner(i)
				if not mins then
					mins = Vector(e)
					maxs = Vector(e)
				else
					mins.x = math.min(mins.x,e.x)
					mins.y = math.min(mins.y,e.y)
					mins.z = math.min(mins.z,e.z)
					maxs.x = math.max(maxs.x,e.x)
					maxs.y = math.max(maxs.y,e.y)
					maxs.z = math.max(maxs.z,e.z)
				end
			end
			local res = ZSBOTAI.DeployNavArea(mins,maxs,true)
			if isstring(res) then
				DEBUG_MessageDev("Couldn't add nav area: "..res,false,1,true)
			else
				nat._Nav = res
			end
		end

		local adj = na:GetAdjacentAreas()
		for _, n in ipairs(adj) do
			nai = n:GetID()
			local nt = navTable[nai]
			if not nt then
				nt = {}
				navTable[nai] = nt
			end
			if nt._Done or n:IsUnderwater() or n:GetCenter():DistToSqr(v)>maxBindDist then continue end

			nt._Done = true
			nt._Next = nat._Next
			nat._Next = n
		end
		na = nat._Next
	end

	na = org

	if NetworkedPlayers then
		StartNavMsg(1)
	end

	-- Now link all nodes.
	while na do
		local nat = navTable[na:GetID()]
		if nat._Nav then
			local adj = na:GetAdjacentAreas()
			for _, nvadj in ipairs(adj) do
				local nt = navTable[nvadj:GetID()]
				if not nt or not nt._Nav then continue end

				local a,b = nt._Nav,nat._Nav
				if a._DELETED or b._DELETED then continue end

				local found = false
				for i=1, #a.r do
					if a.r[i].e==b then
						found = true
						break
					end
				end
				if not found then
					a.r[#a.r+1] = {e=b,d=math.floor(a.P:Distance(b.P)),f=REACHTYPE_Walk}

					if NetworkedPlayers then
						net.WriteBool(true)
						net.WriteUInt(a.Index,16)
						net.WriteUInt(b.Index,16)
						net.WriteUInt(REACHTYPE_Walk,ZSBOTAI.PATH_ReachNetworkSize)
					end
				end

				found = false
				for i=1, #b.r do
					if b.r[i].e==a then
						found = true
						break
					end
				end
				if not found then
					b.r[#b.r+1] = {e=a,d=math.floor(a.P:Distance(b.P)),f=REACHTYPE_Walk}

					if NetworkedPlayers then
						net.WriteBool(true)
						net.WriteUInt(b.Index,16)
						net.WriteUInt(a.Index,16)
						net.WriteUInt(REACHTYPE_Walk,ZSBOTAI.PATH_ReachNetworkSize)
					end
				end
			end
		end

		na = nat._Next
	end

	if NetworkedPlayers then
		net.WriteBool(false)
		net.Send(SendPLList)
	end
end
