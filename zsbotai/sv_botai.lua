-- Bot AI, written by Marco
local pmeta = FindMetaTable("Player")
local GetPlayerTeam = pmeta.Team

ZSBOTAI = {
	AITable={MoveDestination={},MoveStuckTime={},PropAttackCount={},ShouldCrouch={},AttackProp={},Enemy={},LeapPathTimer={},Sight={},SideStepTime={},HumanCompanion={},GoToShop={},PendingHeal={},
		MoveTimer={},JumpCrouch={},BarricadeGhostTime={},SpecialPause={},PendingUse={},PendingJump={},MoveDirection={},LadderPath={},OldMDist={},NextDoorOpenTime={},MoveStuckPos={},LastLadderSpot={}},
	Bots={},
	DesiredRotation=Angle(),
}

include("sh_botai.lua")

include("sv_obj_file.lua")
include("sv_entfilters.lua")
include("sv_botplayer.lua")
include("sv_botreach.lua")
include("sv_botnavigation.lua")
include("sv_botprofiler.lua")
include("sv_botchat.lua")
include("sv_botcade.lua")
include("sv_botladder.lua")

local Bots = ZSBOTAI.Bots
local Bot_Names = {
	-- Unreal bot names
	"Dante","Ash","Rhiannon","Kurgan","Sonja","Bane","Dominator","Drace","Dregor","Ivan","Dimitra","Eradicator","Gina","Arcturus","Kristoph","Vindicator","Krige","Apocalypse",
	"Nikita","Cholerae","Katryn","Terminator","Shiva","Avatar","Raquel","The Reaper","Sonya",
	-- UT bot names
	"Loque","Xan","Alarik","Dessloch","Cryss","Drimacus","Rhea","Raynor","Kira","Karag","Zenith","Cali","Alys","Kosak","Illana","Barak","Kara","Tamerlane","Arachne",
	"Liche","Jared","Ichthys","Tamara","Archon","Athena","Cilia","Sarena","Malakai","Visse","Necroth","Kragoth",
	-- UT2004 bot names
	"Mekkor","Skrilax","Barktooth","Thannis","Malcolm","Brock","Lauren","Diva","Scarab","Asp","Roc","Memphis","Horus","Cleopatra","Hyena","Gorge","Rylisa",
	"Cannonball","Ambrosia","Frostbite","Reinha","Arclite","Siren","Prism","Wraith","Sapphire","Romulus","BlackJack","Torch","Satin","Remus","Damarus","Mokara","Motig",
	"Katana","Seeker","Vector","Sphinx","Natron","Nafiret","Tranquility","Sayiid","Jackyl","Anat","Luxor","Avalanche","Sorrow","Perdition","Jezebel","Lockdown","Molotov",
	"Bulldog","Vengeance","Stargazer","Phantom","Nova","Kain","Faith","Gaul","Silhouette","Tiberius","Mortis","Circe","Septis","Darkling","Samedi","Jigsaw","Avarice","Succubus",
	"Isis","Sunspear","Lexa","Ramses","Hathor","Khepry","Nephthys","Seth","Huntress","Xantares","Cinder","Rust","Mystique","Gryphon","Charisma","Janus","Odin","Hydra","Jackhammer",
	"Matriarch","Obsidian","Medusa","Earthquake","Chaos","Maat","Sekhmet","Bastet","Tefenet","Imhotep","Nekhbet","Osiris","Rampage","Misery","Brutus","Fury","Outrage",
	"Titania","Bullseye","Clangor","Despair","Cipher","Perish","Xargon","Ariel","Dragon","Nemesis","Drekorig","Skakruk","Guardian","ClanLord","Kraagesh","Gaargod","Gkublok",
	"Virus","Enigma","Cyclops","Cathode","Axon","Divisor","Matrix","Jakob","Aryss","Tamika","Othello","Azure","Annika","Riker","Garrett","Baird","Greith","Zarina",
	"Ophelia","Kaela","Rae","Kane","Outlaw","Abaddon",
	-- Other:
	"AREPA Bot","Marco Bot","Brain Damage","pho",
}
ZSBOTAI.BotNameList = Bot_Names

local HardCodedSkills = {
	["Brain Damage"]=0,
	["Marco Bot"]=1,
	["pho"]=1,
}
local UsedBotNames = {}

GM.BotsDisabled = CreateConVar("zs_disablebots", "0", FCVAR_ARCHIVE, "Disable those annoying tryhards"):GetBool()
cvars.AddChangeCallback( "zs_disablebots", function( cmd, old, new )
	local state = tonumber(new) == 1
	GAMEMODE.BotsDisabled = state
	if state then
		for _,v in pairs(player.GetBots()) do v:Kick() end
	else
		GAMEMODE.IsBotSpawned = false
		GAMEMODE:AddBots()
	end
end )

-- Shortcuts.
local REACHTYPE_Walk = ZSBOTAI.PATH_ReachFlags.Walk
local REACHTYPE_Fly = ZSBOTAI.PATH_ReachFlags.Fly
local REACHTYPE_Swim = ZSBOTAI.PATH_ReachFlags.Swim
local REACHTYPE_Headcrab = ZSBOTAI.PATH_ReachFlags.Headcrab
local REACHTYPE_Leap = ZSBOTAI.PATH_ReachFlags.Leap
local REACHTYPE_Climb = ZSBOTAI.PATH_ReachFlags.Climb
local REACHTYPE_Door = ZSBOTAI.PATH_ReachFlags.Door
local REACHTYPE_Teleport = ZSBOTAI.PATH_ReachFlags.Teleport
local REACHTYPE_Zombies = ZSBOTAI.PATH_ReachFlags.Zombies
local REACHTYPE_Humans = ZSBOTAI.PATH_ReachFlags.Humans
local REACHTYPE_NoStrafeTo = ZSBOTAI.PATH_ReachFlags.NoStrafeTo

local BOT_MoveDestination = ZSBOTAI.AITable.MoveDestination
local BOT_DesiredRotation = ZSBOTAI.DesiredRotation
local BOT_PropAttackCount = ZSBOTAI.AITable.PropAttackCount
local BOT_ShouldCrouch = ZSBOTAI.AITable.ShouldCrouch
local BOT_AttackProp = ZSBOTAI.AITable.AttackProp
local BOT_Enemy = ZSBOTAI.AITable.Enemy
local BOT_LeapPathTimer = ZSBOTAI.AITable.LeapPathTimer
local BOT_Sight = ZSBOTAI.AITable.Sight
local BOT_SideStepTime = ZSBOTAI.AITable.SideStepTime
local BOT_HumanCompanion = ZSBOTAI.AITable.HumanCompanion
local BOT_GoToShop = ZSBOTAI.AITable.GoToShop
local BOT_MoveTimer = ZSBOTAI.AITable.MoveTimer
local BOT_JumpCrouch = ZSBOTAI.AITable.JumpCrouch
local BOT_BarricadeGhostTime = ZSBOTAI.AITable.BarricadeGhostTime
local BOT_SpecialPause = ZSBOTAI.AITable.SpecialPause
local BOT_PendingUse = ZSBOTAI.AITable.PendingUse
local BOT_PendingJump = ZSBOTAI.AITable.PendingJump
local BOT_MoveDirection = ZSBOTAI.AITable.MoveDirection
local BOT_LadderPath = ZSBOTAI.AITable.LadderPath
local BOT_OldMDist = ZSBOTAI.AITable.OldMDist
local BOT_NextDoorOpenTime = ZSBOTAI.AITable.NextDoorOpenTime
local BOT_PendingHeal = ZSBOTAI.AITable.PendingHeal

local E_GetPos = FindMetaTable("Entity").GetPos
local math = math

function GM:AddBot( forcename, skill )
	if self.BotsDisabled or hook.Call("ShouldAddBot") == false or player.GetCount() <= 0 then return end

	local n = 0

	if forcename then
		n = nil
	else
		local numnames = #Bot_Names

		-- Count number of unused bot names
		for i=1, numnames do
			if not UsedBotNames[i] then
				n = n+1
			end
		end

		if n==0 then -- No available names, pick random name.
			n = math.random(numnames)
		else
			n = math.random(n)
			for i=1, numnames do
				if not UsedBotNames[i] then
					n = n-1
					if n<=0 then
						n = i
						break
					end
				end
			end
		end
		UsedBotNames[n] = (UsedBotNames[n] or 0) + 1
		forcename = Bot_Names[n]
	end

	self.bForceZombieSpawn = true
	self._NewBotName = forcename
	local bot = player.CreateNextBot(forcename)
	self.bForceZombieSpawn = nil
	self._NewBotName = nil
	if IsValid(bot) then
		if n then
			bot.BOT_NameIndex = n
		end
		bot.BOT_Skill = math.Clamp(skill or bot.BOT_Skill,0,2)
		local sk = HardCodedSkills[forcename]
		if sk then -- SuperBot
			bot.BOT_Skill = sk
		end
		if bot:Alive() then
			ZSBOTAI.BotPostSpawn(bot)
		end
		return bot
	end
end

concommand.Add("zs_addbot", function(sender, command, arguments)
	if GAMEMODE:PlayerIsAdmin(sender) then
		local bot = GAMEMODE:AddBot(arguments[1],arguments[2] and tonumber(arguments[2]) or nil)
		if bot then
			DEBUG_MessageDev(sender:Nick().." added named bot: "..bot:Name().." (skill "..tostring(math.Round(bot.BOT_Skill,2))..")",false,0,true)
		end
	end
end)

function GM:RemoveBot()
	local bot = nil

	for i, b in ipairs(Bots) do
		if IsValid(b) and b:Health()<=0 then
			bot = b
			break
		end
	end

	if not bot then
		for i, b in ipairs(Bots) do
			if IsValid(b) then
				bot = b
				break
			end
		end
	end

	if bot then
		bot:Kick("Removebot")
	end
end

local COMBAT_ShouldFireWeapons = true
local COMBAT_ShouldMove = true

function ZSBOTAI.SetBotCombatStyle( Flags, bEnable )
	if Flags == 0 then
		COMBAT_ShouldFireWeapons = bEnable
	elseif Flags == 1 then
		COMBAT_ShouldMove = bEnable
	end
end

local bHasInit = false

local RandomFollowLines = {
	", I've got your back!",
	", I'm following you!",
	", I'm coming with you!",
	", I follow you!",
}

