---Rather than storing multiple network strings, we'll store one and send an index
---
---Net requirements
--- - For every sender, there **must** be a receiver.
--- - Every sender name must be unique.

if SERVER then
	util.AddNetworkString("RagdollPoser")
	util.AddNetworkString("RagdollPoser_AddReceiver")
	util.AddNetworkString("RagdollPoser_AddSender")
end

---@alias NetStarter function
---@alias NetReceiver fun(len: integer, ply: Player)

---[SERVER AND CLIENT]
---
---Networking helpers which bypass the 4096 network string limitation with uints
---
---This module improves on the legacy version by allowing one to define network senders / receivers
---anywhere in the codebase, rather than in one single file.
---
---
---@class RagdollPoser.Networking
---@field SenderToID {[string]: integer}
---@field ReceiverIDToName {[integer]: string}
---@field ReceiverNameToID {[string]: integer}
---@field ReceiverCallbackBuffer {[string]: NetReceiver}
---@field Receivers NetReceiver[]
---@field Senders string[]
local MGR = RagdollPoser.Networking
	or {
		SenderToID = {},
		ReceiverIDToName = {},
		ReceiverNameToID = {},
		ReceiverCallbackBuffer = {},
		Receivers = {},
		Senders = {},
	}

local SenderToID = MGR.SenderToID
local ReceiverIDToName = MGR.ReceiverIDToName
local ReceiverNameToID = MGR.ReceiverNameToID
local ReceiverCallbackBuffer = MGR.ReceiverCallbackBuffer
local Receivers = MGR.Receivers
local Senders = MGR.Senders

---@type NetReceiver
local function empty() end

---@package
---@return integer
function MGR.GetSenderCountBits()
	return math.ceil(math.log(#Senders + 1, 2))
end

---@param name string
---@param count integer
---@param ply Player?
local function sendReceiver(name, count, ply)
	local function send()
		net.Start("RagdollPoser_AddReceiver")
		net.WriteString(name)
		net.WriteUInt(count, 12)
		if SERVER then
			if ply then
				net.Send(ply)
			else
				net.Broadcast()
			end
		else
			net.SendToServer()
		end
	end
	if player.GetCount() > 0 then
		send()
	else
		timer.Simple(0, send)
	end
end

---@param name string
---@return NetStarter
function MGR.DefineSender(name)
	-- print("define sender", name)
	local count = SenderToID[name]
	if not count then
		count = #Senders
		table.insert(Senders, name)
		SenderToID[name] = count
	end
	sendReceiver(name, count, CLIENT and LocalPlayer() or nil)

	---@type NetStarter
	local function netStarter()
		net.Start("RagdollPoser", true)
		net.WriteUInt(count, MGR.GetSenderCountBits())
	end

	return netStarter
end

---@param name string
---@param callback NetReceiver
function MGR.DefineReceiver(name, callback)
	ReceiverCallbackBuffer[name] = callback
	-- Suppose the server/client already defined the network string first,
	-- then give the id to the callback
	-- print("define receiver", name)
	-- PrintTable(ReceiverNameToID)
	if ReceiverNameToID[name] then
		-- print(ReceiverNameToID[name], "defined earlier, so let's set it")
		Receivers[ReceiverNameToID[name]] = callback
	end
end

function MGR.GetNetworkInfo()
	PrintTable(ReceiverCallbackBuffer)
	PrintTable(ReceiverIDToName)
	PrintTable(ReceiverNameToID)
end

---@type NetReceiver
local function addReceiver()
	local name = net.ReadString()
	local id = net.ReadUInt(12)
	-- If we already defined a receiver with a specific name
	-- print("add receiver", name, id)
	if ReceiverCallbackBuffer[name] then
		Receivers[id] = ReceiverCallbackBuffer[name]
	end
	-- Otherwise, store the id of the sender here.
	-- When we define it later, then assign it
	ReceiverIDToName[id] = name
	ReceiverNameToID[name] = id
	-- PrintTable(ReceiverIDToName)
	-- PrintTable(ReceiverNameToID)
	-- PrintTable(ReceiverCallbackBuffer)
end
net.Receive("RagdollPoser_AddReceiver", addReceiver)

---@type NetReceiver
local function netReceiver(len, ply)
	-- print("receive message")
	local index = net.ReadUInt(MGR.GetSenderCountBits())
	-- print(index)
	-- PrintTable(ReceiverNameToID)
	-- PrintTable(ReceiverIDToName)
	-- PrintTable(ReceiverCallbackBuffer)
	if Receivers[index] then
		Receivers[index](len, ply)
	else
		-- print("set it")
		if ReceiverIDToName[index] then
			Receivers[index] = ReceiverCallbackBuffer[ReceiverIDToName[index]]
		else
			Receivers[index] = empty
		end
	end
end
net.Receive("RagdollPoser", netReceiver)

if CLIENT then
	hook.Add("CreateMove", "RagdollPoser_InitializeServerReceiver", function(_)
		-- print("setup")
		net.Start("RagdollPoser_AddSender")
		net.SendToServer()

		hook.Remove("CreateMove", "RagdollPoser_InitializeServerReceiver")
	end)
else
	local function updateClientServerReceivers(len, ply)
		for senderID, senderName in ipairs(Senders) do
			sendReceiver(senderName, senderID - 1, ply)
		end
	end
	net.Receive("RagdollPoser_AddSender", updateClientServerReceivers)
end

RagdollPoser.Networking = MGR
