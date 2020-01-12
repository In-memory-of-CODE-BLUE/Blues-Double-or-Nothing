AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
AddCSLuaFile("bdon_config.lua")
include('shared.lua')
include('bdon_config.lua')

--Network strings
util.AddNetworkString("bdon:updateScreenEffect") --Mad at inconsitant namings? >:D
util.AddNetworkString("bdn:setselectedbutton")
util.AddNetworkString("bdn:winninginfo")
util.AddNetworkString("bdn:beginjackpot")
util.AddNetworkString("bdn:jackpotinfo")

--All the materials for the light strips
local lightMaterials = {
	[1] = "bluesdoubleornothing/bdn_light_strip.vmt",
	[2] = "bluesdoubleornothing/bdn_light_strip_2.vmt",
	[3] = "bluesdoubleornothing/bdn_light_strip_3.vmt",
	[4] = "bluesdoubleornothing/bdn_light_strip_4.vmt",
	[5] = "bluesdoubleornothing/bdn_light_strip_5.vmt",
}

local buttonLights = {
	off = "bluesdoubleornothing/bdn_cashout_button_off.vmt",
	on = "bluesdoubleornothing/bdn_cashout_button.vmt"
}

function ENT:Initialize()
	self:SetModel("models/bluesdoubleornothing/slots_1.mdl")
	self:PhysicsInit( SOLID_VPHYSICS )
	self:SetMoveType( MOVETYPE_VPHYSICS )
	self:SetSolid( SOLID_VPHYSICS )
	self:SetUseType(SIMPLE_USE)

	local phys = self:GetPhysicsObject()
	if (phys:IsValid()) then
		phys:Wake() 
	end

	--If set to true, all automatic light effects are disable. This is so the jackpot etc can override it
	self.overrideLights = false

	--Handles auto changing light patterns
	self.nextChangeAt = CurTime() + 6
	self.currentLight = 1 --1, 2 or 3. Keeps track of what lights are on the strips

	--Stores the user of the machine
	self.user = nil
	self:SetUserName("Nobody")
	--The time in seconds since the user last interacted with the machine
	self.timeSinceLastUsed = CurTime()

	--The multiplier amount (between 1 and 10) (10 is jackpot)
	self:SetMultiplier(0)

	--If false restrics interaction
	self.canSpin = true

	--Has a game been started, or are we at the start screen
	self:SetGameStarted(false)

	--The amount the user cashed out for the client side screen
	self:SetCashOutAmount(0)

	--State of the button (false = double, true = cashout)
	self.userState = false

	--Generate random jackpot
	self:SetJackpot(math.random(BDON_CONFIG.minJackpot, BDON_CONFIG.maxJackpot))
end

--Tells all other players that the entity should begin a jackpot
function ENT:PlayJackpot()
	net.Start("bdn:beginjackpot")
	net.WriteEntity(self)
	net.Broadcast()
 
	self.user.bdonTimeSinceLastUse = CurTime() + 59 --Dont let anyone have the machine until the jackpot ends
	self:SetUserLastInteract(self.user.bdonTimeSinceLastUse)

	self.overrideLights = true

	self.currentLight = 4
	self:UpdateLights()

	timer.Simple(15.09, function()
		self.currentLight = 3
		self:UpdateLights()
	end)
 
	timer.Simple(45.09, function()
		--Add the money
		if self.user ~= nil then

			BDON_CONFIG.addMoney(self.user, self:GetJackpot())

			net.Start("bdn:jackpotinfo")
			net.WriteEntity(self.user)
			net.WriteInt(self:GetJackpot(), 32)
			net.Broadcast()
		end
	end)
 
	--Timer to reset
	timer.Simple(59, function()
		self:SetGameStarted(false)
		self:ResetMultiplier()
		self.overrideLights = false 
		self:UpdateLights()

		self.canSpin = true

	    --Generate random jackpot
		self:SetJackpot(math.random(BDON_CONFIG.minJackpot, BDON_CONFIG.maxJackpot))

		net.Start("bdon:updateScreenEffect")
		net.WriteEntity(self)
		net.WriteFloat(2)
		net.Broadcast()	
	end)
end

--Adds one multiplier, updates the client and tells them to perform a new effect
function ENT:AddMultiplier(overrideEffect)
	self:SetGameStarted(true)

	if self:GetMultiplier() + 1 > 10 then return false end
	self:SetMultiplier(self:GetMultiplier() + 1)

	--Tell clients to do the update screen effect
	net.Start("bdon:updateScreenEffect")
	net.WriteEntity(self)
	if overrideEffect ~= nil then
		net.WriteFloat(overrideEffect)
	end
	net.Broadcast()
 
	if self:GetMultiplier() > 4 then
		self.overrideLights = true
		self.currentLight = 3
	end

	self:UpdateLights()

	return true
