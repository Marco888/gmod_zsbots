SWEP.PrintName = "Admin Path Tool"
SWEP.NewSlot = 6
SWEP.SlotPos = 100
 
SWEP.ViewModelFOV = 62
SWEP.ViewModelFlip = false
SWEP.AnimPrefix = "stunstick"
 
SWEP.Spawnable = false
SWEP.AdminSpawnable = false
SWEP.AdminOnly = true

SWEP.ViewModel = "models/weapons/c_stunstick.mdl"
SWEP.WorldModel = "models/weapons/w_stunbaton.mdl"
SWEP.UseHands = true
 
local FSound = Sound("weapons/stunstick/stunstick_swing1.wav")
 
SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = 0
SWEP.Primary.Automatic = false 
SWEP.Primary.Ammo = ""
 
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = 0
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = ""
SWEP.Undroppable = true
SWEP.UnGiveable = true

SWEP.OnlyCrosshairDot = true

local function DoPlayStrike( w )
	if w:GetNextPrimaryFire()>CurTime() then return false end
	
	w:SetNextPrimaryFire(CurTime() + 0.25)

	w:GetOwner():SetAnimation(PLAYER_ATTACK1)
	
	if CLIENT then
		w:EmitSound(FSound)
	end
	w:SendWeaponAnim(ACT_VM_HITCENTER)
	return CLIENT
end

function SWEP:PrimaryAttack()
	if DoPlayStrike(self) then
		self:DeployNode(0)
	end
end
 
function SWEP:SecondaryAttack()
	if DoPlayStrike(self) then
		self:DeployNode(1)
	end
end

function SWEP:Reload()
	if DoPlayStrike(self) then
		self:DeployNode(2)
	end
end
