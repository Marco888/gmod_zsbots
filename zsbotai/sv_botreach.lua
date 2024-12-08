local meta = FindMetaTable("Player")
local GetPlayerTeam = meta.Team
local AI_WalkableZ = 0.7

-- Special AI entities:
local BreakableBlocks = {
	["func_physbox"]=true,
	["func_physbox_multiplayer"]=true,
	["func_breakable"]=true,
}
local ZAttackProps = {
	["prop_food"]=true,
	["prop_physics"]=true,
	["prop_physics_multiplayer"]=true,
	["prop_ffemitter"]=true,
	["prop_ffemitter_supply"]=true,
	["prop_ffemitter_research"]=true,
	["prop_arsenalcrate"]=true,
	["prop_aegisboard"]=true,
	["prop_metalboard"]=true,
	["prop_carbonboard"]=true,
	["prop_gunturret"]=true,
	["prop_gunturret_assault"]=true,
	["prop_gunturret_buckshot"]=true,
	["prop_gunturret_laser"]=true,
	["prop_resupplybox"]=true,
	["prop_spotlamp"]=true,
	["prop_zapper"]=true,
	["prop_zapper_arc"]=true,
	["prop_recycler"]=true,
	["prop_repairnail"]=true,
	["prop_remantler"]=true,
	["prop_defend_obj"]=true,
	["vodoo_skull"]=true,
}
local CadeProps = {
	["prop_food"]=true,
	["func_physbox"]=true,
	["func_physbox_multiplayer"]=true,
	["prop_physics"]=true,
	["prop_physics_multiplayer"]=true,
	["prop_ffemitter"]=true,
	["prop_ffemitterfield"]=true,
	["prop_arsenalcrate"]=true,
	["prop_aegisboard"]=true,
	["prop_gunturret"]=true,
	["prop_resupplybox"]=true,
	["prop_spotlamp"]=true,
	["prop_defend_obj"]=true,
	["prop_ffemitterfield_supply"]=true,
}
local UseableDoors = {
	["func_door_rotating"]=true,
	["prop_door_rotating"]=true,
	["func_door"]=true,
	["func_movelinear"]=true,
}

-- Shortcuts.
local BOT_MoveDestination = ZSBOTAI.AITable.MoveDestination
local BOT_DesiredRotation = ZSBOTAI.DesiredRotation
local BOT_MoveStuckTime = ZSBOTAI.AITable.MoveStuckTime
local BOT_PropAttackCount = ZSBOTAI.AITable.PropAttackCount
local BOT_ShouldCrouch = ZSBOTAI.AITable.ShouldCrouch
local BOT_AttackProp = ZSBOTAI.AITable.AttackProp
local BOT_LeapPathTimer = ZSBOTAI.AITable.LeapPathTimer
local BOT_SideStepTime = ZSBOTAI.AITable.SideStepTime
local BOT_MoveTimer = ZSBOTAI.AITable.MoveTimer
local BOT_JumpCrouch = ZSBOTAI.AITable.JumpCrouch
local BOT_BarricadeGhostTime = ZSBOTAI.AITable.BarricadeGhostTime
local BOT_PendingUse = ZSBOTAI.AITable.PendingUse
local BOT_PendingJump = ZSBOTAI.AITable.PendingJump
local BOT_NextDoorOpenTime = ZSBOTAI.AITable.NextDoorOpenTime
local BOT_MoveStuckPos = ZSBOTAI.AITable.MoveStuckPos
local BOT_LastLadderSpot = ZSBOTAI.AITable.LastLadderSpot

local GetReachTraceInfo = ZSBOTAI.GetReachTraceInfo
local util_TraceHull = util.TraceHull
local E_GetPos = FindMetaTable("Entity").GetPos

function ZSBOTAI.DirectReachable( dest, startPos, mins, maxs, meleeRange )
	-- Check destination
	local DestPos
	local DestHeight = maxs.z
	local DestRadii = maxs.x
	if isvector(dest) then
		DestPos = dest
	elseif dest:IsPlayer() then
		local bottom, top
		if dest:Crouching() then
			bottom, top = dest:GetHullDuck()
		else
			bottom, top = dest:GetHull()
		end
		DestRadii = DestRadii+top.x+(meleeRange or 0)
		DestPos = E_GetPos(dest)
	else
		DestPos = E_GetPos(dest)
	end

	local dir = (DestPos-startPos):GetNormalized()
	DestPos = DestPos-dir*DestRadii

	-- Try direct
	local tri = GetReachTraceInfo(startPos,DestPos,mins,maxs)
	if not util_TraceHull(tri).Hit then
		return true
	end

	-- try above
	tri.endpos.z = tri.endpos.z+DestHeight
	return not util_TraceHull(tri).Hit
end

local TEMP_Tab = {}

