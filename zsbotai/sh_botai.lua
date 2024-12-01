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
local CF_BotReach = bit.bor(ZS_COLLISIONGROUP_HUMAN,ZS_COLLISIONGROUP_ZOMBIE,ZS_COLLISIONGROUP_CROW)
local ent_GetClass = FindMetaTable("Entity").GetClass

local function RTI_Filter( ent )
	return (SolidClasses[ent_GetClass(ent)] and GM_TryCollides(ent,ZS_COLLISIONGROUP_STATICPROP,CF_BotReach))
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
