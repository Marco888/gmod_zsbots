
local LadderHooks = false

-- Shortcuts.
local BOT_MoveDestination = ZSBOTAI.AITable.MoveDestination
local BOT_ShouldCrouch = ZSBOTAI.AITable.ShouldCrouch
local BOT_AttackProp = ZSBOTAI.AITable.AttackProp
local BOT_MoveTimer = ZSBOTAI.AITable.MoveTimer
local BOT_LadderPath = ZSBOTAI.AITable.LadderPath

local function ResetLadderHandle( pl )
	ZSBOTAI.EndLadderMove(pl)
end

local function BotLadderMove( pl, mv )
	if not BOT_LadderPath[pl] then return end
	
	local startpos, endpos = pl.BOT_LadderStart, BOT_MoveDestination[pl]
	if not isvector(endpos) then
		ZSBOTAI.EndLadderMove(pl)
		return
	end
	
	if BOT_AttackProp[pl] then
		mv:SetVelocity(Vector(0,0,0))
		return true
	end
	local dir = (endpos - startpos)
	local ct = BOT_MoveTimer[pl] + FrameTime()
	local t = ct / pl.BOT_LadderTime
	if t>=1 then
		mv:SetVelocity(Vector(0,0,0))
		mv:SetOrigin(endpos)

		-- End move and ladder.
		BOT_MoveDestination[pl] = nil
		BOT_MoveTimer[pl] = nil
		BOT_ShouldCrouch[pl] = nil
		local mcount = BOT_LadderPath[pl]
		if mcount>=1 then
			ZSBOTAI.EndLadderMove(pl)
		else
			BOT_LadderPath[pl] = mcount+1
		end
	else
		local des = (startpos + dir*t)
		if ZSBOTAI.CheckCadeProps(pl,des) then
			mv:SetVelocity(Vector(0,0,0))
			return true
		end
		mv:SetVelocity(dir)
		mv:SetOrigin(des)
		BOT_MoveTimer[pl] = ct
	end
	return true
end

function ZSBOTAI.EndLadderMove( pl )
	if BOT_LadderPath[pl] then
		BOT_LadderPath[pl] = nil
		if LadderHooks then
			LadderHooks = LadderHooks-1
			if LadderHooks==0 then
				LadderHooks = false
				hook.Remove("ResetAI","ResetAI.BotLadderPhy")
				hook.Remove("Move","Move.BotLadderPhy")
			end
		end
	end
	pl.BOT_PendingLadder = nil
	pl.BOT_LadderStart = nil
end

function ZSBOTAI.StartLadderMove( pl, dest )
	local maxSpeed = pl:GetMaxSpeed()*1.1
	if pl.BOT_PendingLadder then
		if not BOT_LadderPath[pl] then
			maxSpeed = maxSpeed*2
		end
		BOT_LadderPath[pl] = 0
		pl.BOT_PendingLadder = nil
	end
	if BOT_LadderPath[pl] then
		if BOT_LadderPath[pl]==1 then
			maxSpeed = maxSpeed*2
		end
		pl.BOT_LadderStart = pl:GetPos()
		local bottom, top = pl:GetHullDuck()
		local Res = util.FindSpot(dest, bottom, top)
		if isvector(Res) then
			dest = Res
		end
		BOT_MoveDestination[pl] = dest
		local movet = (dest:Distance(pl:GetPos()) / maxSpeed)
		pl.BOT_LadderTime = movet
		BOT_MoveTimer[pl] = 0
		BOT_ShouldCrouch[pl] = true
		
		if not LadderHooks then
			LadderHooks = 1
			hook.Add("ResetAI","ResetAI.BotLadderPhy",ResetLadderHandle)
			hook.Add("Move","Move.BotLadderPhy",BotLadderMove)
		else
			LadderHooks = LadderHooks+1
		end
		return true
	end
	return false
end