-- Handle bot joining and disconnecting
hook.Add("WaveStateChanged","Bot.WaveStateChanged",function(newstate)
	if not newstate and not GAMEMODE.ZombieEscape then
		ZSBOTAI.CheckActiveCades()
	end
end)

-- Player died or disconnected, we can't target them anymore!
local function OnPlayerRemove( ply )
	for i = 1, #Bots do
		local b = Bots[i]
		if BOT_Enemy[b] == ply then
			BOT_Enemy[b] = nil
			BOT_Sight[b] = CurTime() + math.random() * 0.05
		end
		if b.BOT_AquirePos == ply then
			b.BOT_AquirePos = nil
		end
		if BOT_MoveDestination[b] == ply then
			BOT_MoveTimer[b] = 0
		end
		if BOT_HumanCompanion[b] == ply then
			ply.NumBotCompanions = ply.NumBotCompanions-1
			if ply.NumBotCompanions <= 0 then
				ply.NumBotCompanions = nil
			end
			BOT_HumanCompanion[b] = nil
		end
	end
end

-- Hooks needed for bots.
hook.Add("PlayerInitialSpawn","Bot.PlayerInitialSpawn",function(ply)
	if ply:IsBot() then
		Bots[#Bots+1] = ply
		ZSBOTAI.MakeBot(ply,true)
		ZSBOTAI.InitBot(ply)
	end
end)

hook.Add("PlayerDisconnected","Bot.PlayerDisconnected",function(ply)
	if ply:UseBotAI() then
		ZSBOTAI.MakeBot(ply,false)
	end
	if ply:IsBot() then
		table.RemoveByValue(Bots,ply)
	else
		ZSBOTAI.EndNetworkPathList(ply)
	end
	OnPlayerRemove(ply)
end)

hook.Add( "OnPlayerChangedTeam", "bots.OnPlayerChangedTeam",function(pl, oldteam, newteam)
	OnPlayerRemove(pl)
end)

hook.Add( "WeaponEquip", "bots.WeaponEquip", function( wep, pl )
	if pl:UseBotAI() and wep.CanHealUser then
		pl.BOT_HasMedic = true
	end
end)

ZSBOTAI.ControlledPlayerCommands = {}

local Bot_ThinkMove
local function BotHandleMove( ply, cmd )
	if not GAMEMODE.BotsDisabled and ply:UseBotAI() then
		if cmd:GetButtons() > 1 then
			ZSBOTAI.ControlledPlayerCommands[ply] = cmd
		end

		Bot_ThinkMove(ply,cmd)
	end
end

function GM:ResetAI( pl, disconnect )
	local com = BOT_HumanCompanion[pl]
	if IsValid(com) then
		com.NumBotCompanions = com.NumBotCompanions-1
		if com.NumBotCompanions<=0 then
			com.NumBotCompanions = nil
		end
	end

	-- Reset bot AI
	for nm, tab in pairs(ZSBOTAI.AITable) do
		tab[pl] = nil
	end

	pl.BOT_HasMedic = nil

	if not disconnect then
		BOT_PropAttackCount[pl] = math.random(0,5)
		BOT_Sight[pl] = CurTime()+1

		-- Could be new bot player...
		for i, w in pairs(pl:GetWeapons()) do
			if w.CanHealUser then
				pl.BOT_HasMedic = true
				break
			end
		end
	end

	pl.BOT_AquirePos = nil
	pl.BOT_PendingShopTimer = nil
	pl.BOT_ShopTimer = nil
	pl.BOT_IsShadeEnemy = nil
	pl.BOT_RandomDestination = nil
	pl.BOT_ClimbWall = nil
	pl.BOT_TeleportTimer = nil
	pl.BOT_BlockedPaths = {}
	pl.BOT_NextCheckRouteTime = CurTime()+20
	pl.BOT_RouteCache = nil
	pl.BOT_HuntFails = nil
	pl.BOT_NextAckCounter = nil
	pl.BOT_LastSeenPos = nil
	pl.BOT_StrafeMode = nil
	pl.BOT_Barricader = nil
	pl.BOT_LastSeenTime = 0
	pl.BOT_BHopTimer = math.Rand(0,0.5)
	pl.BOT_BHopDir = (math.random(2)==1)
	if GetPlayerTeam(pl)==TEAM_HUMAN then
		pl.bAllowBunnyHop = (pl.BOT_Skill>math.Rand(0.9,1.05))
		pl.bShouldAimAtEnemy = nil
	end
end

local function BotHandleDeath( victim, inflictor, attacker )
	if IsValid(victim) then
		if victim:UseBotAI() then
			if GetPlayerTeam(victim)==TEAM_UNDEAD and not GAMEMODE.ZombieEscape then
				ZSBOTAI.select_class_new(victim)
			end

			hook.Run("ResetAI",victim)
		end

		-- Make sure no bots target this dead player anymore now.
		OnPlayerRemove(victim)
	end
end

local function BotHandleSpawn( pl )
	if pl:UseBotAI() then
		local classtab = GetPlayerTeam(pl)==TEAM_UNDEAD and pl:GetZombieClassTable() or false
		if classtab then
			pl.bFlyingZombie = classtab.CanFly
			pl.bLeaperZombie = classtab.CanLeap
			pl.bHeadcrabZombie = classtab.IsHeadcrab
			pl.bWallClimbZombie = classtab.CanWallClimb
			pl.bShouldAimAtEnemy = classtab.CanFly or classtab.CanWallClimb
			local skill = pl.BOT_Skill
			pl.bAllowBunnyHop = (classtab.NoFallSlowdown or skill>math.Rand(0.9,1.1)) and not classtab.CanFly and not classtab.CanLeap and not classtab.IsHeadcrab and not classtab.CanWallClimb and skill>math.Rand(0.8,1.2)
			pl.BOT_MoveFlags = bit.bor(REACHTYPE_Walk,REACHTYPE_Zombies,pl.bFlyingZombie and REACHTYPE_Fly or 0,(pl.bLeaperZombie or pl.bFlyingZombie) and REACHTYPE_Leap or 0,pl.bWallClimbZombie and REACHTYPE_Climb or 0,pl.bHeadcrabZombie and REACHTYPE_Headcrab or 0)

			pl.AIShouldStrafe = math.random(2) == 1
		else
			pl.bFlyingZombie = nil
			pl.bLeaperZombie = nil
			pl.bShouldAimAtEnemy = nil
			pl.bHeadcrabZombie = nil
			pl.bWallClimbZombie = nil
			pl.bAllowBunnyHop = nil
			pl.BOT_MoveFlags = bit.bor(REACHTYPE_Walk,REACHTYPE_Humans)
		end

		hook.Run("ResetAI",pl)
	end
end

local function CheckBotsAlive()
	if not GAMEMODE.RoundEnded then
		for i, b in ipairs(Bots) do
			if IsValid(b) and not b:Alive(true) then
				hook.Run("PlayerDeathThink", b)
			end
		end
	end
end

local function BotChatter()
	timer.Simple(math.Rand(5,75),BotChatter)
	if #Bots==0 then return end

	local b = Bots[math.random(#Bots)]
	if IsValid(b) then
		ZSBOTAI.MakeBotChat(b)
	end
end

function ZSBOTAI.BotPostSpawn( pl )
	if pl:IsBot() then
		pl._StatSpeedMod = 1.05
		pl.SleightOfHandRate = pl.BOT_Skill*0.5
		pl:ResetSpeed()
	end
end

-- Bot entering and leaving.
function ZSBOTAI.InitBot( pl )

	-- Make sure bots go by idle orders from start.
	if not bHasInit then
		bHasInit = true
		RunConsoleCommand("bot_zombie",1)
		hook.Add("StartCommand","Bot.ThinkMove",BotHandleMove)
		hook.Add("PlayerDeath","Bot.PlayerDeath",BotHandleDeath)
		hook.Add("PostPlayerSpawn","Bot.PostPlayerSpawn.HandleSpawn",BotHandleSpawn)
		hook.Add("PostPlayerSpawn","Bot.PostPlayerSpawn.PostSpawn",ZSBOTAI.BotPostSpawn)
		if GAMEMODE.IsObjectiveMap or GAMEMODE.ZombieEscape then
			hook.Add("ObjectiveAdvance","Bot.ObjectiveAdvance",Bot_AdvanceObjective)
		end
		timer.Create( "bot.CheckAlive", 0.5, 0, CheckBotsAlive )
		ZSBOTAI.InitNavigationNetwork()

		timer.Simple(math.Rand(15,35),BotChatter)
	end

	BOT_Sight[pl] = CurTime()+1
	BOT_PropAttackCount[pl] = math.random(0,5)
	pl.BOT_LoneWolf = math.random(5)==1
	pl.BOT_TrailDistance = math.Rand(50,120)
	pl.BOT_TrailDistance = pl.BOT_TrailDistance*pl.BOT_TrailDistance
	pl.BOT_BlockedPaths = {}
	pl.BOT_NextCheckRouteTime = CurTime()+20
	pl.BOT_Skill = pl.BOT_Skill or math.random()
	hook.Run("ResetAI",pl)

	if not GAMEMODE.ZombieEscape then
		ZSBOTAI.select_class_new(pl)
	end
end

function ZSBOTAI.ExitBot( pl )
	if pl.BOT_NameIndex then
		local n = pl.BOT_NameIndex
		-- Unregister name entry.
		if UsedBotNames[n] then
			if UsedBotNames[n]==1 then
				UsedBotNames[n] = nil
			else
				UsedBotNames[n] = UsedBotNames[n] - 1
			end
		end
		pl.BOT_NameIndex = nil
	end
	hook.Run("ResetAI",pl,true)
end

local function SwitchToBestWeapon( pl )
	if BOT_Enemy[pl] then
		pl.BOT_NextWeaponSwitchTime = CurTime() + math.Rand(0.5,1.25)
	else
		pl.BOT_NextWeaponSwitchTime = CurTime() + math.Rand(2,4)
	end

	local BestWeapon = nil
	local BestRate = nil

	-- Go through all weapons.
	for _, w in pairs(pl:GetWeapons()) do
		-- Calc rating.
		local f = w.CalcBotRate
		local Rate = f and f(w) or (w.AIRating or 0)

		-- Extra desire for current weapon.
		if w==pl:GetActiveWeapon() then
			Rate = Rate*1.5
		end

		if not BestWeapon or (BestRate<Rate) then
			BestWeapon = w
			BestRate = Rate
		end
	end

	if BestWeapon and BestWeapon~=pl:GetActiveWeapon() then
		pl:SelectWeapon(BestWeapon:GetClass())
	end
end

function ZSBOTAI.BotSelectBoss( pl )
	pl.BOT_BossIndex = GAMEMODE:GetRandomBoss()
end

local SightTraceInfo = {mask=MASK_SOLID_BRUSHONLY}
-- Return true if did not hit.
local function SightTrace( startPos, endPos )
	SightTraceInfo.start = startPos
	SightTraceInfo.endpos = endPos
	return not util.TraceLine(SightTraceInfo).Hit
end

local TRACE_Group,TRACE_Flags
local function BulletTraceFilter( ent )
	return GAMEMODE:TryCollides(ent, TRACE_Group, TRACE_Flags)
end

local tr_tbl = {}
function SV_TraceHit(posa, posb, mask, attacker, filter)
    tr_tbl.start = posa
    tr_tbl.endpos = posb
    tr_tbl.mask = mask
    tr_tbl.filter = filter

    return util.TraceLine(tr_tbl).Hit
end

function ShootTrace(pl, startPos, endPos)
	TRACE_Group, TRACE_Flags = GetHitScanFlags(pl)

	return SV_TraceHit(startPos, endPos, MASK_SOLID, pl, BulletTraceFilter)
end

local function ProcessPurchase( pl, ars )
	-- first look for best weapon that can be bought.
	local BestWep = nil
	local BestRate = nil
	local BestIdx = nil
	local spentpts = 0
	for i, tab in pairs(GAMEMODE.Items) do
		if tab.PointShop and (tab.Category==ITEMCAT_GUNS or tab.Category==ITEMCAT_MELEE) and (not tab.ObjectiveOnly or GAMEMODE.IsObjectiveMap) and (not tab.Stock or tab.Stock>0) and hook.Call("IsWeaponUnlocked", GAMEMODE, tab) then
			local rate = tab.Worth * math.Rand(0.75,1.5)
			if tab.Category==ITEMCAT_MELEE then -- Avoid melee...
				--rate = rate*0.45
				continue -- NEVER melee!
			end

			if pl:HasWeapon(tab.SWEP) then -- Prefer to buy ammo for already owned weapon.
				rate = rate*1.35
			end

			if not BestWep or BestRate<rate then
				BestWep = tab
				BestRate = rate
				BestIdx = i
			end
		elseif tab.Signature=="ps_jihad" and math.random(14)==1 and not pl:HasWeapon(tab.SWEP) then
			-- Buy jihad!
			pl:Give(tab.SWEP)
			spentpts = spentpts+tab.Worth
		end
	end

	if not BestWep then
		return
	end

	-- Check if already owned.
	local wep = nil
	if not pl:HasWeapon(BestWep.SWEP) then
		wep = pl:Give(BestWep.SWEP)
		wep.AIRating = (wep.AIRating or 1) + BestWep.Worth -- Add extra desire to use bought weapons.
		wep._BotBuy = true -- Strip this once un-AFK
		spentpts = spentpts+BestWep.Worth

		-- Reduce stock if there is.
		if BestWep.Stock then
			BestWep.Stock = BestWep.Stock - 1

			net.Start("zs_pointshopstocks")
				net.WriteUInt(BestIdx, GAMEMODE.ItemsNetworkSize)
				net.WriteUInt(BestWep.Stock, 7)
			net.Broadcast()
		end
	else
		wep = pl:GetWeapon(BestWep.SWEP)
	end

	-- Buy ammo
	if wep.Primary then
		local primary = wep:ValidPrimaryAmmo()
		if primary and pl:GetAmmoCount(primary)<100 then
			spentpts = spentpts+70
			pl:GiveAmmo(100,primary,true)
		end
	end

	if spentpts==0 then
		return
	end

	-- Take pts from self.
	pl:TakePoints(spentpts)

	-- Give commission for owner.
	local owner = ars:GetObjectOwner()
	if IsValid(owner) then
		local nonfloorcommission = spentpts * 0.025
		local commission = math.floor(nonfloorcommission)
		if commission > 0 then
			owner.PointsCommission = owner.PointsCommission + spentpts

			owner:AddPoints(commission, true)

			if not owner:IsBot() then
				net.Start("zs_commission", true)
					net.WriteEntity(ars)
					net.WriteEntity(pl)
					net.WriteUInt(commission, 8)
				net.Send(owner)
			end
		end
	end
end

local function GetRandomMove( pl, moveDist )
	-- Trace around to pick a random move.
	local bestDest = nil
	local bestDist = nil
	local org = pl:GetPlayerOrigin()
	local tri = {start=org, filter=player.GetAll()}
	for i=0, 8 do
		local v = VectorRand()
		v.z = v.z*0.2
		tri.start = org
		tri.endpos = org + (v * math.random() * moveDist)

		-- Trace out to see how far we can move.
		local tr = util.TraceLine(tri)
		if not tr.Hit then
			v = tri.endpos
		else
			v = tr.HitPos
		end

		tri.start = v
		tri.endpos = v - Vector(0,0,2000)

		-- See if it is a deep pit at this position.
		tr = util.TraceLine(tri)
		local dist
		if not tr.Hit then
			dist = 50000000
		else
			v = tr.HitPos
			dist = v:DistToSqr(org)

			if dist>250000 then
				return tr.HitPos
			end
		end

		if not bestDest or (bestDist<dist) then
			bestDest = v
			bestDist = dist
		end
	end
	return bestDest
end

-- Pick a random move.
local function PickRandomDest( pl )
	local path, idx = ZSBOTAI.FindRandomPath(pl,pl.BOT_RandomDestination)
	if path then
		pl.BOT_RandomDestination = idx>0 and idx or nil
		return path
	end
	pl.BOT_RandomDestination = nil

	return GetRandomMove(pl,1000)
end

-- Start a new move to a destination.
local function MoveTo( pl, Dest )
	local des = nil
	pl.BOT_BhopMove = nil
	BOT_OldMDist[pl] = nil

	if isvector(Dest) then
		if ZSBOTAI.StartLadderMove(pl,Dest) then
			return
		end
		des = Dest
	elseif IsValid(Dest) then
		des = E_GetPos(Dest)
	else
		ZSBOTAI.EndLadderMove(pl)
		BOT_MoveDestination[pl] = nil
		BOT_MoveTimer[pl] = nil
		ZSBOTAI.BotOrders(pl,1)
		return
	end

	ZSBOTAI.EndLadderMove(pl)

	BOT_MoveDestination[pl] = Dest
	local movedir = (des-E_GetPos(pl)):GetNormalized()
	BOT_MoveDirection[pl] = movedir
	local maxSpeed = pl:GetMaxSpeed()
	if pl:WaterLevel()>=2 then
		maxSpeed = maxSpeed*0.6
	end
	BOT_MoveTimer[pl] = CurTime() + (des:Distance(E_GetPos(pl)) / maxSpeed) + 0.75
	pl.BOT_UpDirection = (movedir.z>0)
	pl.BOT_FlatMove = (math.abs(movedir.z)<0.1)
	if pl.BOT_FlatMove then
		movedir.z = 0
	end

	ZSBOTAI.BotOrders(pl,1,Dest,BOT_MoveTimer[pl])
	local pmv = pl.BOT_PendingMoveFlags
	if pmv then
		pl:SetEyeAngles(movedir:Angle())
		if (pl.bLeaperZombie and bit.band(pmv,REACHTYPE_Leap)~=0) or (pl.bHeadcrabZombie and bit.band(pmv,REACHTYPE_Headcrab)~=0) then
			if pl.bLeaperZombie then -- Fast zombie path!
				BOT_MoveTimer[pl] = BOT_MoveTimer[pl]+4
				BOT_LeapPathTimer[pl] = BOT_MoveTimer[pl]

				local w = pl:GetActiveWeapon()
				if IsValid(w) and w.NextAllowPounce then
					w:SecondaryAttack()
				end
			else -- Headcrab path!
				BOT_MoveTimer[pl] = BOT_MoveTimer[pl]+1
				BOT_LeapPathTimer[pl] = BOT_MoveTimer[pl]

				local w = pl:GetActiveWeapon()
				if IsValid(w) and w.DoPounce then
					w:PrimaryAttack()
				end
			end
		elseif bit.band(pmv,REACHTYPE_Teleport)~=0 then -- TELEPORT HACK
			pl:SetPos(Dest)
			BOT_MoveTimer[pl] = CurTime() + 0.01
			pl:FindSpot()
		end
		if bit.band(pmv,REACHTYPE_NoStrafeTo)~=0 then -- No bhop path
			pl:SetAbsVelocity(Vector(0,0,0)) -- Stop sidetrack move momentum.
			pl.BOT_BhopMove = false
		end
		pl.BOT_PendingMoveFlags = nil
	else
		if BOT_LeapPathTimer[pl] then
			BOT_LeapPathTimer[pl] = nil
			pl.BOT_ClimbWall = nil
		end

		pl.BOT_BhopMove = (pl.BOT_Skill>math.Rand(0.8,1.2))
	end
end

local function AI_Orders_Zombie( pl )
	-- Obj teleportation.
	local enemy = BOT_Enemy[pl]
	if pl.BOT_TeleportTimer and (not IsValid(enemy) or E_GetPos(pl):DistToSqr(E_GetPos(enemy))>250000) then -- Square(500)
		if GetPlayerTeam(pl)~=TEAM_HUMAN then
			if pl.BOT_TeleportTimer<CurTime() then
				pl:Kill()
			else
				GAMEMODE:SendToNewSpawn(pl)
			end
		end
		pl.BOT_TeleportTimer = nil
	end

	if IsValid(enemy) and enemy:Alive() then
		local EnemyCatch = pl.ShouldQuitNode and 10000 < enemy:GetPos():DistToSqr(pl:GetPos())
		if not EnemyCatch and not BOT_LadderPath[pl] and pl:PointReachable(enemy,0,true) then
			MoveTo(pl,enemy)
			ZSBOTAI.BotOrders(pl,7)
			pl.BOT_HuntFails = nil
			pl.BOT_LastSeenPos = enemy:GetPlayerOrigin()
		else
			local path = ZSBOTAI.FindPathToward(pl, enemy, (pl.BOT_HuntFailCounter or 0) > 0)

			if path then
				MoveTo(pl,path)
				ZSBOTAI.BotOrders(pl,8)
				pl.BOT_HuntFails = nil
				pl.BOT_LastSeenPos = enemy:GetPlayerOrigin()
			elseif not BOT_LadderPath[pl] and pl:PointReachable(enemy) then
				MoveTo(pl,enemy)
				ZSBOTAI.BotOrders(pl,7)
				pl.BOT_HuntFails = nil
				pl.BOT_LastSeenPos = enemy:GetPlayerOrigin()
			else
				if pl.BOT_LastSeenPos then
					if pl:PointReachable(pl.BOT_LastSeenPos) then
						MoveTo(pl,pl.BOT_LastSeenPos)
						pl.BOT_LastSeenPos = nil
						ZSBOTAI.BotOrders(pl,13)
						return
					else
						path = ZSBOTAI.FindPathToward(pl, pl.BOT_LastSeenPos, (pl.BOT_HuntFailCounter or 0)>0)
						if path then
							MoveTo(pl,path)
							ZSBOTAI.BotOrders(pl,13)
							return
						end
						pl.BOT_LastSeenPos = nil
					end
				end
				ZSBOTAI.BotOrders(pl,9)
				MoveTo(pl,PickRandomDest(pl))

				if GetPlayerTeam(pl)==TEAM_UNDEAD then
					if not pl.BOT_HuntFails then
						pl.BOT_HuntFails = CurTime()+30
						pl.BOT_HuntFailCounter = 0
					elseif pl.BOT_HuntFails<CurTime() then
						pl.BOT_HuntFailCounter = pl.BOT_HuntFailCounter+1
						pl.BOT_HuntFails = CurTime()+15
						BOT_Enemy[pl] = nil
						enemy = nil
						ZSBOTAI.BotOrders(pl,12,nil)

						if pl.BOT_HuntFailCounter>=3 then
							pl:Kill()
						end
					end
				end
			end
		end
		return
	end

	-- Go to random enemy position!
	local e = pl.BOT_AquirePos
	if not e then
		e = ZSBOTAI.FindNextEnemy(pl)
		if e then
			pl.BOT_AquirePos = e
			pl.BOT_AquireNum = 12
		end
	end
	if e then
		ZSBOTAI.BotOrders(pl,3)
		local n = pl.BOT_AquireNum - 1
		pl.BOT_AquireNum = n
		if not IsValid(e) or not e:Alive() or GetPlayerTeam(e)~=TEAM_HUMAN or n<0 then
			e = ZSBOTAI.FindNextEnemy(pl)
			if e then
				pl.BOT_AquirePos = e
				pl.BOT_AquireNum = 12
				n = 15
			else
				pl.BOT_AquirePos = nil
			end
		end
		if e then
			if pl:PointReachable(e,0,true) then
				MoveTo(pl,e)
				pl.BOT_AquirePos = nil
				return
			else
				local path = ZSBOTAI.FindPathToward(pl, e, n>6)

				if path then
					MoveTo(pl,path)
					return
				elseif pl:PointReachable(e,20) then
					MoveTo(pl,e)
					pl.BOT_AquirePos = nil
					return
				elseif math.random(4)==2 then
					pl.BOT_AquirePos = nil
				end
			end
		end
	end

	ZSBOTAI.BotOrders(pl,6)
	MoveTo(pl,PickRandomDest(pl))
end

local function TrySelfHeal( pl )
	if not hook.Run("PlayerCanBeHealed", pl, true) then return false end

	for i, w in pairs(pl:GetWeapons()) do
		local f = w.CanHealUser
		if f and f(w,pl) then
			if pl.status_human_holding then -- Drop anything holding right now!
				pl.status_human_holding:Remove()
			end

			if pl:GetActiveWeapon()~=w then
				pl:SelectWeapon(w:GetClass())
			else
				w:HealFire(pl)
			end
			BOT_SpecialPause[pl] = CurTime()+0.25
			return true
		end
	end
end

local function TryHealOther( pl, bLowHealth )
	local plList = team.GetPlayers(TEAM_HUMAN)
	local bestHeal = false
	local bestHScore

	for i=1, #plList do
		local e = plList[i]
		if e~=pl and e:Alive() and not e:GetNoDraw() and e:Health()<(bLowHealth and 60 or e:GetMaxHealth()) then
			local score = E_GetPos(pl):Distance(E_GetPos(e))
			if score>600 then continue end

			score = 1000/score
			if e:Health()<45 then score = score*4 end

			if (not bestHeal or bestHScore<score) and pl:PointReachable(e,50) and hook.Run("PlayerCanBeHealed",e,false) then
				bestHeal = e
				bestHScore = score
			end
		end
	end

	if not bestHeal then return false end

	for i, w in pairs(pl:GetWeapons()) do
		local f = w.CanHealUser
		if f and f(w,bestHeal) then
			if pl.status_human_holding then -- Drop anything holding right now!
				pl.status_human_holding:Remove()
			end

			local mode = f(w,bestHeal,true)
			if mode==1 and E_GetPos(pl):Distance(E_GetPos(bestHeal))>72 then -- Must move close to target!
				if pl:GetActiveWeapon()~=w then
					pl:SelectWeapon(w:GetClass())
				end

				MoveTo(pl,bestHeal)
				if bestHeal:UseBotAI() then
					MoveTo(bestHeal,pl)
				end
				return true
			end

			if pl:GetActiveWeapon()~=w then
				pl:SelectWeapon(w:GetClass())
			else
				w:HealFire(bestHeal)
			end
			BOT_SpecialPause[pl] = CurTime()+0.25
			return true
		end
	end
end

local function AI_Orders_Human( pl )
	local enemy = BOT_Enemy[pl]
	if enemy and (not enemy:IsValid() or not enemy:Alive()) then
		BOT_Enemy[pl] = nil
		enemy = nil
	end

	-- Check heal
	if pl.BOT_HasMedic and (pl.BOT_NextMedicTime or 0)<CurTime() then
		if enemy then
			if TryHealOther(pl,true) then
				BOT_PendingHeal[pl] = true
				return
			end

			if pl:Health()<50 and TrySelfHeal(pl) then
				BOT_PendingHeal[pl] = true
				return
			end
		else
			if TryHealOther(pl) then
				BOT_PendingHeal[pl] = true
				return
			end

			if pl:Health()<pl:GetMaxHealth() and TrySelfHeal(pl) then
				BOT_PendingHeal[pl] = true
				return
			end
		end

		pl.BOT_NextMedicTime = CurTime()+5
	end

	local bCadingMode = pl.BOT_Barricader

	-- Go to arsenal crate for shopping.
	if (pl.BOT_NextShopTime or 0)<CurTime() then
		pl.BOT_NextShopTime = CurTime() + math.Rand(3,8)

		if GAMEMODE:GetWave()>0 and not pl:GetUnlucky() then
			local BestArs = nil
			local BestDist = nil
			local plpos = E_GetPos(pl)+Vector(0,0,32)

			for i, ars in ipairs( ents.FindByClass("prop_arsenalcrate") ) do
				local arspos = E_GetPos(ars)+Vector(0,0,5)
				local dist = arspos:DistToSqr(plpos)
				if dist<4000000 and (not BestArs or BestDist>dist) then -- Square(2000)
					BestArs = ars
					BestDist = dist
				end
			end

			if BestArs then
				pl.BOT_PendingShopTimer = nil
				BOT_GoToShop[pl] = BestArs
				pl.BOT_ShopTimer = CurTime() + 60
				pl.BOT_NextShopTime = CurTime() + 60 -- Longer pause if about to use an arsenal right now.
				ZSBOTAI.BotOrders(pl,4,BestArs,pl.BOT_NextShopTime)
			end
		end
	end

	if IsValid(BOT_GoToShop[pl]) then
		if pl:GetUnlucky() then
			BOT_GoToShop[pl] = nil
		elseif pl.BOT_PendingShopTimer then -- About to buy now!
			if pl.BOT_PendingShopTimer<CurTime() then
				ProcessPurchase(pl,BOT_GoToShop[pl])
				pl.BOT_PendingShopTimer = nil
				pl.BOT_ShopTimer = nil
				BOT_GoToShop[pl] = nil
				pl.BOT_NextShopTime = CurTime() + math.Rand(35,120)
			else
				return
			end
		elseif E_GetPos(BOT_GoToShop[pl]):DistToSqr(E_GetPos(pl))<6400 then -- We've reached the ars
			pl.BOT_PendingShopTimer = CurTime()+math.Rand(0.5,1.25)
			pl.BOT_ShopTimer = pl.BOT_PendingShopTimer+10
			BOT_SpecialPause[pl] = pl.BOT_PendingShopTimer+0.2 -- Sleep here!
			BOT_GoToShop[pl]:Use(pl, pl, USE_ON, 0) -- Try to claim this crate if its unowned.
			return
		else
			local nextmove = false
			if pl:PointReachable(BOT_GoToShop[pl]) then
				nextmove = BOT_GoToShop[pl]
			else
				local path = ZSBOTAI.FindPathToward(pl, BOT_GoToShop[pl], false)

				if not path then
					pl.BOT_PendingShopTimer = nil
					BOT_GoToShop[pl] = nil
					pl.BOT_ShopTimer = nil
				else
					nextmove = path
				end
			end

			if nextmove then
				local dest = isentity(nextmove) and E_GetPos(nextmove) or nextmove

				-- Check if enemy is in our way to ars!
				if not enemy or ((E_GetPos(enemy):DistToSqr(dest)*0.8)>E_GetPos(pl):DistToSqr(dest)) then
					MoveTo(pl,dest)
					ZSBOTAI.BotOrders(pl,4,BOT_GoToShop[pl],pl.BOT_NextShopTime)
					return
				end
			end
		end
	end

	-- Fight enemy!
	if enemy then
		local combatdist = pl.BOT_AttackStyle or 160000 -- 400^2
		local dist = E_GetPos(enemy):DistToSqr(E_GetPos(pl))

		if dist<(combatdist*0.75) or pl:Health()<50 then -- Too close or too weak, back off!
			local path = ZSBOTAI.GetRetreatDest(pl,enemy)
			if path then
				MoveTo(pl,path)
				ZSBOTAI.BotOrders(pl,8)
				return
			end
			MoveTo(pl,PickRandomDest(pl))
			ZSBOTAI.BotOrders(pl,8)
			return
		elseif dist>(combatdist*1.75) then -- Too far, move closer!
			if pl:PointReachable(enemy,0,true) then
				MoveTo(pl,enemy)
				ZSBOTAI.BotOrders(pl,7)
				pl.BOT_HuntFails = nil
				return
			end

			local path = ZSBOTAI.FindPathToward(pl, enemy, (pl.BOT_HuntFails or 0)>0)
			if path then
				MoveTo(pl,path)
				ZSBOTAI.BotOrders(pl,8)
				return
			else
				pl.BOT_HuntFails = (pl.BOT_HuntFails or 0)+1
			end
		end

		-- At optimal distance, keep firing!
		if dist>40000 then -- 200^2
			BOT_ShouldCrouch[pl] = true -- Increase accuracy when firing far distance.
		end

		if math.random(3)==0 then
			-- Minor small move.
			MoveTo(pl,GetRandomMove(pl,250))
		else
			BOT_SpecialPause[pl] = CurTime()+math.Rand(0.25,0.5)
		end
	end

	if not bCadingMode and math.random(3)==1 and ZSBOTAI.ShouldBuildCade(pl) then -- Check if we should build cade now!
		pl.BOT_Barricader = true
		bCadingMode = true
	end
	if bCadingMode then
		local path = ZSBOTAI.PickCadeMove(pl)
		if path then
			if isnumber(path) then
				BOT_SpecialPause[pl] = CurTime()+path
			else
				MoveTo(pl,path)
			end
			return
		end
	end

	-- Follow companion if we have one!
	local com = BOT_HumanCompanion[pl]
	if com then
		if not IsValid(com) or GetPlayerTeam(com)~=TEAM_HUMAN then
			if IsValid(com) then
				com.NumBotCompanions = com.NumBotCompanions-1
				if com.NumBotCompanions<=0 then
					com.NumBotCompanions = nil
				end
			end
			BOT_HumanCompanion[pl] = nil
		elseif pl:PointReachable(com) then
			MoveTo(pl,com)
			ZSBOTAI.BotOrders(pl,5,com)
			return
		else
			local path = ZSBOTAI.FindPathToward(pl, com, false)
			if path then
				MoveTo(pl,path)
				ZSBOTAI.BotOrders(pl,5,com)
				return
			end
		end
	elseif not pl.BOT_LoneWolf and math.random(20)==1 and (GAMEMODE:GetWave()>0 or GAMEMODE:GetWaveActive()) then -- Pick a random companion.
		local plpos = E_GetPos(pl)
		local BestComp = nil
		local BestDist = nil

		for _, h in ipairs(team.GetPlayers(TEAM_HUMAN)) do
			if h~=pl and h:Alive() and not h:UseBotAI() and (h.NumBotCompanions or 0)<4 then
				local dist = plpos:Distance(E_GetPos(h)) * math.Rand(0.8,1.2) * (1 + (h.NumBotCompanions or 0)*0.5)

				if not BestComp or BestDist>dist then
					BestComp = h
					BestDist = dist
				end
			end
		end

		if BestComp then
			BOT_HumanCompanion[pl] = BestComp
			BestComp.NumBotCompanions = (BestComp.NumBotCompanions or 0)+1
			if pl:IsBot() then
				pl:Say(BestComp:Nick()..RandomFollowLines[math.random(#RandomFollowLines)])
			end
		end
	end

	-- Nothing else to do so random move!
	ZSBOTAI.BotOrders(pl,6)
	MoveTo(pl,PickRandomDest(pl))
end

local function ChoseNextOrders( pl )
	if not COMBAT_ShouldMove then
		return
	end

	if BOT_PendingHeal[pl] then
		BOT_PendingHeal[pl] = nil
		pl.BOT_NextWeaponSwitchTime = nil
	end

	if GetPlayerTeam(pl)==TEAM_HUMAN then
		AI_Orders_Human(pl)
	else
		AI_Orders_Zombie(pl)
	end
end

-- Handle a finished move.
local function HandleFinishedMove( pl )
	BOT_MoveDestination[pl] = nil
	BOT_MoveTimer[pl] = nil
	BOT_ShouldCrouch[pl] = nil
	pl.BOT_RemainCrouch = nil
	ZSBOTAI.EndLadderMove(pl)
	ChoseNextOrders(pl)
end

-- Abort move toward without any further actions.
function ZSBOTAI.AbortMove( pl )
	BOT_MoveDestination[pl] = nil
	BOT_MoveTimer[pl] = nil
	BOT_ShouldCrouch[pl] = nil
	pl.BOT_SideStepMove = nil
	BOT_SideStepTime[pl] = nil
	pl.BOT_RemainCrouch = nil
	ZSBOTAI.EndLadderMove(pl)
end

local BotColFlags = 0
local function FilterBotMove( ent )
	return not ent:IsPlayer() and ent:ShouldBlockPlayer() and not (ent:GetCustomCollisionGroup()>0 and bit.band(ent:GetCustomCollisionGroup(),BotColFlags)==0)
end

-- Process a move towards destination.
local function ProcessMoveToward( pl, cmd )
	local des = nil
	local md = BOT_MoveDestination[pl]

	if isvector(md) then
		des = md
		if BOT_LadderPath[pl] then -- Ladder move!
			return
		end
	elseif IsValid(md) then
		des = E_GetPos(md)

		if md:IsPlayer() then
			local diff = des-E_GetPos(pl)
			local pbottom, ptop = pl:GetHull()
			local dbottom, dtop = md:GetHull()
			local xs,ys = math.abs(ptop.x+dtop.x),math.abs(ptop.y+dtop.y)

			if not pl.BOT_StrafeMode then
				pl.BOT_StrafeMode = math.random(1,2)
			end

			if math.abs(diff.x)<xs and math.abs(diff.y)<ys then
				-- Standing ontop or under the entity, move back.
				local ang = diff:Angle()
				cmd:SetViewAngles(ang)
				BOT_DesiredRotation:Set(ang)

				cmd:SetSideMove(1000)
				cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_BACK))

				if pl.BOT_StrafeMode==1 then
					cmd:SetSideMove(1000)
					cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_MOVELEFT))
				else
					cmd:SetSideMove(-1000)
					cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_MOVERIGHT))
				end
				return
			elseif BOT_PendingHeal[pl] and math.abs(diff.x)<(xs+20) and math.abs(diff.y)<(ys+20) then -- Close enough to heal!
				HandleFinishedMove(pl)
				return
			elseif math.abs(diff.x)<(xs+20) and math.abs(diff.y)<(ys+20) and pl.BOT_Skill>0.55 then
				-- Near target, strafe around
				if pl.BOT_StrafeMode==1 then
					cmd:SetSideMove(1000)
					cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_MOVELEFT))
				else
					cmd:SetSideMove(-1000)
					cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_MOVERIGHT))
				end
				return
			end

			-- If flying or swimming, go to nearest part of the body.
			if pl.bFlyingZombie or pl:WaterLevel()>=2 then
				des = md:NearestPoint(E_GetPos(pl))
			end
		end
	else
		HandleFinishedMove(pl)
		return
	end

	if BOT_NextDoorOpenTime[pl] then
		if BOT_NextDoorOpenTime[pl]>CurTime() then
			return
		end
		BOT_NextDoorOpenTime[pl] = nil
	end

	-- Finish move if we teleported (or destination did)
	local ndist = des:DistToSqr(E_GetPos(pl))
	local odist = BOT_OldMDist[pl]
	if odist and math.abs(ndist-odist)>90000 then -- 300^2
		HandleFinishedMove(pl)
		return
	end
	BOT_OldMDist[pl] = ndist

	-- Finish move when either we pass destination origin or run out of movement time.
	local mdir = (des - E_GetPos(pl))
	if pl.BOT_FlatMove then
		mdir.z = 0
	end
	if BOT_MoveTimer[pl]<CurTime() or mdir:Dot(BOT_MoveDirection[pl])<=0 then
		HandleFinishedMove(pl)
		return
	end

	ZSBOTAI.POLL_MoveTowards(pl,des,cmd)
