-- Freaky bot chatting AI, by Marco

local SingleWords,SentWords

local StartSentances,ParentWords

local Punctuation = {".","!",",","?"}
local PLookup = {}

local VocabFileName = "zs_botchatlog.txt"
local neuralSkill = 0.8 -- Minimum skill level for bot to start using neural network for chatting.

local MAX_ShortWords = 1000
local MAX_StoreShortWords = 1200
local MAX_LongWords = 1500
local MAX_StoreLongWords = 2000
local SAVE_Tag = 1

local CortexEntropy = 0.5
local CortexModel = "90950"
local CortexPersonality = "Kendall Schmidt"

-- List of names bots will identify as a human name.
local NameNotifys = {
	["bot"]=true,
	["bots"]=true,
	["marco"]=true,
	["forrest"]=true,
	["pho"]=true,
	["fume"]=true,
	["ryze"]=true,
	["kleiner"]=true,
	["homer"]=true,
	["techmo"]=true
}
local RespondNotifies = {
	["bot"]=true,
	["bots"]=true,
}

hook.Add( "Initialize", "Initialize.InitNameList", function() -- Also identify all default bot names.
	local nl = ZSBOTAI.BotNameList
	for i=1, #nl do
		NameNotifys[string.lower(nl[i])] = true
	end
end)