function ZSBOTAI.PointReachable( dest, startPos, mins, maxs, meleeRange, bNoJump, direct )
	if direct then
		return ZSBOTAI.DirectReachable( dest, startPos, mins, maxs, meleeRange )
	end

	-- Check destination
	local DestPos
	local DestHeight = maxs.z
	local DestRadii = maxs.x
	if isvector(dest) then
		DestPos = dest
	elseif dest:IsPlayer() and meleeRange then
		local bottom, top
		if dest:Crouching() then
			bottom, top = dest:GetHullDuck()
		else
			bottom, top = dest:GetHull()
		end
		DestRadii = DestRadii+top.x+meleeRange -- Add melee range.
		DestHeight = DestHeight+meleeRange
		DestPos = E_GetPos(dest)
	else
		DestPos = E_GetPos(dest)
	end

	if (DestPos-startPos):Length2DSqr()>1265625 then
		return false -- too far distance.
	end

	if util.TraceLine({start=startPos+Vector(0,0,25), endpos=DestPos+Vector(0,0,25), mask=MASK_PLAYERSOLID_BRUSHONLY}).Hit then
		return false -- not visible.
	end

	-- Setup trace info.
	local tri = GetReachTraceInfo(startPos,nil,mins,maxs)
	local bFalling = false
	local VelZ = 0
	DestRadii = DestRadii*DestRadii

	-- Keep iterating until we find the goal.
	for i=0, 24 do
		local Dir = (DestPos-tri.start)

		if Dir:Length2DSqr()<(DestRadii+2000) then -- we've reached the goal now.
			if Dir.z>-5 and Dir.z<=DestHeight then -- were overlapping the dest.
				return true
			end

			if Dir.z<0 then -- above dest, see if we can fall down.
				tri.endpos = DestPos+Vector(0,0,DestHeight)
				local tr = util_TraceHull( tri )
				return not tr.Hit
			end

			-- under the dest, can't help it....
			return false
		end

		Dir.z = 0
		Dir = Dir:GetNormalized()*65
		if bFalling then -- apply falling velocity.
			VelZ = VelZ-48
			Dir.z = Dir.z + VelZ
		end
		tri.endpos = tri.start+Dir

		local tr = util_TraceHull(tri)

		if tr.Hit then
			tri.start = tr.HitPos

			if bFalling then
				if tr.HitNormal.z>AI_WalkableZ then -- landed on floor, start walking again.
					bFalling = false
					continue
				end
			elseif tr.HitNormal.z<=AI_WalkableZ then -- walked into an unwalkable floor (wall or slope)
				-- see if we can step over it.
				tri.endpos = tri.start+Vector(0,0,20)
				local bCanStep = false
				tri.output = TEMP_Tab -- Need a different op here
				if not util_TraceHull(tri).Hit then -- did not bump head when moving up.
					tri.start = Vector(tri.endpos)
					tri.endpos = tri.endpos+Dir*0.15

					if not util_TraceHull(tri).Hit then -- did not bump the knee when moving forward a step
						tri.start = Vector(tri.endpos)
						tri.endpos = tri.endpos-Vector(0,0,20)

						local trb = util_TraceHull(tri)
						if trb.Hit and trb.HitNormal.z>AI_WalkableZ then -- did step on a step with an acceptable normal
							tri.start = trb.HitPos
							bCanStep = true
							tr.HitNormal = trb.HitNormal
						end
					end
				end
				tri.output = tr -- Restore

				if not bCanStep then -- jump.
					bFalling = true
					VelZ = (bNoJump and 5 or 50)
					continue
				end
			end

			Dir = Dir - Dir:Dot(tr.HitNormal) * tr.HitNormal + tr.HitNormal*0.15
			tri.endpos = tri.start+Dir

			-- try moving remaining time.
			tr = util_TraceHull(tri)

			if tr.Hit then
				tri.start = tr.HitPos
			else
				tri.start = tri.endpos
			end
		else
			tri.start = tri.endpos
		end

		-- Check if were in air.
		if not bFalling then
			tri.endpos = tri.start-Vector(0,0,10)
			tr = util_TraceHull(tri)

			if not tr.Hit or tr.HitNormal.z<AI_WalkableZ then
				bFalling = true
				VelZ = (bNoJump and -10 or 65)
			end
		end
	end

	return false -- ran out of iterations.
end

function ZSBOTAI.CheckBlockedAIPath( pl, Node )
	if not pl.BOT_RouteCache then
		pl.BOT_RouteCache = {}
		pl.BOT_NumFailures = nil
	end
	if pl.BOT_RouteCache[1]==Node or pl.BOT_RouteCache[2]==Node then
		pl.BOT_NumFailures = pl.BOT_NumFailures+1

		if Node and Node.Index and pl.BOT_NumFailures > 8 then
			pl.BOT_BlockedPaths[Node.Index] = CurTime() + 15
			pl.BOT_NumFailures = 0
		end
	else
		pl.BOT_NumFailures = 0
		pl.BOT_RouteCache[2] = pl.BOT_RouteCache[1]
		pl.BOT_RouteCache[1] = Node
	end