end

local strafe_shift, strafe_result = {}, {}
local function FireWeaponAt( pl, targ, cmd )
	-- Chose attack mode.
	local w = pl:GetActiveWeapon()
	local optdist = 10
	if IsValid(w) then
		optdist = w.AICombatRange or 10
		local Mode = 0
		if w.BotAttackMode then
			Mode = w:BotAttackMode(targ)
		end

		if COMBAT_ShouldFireWeapons then
			local plt = targ:IsPlayer()
			if not plt or not pl.BOT_IsShadeEnemy then
				if not plt and GetPlayerTeam(pl)==TEAM_HUMAN then -- HACK, make bots faster at breaking doors.
					targ:TakeDamage(50,pl,pl)
				end
				if pl.status_human_holding then -- Drop anything holding right now!
					pl.status_human_holding:Remove()
				end

				local time = CurTime()
				if pl.AIShouldStrafe then
					if time > (strafe_shift[pl] or 0) then
						strafe_shift[pl] = time + 0.1
						strafe_result[pl] = math.random(7)
					end

					local res = strafe_result[pl] or 0
					if res >= 1 and res <= 2 then
						cmd:SetSideMove(res == 1 and -1000 or 1000)
						cmd:SetButtons(bit.bor(cmd:GetButtons(), res == 1 and IN_MOVELEFT or IN_MOVERIGHT))
					end
				end

				if Mode==0 then
					cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_ATTACK))
					if w:GetNextPrimaryFire()<=CurTime() and w.PrimaryAttack then
						w:PrimaryAttack()
					end
				elseif Mode==1 then
					cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_ATTACK2))
					if w:GetNextSecondaryFire()<=CurTime() and w.SecondaryAttack then
						w:SecondaryAttack()
					end
				elseif Mode==2 then
					cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_RELOAD))
					if w:GetNextPrimaryFire()<=CurTime() and w:GetNextSecondaryFire()<=CurTime() and w.Reload then
						w:Reload()
					end
				end
			elseif not pl:FlashlightIsOn() then
				pl:ToggleFlashlight()
				optdist = 130
			end
		end
	else
		optdist = 600
	end
	pl.BOT_AttackStyle = optdist^2
