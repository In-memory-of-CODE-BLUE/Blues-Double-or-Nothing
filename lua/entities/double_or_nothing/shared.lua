ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Double Or Nothing"
ENT.Author = "<CODE BLUE>"
ENT.Contact = "Via Steam"
ENT.Spawnable = true
ENT.Category = "Blues Slots"
ENT.AdminSpawnable = true 

ENT.WheelSides = 8

function ENT:SetupDataTables()
	--Stores the current user name of the machine.
	--Will be "No One" if one one is using it.
	self:NetworkVar( "String", 0, "UserName")
	self:NetworkVar( "Float", 0, "UserLastInteract")
	self:NetworkVar( "Int", 0, "Multiplier")
	self:NetworkVar( "Bool", 0, "GameStarted")
	self:NetworkVar( "Int", 1, "CashOutAmount")
	self:NetworkVar( "Int", 2, "Jackpot")
end