end

function ENT:ResetMultiplier()
	self:SetMultiplier(0)
	self.overrideLights = false
	self.currentLight = 2  
	self:UpdateLights()
	self.userState = false
	net.Start("bdon:updateScreenEffect")
	net.WriteEntity(self)
	net.WriteFloat(2)
	net.Broadcast()
 
	self:SetGameStarted(false)
end

--When called applies all light effects to the model.
function ENT:UpdateLights()
	self:SetSubMaterial(5, lightMaterials[self.currentLight])
	if self:GetMultiplier() > 0 then
		self:SetSubMaterial(9, buttonLights.on)
	else
		self:SetSubMaterial(9, buttonLights.off)
	end
end

function ENT:Think()
	if not self.overrideLights then
		if CurTime() > self.nextChangeAt then
			self.nextChangeAt = CurTime() + 6
			--Toggle between 1 and 2
			if self.currentLight == 1 then 
				self.currentLight = 2
			else
				self.currentLight = 1
			end
			self:UpdateLights() --Update the change
		end
	end

	--Handle clearing a user who has been AFK for too long
	if self.user ~= nil and self.timeSinceLastUsed + 30 - CurTime() < 0 then
		--Times up
		self.user = nil
		self:SetUserName("Nobody")
	end
end

--Returns the amount the user should win
function ENT:CalculateWinning()
	local bet = BDON_CONFIG.bet
	for i = 1 , self:GetMultiplier() - 1 do
		bet = bet * 2
	end

	return bet
end

function ENT:Use(act, call)
	if call:IsPlayer() and self.canSpin == true then
		if self.user ~= nil and self.user ~= call then
			call:ChatPrint("[BLUE'S SLOTS] This machine belongs to "..self.user:Name()..", wait for them to finish there turn!")
			return --Cannot spin as its someone elses machine		
		end

		if call.bdonLastUsedSlot ~= self and call.bdonLastUsedSlot ~= nil then
			call:ChatPrint("[BLUE'S SLOTS] Please wait before switching machines!")
			return --Cannot spin as your on anouther machine
		end

		if self.user == call then
			self.timeSinceLastUsed = CurTime()
			self.user.bdonTimeSinceLastUse = CurTime()
			self.user.bdonLastUsedSlot = self
			self:SetUserLastInteract(self.timeSinceLastUsed)
			shouldSpin = true
		elseif self.user == nil then
			--New user, asign them to the machine
			self.user = call
			self.timeSinceLastUsed = CurTime()
			self.user.bdonLastUsedSlot = self
			self.user.bdonTimeSinceLastUse = CurTime()
			self:SetUserName(call:Name())
			self:SetUserLastInteract(self.timeSinceLastUsed)
			shouldSpin = true
		end

		if self:GetMultiplier() == 0 then
			--Take money
			if BDON_CONFIG.canAfford(call, BDON_CONFIG.bet) then
				BDON_CONFIG.takeMoney(call, BDON_CONFIG.bet)
			else
				call:ChatPrint("[BLUE'S SLOTS] You cannot afford to play! ("..BDON_CONFIG.CurrenyPrefix..BDON_CONFIG.bet..")")
				return false
			end 

			--Set up game
			self:AddMultiplier(2)
			self:EmitSound("doubleornothing/x1.mp3", 65 * BDON_CONFIG.Volume, 100, 1)

			return
		end

		if shouldSpin and self.userState == true then
			--They want to cash out so check if they can
			if self:GetMultiplier() > 0 then
				self:SetCashOutAmount(self:CalculateWinning())

				self.currentLight = 5
				self:UpdateLights()

				net.Start("bdon:updateScreenEffect")
				net.WriteEntity(self)
				net.WriteFloat(2)
				net.Broadcast()

				--Give the user the money
				BDON_CONFIG.addMoney(call, self:GetCashOutAmount())

				self:EmitSound("doubleornothing/cashout.mp3", 65 * BDON_CONFIG.Volume, 100, 1)

				--Let them know they won
				net.Start("bdn:winninginfo")
				net.WriteInt(self:GetCashOutAmount(), 32)
				net.Send(self.user)

				--Disable spinning and wait 5 seconds 
				self.canSpin = false
				timer.Simple(5, function()
					self.canSpin = true 
					self:SetGameStarted(false)
					self:SetCashOutAmount(0)

					--Tell clients to do the update screen effect
					net.Start("bdon:updateScreenEffect")
					net.WriteEntity(self)
					net.WriteFloat(2)
					net.Broadcast()

					self:SetMultiplier(0)
					self.canSpin = false
					self.currentLight = 2
					self:UpdateLights()
					self:ResetMultiplier()
					self.canSpin = true
				end)
			else
				--Play some kinda sound to let them know it failed
			end

			return
		end

		if shouldSpin and math.random(0, 100) <= BDON_CONFIG.doubleChance then
			if self:GetMultiplier() + 1 == 10 then
				--They won the jackpot!
				self.canSpin = false
				self:PlayJackpot() 
				self:SetMultiplier(10) --Dont add otherwise we get unwarned screen effects
				return 
			end

			self:AddMultiplier()

			--Play the sound
			self:EmitSound("doubleornothing/x"..self:GetMultiplier()..".mp3", 65 * BDON_CONFIG.Volume, 100, 1)

  
			if shouldSpin then
				self.canSpin = false
				timer.Simple(0.5, function()
					self.canSpin = true
				end)
			end
		else
			self:SetGameStarted(true)
			--Tell clients to do the update screen effect
			net.Start("bdon:updateScreenEffect")
			net.WriteEntity(self)
			net.WriteFloat(2)
			net.Broadcast()
			self:SetMultiplier(0)
			self.canSpin = false
			self.currentLight = 4
			self:UpdateLights()

			self:EmitSound("doubleornothing/nothing.mp3", 65 * BDON_CONFIG.Volume, 100, 1)

			timer.Simple(1, function()
				self:ResetMultiplier()
				self.canSpin = true
			end)
		end
	end