end

local function HandleBHopping( pl, cmd )
	local mindist = 0
	local md = BOT_MoveDestination[pl]
	if isvector(md) then
		des = md
	elseif IsValid(md) then
		des = E_GetPos(md)
		mindist = 2500 -- 50^2
	end

	local src = E_GetPos(pl)
	local myvel = pl:GetVelocity()
	local movdir = (des-src)
	movdir.z = 0
	if src.z<(des.z-20) or src:DistToSqr(des)<mindist or myvel:Dot(movdir)<0 or myvel:Length2DSqr()<((pl:GetMaxSpeed()*0.7)^2) then return end

	cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_DUCK))
	local flg = pl:GetFlags()
	if bit.band(flg,FL_ONGROUND)~=0 and bit.band(flg,FL_INWATER)==0 then
		cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_JUMP))
		myvel.z = 0
		pl:SetVelocity(myvel*0.25)
	end

	local t = pl.BOT_BHopTimer
	t = t+FrameTime()
	if t>0.6 then
		t = 0
		pl.BOT_BHopTimer = 0
		pl.BOT_BHopDir = (not pl.BOT_BHopDir)
	else
		pl.BOT_BHopTimer = t
	end
	t = ((t/0.6)-0.5)*2

	local angy = movdir:Angle().yaw

	cmd:SetForwardMove(0)
	if pl.BOT_BHopDir then
		cmd:SetSideMove(1000)
		cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_MOVELEFT))
		angy = angy+20-(40*t)
	else
		cmd:SetSideMove(-1000)
		cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_MOVERIGHT))
		angy = angy-20+(40*t)
	end
	cmd:SetViewAngles(Angle(0,angy,0))