end

local function TwoWallAdjust( Dir, HitNormal, OldHitNormal )
	local X = Dir:GetNormalized()
	local Result
	if OldHitNormal:Dot(HitNormal) <= 0 then -- 90 or less corner, so use cross product for dir
		local NewDir = HitNormal:Cross(OldHitNormal)
		NewDir = NewDir:GetNormalized()
		Result = Dir:Dot(NewDir) * NewDir;
		if X:Dot(Result) < 0 then
			Result = -Result
		end
	else -- adjust to new wall
		Result = Dir - HitNormal * Dir:Dot(HitNormal)
	end
	return Result
end

local function CheckDoorBlockAggro( pl, ent )
	local tab = pl.BOT_DoorAggro
	if not tab or tab.Door~=ent or tab.Time<CurTime() then
		if not tab then
			tab = {}
			pl.BOT_DoorAggro = tab
		end
		tab.Door = ent
		tab.Time = CurTime()+5
		tab.Count = 0
	else
		tab.Time = CurTime()+5
		tab.Count = tab.Count+1
		if tab.Count>=5 then
			BOT_AttackProp[pl] = ent
			pl.BOT_PropAttackTime = CurTime()+math.Rand(1.25,2)
			BOT_MoveStuckTime[pl] = nil
			ZSBOTAI.BotOrders(pl,10,ent,pl.BOT_PropAttackTime)
			ZSBOTAI.AbortMove(pl)
			return true
		end
	end
end

local BOT_SpecialGoal
local BOT_SpecialGoalB

local DoorFunctions = {
	["func_door"] = function( self )
		return self:GetSaveTable().m_bLocked or self:GetSaveTable().m_toggle_state == 0
	end,
	["func_door_rotating"] = function( self )
		return self:GetSaveTable().m_bLocked or self:GetSaveTable().m_toggle_state == 0
	end,
	["prop_door_rotating"] = function( self )
		return self:GetSaveTable().m_bLocked or self:GetSaveTable().m_eDoorState ~= 0
	end,
	["func_movelinear"] = function( self )
		return self:GetSaveTable().m_toggle_state == 0
	end,
}

local function IsDoorLocked( ent )
	local func = DoorFunctions[ent:GetClass()]
	if func then
		return func(ent)
	end
end

local function EntIsBreakable( ent, pl )
	if not ent:CheckPassesDamageFilterEnt(pl) then return false end

	if ent:GetClass()=="func_breakable" and (ent:GetKeyValues().health or 1)==0 then return false end

	return true
end

-- Prepare that may need to do something about this entity, but not yet.
local function PrenotifyHitEnt( pl, ent )
	if BOT_SpecialGoal or not IsValid(ent) then return end

	local eclass = ent:GetClass()
	pent = ent:GetParent()
	local plt = GetPlayerTeam(pl)

	if UseableDoors[eclass] then
		if IsDoorLocked(ent) then return end

		if not BOT_SpecialGoal then
			BOT_SpecialGoal = ent
		end
		return true
	elseif IsValid(pent) and UseableDoors[pent:GetClass()] then
		if IsDoorLocked(pent) then return end

		if not BOT_SpecialGoal then
			BOT_SpecialGoal = pent
		end
		return true
	elseif plt==TEAM_UNDEAD and ZAttackProps[eclass] then
		if not BOT_SpecialGoal then
			BOT_SpecialGoal = ent
		elseif not BOT_SpecialGoalB then
			BOT_SpecialGoalB = ent
		end
		return true
	elseif plt==TEAM_HUMAN and CadeProps[eclass] then
		if not BOT_SpecialGoal then
			BOT_SpecialGoal = ent
		end
		return true
	elseif BreakableBlocks[eclass] then
		local bt = ent.BOT_BreakableTeam
		if not bt then
			bt = {}
			ent.BOT_BreakableTeam = bt
		end
		if bt[plt]==nil then
			bt[plt] = EntIsBreakable(ent,pl)
		end
		if bt[plt] then
			if not BOT_SpecialGoal then
				BOT_SpecialGoal = ent
			elseif not BOT_SpecialGoalB then
				BOT_SpecialGoalB = ent
			end
			return true
		end
	end
end

