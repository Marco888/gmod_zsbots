
local ProfilingBot
local BotMoveTarget = false
local BotEnemy = nil
local BotMoveTime
local BotRouteList = false
local OrderString = false
local OrderTime = false
local OrderEnt
local TempOrders = false
local TempOrderEnt
local TempOrdersTime

local OrderList = {"Idle","StakeOut","GoShopping","Follow Companion","Charge","Hunting","StakeOut while hunting","Move to last seen"}

local function DrawAIOrders()
	local dfont = "DermaDefault"
	local x,y = 60,100
	draw.SimpleText("Profiling "..tostring(ProfilingBot),dfont,x,y)
	y = y+16
	if IsValid(ProfilingBot) then
		local wp = ProfilingBot:GetActiveWeapon()
		if IsValid(wp) then
			draw.SimpleText("Weapon: "..tostring(wp).." Clip: "..tostring(wp:Clip1()),dfont,x,y)
			y = y+16
		end
	end
	if BotMoveTarget then
		draw.SimpleText("MoveTimer: "..tostring(math.max(BotMoveTime-CurTime(),0)),dfont,x,y)
		y = y+16
	end
	if IsValid(BotEnemy) then
		draw.SimpleText("Enemy: "..tostring(BotEnemy),dfont,x,y)
		y = y+16
	end
	if OrderString then
		draw.SimpleText("Orders: "..OrderString,dfont,x,y)
		y = y+16
		
		if IsValid(OrderEnt) then
			draw.SimpleText("Target: "..tostring(OrderEnt),dfont,x,y)
			y = y+16
		end
		if OrderTime then
			draw.SimpleText("Order time: "..tostring(math.max(OrderTime-CurTime(),0)),dfont,x,y)
			y = y+16
		end
	end
	if TempOrders then
		draw.SimpleText("Temp Orders: "..TempOrders,dfont,x,y)
		y = y+16
		
		if IsValid(TempOrderEnt) then
			draw.SimpleText("Target: "..tostring(TempOrderEnt),dfont,x,y)
			y = y+16
		end
		if TempOrdersTime then
			draw.SimpleText("Time: "..tostring(math.max(TempOrdersTime-CurTime(),0)),dfont,x,y)
			y = y+16
			
			if TempOrdersTime<CurTime() then
				TempOrders = false
			end
		end
	end
end

local function DrawAIRoute()
	if BotMoveTarget then
		local endpos
		if isvector(BotMoveTarget) then
			endpos = BotMoveTarget
		elseif IsValid(BotMoveTarget) then
			endpos = BotMoveTarget:GetPos()
		end
		
		if endpos then
			local startpos = ProfilingBot:GetPlayerOrigin()
			render.DrawLine(startpos,endpos,COLOR_CYAN,false)
			local ang = (endpos-startpos):Angle()
			local x = ang:Forward()*12
			local y = ang:Right()*4
			
			render.DrawLine(endpos-x-y,endpos,COLOR_CYAN,false)
			render.DrawLine(endpos-x+y,endpos,COLOR_CYAN,false)
			render.DrawLine(endpos-x+y,endpos-x-y,COLOR_CYAN,false)
		end
	end
	if BotRouteList then
		for i=2, #BotRouteList do
			local a = GAMEMODE.AI_PATHLIST[BotRouteList[i]]
			local b = GAMEMODE.AI_PATHLIST[BotRouteList[i-1]]
			if a and b then
				render.DrawLine(a.P,b.P,COLOR_YELLOW,false)
			end
		end
	end
	if IsValid(BotEnemy) then
		render.DrawLine(ProfilingBot:GetPos(),BotEnemy:GetPos(),COLOR_RED,false)
	end
end

net.Receive("zs_ai_profile", function(length)
	local code = net.ReadUInt(3)
	
	if code==0 then -- Start/End profiling.
		if net.ReadBool() then
			ProfilingBot = net.ReadEntity()
			if IsValid(ProfilingBot) then
				hook.Add("PostDrawOpaqueRenderables","BotProfile.PostDrawOpaqueRenderables",DrawAIRoute)
				hook.Add("HUDPaint","BotProfile.HUDPaint",DrawAIOrders)
				return
			end
		end
		ProfilingBot = nil
		BotMoveTarget = false
		BotRouteList = false
		hook.Remove("PostDrawOpaqueRenderables","BotProfile.PostDrawOpaqueRenderables")
		hook.Remove("HUDPaint","BotProfile.HUDPaint")
	elseif code==1 then -- Update bot move target
		local dtype = net.ReadUInt(2)
		if dtype==0 then
			BotMoveTarget = net.ReadVector()
		elseif dtype==1 then
			BotMoveTarget = net.ReadEntity()
			if not IsValid(BotMoveTarget) then
				BotMoveTarget = false
			end
		else
			BotMoveTarget = false
			return
		end
		BotMoveTime = net.ReadFloat()
	elseif code==2 then -- Update bot route
		local route = {}
		while net.ReadBool() do
			route[#route+1] = net.ReadUInt(16)
		end
		if #route>1 then
			BotRouteList = route
		else
			BotRouteList = false
		end
	elseif code==3 then -- Update bot orders
		local orders = net.ReadUInt(6)
		
		if orders>=36 then
			if orders==36 then
				TempOrders = "Break Prop"
			else
				TempOrders = "Open Door"
			end
			TempOrderEnt = net.ReadEntity()
			TempOrdersTime = net.ReadFloat()
		else
			OrderTime = false
			OrderEnt = nil
			TempOrders = false
			
			OrderString = OrderList[orders+1]
			if orders==2 then -- Shopping
				OrderEnt = net.ReadEntity()
				OrderTime = net.ReadFloat()
			elseif orders==3 then -- Follow companion
				OrderEnt = net.ReadEntity()
			end
		end
	elseif code==4 then -- New enemy
		BotEnemy = net.ReadEntity()
	end
end)
