
AddCSLuaFile("cl_botprofiler.lua")
util.AddNetworkString("zs_ai_profile")

local function StartAINet( code )
	net.Start("zs_ai_profile")
	net.WriteUInt(code,3)
end

function ZSBOTAI.BotOrders( bot, tag, a, b, c )
	local tab = bot.AIProfilers
	if not tab then return end

	if tag==1 then -- Bot begin moving towards
		StartAINet(1)
		
		if isvector(a) then
			net.WriteUInt(0,2)
			net.WriteVector(a)
			net.WriteFloat(b)
		elseif IsValid(a) then
			net.WriteUInt(1,2)
			net.WriteEntity(a)
			net.WriteFloat(b)
		else
			net.WriteUInt(2,2)
		end
	elseif tag==2 then -- New bot route
		StartAINet(2)

		while b.previousPath do
			net.WriteBool(true)
			net.WriteUInt(b.Index,16)
			b = b.previousPath
		end
		net.WriteBool(false)
	elseif tag==3 then -- Stakeout
		StartAINet(3)
		net.WriteUInt(1,6)
	elseif tag==4 then -- Go shopping
		StartAINet(3)
		net.WriteUInt(2,6)
		net.WriteEntity(a)
		net.WriteFloat(b)
	elseif tag==5 then -- Follow companion.
		StartAINet(3)
		net.WriteUInt(3,6)
		net.WriteEntity(a)
	elseif tag==6 then -- Idle orders.
		StartAINet(3)
		net.WriteUInt(0,6)
	elseif tag==7 then -- Charge enemy
		StartAINet(3)
		net.WriteUInt(4,6)
	elseif tag==8 then -- Hunt enemy
		StartAINet(3)
		net.WriteUInt(5,6)
	elseif tag==9 then -- Hunt enemy but can't find it
		StartAINet(3)
		net.WriteUInt(6,6)
	elseif tag==10 then -- Break prop
		StartAINet(3)
		net.WriteUInt(36,6)
		net.WriteEntity(a)
		net.WriteFloat(b)
	elseif tag==11 then -- Open door
		StartAINet(3)
		net.WriteUInt(37,6)
		net.WriteEntity(a)
		net.WriteFloat(b)
	elseif tag==12 then -- Gained enemy
		StartAINet(4)
		net.WriteEntity(a)
	elseif tag==13 then -- Move to last seen enemy location
		StartAINet(3)
		net.WriteUInt(7,6)
	else
		DEBUG_MessageDev("Unknown bot order code '"..tostring(tag).."' from "..tostring(bot),false,1)
		return
	end
	
	local pls = {}
	for ppl, val in pairs(tab) do
		pls[#pls+1] = ppl
	end
	net.Send(pls)
end

function ZSBOTAI.SetProfileTarget( pl, bot, DC )
	if pl._Profile==bot then return end

	-- Uninit profiler for old bot
	if pl._Profile then
		local b = pl._Profile
		if IsValid(b) and b.AIProfilers then
			b.AIProfilers[pl] = nil
			
			local bAny = false
			for ppl, val in pairs(b.AIProfilers) do
				bAny = true
				break
			end
			if not bAny then
				b.AIProfilers = nil
			end
		end
	end
	
	if not IsValid(bot) then
		pl._Profile = nil
		
		if not DC then
			StartAINet(0)
			net.WriteBool(false)
			net.Send(pl)
		end
		return
	end
	
	hook.Add("PlayerDisconnected", "PlayerDisconnected.AIProfiler", function( ply )
		if ply:IsBot() then
			if ply.AIProfilers then
				local tb = ply.AIProfilers
				ply.AIProfilers = nil
				for ppl, val in pairs(tb) do
					ZSBOTAI.SetProfileTarget(ppl,nil)
				end
			end
		elseif ply._Profile then
			ZSBOTAI.SetProfileTarget(ply,nil,true)
		end
	end)
	
	StartAINet(0)
		net.WriteBool(true)
		net.WriteEntity(bot)
	net.Send(pl)
	
	pl._Profile = bot
	local tab = bot.AIProfilers
	if not tab then
		tab = {}
		bot.AIProfilers = tab
	end
	tab[pl] = true
	
	ZSBOTAI.NetworkPathList(pl) -- Client needs this to draw path info.
end
