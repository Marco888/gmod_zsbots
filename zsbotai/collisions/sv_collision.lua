-- -- To Avoid lua refresh as well...
if not CollisionLuaLoaded then
	List_CollisionGroups = {}
	List_CollisionFlags = {}

	List_Movement_CollisionGroups = {}
	List_Movement_CollisionFlags = {}

	CollisionLuaLoaded = true
end

local meta = FindMetaTable("Entity")
if not meta then return end

local bit_band = bit.band
local bit_bor = bit.bor
local bit_bnot = bit.bnot

-- Get projectile collision flags for projectiles.
function GetProjectileFlags(ent, custom_movetype)
	local ply = ent:GetOwner()
	if not IsValid(ply) or not ply:IsPlayer() or ply:Team() == TEAM_UNDEAD then
		return ZS_COLLISIONGROUP_PROJECTILE_ZOMBIE, GAMEMODE.RoundEnded and ZS_COLLISIONFLAGS_ANYPROJ or (custom_movetype and ZS_COLLISIONFLAGS_NEWZOMBIEPROJ or ZS_COLLISIONFLAGS_ZOMBIEPROJ)
	end
	ent:SetCustomCollisionCheck(true) -- Hack, to allow human projectiles to pass through turrets.
	return ZS_COLLISIONGROUP_PROJECTILE, GAMEMODE.HitEveryone and ZS_COLLISIONFLAGS_ANYPROJ or (custom_movetype and ZS_COLLISIONFLAGS_NEWHUMANPROJ or ZS_COLLISIONFLAGS_HUMANPROJ)
end

function GetHitScanFlags(ply)
	if not IsValid(ply) then -- No player? Hit nothing but objects
		return ZS_COLLISIONGROUP_TELEPORT, ZS_COLLISIONFLAGS_PROP
	end

	if ply:Team() == TEAM_UNDEAD then
		return ZS_COLLISIONGROUP_ZOMBIE, GAMEMODE.RoundEnded and bit.bor(ZS_COLLISIONFLAGS_ANYPROJ,ZS_COLLISIONGROUP_CROW) or bit.bor(ZS_COLLISIONFLAGS_ZOMBIE, ZS_COLLISIONGROUP_NOCOLLIDE_TEAM)
	end

	return ZS_COLLISIONGROUP_HUMAN, GAMEMODE.ThePurge and ZS_COLLISIONFLAGS_ANYPROJ or ZS_COLLISIONFLAGS_HUMANPROJ
end

function meta:GetCustomCollisionGroup()
	return List_CollisionGroups[self] or 0
end

function meta:GetCollisionFlags()
	return List_CollisionFlags[self] or 0
end

local function SWAPCollision_MOVEMENT(self, flags)
	if flags == ZS_COLLISIONFLAGS_ZOMBIEPROJ then
		flags = ZS_COLLISIONFLAGS_NEWZOMBIEPROJ
	elseif flags == ZS_COLLISIONFLAGS_HUMANPROJ then
		flags = ZS_COLLISIONFLAGS_NEWHUMANPROJ
	elseif flags == bit.bor(ZS_COLLISIONFLAGS_ZOMBIECROW, ZS_COLLISIONGROUP_PROJECTILE) then
		flags = ZS_COLLISIONFLAGS_ZOMBIECROW
	end

	return flags
end

function meta:SetCustomCollisionGroup(NewGroup)
	if List_CollisionGroups[self] == NewGroup then return end

	self:SetDTInt(DT_PLAYER_AND_ENTITY_INT_COLLISION_GROUP, NewGroup)

	List_CollisionGroups[self] = NewGroup
	List_Movement_CollisionGroups[self] = NewGroup

	self:CollisionRulesChanged()
end

function meta:SetCollisionFlags(NewFlags)
	if List_CollisionFlags[self] == NewFlags then return end

	local swapflags = SWAPCollision_MOVEMENT(self, NewFlags)
	self:SetDTInt(DT_PLAYER_AND_ENTITY_INT_COLLISION_FLAG, swapflags)

	List_CollisionFlags[self] = NewFlags
	List_Movement_CollisionFlags[self] = swapflags

	self:CollisionRulesChanged()
end