end

local function AttackEnemy( pl, enemy, cmd )
	-- Pick aiming position on enemy.
	local AimPos = E_GetPos(enemy)
	local bottom, top
	if enemy:Crouching() then
		bottom, top = enemy:GetHullDuck()
	else
		bottom, top = enemy:GetHull()
	end
	AimPos.z = AimPos.z + (top.z*0.8)

	local StartPos = pl:EyePos()
	local ang = (AimPos - StartPos):Angle()

	BOT_DesiredRotation:Set(ang)
	pl:SetEyeAngles(ang)

	if not pl.BOT_NextCanAttackTime or pl.BOT_NextCanAttackTime<CurTime() then
		pl.BOT_NextCanAttackTime = CurTime()+(0.6-math.min(pl.BOT_Skill*0.4,0.5))
		pl.BOT_ReadyToAttack = ShootTrace(pl,StartPos,AimPos)
	end
	if pl.BOT_ReadyToAttack then
		FireWeaponAt(pl,enemy,cmd)
	end
end

-- Movement planning.
function Bot_ThinkMove( pl, cmd )
	if not pl:Alive(true) or pl:IsFrozen() then
		return
	end

	BOT_DesiredRotation:Set(pl:EyeAngles())

	-- Thinking logics.
	if BOT_Sight[pl]<CurTime() then
		BOT_Sight[pl] = math.max(BOT_Sight[pl]+(1-pl.BOT_Skill*0.65),CurTime())
		ZSBOTAI.SightCheck(pl)

		-- Switch weapon if desired.
		if not pl.BOT_NextWeaponSwitchTime or pl.BOT_NextWeaponSwitchTime<CurTime() and not BOT_PendingHeal[pl] then
			SwitchToBestWeapon(pl)
		end
	end

	cmd:ClearButtons()

	if BOT_SpecialPause[pl] then
		if BOT_SpecialPause[pl]>CurTime() then
			local enemy = BOT_Enemy[pl]
			if IsValid(enemy) and (not BOT_LeapPathTimer[pl] or BOT_LeapPathTimer[pl]<CurTime()) then
				AttackEnemy(pl,enemy,cmd)
			end
			return
		end
		BOT_SpecialPause[pl] = nil
		if BOT_PendingHeal[pl] then
			BOT_PendingHeal[pl] = nil
			pl.BOT_NextWeaponSwitchTime = nil
		end
	end

	if BOT_AttackProp[pl] then
		if not IsValid(BOT_AttackProp[pl]) or pl.BOT_PropAttackTime<CurTime() then
			BOT_AttackProp[pl] = nil
		else
			local ang = (E_GetPos(BOT_AttackProp[pl]) - E_GetPos(pl)):Angle()
			cmd:SetViewAngles(ang)
			BOT_DesiredRotation:Set(ang)
			FireWeaponAt(pl,BOT_AttackProp[pl],cmd)
		end
	elseif BOT_MoveDestination[pl] then
		if not IsValid(BOT_HumanCompanion[pl]) or BOT_MoveDestination[pl]~=BOT_HumanCompanion[pl] or E_GetPos(BOT_HumanCompanion[pl]):DistToSqr(E_GetPos(pl))>pl.BOT_TrailDistance then
			ProcessMoveToward(pl,cmd)
		end
	else
		ChoseNextOrders(pl)
	end

	local enemy = BOT_Enemy[pl]
	if IsValid(enemy) and not BOT_AttackProp[pl] and (not pl.bShouldAimAtEnemy or BOT_MoveDestination[pl]==enemy) and (not BOT_LeapPathTimer[pl] or BOT_LeapPathTimer[pl]<CurTime()) and not BOT_PendingHeal[pl] then
		-- Pick aiming position on enemy.
		AttackEnemy(pl,enemy,cmd)

		if BOT_MoveDestination[pl]==enemy and not BOT_SideStepTime[pl] and COMBAT_ShouldMove and pl.BOT_AttackStyle and E_GetPos(enemy):DistToSqr(E_GetPos(pl))<pl.BOT_AttackStyle and not pl.ShouldQuitNode then -- Too close, back off...!
			if not pl.BOT_RandMoveTime or (pl.BOT_RandMoveTime<CurTime()) then
				pl.BOT_RandMove = math.random(2)
				pl.BOT_RandMoveTime = CurTime()+math.Rand(0.4,0.75)
			end

			if pl.BOT_RandMove==1 then
				cmd:SetForwardMove(-1000)
				cmd:SetSideMove(1000)
				cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_BACK,IN_MOVELEFT))
			else
				cmd:SetForwardMove(-1000)
				cmd:SetSideMove(-1000)
				cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_BACK,IN_MOVERIGHT))
			end
		end
	end

	pl:SetEyeAngles(BOT_DesiredRotation)

	if BOT_JumpCrouch[pl] then
		if bit.band(pl:GetFlags(),bit.bor(FL_ONGROUND,FL_INWATER))~=0 then
			BOT_JumpCrouch[pl] = nil
		else
			cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_DUCK))
		end
	elseif BOT_ShouldCrouch[pl] then
		cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_DUCK))
	end

	if GetPlayerTeam(pl)==TEAM_UNDEAD and pl.bPlayerIsCrow then
		if not IsValid(BOT_Enemy[pl]) or E_GetPos(BOT_Enemy[pl]):DistToSqr(E_GetPos(pl))>10000 then -- Square(100)
			if pl:OnGround() and not BOT_PendingJump[pl] then -- Toggle jump on ground to make the bot crow take off.
				BOT_PendingJump[pl] = true
			else
				cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_JUMP))
				BOT_PendingJump[pl] = nil
			end
		end
	elseif BOT_PendingJump[pl] then
		cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_JUMP))
		BOT_JumpCrouch[pl] = not pl.bFlyingZombie
		BOT_PendingJump[pl] = nil

		if BOT_JumpCrouch[pl] then
			cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_DUCK))
		end
	end

	if BOT_PendingUse[pl] then
		cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_USE))
		BOT_PendingUse[pl] = nil
	end

	if BOT_BarricadeGhostTime[pl] then
		if BOT_BarricadeGhostTime[pl]<CurTime() then
			BOT_BarricadeGhostTime[pl] = nil
		else
			cmd:SetButtons(bit.bor(cmd:GetButtons(),IN_ZOOM))
		end
	end

	if pl.BOT_BhopMove and BOT_MoveDestination[pl] and pl.bAllowBunnyHop then
		HandleBHopping(pl,cmd)
	end
