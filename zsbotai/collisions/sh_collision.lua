-- global enums.

DT_PLAYER_AND_ENTITY_INT_COLLISION_FLAG = 18
DT_PLAYER_AND_ENTITY_INT_COLLISION_GROUP = 19

local PowIndex
local function GetNextPow(i)
	if i then PowIndex = i end
	local r = PowIndex
	PowIndex = bit.lshift(PowIndex, 1)
	return r
end

-- keep in minds, this is bit wise, limit at 32 index because of lua's bitwise limitation.
ZS_COLLISIONGROUP_DEFAULT = 0
ZS_COLLISIONGROUP_NONE = GetNextPow(1)
ZS_COLLISIONGROUP_ALL = GetNextPow()
ZS_COLLISIONGROUP_DYNAMICPROP = GetNextPow()
ZS_COLLISIONGROUP_STATICPROP = GetNextPow()
ZS_COLLISIONGROUP_HUMAN = GetNextPow()
ZS_COLLISIONGROUP_ZOMBIE = GetNextPow()
ZS_COLLISIONGROUP_CROW = GetNextPow()
ZS_COLLISIONGROUP_SPECTATOR = GetNextPow()
ZS_COLLISIONGROUP_PROJECTILE = GetNextPow()
ZS_COLLISIONGROUP_CARRIEDPROP = GetNextPow()
ZS_COLLISIONGROUP_DEPLOYABLE = GetNextPow()
ZS_COLLISIONGROUP_DEPLOYABLE_HUMAN = GetNextPow()
ZS_COLLISIONGROUP_DEPLOYABLE_TURRET = GetNextPow()
ZS_COLLISIONGROUP_DEPLOYABLE_NONESOLID = GetNextPow()
ZS_COLLISIONGROUP_DEPLOYABLE_HPROJSOLID = GetNextPow()
ZS_COLLISIONGROUP_TELEPORT = GetNextPow()
ZS_COLLISIONGROUP_FORCEFIELD = GetNextPow()
ZS_COLLISIONGROUP_PROP_DAMAGED = GetNextPow()
-- map profile entities.
ZS_COLLISIONGROUP_BLOCK_WALL_HUMAN = GetNextPow()
ZS_COLLISIONGROUP_BLOCK_WALL_ZOMBIE = GetNextPow()
ZS_COLLISIONGROUP_BLOCK_WALL_ALL_TEAM = GetNextPow()