function meta:SetCustomGroupAndFlags(group, flags)
	if List_CollisionGroups[self] == group and List_CollisionFlags[self] == flags then return end

	local swapflags = SWAPCollision_MOVEMENT(self, flags)

	self:SetDTInt(DT_PLAYER_AND_ENTITY_INT_COLLISION_FLAG, swapflags)
	self:SetDTInt(DT_PLAYER_AND_ENTITY_INT_COLLISION_GROUP, group)

	List_CollisionGroups[self] = group
	List_CollisionFlags[self] = flags

	List_Movement_CollisionGroups[self] = group
	List_Movement_CollisionFlags[self] = swapflags

	self:CollisionRulesChanged()
end

function meta:AddCollisionFlag(Flag)
	local CurrentFlags = List_CollisionFlags[self] or 0
	if bit_band(CurrentFlags, Flag) == Flag then return end

	self:SetCollisionFlags(bit_bor(CurrentFlags, Flag))
end

function meta:RemoveCollisionFlag(Flag)
	local CurrentFlags = List_CollisionFlags[self] or 0
	if bit_band(CurrentFlags, Flag) == 0 then return end

	self:SetCollisionFlags(bit_band(CurrentFlags, bit_bnot(Flag)))
end

local ShouldCleanTables = false
hook.Add("EntityRemoved", "EntityRemoved.CollisionMode", function(ent)
	if not ShouldCleanTables and (List_CollisionGroups[ent] or List_CollisionFlags[ent]) then
		List_CollisionFlags[ent] = nil
		List_CollisionGroups[ent] = nil
		List_Movement_CollisionGroups[ent] = nil
		List_Movement_CollisionFlags[ent] = nil
	end
end, HOOK_MONITOR_HIGH)

-- Wipe entire tables to save RAM Memory!
local function CleanMemory()
	if GAMEMODE.ZombieEscape then return end -- bug ill work soon

	ShouldCleanTables = true

	List_CollisionFlags = {}
	List_CollisionGroups = {}
	List_Movement_CollisionGroups = {}
	List_Movement_CollisionFlags = {}

	ShouldCleanTables = false
end

hook.Add("ShutDown", "ShutDown.CollisionMode", CleanMemory, HOOK_MONITOR_HIGH)
hook.Add("PreCleanupMap", "PreCleanupMap.CollisionMode", CleanMemory, HOOK_MONITOR_HIGH)

-- prevent projectiles that made player stuck on it because of gamemovement, so we dont have collision ID in shouldcollide.
local was_from_gamemovement = {}
hook.Add("StartCommand", "CollisionModeSwitch.StartCommand", function( ply, mv )
	was_from_gamemovement[ply] = true
end)

hook.Add("FinishMove", "CollisionModeSwitch.FinishMove", function( ply, mv )
	was_from_gamemovement[ply] = nil -- finished.
end)

-- this is replace your ShouldCollide in gamemode. may to rename this or whatever.
-- very great performance compared to jetboom's Shouldcollide in Zombie Survival.

local ga, gb, fa, fb, gm_ga, gm_gb, gm_fa, gm_fb
function GM:ShouldCollide(enta, entb)
	if was_from_gamemovement[enta] or was_from_gamemovement[entb] then
		gm_ga, gm_gb, gm_fa, gm_fb = List_Movement_CollisionGroups[enta], List_Movement_CollisionGroups[entb], List_Movement_CollisionFlags[enta], List_Movement_CollisionFlags[entb]
		return not gm_ga or not gm_gb or not gm_fa or not gm_fb or bit_band(gm_ga, gm_fb) ~= 0 or bit_band(gm_gb, gm_fa) ~= 0
	end

	ga, gb, fa, fb = List_CollisionGroups[enta], List_CollisionGroups[entb], List_CollisionFlags[enta], List_CollisionFlags[entb]
	return not ga or not gb or not fa or not fb or bit_band(ga, fb) ~= 0 or bit_band(gb, fa) ~= 0
end

local function TryToCollides(e, g, f)
	local ga, fa = rawget(List_CollisionGroups, e), rawget(List_CollisionFlags, e)
	return not ga or not fa or bit_band(ga, f) ~= 0 or bit_band(g, fa) ~= 0
end

function GM:TryCollides(e, g, f)
	return TryToCollides(e, g, f)
end