end

local function GetEnemyTeam( ET )
	-- Pick opposing team.
	if ET==TEAM_HUMAN or GAMEMODE.RoundEnded then
		ET = TEAM_UNDEAD
	else
		ET = TEAM_HUMAN
	end
	return ET
end

function ZSBOTAI.GetNearEnemies( pl, pos, dist )
	dist = dist^2
	local res = 0

	-- Pick opposing team.
	local ET = GetEnemyTeam(GetPlayerTeam(pl))
	for pass=1, 2 do
		-- Quickly find the closest best enemy.
		local plList = team.GetPlayers(ET)
		for i=1, #plList do
			local e = plList[i]
			if e~=pl and e:Alive() and not e:HasGodMode() then
				local epos = e:GetPlayerOrigin()
				local edist = epos:DistToSqr(pos)

				-- Must be within 2000 range, infront of the player (or within 1000 range), closer then best enemy and visible.
				if edist<dist and not e.SpawnProtection and SightTrace(pos,epos) then
					res = res+1
				end
			end
		end

		if ET==TEAM_UNDEAD and GAMEMODE.ThePurge then
			ET = TEAM_HUMAN
		else
			break
		end
	end
	return res
end

-- ZOMBIE: find next target to hunt!
function ZSBOTAI.FindNextEnemy( pl )
	local ET = GetEnemyTeam(TEAM_UNDEAD)
	local plpos = E_GetPos(pl)
	local _alive = pl.Alive
	local best = false
	local bestscore

	-- Find largest group/closest human
	local plList = team.GetPlayers(ET)
	for i=1, #plList do
		local e = plList[i]
		if e~=pl and _alive(e) and not e:GetNoDraw() and not e:HasGodMode() then
			local epos = E_GetPos(e)
			local score = 1000 / plpos:Distance(epos)

			for j=1, #plList do
				local d = plList[j]
				if d~=pl and d~=e and _alive(d) then
					local odist = epos:DistToSqr(E_GetPos(d))
					if odist<640000 then -- 800^2
						score = score+0.75
					end
				end
			end

			if not best or bestscore<score then
				best = e
				bestscore = score
			end
		end
	end
	return best
end