ZS_COLLISIONFLAGS_ANYPROJ = bit.bor(ZS_COLLISIONGROUP_ALL, ZS_COLLISIONGROUP_DYNAMICPROP, ZS_COLLISIONGROUP_HUMAN, ZS_COLLISIONGROUP_ZOMBIE, ZS_COLLISIONGROUP_STATICPROP, ZS_COLLISIONGROUP_DEPLOYABLE, ZS_COLLISIONGROUP_DEPLOYABLE_TURRET, ZS_COLLISIONGROUP_DEPLOYABLE_HUMAN, ZS_COLLISIONGROUP_PROP_DAMAGED)
ZS_COLLISIONFLAGS_ZOMBIEPROJ = bit.bor(ZS_COLLISIONGROUP_ALL, ZS_COLLISIONGROUP_DYNAMICPROP, ZS_COLLISIONGROUP_HUMAN, ZS_COLLISIONGROUP_STATICPROP, ZS_COLLISIONGROUP_CARRIEDPROP, ZS_COLLISIONGROUP_DEPLOYABLE, ZS_COLLISIONGROUP_DEPLOYABLE_TURRET, ZS_COLLISIONGROUP_DEPLOYABLE_NONESOLID, ZS_COLLISIONGROUP_DEPLOYABLE_HUMAN, ZS_COLLISIONGROUP_PROP_DAMAGED)
ZS_COLLISIONFLAGS_NEWZOMBIEPROJ = bit.bor(ZS_COLLISIONGROUP_ALL, ZS_COLLISIONGROUP_DYNAMICPROP, ZS_COLLISIONGROUP_STATICPROP, ZS_COLLISIONGROUP_CARRIEDPROP, ZS_COLLISIONGROUP_DEPLOYABLE, ZS_COLLISIONGROUP_DEPLOYABLE_TURRET, ZS_COLLISIONGROUP_DEPLOYABLE_NONESOLID, ZS_COLLISIONGROUP_DEPLOYABLE_HUMAN, ZS_COLLISIONGROUP_PROP_DAMAGED)
ZS_COLLISIONFLAGS_HUMANPROJ = bit.bor(ZS_COLLISIONGROUP_ALL, ZS_COLLISIONGROUP_DYNAMICPROP, ZS_COLLISIONGROUP_ZOMBIE, ZS_COLLISIONGROUP_STATICPROP, ZS_COLLISIONGROUP_DEPLOYABLE, ZS_COLLISIONGROUP_PROP_DAMAGED, ZS_COLLISIONGROUP_DEPLOYABLE_HPROJSOLID)
ZS_COLLISIONFLAGS_NEWHUMANPROJ = bit_bor(ZS_COLLISIONGROUP_ALL, ZS_COLLISIONGROUP_DYNAMICPROP, ZS_COLLISIONGROUP_STATICPROP, ZS_COLLISIONGROUP_DEPLOYABLE, ZS_COLLISIONGROUP_PROP_DAMAGED, ZS_COLLISIONGROUP_DEPLOYABLE_HPROJSOLID)
ZS_COLLISIONFLAGS_ZOMBIECROW = bit_bor(ZS_COLLISIONGROUP_ALL, ZS_COLLISIONGROUP_DYNAMICPROP, ZS_COLLISIONGROUP_STATICPROP, ZS_COLLISIONGROUP_DEPLOYABLE, ZS_COLLISIONGROUP_DEPLOYABLE_TURRET, ZS_COLLISIONGROUP_DEPLOYABLE_HUMAN, ZS_COLLISIONGROUP_PROP_DAMAGED)
ZS_COLLISIONFLAGS_ZOMBIE = bit.bor(ZS_COLLISIONFLAGS_ZOMBIECROW, ZS_COLLISIONGROUP_BLOCK_WALL_ALL_TEAM, ZS_COLLISIONGROUP_BLOCK_WALL_ZOMBIE, ZS_COLLISIONGROUP_HUMAN)
ZS_COLLISIONFLAGS_HUMAN = bit.bor(ZS_COLLISIONGROUP_ALL, ZS_COLLISIONGROUP_DYNAMICPROP, ZS_COLLISIONGROUP_STATICPROP, ZS_COLLISIONGROUP_BLOCK_WALL_ALL_TEAM, ZS_COLLISIONGROUP_BLOCK_WALL_HUMAN, ZS_COLLISIONGROUP_ZOMBIE, ZS_COLLISIONGROUP_DEPLOYABLE, ZS_COLLISIONGROUP_PROP_DAMAGED)
ZS_COLLISIONFLAGS_HUMAN_PHASE = bit.bor(ZS_COLLISIONGROUP_STATICPROP, ZS_COLLISIONGROUP_DEPLOYABLE, ZS_COLLISIONGROUP_PROP_DAMAGED)
ZS_COLLISIONFLAGS_SPECTATOR = ZS_COLLISIONGROUP_SPECTATOR
ZS_COLLISIONFLAGS_PROP = bit.bor(ZS_COLLISIONGROUP_ALL, ZS_COLLISIONGROUP_DYNAMICPROP, ZS_COLLISIONGROUP_STATICPROP, ZS_COLLISIONGROUP_CARRIEDPROP)

-- includes them.
if SERVER then
	AddCSLuaFile("cl_collision.lua")
	include("sv_collision.lua")
else
	include("cl_collision.lua")
end

hook.Add("OnEntityCreated", "OnEntityCreated.Collision", function(ent)
	if ent:IsAPhysicsProp() and ent:GetCustomCollisionGroup() == 0 then
		ent:SetCustomGroupAndFlags(ZS_COLLISIONGROUP_DYNAMICPROP, ZS_COLLISIONFLAGS_PROP, true)
	end
end)