local function InitLookupList()
	StartSentances = {[TEAM_HUMAN]={},[TEAM_UNDEAD]={}}
	ParentWords = {[TEAM_HUMAN]={},[TEAM_UNDEAD]={}}

	for Pass=1, 2 do
		local tm = (Pass==1 and TEAM_HUMAN or TEAM_UNDEAD)
		local wtab = SentWords[tm]
		local stab = StartSentances[tm]
		local ptab = ParentWords[tm]
		for i=1, #wtab do
			local p = wtab[i]
			if not p.p then
				stab[#stab+1] = i
			else
				local tab = ptab[p.p]
				if not tab then
					tab = {}
					ptab[p.p] = tab
				end
				tab[#tab+1] = i
			end
		end
	end
end

local function InitWording()
	for i=1, #Punctuation do
		PLookup[Punctuation[i]] = true
	end

	SingleWords = {}
	SingleWords[TEAM_HUMAN] = {}
	SingleWords[TEAM_UNDEAD] = {}
	SentWords = {}
	SentWords[TEAM_HUMAN] = {}
	SentWords[TEAM_UNDEAD] = {}

	local f = file.Open(VocabFileName,"rb","DATA")
	if f then
		local succ, err = pcall(function()
			local tg = f:ReadByte()
			if tg~=SAVE_Tag then
				error("Invalid bot chat data version.")
			end

			for Pass=1, 2 do
				local tm = (Pass==1 and TEAM_HUMAN or TEAM_UNDEAD)

				local num = f:ReadULong()
				local wtab = SingleWords[tm]
				for i=1, num do
					local sz = f:ReadUShort()
					if sz==0 then
						error("Nil size string? (short phase)")
					end
					wtab[i] = f:Read(sz)
				end

				num = f:ReadULong()
				wtab = SentWords[tm]
				for i=1, num do
					local tab = {}
					local sz = f:ReadUShort()
					if sz==0 then
						error("Nil size string? (long phase)")
					end
					tab.w = f:Read(sz)
					sz = f:ReadUShort()
					if sz>0 then
						tab.p = f:Read(sz)
					end
					local flags = f:ReadByte()
					if bit.band(flags,1)~=0 then
						tab.e = true
					end
					if bit.band(flags,2)~=0 then
						tab.n = true
					end
					wtab[#wtab+1] = tab
				end
			end
		end)
		f:Close()

		if not succ then
			SingleWords = {}
			SingleWords[TEAM_HUMAN] = {}
			SingleWords[TEAM_UNDEAD] = {}
			SentWords = {}
			SentWords[TEAM_HUMAN] = {}
			SentWords[TEAM_UNDEAD] = {}
			DEBUG_MessageDev("ERROR! Failed to load bot chat data: "..err,false,1)
		end
	end
	InitLookupList()
end

InitWording()

local function SaveVocabulary()
	local f = file.Open(VocabFileName,"wb","DATA")
	if not f then
		DEBUG_MessageDev("WARNING: Couldn't save bot vocabulary!",false,1)
		return
	end

	local succ, err = pcall(function()
		f:WriteByte(SAVE_Tag)

		for Pass=1, 2 do
			local tm = (Pass==1 and TEAM_HUMAN or TEAM_UNDEAD)

			local wtab = SingleWords[tm]
			f:WriteULong(math.min(#wtab,MAX_ShortWords))
			for i=math.max(#wtab-MAX_ShortWords+1,1), #wtab do
				local w = wtab[i]
				f:WriteUShort(#w)
				f:Write(w)
			end

			wtab = SentWords[tm]
			f:WriteULong(math.min(#wtab,MAX_LongWords))
			for i=math.max(#wtab-MAX_LongWords+1,1), #wtab do
				local p = wtab[i]
				f:WriteUShort(#p.w)
				f:Write(p.w)
				if p.p then
					f:WriteUShort(#p.p)
					f:Write(p.p)
				else
					f:WriteUShort(0)
				end
				local flags = (p.e and 1 or 0)
				if p.n then
					flags = flags+2
				end
				f:WriteByte(flags)
			end
		end
	end)
	f:Close()

	if not succ then
		DEBUG_MessageDev("ERROR! Failed to save bot chat data: "..err,false,1)
	end
end

hook.Add("ShutDown","ShutDown.SaveBotChat",SaveVocabulary)

local NextBotRespondTime = 0
local NextResponder,NextRespondedTo

local function HandleRespons()
	ZSBOTAI.RoastPlayer(NextResponder,NextRespondedTo)
end

local ParseCounter = 0

local epic_shit = {
	"child",
	"porn",
	"nigger",
	"nigga",
	"niga",
	"nig",
	"faggot",
	"fag",
	"www.",
	"http://",
	"https://",
	"download"
}

local function ParseChat( pl, msg )
	local iteam = GetPlayerTeam(pl)
	if iteam~=TEAM_HUMAN and iteam~=TEAM_UNDEAD then return end -- Make sure not spectator

	local wrds = string.Explode(" ",msg,false)
	if #wrds==0 then return end -- Incomplete sentance.

	for _, bad_phrase in pairs(epic_shit) do
		if string.match(string.lower(msg), bad_phrase) then
			return
		end
	end

	-- See if a bot should respond to this.
	if NextBotRespondTime<RealTime() then
		local lmsg = string.lower(msg)
		for i=1, #ZSBOTAI.Bots do
			if string.find(lmsg,string.lower(ZSBOTAI.Bots[i]:Name()),1,true) then
				NextBotRespondTime = RealTime()+6
				NextResponder = ZSBOTAI.Bots[i]
				NextRespondedTo = pl:Nick()
				timer.Simple(math.Rand(2,3),HandleRespons)
				break
			end
		end
	end

	if #wrds==1 then
		local stab = SingleWords[iteam]
		local w = wrds[1]
		if #w<=2 or #stab>MAX_StoreShortWords then return end -- Too short...

		for i=1, #stab do
			if stab[i]==w then
				return
			end
		end

		stab[#stab+1] = w
		return
	end

	local stab = SentWords[iteam]
	if #stab>MAX_StoreLongWords then return end

	local pw = false
	for i=1, #wrds do
		local w = wrds[i]
		if #w==0 then continue end

		local l = string.Left(w,1)
		if PLookup[l] then -- Bad spacing of words and punctuations, assumes a punctuation
			if pw then
				pw.w = pw.w..l
			end
			continue
		end

		local tab = {w=w}
		if pw then
			tab.p = string.lower(pw.w)
		end
		pw = tab
		if NameNotifys[string.lower(pw.w)] then
			pw.n = true

			-- See if a random bot should respond to this.
			if NextBotRespondTime<RealTime() and #ZSBOTAI.Bots>0 and RespondNotifies[string.lower(pw.w)] then
				NextBotRespondTime = RealTime()+6
				NextResponder = ZSBOTAI.Bots[math.random(#ZSBOTAI.Bots)]
				NextRespondedTo = pl:Nick()
				timer.Simple(math.Rand(2,3),HandleRespons)
			end
		end
		stab[#stab+1] = tab
	end
	if pw then
		pw.e = true
	end

	ParseCounter = ParseCounter+1
	if ParseCounter>100 then
		InitLookupList()
		ParseCounter = 0
	end
end

local function PickRandomName()
	local pls = player.GetHumans()
	if #pls==0 then return "Someone" end
	return pls[math.random(#pls)]:Nick()
end

local function GenerateChatMsg( iteam, RespondTo )
	if iteam~=TEAM_HUMAN and iteam~=TEAM_UNDEAD then
		iteam = (math.random(2)==1 and TEAM_HUMAN or TEAM_UNDEAD) -- Make sure not spectator
	end

	local stab = SingleWords[iteam]
	if not RespondTo and math.random(5)==1 and #stab>0 then
		return stab[math.random(#stab)]
	end

	stab = StartSentances[iteam]
	if #stab==0 then return end

	local wtab = SentWords[iteam]
	local ptab = ParentWords[iteam]
	local result

	for Pass=1, 10 do -- Try 10 times to find a sentance containing a player name for bots to respond to.
		local cur = wtab[stab[math.random(#stab)]]
		if cur.n and (RespondTo or (math.random(6)<5)) then
			result = RespondTo or PickRandomName()
			RespondTo = nil
		else
			result = cur.w
		end
		local i = math.random(0,10)

		while i<20 do
			i = i+1
			local n = ptab[string.lower(cur.w)]
			if not n then break end

			n = wtab[n[math.random(#n)]]
			if n.n and (RespondTo or (math.random(6)<5)) then
				result = result.." "..(RespondTo or PickRandomName())
				RespondTo = nil
			else
				result = result.." "..n.w
			end

			if n.e and math.random(1,3)==1 then break end
			cur = n
		end

		if not RespondTo then break end
	end

	local dec = math.random(1,15)
	if dec<=5 then
		if dec==2 then
			result = string.upper(result)
		elseif dec==3 then
			result = string.lower(result)
		else
			result = string.upper(string.Left(result,1))..string.lower(string.Right(result,#result-1)) -- Make nice formatting, with first char being caps, rest locs
		end
	end
	return result
end

local bNeuralBroken = false
local pendingBotChat = false
local _ParseNext = false
local nextParse = 0
local nextPly
hook.Add( "PlayerSay", "PlayerSay.BotSniffChat", function( ply, text, team )
	_ParseNext = (IsValid(ply) and not ply:IsBot())
	if _ParseNext then
		nextPly = ply
	end
end,HOOK_MONITOR_HIGH)

hook.AddPost( "PlayerSay", "PlayerSay.BotSniffChatPost", function( text )
	if _ParseNext and nextParse<RealTime() and isstring(text) and #text>0 then
		nextParse = RealTime()+0.5
		_ParseNext = false

		local l = string.Left(text,1)
		if l=="!" or l=="." or l=="/" then return end -- Skip commands
		ParseChat(nextPly,text)
		if not bNeuralBroken then
			ZSBOTAI.SubmitNeuralChat(nextPly,text)
		end
	end
end)

function ZSBOTAI.MakeBotChat( pl )
	if pl.BOT_Skill>=neuralSkill and not bNeuralBroken then
		pendingBotChat = pl
	else
		local msg = GenerateChatMsg(GetPlayerTeam(pl))
		if msg then
			pl:Say(msg)
		end
	end
end

function ZSBOTAI.RoastPlayer( bot, plname )
	if bot.BOT_Skill>=neuralSkill and not bNeuralBroken then
		pendingBotChat = bot
		ZSBOTAI.SubmitNeuralChat(plname,"hi")
	else
		local msg = GenerateChatMsg(GetPlayerTeam(bot),plname)
		if msg then
			bot:Say(msg)
		end
	end
end

concommand.Add("zs_cleanupbotchat", function(sender, command, arguments)
	if GAMEMODE:PlayerIsSuperAdmin(sender) then
		table.Empty(StartSentances[TEAM_HUMAN])
		table.Empty(StartSentances[TEAM_UNDEAD])
		table.Empty(ParentWords[TEAM_HUMAN])
		table.Empty(ParentWords[TEAM_UNDEAD])
		table.Empty(SingleWords[TEAM_HUMAN])
		table.Empty(SingleWords[TEAM_UNDEAD])
		table.Empty(SentWords[TEAM_HUMAN])
		table.Empty(SentWords[TEAM_UNDEAD])
		ParseCounter = 0
		DEBUG_MessageDev("NOTE: "..sender:Nick().." emptied bot chat history!")
	end
end)

local TransIndex
local TransmitLines = {}
local AwaitingResponse = false

local function SendNextLine()
	if not pendingBotChat:IsValid() then
		AwaitingResponse = false
		pendingBotChat = false
		return
	end

	pendingBotChat:Say(TransmitLines[TransIndex])
	TransIndex = TransIndex+1

	if TransIndex>#TransmitLines then
		AwaitingResponse = false
		pendingBotChat = false
	else
		timer.Simple(math.Rand(3,5),SendNextLine)
	end
end

local httpmethod = {
	url="http://24.10.136.241:8190/cortex/respond",
	method="POST",
	headers={},
	type="json",
	success=function(code,body,headers)
		if pendingBotChat and not string.StartWith(body,"<html>") then
			local ls = string.Split(body,"\n")
			table.Empty(TransmitLines)
			for i=1, #ls do
				if #ls[i]>0 then
					TransmitLines[#TransmitLines+1] = ls[i]
				end
			end
			if #TransmitLines>0 then
				TransIndex = 1
				timer.Simple(math.Rand(0.1,0.6),SendNextLine)
			else
				AwaitingResponse = false
			end
		else
			AwaitingResponse = false
		end
	end,
	failed=function(reason)
		DEBUG_MessageDev("Neural bot chat broken, HTTP error: "..reason, true, 1, true)
		bNeuralBroken = true
		AwaitingResponse = false
		pendingBotChat = false
	end,
}

function ZSBOTAI.SubmitNeuralChat( pl, msg )
	if AwaitingResponse then return end

	local NumZombies = 0
	local NumHumans = 0

	-- Get player count on each team
	local ptable = player.GetAll()
	for k, v in pairs(ptable) do
		local t = v:Team()
		if t == 'TEAM_UNDEAD' then
			NumZombies = NumZombies + 1
		elseif t == 'TEAM_HUMAN' then
			NumHumans = NumHumans + 1
		end
	end

	AwaitingResponse = true
	httpmethod.body = [[{
	"name": "]]..(isstring(pl) and pl or pl:Nick())..[[",
	"message": "]]..msg..[[",
	"entropy": ]]..CortexEntropy..[[,
	"num_responses": ]]..(pendingBotChat and "2" or "0")..[[,
	"personality": "]]..CortexPersonality..[[",
	"team": "]] .. (isstring(pl) and "TEAM_HUMAN" or pl:Team()) .. [[",
	"zcount": ]] .. (NumZombies or -1).. [[,
	"hcount": ]] .. (NumHumans or -1) .. [[,
	"wave": ]] .. (GAMEMODE:GetWave() or -1) .. [[
}]]
	HTTP(httpmethod)
end

concommand.Add("cortex_setentropy", function(ply, cmd, args)
	if ply:IsUserGroup("developer") then
		local val = tonumber(args[1])
		if val ~= nil then
			if val > 0 and val <= 1 then
				CortexEntropy = val

				PrintMessage(HUD_PRINTTALK, ply:Nick() .. " set the neural entropy to '" .. val .. "'")
			end
		end
	end
end )

concommand.Add("cortex_setbroken", function(ply, cmd, args)
	if ply:IsUserGroup("developer") then
		local val = tobool(args[1])
		if val ~= nil then
			if val == true or val == false then
				bNeuralBroken = val
			end
		end
	end
end )

concommand.Add("cortex_minimumskill", function(ply, cmd, args)
	if ply:IsUserGroup("developer") then
		local val = tonumber(args[1])
		if val ~= nil then
			if val >= 0 and val <= 1 then
				neuralSkill = val

				PrintMessage(HUD_PRINTTALK, ply:Nick() .. " set the minimum bot skill for neural chat to '" .. val .. "'")
			end
		end
	end
end )


concommand.Add("cortex_setpersonality", function(ply, cmd, args, argstr)
	if ply:IsUserGroup("developer") then
		local val = argstr
		if val ~= nil and val ~= "" then
				CortexPersonality = val
				PrintMessage(HUD_PRINTTALK, ply:Nick() .. " set the neural personality bias to '" .. val .. "'")
		end
	end
end )