end

function ENT:Think()
	if self.user ~= nil then
		if self.user.bdonLastUsedSlot ~= self then
			self.user = nil
			self:UnlinkUser()
			return
		end

		if CurTime() - self.user.bdonTimeSinceLastUse >= 30 then
			self:UnlinkUser()
		end
	end
end

--if a user is linked to the machine it unlinks them.
function ENT:UnlinkUser()
	self:SetGameStarted(false)
	self:SetUserName("Nobody")

	self:SetUserLastInteract(0)

	if self.user ~= nil then
		self.user.bdonLastUsedSlot = nil
		self.user.bdonTimeSinceLastUse = 0
	end
	
	self.userState = false
	self.user = nil

	self:ResetMultiplier()
end

net.Receive("bdn:setselectedbutton", function(len, ply)
	local e = net.ReadEntity()
	local state = net.ReadBool()

	if e ~= nil and e:IsValid() and e:GetClass() == "double_or_nothing" then
		if state ~= nil  and e.user == ply then
			e.userState = state
			e:UpdateLights()
		end
	end
end)


timer.Create("bdon:cleanUpUsedMachines", 1, 0, function()
	for k ,v in pairs(player.GetAll()) do
		if v.bdonTimeSinceLastUse ~= nil and v.bdonLastUsedSlot ~= nil and CurTime() - v.bdonTimeSinceLastUse > 30 then
			v.bdonLastUsedSlot:UnlinkUser()
		end
	end
end)

hook.Add("PlayerInitialSpawn", "bdn:setupmachine", function(ply)
	ply.bdonLastUsedSlot = nil
	ply.bdonTimeSinceLastUse = 0
end)

local function SaveDoubleOrNothingSlots()
	local data = {}
	for k ,v in pairs(ents.FindByClass("double_or_nothing")) do
		table.insert(data, {pos = v:GetPos(), ang = v:GetAngles()})
	end
	if not file.Exists("double_or_nothing" , "DATA") then
		file.CreateDir("double_or_nothing")
	end

	file.Write("double_or_nothing/"..game.GetMap()..".txt", util.TableToJSON(data))
end

local function LoadDoubleOrNothingSlots()
	if file.Exists("double_or_nothing/"..game.GetMap()..".txt" , "DATA") then
		local data = file.Read("double_or_nothing/"..game.GetMap()..".txt", "DATA")
		data = util.JSONToTable(data)
		for k, v in pairs(data) do
			local slot = ents.Create("double_or_nothing")
			slot:SetPos(v.pos)
			slot:SetAngles(v.ang)
			slot:Spawn()
			slot:GetPhysicsObject():EnableMotion(false)
		end
		print("[Blue's Slots] Finished loading DOUBLE OR NOTHING entities.")
	else
		print("[Blue's Slots] No map data found for DOUBLE OR NOTHING entities. Please place some and do !saveslots to create the data.")
	end
end

hook.Add("InitPostEntity", "SpawnDoubleOrNothingSlots", function()
	LoadDoubleOrNothingSlots()
end)

--Handle saving and loading of slots
hook.Add("PlayerSay", "HandleBDONCommands" , function(ply, text)
	if string.sub(string.lower(text), 1, 10) == "!saveslots" then
		if table.HasValue(BDON_CONFIG.AdminRanks, ply:GetUserGroup()) then
			SaveDoubleOrNothingSlots()
			ply:ChatPrint("Double Or Nothing Slot Machines have been saved for the map "..game.GetMap().."!")
		else
			ply:ChatPrint("You do not have permission to perform this action, please contact an admin.")
		end
	end
end)