-- Deal with some bumped entity
local function HandleBumpedProp( pl, ent )
	local eclass = ent:GetClass()
	pent = ent:GetParent()
	local plt = GetPlayerTeam(pl)

	if UseableDoors[eclass] then
		if IsDoorLocked(ent) or CheckDoorBlockAggro(pl,ent) then return end

		ent:Use(pl,pl,USE_TOGGLE,0)
		if BOT_SpecialGoalB then
			BOT_AttackProp[pl] = ent
			pl.BOT_PropAttackTime = CurTime()+math.Rand(0.8,2)
			BOT_MoveStuckTime[pl] = nil
			ZSBOTAI.BotOrders(pl,10,ent,pl.BOT_PropAttackTime)
			ZSBOTAI.AbortMove(pl)
			return
		end
		BOT_NextDoorOpenTime[pl] = CurTime()+0.75
		BOT_MoveStuckTime[pl] = nil
		ZSBOTAI.BotOrders(pl,11,ent,BOT_NextDoorOpenTime[pl])
	elseif IsValid(pent) and UseableDoors[pent:GetClass()] then
		if IsDoorLocked(pent) or CheckDoorBlockAggro(pl,pent) then return end

		pent:Use(pl,pl,USE_TOGGLE,0)
		if BOT_SpecialGoalB then
			BOT_AttackProp[pl] = ent
			pl.BOT_PropAttackTime = CurTime()+math.Rand(0.8,2)
			BOT_MoveStuckTime[pl] = nil
			ZSBOTAI.BotOrders(pl,10,ent,pl.BOT_PropAttackTime)
			ZSBOTAI.AbortMove(pl)
			return
		end
		BOT_NextDoorOpenTime[pl] = CurTime()+0.75
		BOT_MoveStuckTime[pl] = nil
		ZSBOTAI.BotOrders(pl,11,pent,BOT_NextDoorOpenTime[pl])
	elseif plt==TEAM_UNDEAD and ZAttackProps[eclass] then
		BOT_AttackProp[pl] = ent
		pl.BOT_PropAttackTime = CurTime()+math.Rand(0.8,2)
		BOT_MoveStuckTime[pl] = nil
		ZSBOTAI.BotOrders(pl,10,ent,pl.BOT_PropAttackTime)
		ZSBOTAI.AbortMove(pl)
		return true
	elseif plt==TEAM_HUMAN and CadeProps[eclass] then
		if pl:AllowGhosting() and ent:IsStaticProp() then
			pl:SetBarricadeGhosting(true)
			BOT_BarricadeGhostTime[pl] = CurTime()+0.5
		elseif not ent:IsStaticProp() then
			pl.IAmBuff = true
			hook.Call("TryHumanPickup",GAMEMODE,pl,ent) -- Pickup and throw prop away.
		end
	elseif BreakableBlocks[eclass] then
		local bt = ent.BOT_BreakableTeam
		if not bt then
			bt = {}
			ent.BOT_BreakableTeam = bt
		end
		if not bt[plt] then
			bt[plt] = ent:CheckPassesDamageFilterEnt(pl)
		end
		if bt[plt] then
			BOT_AttackProp[pl] = ent
			pl.BOT_PropAttackTime = CurTime()+math.Rand(0.8,2)
			BOT_MoveStuckTime[pl] = nil
			ZSBOTAI.BotOrders(pl,10,ent,pl.BOT_PropAttackTime)
			ZSBOTAI.AbortMove(pl)
			return true
		end
	end
end

local function IsFarDist( v )
	return (math.abs(v.z)>50 or v:Length2DSqr()>100)
end

local BOT_TESTCG,BOT_TESTCF
local _TryCollides = GM.TryCollides
local function FilterBotMove( ent )
	return (not ent:IsPlayer() and _TryCollides(ent,BOT_TESTCG,BOT_TESTCF) and ent:ShouldBlockPlayer())
end

local TF_CadePropInfo = {filter=FilterBotMove, mask=MASK_PLAYERSOLID, ignoreworld=true, output={}}
local TF_MoveCheckInfo = {filter=FilterBotMove, mask=MASK_PLAYERSOLID, output={}}

-- Make zombies attack props.
function ZSBOTAI.CheckCadeProps( pl, dest )
	if GetPlayerTeam(pl)~=TEAM_UNDEAD then return false end

	local bottom, top
	if pl:Crouching() then
		bottom, top = pl:GetHullDuck()
	else
		bottom, top = pl:GetHull()
	end

	TF_CadePropInfo.mins = bottom
	TF_CadePropInfo.maxs = top
	TF_CadePropInfo.start = E_GetPos(pl)
	TF_CadePropInfo.endpos = dest
	local tr = util_TraceHull(TF_CadePropInfo)
	local ent = tr.Entity
	if tr.Hit and IsValid(ent) and ZAttackProps[ent:GetClass()] then
		BOT_AttackProp[pl] = ent
		pl.BOT_PropAttackTime = CurTime()+math.Rand(0.8,2)
		BOT_MoveStuckTime[pl] = nil
		ZSBOTAI.BotOrders(pl,10,ent,pl.BOT_PropAttackTime)
		return true
	end
	return false
