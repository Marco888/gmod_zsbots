local meta = FindMetaTable("Entity")
if not meta then return end

--- FOR BOT SYSTEM
--- ENTITY FILTER BY MARCO.
local DmgFilterList = {}
-- Optimize by only handing for these classes:
local RequestedDmgFilters = {
	["func_physbox"] = true,
	["func_physbox_multiplayer"] = true,
	["func_breakable"] = true,
	["func_button"] = true,
}

function meta:CheckPassesDamageFilterEnt(ent)
	local f = DmgFilterList[self]
	if IsValid(f) then
		return f:PassesFilter(self, ent)
	end
	return true
end

function meta:CheckPassesDamageFilter(dmg)
	local f = DmgFilterList[self]
	if IsValid(f) then
		return f:PassesDamageFilter(dmg)
	end
	return true
end

local PendingEnts = {}
hook.Add("EntityKeyValue", "EntityKeyValue.Filters", function(ent, key, value)
	if PendingEnts then
		local c = ent:GetClass()
		if RequestedDmgFilters[c] and string.lower(key) == "damagefilter" then
			ent.m_DmgFilterName = value
			PendingEnts[ent] = true
		end
	end
end)

hook.Add("PreCleanupMap", "PreCleanupMap.Filters", function()
	DmgFilterList = {}
	PendingEnts = {}
end)

hook.Add("InitPostEntityMap", "InitPostEntity.Filters", function()
	for ent, v in pairs(PendingEnts) do
		if IsValid(ent) then
			if ent.m_DmgFilterName and #ent.m_DmgFilterName > 0 then
				DmgFilterList[ent] = ents.FindByName(ent.m_DmgFilterName)[1]
			end

			ent.m_FilterName = nil
			ent.m_DmgFilterName = nil
		end
	end
	PendingEnts = nil
end)