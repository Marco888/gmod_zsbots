AddCSLuaFile()

ZSBOTAI.PATH_Type = {
	["Walk"]=0,
	["Fly"]=1,
	["Swim"]=2,
	["Ladder"]=3,
	["Objective"]=4,
	["NavMesh"]=5,
	["NavMeshTris"]=6,
	["NoQuitNode"]=7,
	["ZSpawn"]=8,
}
ZSBOTAI.PATH_TypeNetworkSize = 3

ZSBOTAI.PATH_ExtraType = {
	["NoAutoPath"] = 1,
}
ZSBOTAI.PATH_ExTypeNetworkSize = 1

ZSBOTAI.PATH_ReachFlags = {
	["Walk"]=1,
	["Fly"]=2,
	["Swim"]=4,
	["Headcrab"]=8,
	["Leap"]=16,
	["Climb"]=32,
	["Door"]=64,
	["Teleport"]=128,
	["Zombies"]=256,
	["Humans"]=512,
	["NoStrafeTo"]=1024,
}
ZSBOTAI.PATH_ReachNetworkSize = 11

local SolidClasses = {
	["prop_detail"]=true,
	["prop_dynamic"]=true,
	["prop_dynamic_ornament"]=true,
	["prop_dynamic_override"]=true,
	["prop_thumper"]=true,
	["env_headcrabcanister"]=true,
	["func_wall"]=true,
	["func_brush"]=true,
	["func_wall_toggle"]=true,
	["func_door_rotating"]=true,
	["func_door"]=true,
	["func_movelinear"]=true,
	["func_breakable"]=true,
	["prop_playerblocker"]=true,
}

local GM_TryCollides = GM.TryCollides
local CF_BotReach = bit.bor(ZS_COLLISIONGROUP_HUMAN, ZS_COLLISIONGROUP_ZOMBIE, ZS_COLLISIONGROUP_CROW)
local ent_GetClass = FindMetaTable("Entity").GetClass

local function RTI_Filter( ent )
	return (SolidClasses[ent_GetClass(ent)] and GM_TryCollides(ent, ZS_COLLISIONGROUP_STATICPROP, CF_BotReach))
end

local RTI_TraceInfo = {
	filter=RTI_Filter,
	mask=MASK_PLAYERSOLID,
	output={},
}
function ZSBOTAI.GetReachTraceInfo( start, endpos, mins, maxs )
	RTI_TraceInfo.start = start
	RTI_TraceInfo.endpos = endpos
	RTI_TraceInfo.mins = mins
	RTI_TraceInfo.maxs = maxs
	return RTI_TraceInfo
end

-- Helper function for FindSpot:
local function EncroachingWorldGeometry( Location, Extent )
	-- Perform the trace (from feet to head).
	local tr = util.TraceHull( {
		start = Vector(Location.X,Location.Y,Location.Z-Extent.Z),
		endpos = Vector(Location.X,Location.Y,Location.Z+Extent.Z),
		mins = Vector(-Extent.X,-Extent.Y,0),
		maxs = Vector(Extent.X,Extent.Y,0),
		mask = MASK_PLAYERSOLID_BRUSHONLY,
	} )
	return tr.Hit
end

-- AdjustSpot used by FindSpot
local function AdjustSpot( Adjusted, TraceDest, TraceLen )
	local tr = util.TraceLine( {
		start = Adjusted,
		endpos = TraceDest,
		mask = MASK_PLAYERSOLID_BRUSHONLY
	} )

	if tr.Hit then
		Adjusted = Adjusted + tr.HitNormal * (1.05 - tr.Fraction) * TraceLen
	end
	return Adjusted
end

-- Adjust a location so it does not overlap level (inspired by UnrealEngine).
-- Returns AdjustedLocation or <Error code>:
-- 0 = nothing was adjusted
-- 1 = error, can't find spot
function util.FindSpot( Pos, Mins, Maxs )
	-- Find center location and extent of hull.
	local Extent = Vector((Maxs.X-Mins.X)*0.5,(Maxs.Y-Mins.Y)*0.5,(Maxs.Z-Mins.Z)*0.5)

	-- Sanity Check.
	-- This check if the Z pos provided is already centered (Props with Center as origin) the tolerance for this check is 1 hammer unit
	-- center = Mins.Z + Extent.Z + Pos.Z / Delta = center - Pos.Z
	local center = Mins.Z + Extent.Z
	local Location = nil
	if math.abs(center) <= 1 then
		Location = Pos
	else
		Location = Pos + Vector(0,0,Extent.Z)
	end

	-- First check if inside world geometry (if so then we can't help it)
	if not util.IsInWorld(Location) then
		return 1
	end

	-- First check if player is already free of obstacles.
	if not EncroachingWorldGeometry(Location,Extent) then
		return 0
	end

	--local StartLoc = Vector(Location.X,Location.Y,Location.Z)

	local i=-1
	while i<2 do
		Location = AdjustSpot(Location, Location + Vector(i * Extent.X,0,0), Extent.X)
		Location = AdjustSpot(Location, Location + Vector(0,i * Extent.Y,0), Extent.Y)
		Location = AdjustSpot(Location, Location + Vector(0,0,i * Extent.Z), Extent.Z)
		i = i+2
	end
	if not EncroachingWorldGeometry(Location,Extent) then
		Location.Z = Location.Z-Extent.Z
		return Location
	end

	local TraceLen = Extent:Length() + 2

	i = -1
	while i<2 do
		local j = -1
		while j<2 do
			local k = -1
			while k<2 do
				Location = AdjustSpot(Location, Location + Vector(i * Extent.X, j * Extent.Y, k * Extent.Z), TraceLen)
				k = k+2
			end
			j = j+2
		end
		i = i+2
	end

	--if Location:DistToSqr(StartLoc) > (TraceLen*TraceLen) then
	--	return 1
	--end

	if not EncroachingWorldGeometry(Location,Extent) then
		Location.Z = Location.Z-Extent.Z
		return Location
	end
	return 1
end

-- meta functions helper.

local meta = FindMetaTable("Entity")

local HollowGroups = {
    [COLLISION_GROUP_DEBRIS]=true,
    [COLLISION_GROUP_DEBRIS_TRIGGER]=true,
    [COLLISION_GROUP_IN_VEHICLE]=true,
    [COLLISION_GROUP_WEAPON]=true,
    [COLLISION_GROUP_WORLD]=true,
}

function meta:ShouldBlockPlayer()
    return not HollowGroups[self:GetCollisionGroup()]
end

function meta:IsAPhysicsProp()
	if not IsValid(self) then return false end

	if not self.CheckedIsPhysProp then
		self.CheckedIsPhysProp = (string.sub(self:GetClass(), 1, 12) == "prop_physics" or string.sub(self:GetClass(), 1, 12) == "func_physbox" or self:GetClass()=="prop_food") and 1 or 0
	end

	return self.CheckedIsPhysProp == 1
end