function ZSBOTAI.SightCheck( pl )
	if not COMBAT_ShouldFireWeapons then
		if BOT_Enemy[pl] then
			BOT_Enemy[pl] = nil
			pl.BOT_IsShadeEnemy = nil
			pl.BOT_HadSight = nil
			pl.BOT_RandMoveTime = nil
		end
		return
	end

	-- Pick opposing team.
	local PLT = GetPlayerTeam(pl)
	local ET = GetEnemyTeam(PLT)
	local eye = pl:EyePos()
	local dir = Angle(0,pl:GetAngles().yaw,0):Forward()
	local BestEnemy = nil
	local BestDist = (500+(pl.BOT_Skill+0.5)*1000) ^ 2
	local callf = pl.CallZombieFunction1 or pl.CallZombieFunction

	for pass=1, 2 do
		-- Quickly find the closest best enemy.
		local plList = team.GetPlayers(ET)
		for i=1, #plList do
			local e = plList[i]
			if e~=pl and e:Alive() and not e:GetNoDraw() and not e:HasGodMode() then
				local epos = e:EyePos()
				local dist = eye:DistToSqr(epos)

				if e:IsPlayer() then
					local wept = e:GetActiveWeapon()

					dist = IsValid(wept) and wept.GetAuraRange and dist * 9 or dist
				end

				local ndir = epos-eye
				ndir.z = 0

				-- Must be within 2000 range, infront of the player (or within 1000 range), closer then best enemy and visible.
				if BestDist>dist and (dir:Dot(ndir)>0 or dist<1000000) and not e.SpawnProtection and (SightTrace(eye,epos) or SightTrace(eye, e:WorldSpaceCenter()) or SightTrace(eye, e:GetPos())) and (ET==TEAM_HUMAN or not callf(e,"IsInvisible",pl)) then
					BestEnemy = e
					BestDist = dist
				end
			end
		end

		if ET==TEAM_UNDEAD and GAMEMODE.ThePurge then
			ET = TEAM_HUMAN
		else
			break
		end
	end

	local enemy = BOT_Enemy[pl]
	if BestEnemy then
		if PLT==TEAM_UNDEAD then
			pl.BOT_LastSeenTime = CurTime()+1.5
		end
		pl.BOT_HuntFails = nil
		if (GetPlayerTeam(pl)==TEAM_HUMAN or pl:PointReachable(BestEnemy)) and not BOT_LadderPath[pl] and pl.BOT_Skill>math.Rand(0.35,0.75) then
			HandleFinishedMove(pl) -- Instantly switch movement tactics!
		end
		if enemy~=BestEnemy then
			BOT_Enemy[pl] = BestEnemy
			pl.BOT_IsShadeEnemy = (GetPlayerTeam(pl)==TEAM_HUMAN and GAMEMODE.ZombieClasses[BestEnemy:GetZombieClass()].Name == "Shade")
			SwitchToBestWeapon(pl)
			pl.BOT_RandMoveTime = nil
			ZSBOTAI.BotOrders(pl,12,BestEnemy)
		end

		pl.BOT_HadSight = true
		pl.BOT_AquireTime = CurTime()
	elseif pl.BOT_HadSight then
		pl.BOT_HadSight = nil
		pl.BOT_RandMoveTime = nil
	elseif IsValid(enemy) and enemy:IsPlayer() and enemy:Alive() and GetPlayerTeam(enemy)==ET and not enemy:HasGodMode() and not enemy.SpawnProtection then -- Check if old enemy is still valid.
		if PLT==TEAM_HUMAN and (CurTime()-pl.BOT_AquireTime)>5 then -- Check if we've seen old enemy within last 5 seconds.
			BOT_Enemy[pl] = nil
			ZSBOTAI.BotOrders(pl,12)
		end
	else
		if GetPlayerTeam(pl)==TEAM_HUMAN and pl:FlashlightIsOn() then -- Turn off flashlight again.
			pl:ToggleFlashlight()
		end
		BOT_Enemy[pl] = nil
		ZSBOTAI.BotOrders(pl,12)
	end
end

local RefreshTimer = 0
local ZombList = {}
local ZCount = 0
local function PickHumanZClass()
	if RefreshTimer<RealTime() then
		RefreshTimer = RealTime()+10
		local zmain = team.GetPlayers(TEAM_UNDEAD)
		ZCount = 0
		for i=1, #zmain do
			local pl = zmain[i]
			if not pl:UseBotAI() and (pl.AFK_Time or 0)==0 then
				ZCount = ZCount+1
				ZombList[ZCount] = (pl.DeathClass or (pl:GetZombieClassTable().Boss and GAMEMODE.DefaultZombieClass or pl:GetZombieClass()))
			end
		end
	end

	if ZCount>=4 then
		return ZombList[math.random(ZCount)]
	end
	return false
end

local classes_default = {
	"Zombie", "Zombie",
	"Wraith", "Ghoul",
	"Bloated Zombie", "Shadow Walker", "Fast Zombie",
	"Fast Zombie", "Fast Zombie", "Fast Zombie",
	"Poison Zombie", "Ghoul", "Zombie", "Skeletal Walker",
	"Skeletal Walker", "Ghoul"
}

local classes_waves = {}
classes_waves[1] = {
	"Zombie", "Zombie", "Zombie",
	"Ghoul", "Zombie", "Ghoul",
	"Ghoul", "Skeletal Walker",
	"Zombie", "Zombie", "Zombie", "Zombie",
	"Skeletal Walker", "Skeletal Walker"
}
classes_waves[2] = {
	"Zombie", "Zombie", "Zombie", "Shadow Walker", "Gore Blaster Zombie",
	"Putrid Ghoul", "Zombie", "Putrid Ghoul", "Shadow Walker",
	"Putrid Ghoul", "Skeletal Walker", "Gore Blaster Zombie",
	"Zombie", "Zombie", "Zombie", "Zombie",
	"Skeletal Walker", "Skeletal Walker"
}
classes_waves[3] = {
	"Zombie", "Zombie", "Skeletal Walker", "Gore Blaster Zombie", "Skeletal Shambler",
	"Shadow Walker", "Bloated Zombie", "Zombie", "Skeletal Shambler", "Gore Blaster Zombie",
	"Putrid Ghoul", "Zombie", "Bloated Zombie", "Gore Blaster Zombie", "Bloated Zombie",
	"Zombie", "Bloated Zombie", "Zombie", "Skeletal Shambler", "Skeletal Shambler",
	"Skeletal Walker", "Bloated Zombie", "Bloated Zombie", "Skeletal Walker", "Fast Zombie"
}
classes_waves[4] = {
	"Poison Zombie", "Bloated Zombie", "Skeletal Shambler", "Nitro Burster",
	"Mutant", "Mutant", "Nitro Burster", "Nitro Burster", "Mutant", "Fast Zombie",
	"Bloated Zombie", "Mutant", "Bloated Zombie", "Nitro Burster", "Slow Zombie",
	"Bloated Zombie",  "Frigid Walker", "Poison Zombie", "Skeletal Shambler",
	"Bloated Zombie", "Poison Zombie", "Poison Zombie", "Poison Zombie"
}
classes_waves[5] = {
	"Corrupted Mutant", "Mutant", "Bloated Zombie", "Nitro Burster", "Corrupted Mutant",
	"Mutant", "Mutant", "Poison Behemoth", "Nitro Burster", "Nitro Burster", "Ice Immolator",
	"Poison Behemoth", "Poison Behemoth", "Ravaged Zombie", "Burster", "Immolator",
	"Poison Behemoth", "Skeletal Shambler", "Frigid Walker", "Immolator",
	"Bloated Zombie", "Poison Behemoth", "Poison Behemoth", "Poison Behemoth"
}
classes_waves[6] = {
	"Zombine", "Zombine", "Zombine", "Nightmare Revenant", "Nightmare Revenant", "Nitro Burster",
	"Venom Zombie", "Zombine", "Nightmare Revenant", "Nightmare Revenant", "Immolator",
	"Zombine", "Zombine", "Zombine", "Zombine", "Nitro Burster", "Nitro Burster",
	"Zombine", "Zombine", "Venom Zombie", "Zombine", "Immolator", "Ravaged Zombie",
	"Zombine", "Nightmare Revenant", "Zombine", "Zombine", "Ice Immolator"
}
classes_infliction = {
	"Poison Zombie", "Poison Zombie", "Poison Zombie", "Poison Zombie",
	"Poison Behemoth", "Poison Behemoth", "Poison Behemoth", "Fast Zombie",
	"Immolator", "Immolator", "Ice Immolator", "Ice Immolator", "Fast Zombie"
}

