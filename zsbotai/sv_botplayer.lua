
local meta = FindMetaTable("Player")
local BotControllers = {}

function ZSBOTAI.MakeBot( pl, Enable )
	if Enable==pl:UseBotAI() then return end

	if Enable then
		BotControllers[pl] = true
		ZSBOTAI.InitBot(pl)
	else
		BotControllers[pl] = nil
		ZSBOTAI.ExitBot(pl)

		if pl:Team()==TEAM_HUMAN and pl:Alive() then
			for _, wep in pairs(pl:GetWeapons()) do
				if wep._BotBuy then
					wep:RemoveWeapon()
				end
			end
		end
	end
	if not pl:IsBot() and pl:Alive() then
		pl:ResetJumpPower()
		pl:DoHulls(nil, nil, true)
	end
end

function meta:UseBotAI()
	return BotControllers[self] or false
end

SUPER_LagCompensation = SUPER_LagCompensation or meta.LagCompensation

function meta:LagCompensation( lagCompensation )
	if not BotControllers[self] then
		SUPER_LagCompensation(self, lagCompensation)
	end
end

local AFKMonitor = {}
local BotControlTime = 2 * 60 -- 2 minutes

local function CheckAFKs()
	for i=#AFKMonitor, 1, -1 do
		local pl = AFKMonitor[i]
		if not pl:IsValid() or pl:UseBotAI() or pl:Team()==TEAM_SPECTATOR then
			table.remove(AFKMonitor,i)
		elseif pl:Team()==TEAM_UNDEAD and (CurTime()-pl:GetDTFloat(DTF_PlayerAfk))>BotControlTime then
			ZSBOTAI.MakeBot(pl,true)
			table.remove(AFKMonitor,i)
		end
	end
	if #AFKMonitor==0 then
		timer.Remove("BotAFKTimer")
	end
end

hook.Add("NotifyPlayerAFK","Bot.NotifyPlayerAFK",function( pl, bAFK )
	if bAFK then
		if pl:Team()==TEAM_SPECTATOR then return end
		if #AFKMonitor==0 then
			timer.Create("BotAFKTimer",3,0,CheckAFKs)
		end
		AFKMonitor[#AFKMonitor+1] = pl
	else
		if pl:UseBotAI() then
			ZSBOTAI.MakeBot(pl,false)
		end
		table.RemoveByValue(AFKMonitor,pl)
	end
end)