end

local function StepAside( pl, pos, cmd )
	local ang = (pos-E_GetPos(pl)):Angle()
	BOT_SideStepTime[pl] = CurTime()+0.4
	pl.BOT_SideStepMove = ang
	cmd:SetViewAngles(ang)
	ZSBOTAI.BotOrders(pl,1,pos,BOT_SideStepTime[pl])
end

function ZSBOTAI.POLL_MoveTowards( pl, dest, cmd )
	local plpos = E_GetPos(pl)
	local dir = (dest - plpos)

	if dir.z>0 and pl.bFlyingZombie then -- Take off from ground.
		BOT_PendingJump[pl] = true
	end

	if pl.BOT_FlatMove then
		dir.z = 0
	end

	-- Check stuck.
	if not BOT_MoveStuckTime[pl] or IsFarDist(BOT_MoveStuckPos[pl]-plpos) then
		BOT_MoveStuckTime[pl] = CurTime()+0.6
		pl.BOT_MoveStuckCounter = 0
		BOT_MoveStuckPos[pl] = plpos
	end

	if BOT_MoveStuckTime[pl]<CurTime() then
		BOT_MoveStuckTime[pl] = CurTime()+0.6
		pl.BOT_MoveStuckCounter = pl.BOT_MoveStuckCounter+1
		if pl.BOT_MoveStuckCounter==10 then
			ZS_UnstuckPlayer(pl)
		elseif pl.BOT_MoveStuckCounter==25 then
			pl:Kill()
			pl.BOT_MoveStuckCounter = 0
			return
		elseif pl.BOT_MoveStuckCounter>1 then
			BOT_PendingJump[pl] = true
			BOT_JumpCrouch[pl] = not pl.bFlyingZombie
		end
	end

	local ang = dir:Angle()
	if pl:GetMoveType()==MOVETYPE_LADDER then -- Handle ladder paths.
		local orgPitch = ang.pitch
		if pl.BOT_UpDirection then
			ang.pitch = -70
			if dest.z<(plpos.z-10) then
				BOT_PendingJump[pl] = true
			end
		else
			ang.pitch = 70
			if dest.z>(plpos.z+10) then
				BOT_PendingJump[pl] = true
			end
		end

		if pl.BOT_GetOffLadder then
			if pl.BOT_LastLadderTime<CurTime() then
				pl.BOT_GetOffLadder = nil
				BOT_LastLadderSpot[pl] = nil
			end
			-- Persistent ladder, try to get off it...
			ang.pitch = orgPitch + math.random(-48,48)
			BOT_PendingUse[pl] = (math.random(5)==1)
			BOT_PendingJump[pl] = (math.random(6)==1)
		elseif not BOT_LastLadderSpot[pl] or BOT_LastLadderSpot[pl]:DistToSqr(plpos)>10 then
			BOT_LastLadderSpot[pl] = plpos
			pl.BOT_LastLadderTime = CurTime()+0.25
		elseif pl.BOT_LastLadderTime<CurTime() then
			ang.pitch = orgPitch
			BOT_PendingUse[pl] = true
			pl.BOT_LastLadderTime = CurTime()+0.5
			pl.BOT_GetOffLadder = true
		elseif pl.BOT_UpDirection then
			BOT_ShouldCrouch[pl] = true
		end
	else
		if BOT_LastLadderSpot[pl] then
			BOT_LastLadderSpot[pl] = nil
			pl.BOT_GetOffLadder = nil
		end
		if BOT_LeapPathTimer[pl] and BOT_LeapPathTimer[pl]>CurTime() and pl.BOT_ClimbWall then
			cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_ATTACK2))
			if pl.BOT_UpDirection then
				ang.pitch = -70
				if dest.z<(plpos.z-10) then
					pl.BOT_ClimbWall = nil
				end
			else
				ang.pitch = 70
				if dest.z>(plpos.z+10) then
					pl.BOT_ClimbWall = nil
				end
			end
		end
	end

	-- Handle side stepping past obstacles.
	if BOT_SideStepTime[pl] then
		if BOT_SideStepTime[pl]<CurTime() then
			pl.BOT_SideStepMove = nil
			BOT_SideStepTime[pl] = nil
			ZSBOTAI.BotOrders(pl,1,BOT_MoveDestination[pl],BOT_MoveTimer[pl])
		else
			ang = pl.BOT_SideStepMove
		end
	end

	cmd:SetViewAngles(ang)
	BOT_DesiredRotation:Set(ang)
	cmd:SetForwardMove(1000)
	cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_FORWARD))

	-- Check move ahead if we bump into something...
	BOT_PropAttackCount[pl] = BOT_PropAttackCount[pl]+1
	if BOT_PropAttackCount[pl]<10 then return end
	BOT_PropAttackCount[pl] = 0

	if pl.BOT_RemainCrouch then
		pl.BOT_RemainCrouch = pl.BOT_RemainCrouch-1
		if pl.BOT_RemainCrouch<=0 then
			pl.BOT_RemainCrouch = nil
		end
	end

	BOT_TESTCG,BOT_TESTCF = pl:GetCustomCollisionGroup(),pl:GetCollisionFlags()
	local bottom, top = pl:GetHull()
	local cr_bottom, cr_top = pl:GetHullDuck()

	TF_MoveCheckInfo.mins = bottom
	TF_MoveCheckInfo.maxs = top
	local tr

	BOT_SpecialGoal = false -- Reset special goal.
	BOT_SpecialGoalB = false

	if pl:GetMoveType()==MOVETYPE_LADDER then -- Handle ladder paths.
		if pl:Crouching() then
			TF_MoveCheckInfo.mins = cr_bottom
			TF_MoveCheckInfo.maxs = cr_top
		end

		local X = pl.BOT_UpDirection and Vector(0,0,18) or Vector(0,0,-18)
		TF_MoveCheckInfo.start = plpos
		TF_MoveCheckInfo.endpos = plpos+X
		tr = util_TraceHull(TF_MoveCheckInfo)
		if tr.Hit and tr.Entity then
			HandleBumpedProp(pl,tr.Entity)
		end
		return
	end

	if not pl.BOT_RemainCrouch then
		if BOT_ShouldCrouch[pl] then
			TF_MoveCheckInfo.start = plpos
			TF_MoveCheckInfo.endpos = plpos
			tr = util_TraceHull(TF_MoveCheckInfo)
			if not tr.Hit then
				BOT_ShouldCrouch[pl] = nil -- Stop crouching when we don't need it.
			else
				TF_MoveCheckInfo.mins = cr_bottom
				TF_MoveCheckInfo.maxs = cr_top
			end
		end
	elseif BOT_ShouldCrouch[pl] then
		TF_MoveCheckInfo.mins = cr_bottom
		TF_MoveCheckInfo.maxs = cr_top
	end

	if pl.bFlyingZombie or pl:WaterLevel()>=2 then -- Swimming or flying.
		local X = dir:GetNormalized()
		local dist = dir:Length()
		local MX = X*math.min(dist,60)

		TF_MoveCheckInfo.start = plpos
		TF_MoveCheckInfo.endpos = plpos+X
		tr = util_TraceHull(TF_MoveCheckInfo)

		if not tr.Hit then
			return
		end
		PrenotifyHitEnt(pl,tr.Entity)

		local Y = X:Cross(Vector(0,0,1)):GetNormalized()
		local Z = X:Cross(Y)

		-- Give 12 iterations to find a random route around this obstacle.
		for Pass=1, 2 do
			for i=1, 6 do
				local SMove = plpos+(Y*math.Rand(-1,1) + Z*math.Rand(-1,1)):GetNormalized()*math.Rand(32,76) + X*math.Rand(-32,-8)
				TF_MoveCheckInfo.start = plpos
				TF_MoveCheckInfo.endpos = SMove
				tr = util_TraceHull(TF_MoveCheckInfo)
				if tr.Hit then
					PrenotifyHitEnt(pl,tr.Entity)
					continue
				end

				local tdir = (dest - SMove)
				TF_MoveCheckInfo.start = SMove
				TF_MoveCheckInfo.endpos = SMove+tdir:GetNormalized()*math.min(tdir:Length(),100)
				tr = util_TraceHull(TF_MoveCheckInfo)
				if tr.Hit then
					PrenotifyHitEnt(pl,tr.Entity)
					continue
				end
				StepAside(pl,SMove,cmd)
				break
			end
			if not BOT_ShouldCrouch[pl] then -- Try crouch for second pass.
				BOT_ShouldCrouch[pl] = true
				TF_MoveCheckInfo.mins = cr_bottom
				TF_MoveCheckInfo.maxs = cr_top
			end
		end

		if BOT_SpecialGoal and not BOT_SideStepTime[pl] then -- Break their way through then...
			HandleBumpedProp(pl,BOT_SpecialGoal)
		end
		return
	end

	local bMoveDown = (dir:GetNormalized().z<-0.7) -- We want to move down, then lets break possible props blocking us from moving to it.

	dir.z = 0 -- Don't attempt to move along Z axis if walking.
	local Floor = Vector(0,0,1)
	local StepSize = pl:GetStepSize()

	-- Check floor orientation.
	TF_MoveCheckInfo.start = plpos
	TF_MoveCheckInfo.endpos = plpos-Vector(0,0,10)
	tr = util_TraceHull(TF_MoveCheckInfo)
	if tr.Hit then
		Floor = tr.HitNormal
		if bMoveDown then
			PrenotifyHitEnt(pl,tr.Entity)
		end
	end

	local bStepOver = false -- Pending to step over a step.
	local bMoveBlocked = false
	local bNowCrouching = BOT_ShouldCrouch[pl]
	local bWantedCrouch = false

	-- Do 5 iterations to see move into the future.
	for i=1, 5 do
		-- Update move
		if i>1 then
			dir = (dest - plpos)
			dir.z = 0
		end
		local dist = dir:Length2D()
		if dist<=20 then bMoveBlocked = false break end -- Reached goal already.

		local RX = dir:GetNormalized()
		if Floor.z~=1 then
			dir = dir - dir:Dot(Floor) * Floor
		end
		local X = dir:GetNormalized()
		local MX = X*20
		local SMove = plpos+MX

		TF_MoveCheckInfo.start = plpos
		TF_MoveCheckInfo.endpos = SMove

		tr = util_TraceHull(TF_MoveCheckInfo)
		if not tr.Hit then
			-- Check for floor.
			TF_MoveCheckInfo.start = SMove
			TF_MoveCheckInfo.endpos = SMove-Vector(0,0,30 + StepSize)
			tr = util_TraceHull(TF_MoveCheckInfo)

			if not tr.Hit or tr.HitNormal.z<AI_WalkableZ then -- About to fall, then jump...
				BOT_PendingJump[pl] = true
				bMoveBlocked = false
				break
			end

			plpos = tr.HitPos+Vector(0,0,0.15)
			Floor = tr.HitNormal
			bStepOver = false
			bMoveBlocked = false
			continue
		end

		PrenotifyHitEnt(pl,tr.Entity)
		if tr.HitNormal.z>AI_WalkableZ then -- Hit walkable surface.
			Floor = tr.HitNormal
			plpos = tr.HitPos
			local DesPos = tr.HitPos+Vector(0,0,1)

			TF_MoveCheckInfo.start = tr.HitPos
			TF_MoveCheckInfo.endpos = DesPos
			tr = util_TraceHull(TF_MoveCheckInfo)
			if not tr.Hit then
				plpos = DesPos
			else
				PrenotifyHitEnt(pl,tr.Entity) -- Hit our noggin on something!
			end
			bStepOver = false
			bMoveBlocked = false
			continue
		end

		-- Hit wall, first check if it is a simple step over.
		PrenotifyHitEnt(pl,tr.Entity)
		local HN = tr.HitNormal

		if tr.HitNormal.z>=0 then
			local tpos = tr.HitPos
			TF_MoveCheckInfo.start = tpos
			TF_MoveCheckInfo.endpos = tpos+Vector(0,0,StepSize)
			tr = util_TraceHull(TF_MoveCheckInfo)

			if tr.Hit then -- Can't even step up, we must be hitting our noggin.
				PrenotifyHitEnt(pl,tr.Entity)

				-- Try enter crouch mode if we aren't.
				if not bNowCrouching then
					BOT_ShouldCrouch[pl] = true
					TF_MoveCheckInfo.mins = cr_bottom
					TF_MoveCheckInfo.maxs = cr_top
					bNowCrouching = true
					bWantedCrouch = true
					continue
				end
			elseif not bStepOver then
				bStepOver = true
				plpos = tpos+Vector(0,0,StepSize)
				continue
			end

			if tr.Fraction<0.9 then
				plpos = tpos+Vector(0,0,0.15)
			else
				plpos = tpos
			end

			-- Eh, try to crouch-jump over obstacle?
			TF_MoveCheckInfo.mins = cr_bottom
			TF_MoveCheckInfo.maxs = cr_top

			-- Try with different height levels...
			local JumpOK = false
			for z=30,60,20 do
				local theight = plpos+Vector(0,0,z)
				TF_MoveCheckInfo.start = plpos
				TF_MoveCheckInfo.endpos = theight
				tr = util_TraceHull(TF_MoveCheckInfo)
				if tr.Hit then -- Hit our head, failure!
					PrenotifyHitEnt(pl,tr.Entity)
					break
				end

				local tforward = theight+RX*20
				TF_MoveCheckInfo.start = theight
				TF_MoveCheckInfo.endpos = tforward
				tr = util_TraceHull(TF_MoveCheckInfo)
				if not tr.Hit then -- Didnt hit anything, make sure not just landing forward on a slope to slide back down...
					TF_MoveCheckInfo.start = tforward
					TF_MoveCheckInfo.endpos = tforward-Vector(0,0,z)
					tr = util_TraceHull(TF_MoveCheckInfo)

					if not tr.Hit then continue end -- Shouldnt be possible?

					if tr.HitNormal.z>AI_WalkableZ then -- Landed on a walkable surface, jump OK.
						plpos = tr.HitPos
						JumpOK = true
						break
					end
				elseif tr.HitNormal.z>AI_WalkableZ then -- Hit walkable surface, jump OK.
					plpos = tr.HitPos
					JumpOK = true
					break
				elseif math.abs(tr.HitNormal.z)<0.05 then
					-- Check if just hit a very tiny step
					TF_MoveCheckInfo.start = tr.HitPos-RX
					TF_MoveCheckInfo.endpos = TF_MoveCheckInfo.start-Vector(0,0,z)
					tr = util_TraceHull(TF_MoveCheckInfo)

					if not tr.Hit then continue end -- Shouldnt be possible?

					if tr.HitNormal.z>AI_WalkableZ and tr.HitPos.z>(plpos.z+(z*0.5)) then -- Advanced high enough, accept this jump.
						plpos = tr.HitPos
						JumpOK = true
						break
					end
				end

				-- Hit wall, keep trying...
				PrenotifyHitEnt(pl,tr.Entity)
			end

			if JumpOK then -- end of iteration.
				BOT_PendingJump[pl] = true
				bStepOver = false
				bNowCrouching = true
				continue
			end

			if not bNowCrouching then -- Couldn't crouch-jump, reset back to walking size.
				TF_MoveCheckInfo.mins = bottom
				TF_MoveCheckInfo.maxs = top
			end
		end

		-- Try to walk around this obstacle.
		local Y = X:Cross(Vector(0,0,1)):GetNormalized()

		-- Give 8 iterations to find a random route around this obstacle.
		for i=1, 8 do
			local SideMove = math.Rand(12,82)
			if bit.band(i,1)==0 then
				SideMove = -SideMove
			end
			SideMove = plpos + Y*SideMove + X*math.Rand(-12,-8)
			TF_MoveCheckInfo.start = plpos
			TF_MoveCheckInfo.endpos = SideMove
			tr = util_TraceHull(TF_MoveCheckInfo)
			if tr.Hit then
				PrenotifyHitEnt(pl,tr.Entity)
				continue
			end

			local TX = (dest-SideMove)
			if Floor.z~=1 then
				TX = TX - TX:Dot(Floor) * Floor + Floor*0.15
			end

			TF_MoveCheckInfo.start = SideMove
			TF_MoveCheckInfo.endpos = SideMove+TX:GetNormalized()*100
			tr = util_TraceHull(TF_MoveCheckInfo)
			if tr.Hit then
				PrenotifyHitEnt(pl,tr.Entity)
				continue
			end
			StepAside(pl,SideMove,cmd)
			bMoveBlocked = false
			break
		end
		bStepOver = false
		bMoveBlocked = true

		if not bNowCrouching then -- Try enter crouch mode if we aren't.
			BOT_ShouldCrouch[pl] = true
			bNowCrouching = true
			bWantedCrouch = true
			TF_MoveCheckInfo.mins = cr_bottom
			TF_MoveCheckInfo.maxs = cr_top
			if i==5 then -- Just wait for when we get closer before we atk.
				bMoveBlocked = false
			end
			continue
		end

		-- Check what if we move along the wall...
		local ndir = TwoWallAdjust(MX,HN,Floor)
		TF_MoveCheckInfo.start = plpos
		TF_MoveCheckInfo.endpos = plpos+ndir

		tr = util_TraceHull(TF_MoveCheckInfo)
		if tr.Hit then
			PrenotifyHitEnt(pl,tr.Entity)
			plpos = tr.HitPos
		else
			plpos = plpos+ndir
		end
	end

	if (bMoveBlocked or bMoveDown) and BOT_SpecialGoal then -- Break their way through then...
		HandleBumpedProp(pl,BOT_SpecialGoal)
	elseif bWantedCrouch then
		pl.BOT_RemainCrouch = 4
	end
end

local REACHTYPE_Fly = ZSBOTAI.PATH_ReachFlags.Fly

-- Easy access function to reachable.
function meta:PointReachable( dest, meleeRange, bNoJump )
	local bottom, top
	if self:Crouching() then
		bottom, top = self:GetHullDuck()
	else
		bottom, top = self:GetHull()
	end

	local bAnyDir = (bit.band(self.BOT_MoveFlags or 0,REACHTYPE_Fly)~=0)
	if not bAnyDir and self:WaterLevel()>=2 and isentity(dest) and dest:WaterLevel()>=2 then -- Swimming towards entity in water.
		bAnyDir = true
	end

	return bAnyDir and ZSBOTAI.DirectReachable( dest, E_GetPos(self), bottom, top, meleeRange ) or ZSBOTAI.PointReachable( dest, E_GetPos(self), bottom, top, meleeRange, bNoJump )
end
