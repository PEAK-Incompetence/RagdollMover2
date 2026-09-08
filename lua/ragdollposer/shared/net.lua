---Rather than storing multiple network strings, we'll store one and send an index
---
---Net requirements
--- - For every sender, there **must** be a receiver.
--- - Every sender name must be unique. (Can't have define two senders with the same name: `DefineSender("abc")` `DefineSender("abc")` is disallowed)

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
---@field ServerSenderCount integer
---@field ClientSenderCount integer
local MGR = RagdollPoser.Networking
	or {
		SenderToID = {},
		ReceiverIDToName = {},
		ReceiverNameToID = {},
		ReceiverCallbackBuffer = {},
		Receivers = {},
		Senders = {},

		ServerSenderCount = 0,
		ClientSenderCount = 0,
	}

local SenderToID = MGR.SenderToID
local ReceiverIDToName = MGR.ReceiverIDToName
local ReceiverNameToID = MGR.ReceiverNameToID
local ReceiverCallbackBuffer = MGR.ReceiverCallbackBuffer
local Receivers = MGR.Receivers
local Senders = MGR.Senders

local function empty() end

---Use this for net.Send operations
---@package
---@return integer senderCountBits
function MGR.GetSenderCountBits()
	local count = math.ceil(math.log(#Senders + 1, 2))
	return count
end

---Use this for net.Receive operations
---@package
---@return integer receiverCountBits
function MGR.GetReceiverCountBits()
	local count = math.ceil(math.log((SERVER and MGR.ClientSenderCount or MGR.ServerSenderCount) + 1, 2))
	return count
end

---@param name string
---@param count integer
---@param ply Player?
local function sendReceiver(name, count, ply)
	local function send()
		net.Start("RagdollPoser_AddReceiver")
		net.WriteString(name)
		-- print("send receiver", count)
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

---Start a net message by calling a function instead of `net.Start("message")`
---
---What this does is remove bypass the 4096 net message limit using an unsigned integer. This ensures compatibility with other addons.
---
---Usage:
---```lua
--- -- In server/client
---	local senderMessage = RagdollPoser.Networking.DefineSender("MyMessage")
---
--- -- some code later
---
--- senderMessage()
--- net.WriteVector(v)
--- net.Send(ply)
---```
---@param name string
---@return NetStarter netStarterHeader
function MGR.DefineSender(name)
	-- print("define sender", name)
	local count = SenderToID[name]
	if not count then
		count = #Senders
		table.insert(Senders, name)
		SenderToID[name] = count
	end
	sendReceiver(name, count, CLIENT and LocalPlayer() or nil)

	local function netStarter()
		-- print(count, name)
		net.Start("RagdollPoser", true)
		net.WriteUInt(count, MGR.GetSenderCountBits())
	end

	return netStarter
end

---Receive a message from the other realm. It works like `net.Receive`, but it handles the net message ids underneath.
---
---Usage (this continues off from `DefineSender`):
---```lua
--- RagdollPoser.Networking.DefineReceiver("MyMessage", function(len, ply)
--- 	local v = net.ReadVector(v)
--- end)
---```
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

---Debugging function
function MGR.GetNetworkInfo()
	PrintTable(ReceiverCallbackBuffer)
	PrintTable(ReceiverIDToName)
	PrintTable(ReceiverNameToID)
end

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

	-- We always increment server / client counts, so everytime we get a receiver, we're monotonically increasing our counts
	if SERVER then
		MGR.ClientSenderCount = id + 1
	else
		MGR.ServerSenderCount = id + 1
	end
end
net.Receive("RagdollPoser_AddReceiver", addReceiver)

---General net receiving function which handles the id handling
local function netReceiver(len, ply)
	-- print("receive message")
	-- If receiving from client, get ClientSenderCount; otherwise, get ServerSenderCount
	local index = net.ReadUInt(MGR.GetReceiverCountBits())
	-- print("index", index)
	-- print("receiver id to name", ReceiverIDToName[index])
	-- PrintTable(ReceiverNameToID)
	-- PrintTable(ReceiverIDToName)
	-- PrintTable(ReceiverCallbackBuffer)

	-- This will only happen when the client does not have any info about the server immediately, such as on hooks like
	-- `OnEntityCreated` during server startup. You'll have to wait until after this server loads for you to get entity
	-- info
	if not index then
		return
	end
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
