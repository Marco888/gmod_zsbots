local meta = FindMetaTable("Entity")
if not meta then return end

local bit_band = bit.band
local bit_bor = bit.bor
local bit_bnot = bit.bnot

local tnmb = tonumber

local List_CollisionGroups = {}
local List_CollisionFlags = {}

-- DT Int
local DTVarFuncInt = {
	[DT_PLAYER_AND_ENTITY_INT_COLLISION_FLAG] = function(e,x)
		e:SetCustomCollisionCheck(true)
		List_CollisionFlags[e] = x
		e:CollisionRulesChanged()
	end,
	[DT_PLAYER_AND_ENTITY_INT_COLLISION_GROUP] = function(e,x)
		e:SetCustomCollisionCheck(true)
		List_CollisionGroups[e] = x
		e:CollisionRulesChanged()
	end
}

Old_DTVar_ReceiveProxyGL = Old_DTVar_ReceiveProxyGL or DTVar_ReceiveProxyGL
function DTVar_ReceiveProxyGL(ent, name, id, val)
	if name == "Int" then
		local funcInt = DTVarFuncInt[id]
		if funcInt then
			funcInt(ent, val and val or ent:GetDTInt(id))
		end
	end

	Old_DTVar_ReceiveProxyGL(ent, name, id, val)
end

function meta:GetCustomCollisionGroup()
	return List_CollisionGroups[self] or 0
end

function meta:GetCollisionFlags()
	return List_CollisionFlags[self] or 0
end

function meta:SetCustomCollisionGroup(NewGroup)
	if List_CollisionGroups[self] == NewGroup then return end

	self._CFG = NewGroup
	List_CollisionGroups[self] = NewGroup
	self:CollisionRulesChanged()
end

function meta:SetCollisionFlags(NewFlags)
	if List_CollisionFlags[self] == NewFlags then return end

	self._CFF = NewFlags
	List_CollisionFlags[self] = NewFlags
	self:CollisionRulesChanged()
end

function meta:SetCustomGroupAndFlags(group, flags)
	if List_CollisionGroups[self] == group and List_CollisionFlags[self] == flags then return end

	self._CFG = group
	self._CFF = flags
	List_CollisionGroups[self] = group
	List_CollisionFlags[self] = flags

	self:CollisionRulesChanged()
end

function meta:AddCollisionFlag(Flag)
	local CurrentFlags = List_CollisionFlags[self] or 0
	if bit_band(CurrentFlags,Flag) == Flag then return end

	self:SetCollisionFlags(bit_bor(CurrentFlags, Flag))
end

function meta:RemoveCollisionFlag(Flag)
	local CurrentFlags = List_CollisionFlags[self] or 0
	if bit_band(CurrentFlags,Flag) == 0 then return end

	self:SetCollisionFlags(bit_band(CurrentFlags,bit_bnot(Flag)))
end

function GM.TryCollides( ent, cg, cf )
	local ga,fa = rawget(List_CollisionGroups,ent),rawget(List_CollisionFlags,ent)
	return (not ga or not fa or bit_band(ga,cf)~=0 or bit_band(cg,fa)~=0)
end

local function _ShouldCollide(enta, entb)
	local ga,gb,fa,fb = rawget(List_CollisionGroups,enta),rawget(List_CollisionGroups,entb),rawget(List_CollisionFlags,enta),rawget(List_CollisionFlags,entb)
	return (not ga or not gb or not fa or not fb or bit_band(ga,fb)~=0 or bit_band(gb,fa)~=0)
end

function GM:ShouldCollide(enta, entb)
	local ga,gb,fa,fb = rawget(List_CollisionGroups,enta),rawget(List_CollisionGroups,entb),rawget(List_CollisionFlags,enta),rawget(List_CollisionFlags,entb)
	return (not ga or not gb or not fa or not fb or bit_band(ga,fb)~=0 or bit_band(gb,fa)~=0)
end