-- Select random zombie class
function ZSBOTAI.select_class_new(pl)
	if GAMEMODE.ForceAITestClass then
		local tb = GAMEMODE.ZombieClasses[GAMEMODE.ForceAITestClass]

		pl.DeathClass = tb.Index
		return
	end

	local wave = GAMEMODE.IsObjectiveMap and GAMEMODE:GetObjectiveWaveTier() or GAMEMODE:GetWave()
	local classes = classes_waves[wave] or classes_default

	local zombie_classes = {}
	for _, class in ipairs(classes) do
		local zombie_class = GAMEMODE.ZombieClasses[class]
		if zombie_class and not zombie_class.Locked and (zombie_class.Unlocked or zombie_class.Wave <= wave) then
			zombie_classes[#zombie_classes + 1] = zombie_class
		end
	end

	-- Also include any unlocked Infliction classes
	for _, class in ipairs(classes_infliction) do
		local zombie_class = GAMEMODE.ZombieClasses[class]
		if zombie_class and not zombie_class.Locked and zombie_class.Unlocked and zombie_class.Wave >= wave then
			zombie_classes[#zombie_classes + 1] = zombie_class
		end
	end

	local zombieclass = zombie_classes[math.random(#zombie_classes)]
	if not zombieclass then zombieclass = GAMEMODE.ZombieClasses[GAMEMODE.DefaultZombieClass] end

	local rebirth_for_class = not zombieclass.NoRebirth and zombieclass.BetterClass
	local rebirth_tb = rebirth_for_class and GAMEMODE.ZombieClasses[rebirth_for_class]

	if rebirth_tb and pl:IsBot() and not GAMEMODE.IsObjectiveMap then
		local brain_cost = zombieclass.Brains or 0

		if pl:Frags() >= brain_cost and brain_cost <= 2 then
			zombieclass = rebirth_tb
		end
	end

	pl.DeathClass = zombieclass.Index
end

-- Select random zombie class
function ZSBOTAI.SelectClass( pl )
	if GAMEMODE.ZombieEscape then return end

	-- Try to pick class of a random live human player.
	local desired = PickHumanZClass()

	local n = 0
	for k, v in ipairs(GAMEMODE.ZombieClasses) do
		v.BotLocked = not v.Hidden and not v.NoBot and hook.Call("IsClassUnlocked", GAMEMODE, k)
		if v.BotLocked then
			n = n+1
			if desired==k then
				pl.DeathClass = k
				return
			end
		end
	end

	if n<=1 then
		return
	end

	n = math.random(n)
	local dthcl = nil
	for k, v in ipairs(GAMEMODE.ZombieClasses) do
		if v.BotLocked then
			n = n-1
			if n==0 then
				dthcl = v
				break
			end
		end
	end

	if dthcl then
		pl.DeathClass = dthcl.Index
	end
end

function Bot_AdvanceObjective()
	for _, z in ipairs(team.GetPlayers(TEAM_UNDEAD)) do
		if z:UseBotAI() and z:Alive() then
			z.BOT_TeleportTimer = CurTime()+6
		end
	end
end

local WalkingOrSwimming = bit.bor(FL_ONGROUND,FL_INWATER)
local ShootMaskFlags = bit.band(MASK_SOLID_BRUSHONLY,bit.bnot(CONTENTS_GRATE))

-- From UnrealEngine:
local function SuggestFallVelocity( Dest, Start, XYSpeed, BaseZ, JumpZ, MaxXYSpeed )
	local SuggestedVelocity = Dest - Start
	local DistZ = SuggestedVelocity.z
	SuggestedVelocity.z = 0
	local XYDist = SuggestedVelocity:Length()
	if XYDist==0 or XYSpeed==0 then
		return Vector(0,0,math.max(BaseZ,JumpZ))
	end

	SuggestedVelocity = SuggestedVelocity/XYDist;

	local Gravity = -500
	local GravityZ = 0.5 * Gravity

	-- determine how long I might be in the air
	local ReachTime = XYDist/XYSpeed

	-- calculate starting Z velocity so end at dest Z position
	SuggestedVelocity.z = DistZ/ReachTime - GravityZ * ReachTime

	if SuggestedVelocity.z < BaseZ then
		-- reduce XYSpeed
		-- solve quadratic for ReachTime
		ReachTime = (-1 * BaseZ + math.sqrt(BaseZ * BaseZ + 4 * GravityZ * DistZ))/(2 * GravityZ)
		ReachTime = math.max(ReachTime, 0.05)
		XYSpeed = math.min(MaxXYSpeed,XYDist/ReachTime)
		SuggestedVelocity.z = BaseZ
	elseif SuggestedVelocity.z > BaseZ + JumpZ then
		XYSpeed = XYSpeed * ((BaseZ + JumpZ)/SuggestedVelocity.z)
		SuggestedVelocity.z = BaseZ + JumpZ;
	end

	SuggestedVelocity.x = SuggestedVelocity.x*XYSpeed;
	SuggestedVelocity.y = SuggestedVelocity.y*XYSpeed;

	return SuggestedVelocity;
end

local function AdjustToss( TSpeed, Start, End )
	local Result = nil
	if Start.Z > End.Z + 64 then
		local Dest2D = Vector(End)
		Dest2D.z = Start.z
		local Dist2D = (Start-End):Length2D()
		TSpeed = TSpeed * (Dist2D/End:Distance(Start))
		Result = SuggestFallVelocity(Dest2D,Start,TSpeed,0,TSpeed,TSpeed)
		Result.z = Result.z + (End.z - Start.z) * Result:Length2D()/Dist2D
	else
		Result = SuggestFallVelocity(End,Start,TSpeed,0,TSpeed,TSpeed)
	end
	return Result;
end

local function AddAimError( pl, aimDir )
	local skill = pl.BOT_Skill
	if skill<0.95 then
		skill = 0.3-(skill*0.3)
		aimDir.x = aimDir.x+math.Rand(-skill,skill)
		aimDir.y = aimDir.y+math.Rand(-skill,skill)
		aimDir.z = aimDir.z+math.Rand(-skill,skill)
		aimDir:Normalize()
	end
	return aimDir
end

-- Bot aimbotting:
function ZSBOTAI.BotAdjustAim( pl, aimInfo )
	if IsValid(BOT_AttackProp[pl]) then
		local AimDir = BOT_AttackProp[pl]:WorldSpaceCenter()
		if not aimInfo.start then
			aimInfo.start = pl:GetShootPos()
		end

		return (AimDir-aimInfo.start):GetNormalized()
	end

	local enemy = BOT_Enemy[pl]
	if not IsValid(enemy) then -- No enemy, then aim forward.
		return
	end
	if not aimInfo.start then
		aimInfo.start = pl:GetShootPos()
	end
	local tri = {
		start = aimInfo.start,
		mask = ShootMaskFlags,
	}

	-- Hitscan attack:
	if not aimInfo.speed then
		local bestAimPos = false

		if aimInfo.melee then -- zombie melee, aim anywhere at hitbox.
			tri.endpos = enemy:NearestPoint(aimInfo.start)
			if not util.TraceLine(tri).Hit then
				bestAimPos = tri.endpos
			end
		end

		-- Try aim at head.
		if not bestAimPos then
			local attach = enemy:GetAttachment(enemy:LookupAttachment("anim_attachment_head"))
			if not attach then
				attach = enemy:GetAttachment(enemy:LookupAttachment("head"))
			end
			if attach then
				tri.endpos = attach.Pos

				if not util.TraceLine(tri).Hit then
					bestAimPos = tri.endpos
				end
			end
		end

		-- Try chest.
		if not bestAimPos then
			attach = enemy:GetAttachment(enemy:LookupAttachment("chest"))
			if attach then
				tri.endpos = attach.Pos

				if not util.TraceLine(tri).Hit then
					bestAimPos = tri.endpos
				end
			end
		end

		-- Try feet
		if not bestAimPos then
			tri.endpos = E_GetPos(enemy)+Vector(0,0,5)
			if not util.TraceLine(tri).Hit then
				bestAimPos = tri.endpos
			end
		end

		-- Then just aim at center and hope for the best...
		if not bestAimPos then
			bestAimPos = enemy:GetPlayerOrigin()
		end

		return AddAimError(pl,(bestAimPos-aimInfo.start):GetNormalized())
	else -- Projectile attack, must lead the attack.
		-- Gather enemy information.
		local bottom, top
		if enemy:Crouching() then
			bottom, top = enemy:GetHullDuck()
		else
			bottom, top = enemy:GetHull()
		end
		local TargetHeight = top.z*0.5
		local TargetPos = enemy:GetPlayerOrigin()
		local FireSpot = Vector(TargetPos)
		local TargetVel = enemy:GetVelocity()
		local TargetDist = (TargetPos-aimInfo.start):Length()
		local TravelTime = TargetDist/aimInfo.speed
		local bLeadTargetNow = true

		local bFallingTarget = (enemy:GetMoveType()==MOVETYPE_WALK and bit.band(enemy:GetFlags(),WalkingOrSwimming)==0)

		-- hack guess at projecting falling velocity of target
		if bFallingTarget then
			TargetVel.z = TargetVel.z - TravelTime * 250
			FireSpot = FireSpot + TravelTime*TargetVel
			tri.start = TargetPos
			tri.endpos = FireSpot

			local tr = util.TraceLine(tri)
			if tr.Hit then
				FireSpot = tr.HitPos + Vector(0,0,2)
			end
			bLeadTargetNow = false
		end

		if bLeadTargetNow then
			-- more or less lead target (with some random variation)
			FireSpot = FireSpot + (math.min(1, math.Rand(0.7,1.2)) * TargetVel * TravelTime)
			FireSpot.z = math.min(TargetPos.z, FireSpot.z)
		end

		-- make sure that bot isn't leading into a wall
		tri.start = aimInfo.start
		tri.endpos = FireSpot
		local bClean = not util.TraceLine(tri).Hit
		if not bClean then
			-- reduce amount of leading
			if math.random(3)==1 then
				FireSpot = TargetPos
			else
				FireSpot = 0.5 * (FireSpot + TargetPos)
			end
			tri.endpos = FireSpot
			bClean = not util.TraceLine(tri).Hit
		end

		-- Aim at feet.
		if aimInfo.Splash and (aimInfo.start.z + 19 > TargetPos.z) then
			tri.start = FireSpot
			tri.endpos = FireSpot - Vector(0,0,50)
			local tr = util.TraceLine(tri)
			if tr.Hit then
				FireSpot = tr.HitPos + Vector(0,0,3)
				tri.start = aimInfo.start
				tri.endpos = FireSpot
				bClean = not util.TraceLine(tri).Hit
			else
				tri.start = aimInfo.start
				tri.endpos = FireSpot
				bClean = bFallingTarget and not util.TraceLine(tri).Hit
			end
		end

		if not bClean then
			-- try head
			FireSpot.z = TargetPos.z + 0.9 * TargetHeight
			tri.start = aimInfo.start
			tri.endpos = FireSpot
			bClean = not util.TraceLine(tri).Hit
		end

		if not bClean then
			-- try feet
			FireSpot.z = TargetPos.z - 0.9 * TargetHeight
			tri.start = aimInfo.start
			tri.endpos = FireSpot
			bClean = not util.TraceLine(tri).Hit
		end

		-- adjust for toss distance
		local FireDir = nil
		if aimInfo.Toss then
			FireDir = AdjustToss(aimInfo.speed,aimInfo.start,FireSpot)
		else
			FireDir = FireSpot - aimInfo.start
		end

		return AddAimError(pl,FireDir:GetNormalized())
	end
end

---------------- OPTIONS ------------------
GM.MaxBotZombies = CreateConVar("zs_zombiebotsmax", "6", FCVAR_ARCHIVE + FCVAR_NOTIFY, "Max number of bot zombies."):GetInt()
cvars.AddChangeCallback("zs_zombiebotsmax", function(cvar, oldvalue, newvalue)
	GAMEMODE.MaxBotZombies = tonumber(newvalue)
end)

GM.MaxBotZombiesThreshold = CreateConVar("zs_zombiemaxbotsthreshold", "12", FCVAR_ARCHIVE + FCVAR_NOTIFY, "What playercount should we be at max bot zombies?"):GetInt()
cvars.AddChangeCallback("zs_zombiemaxbotsthreshold", function(cvar, oldvalue, newvalue)
	GAMEMODE.MaxBotZombiesThreshold = tonumber(newvalue)
end)

function GM:GetIdealBotCount()
	if player.GetCount() >= game.MaxPlayers() - 3 then
		return 1
	end

	local human_count = #player.GetHumans()

	local min = 1
	local max = GAMEMODE.MaxBotZombiesThreshold
	local botcap = GAMEMODE.MaxBotZombies
	local normalized = Normalize(human_count, min, max)

	return 	normalized == 0 and 1
					or normalized == 1 and botcap
					or (botcap - 1) * normalized
end