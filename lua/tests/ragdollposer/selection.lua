local requestSingleMessage = "RagdollPoser_Test_RequestSingleEntity"
local requestMultipleMessage = "RagdollPoser_Test_RequestMultipleEntity"
local cleanupRefreshMessage = "RagdollPoser_Test_CleanupRefresh"

if SERVER then
	util.AddNetworkString(requestSingleMessage)
	util.AddNetworkString(requestMultipleMessage)
	util.AddNetworkString(cleanupRefreshMessage)

	local testEntities = {}

	net.Receive(requestSingleMessage, function(_, player)
		local ragdoll = ents.Create("prop_ragdoll")
		ragdoll:SetModel("models/kleiner.mdl")
		ragdoll:Spawn()
		testEntities[player] = { ragdoll }

		RagdollPoser.Data:RefreshEntities(player, ragdoll, 5, { ragdoll }, {})
	end)

	net.Receive(requestMultipleMessage, function(_, player)
		---@type Entity[]
		local ragdolls = {}
		for i = 1, 4 do
			local ragdoll = ents.Create("prop_ragdoll")
			ragdoll:SetModel("models/kleiner.mdl")
			ragdoll:Spawn()
			ragdolls[i] = ragdoll
		end
		testEntities[player] = ragdolls

		RagdollPoser.Data:RefreshEntities(player, ragdolls[1], 5, ragdolls, {})
	end)

	net.Receive(cleanupRefreshMessage, function(_, player)
		local ragdolls = testEntities[player]
		for _, ragdoll in ipairs(ragdolls) do
			if IsValid(ragdoll) then
				ragdoll:Remove()
			end
		end
		testEntities[player] = nil
	end)
end

--- @type GLuaTest_TestGroup
return {
	groupName = "RagdollPoser: Selection",

	cases = {
		{
			clientside = true,
			async = true,
			timeout = 30,
			name = "Select an entity on the next client tick",
			func = function()
				local unselecting = true
				RagdollPoser.Selection:Unselect()
				unselecting = false

				hook.Add("RagdollPoser_Selection_Selected", "RagdollPoser_Test_Selection", function(selection)
					if RagdollPoser.Selection:IsRefreshing() or unselecting then
						return
					end
					local bone = selection[1]
					local client = selection[2] --[[@as ClientEntity]]
					local entity = RagdollPoser.Entity:GetEntityFromClient(client)

					expect(selection).to.equal(RagdollPoser.Selection:GetSelection())
					expect(bone).to.equal(5)
					expect(client).to.beValid()
					expect(entity).to.beValid()
					---@diagnostic disable-next-line: undefined-global
					done()
				end)

				net.Start(requestSingleMessage)
				net.SendToServer()
			end,
			cleanup = function()
				hook.Remove("RagdollPoser_Selection_Selected", "RagdollPoser_Test_Selection")
				RagdollPoser.Selection:Unselect()

				net.Start(cleanupRefreshMessage)
				net.SendToServer()
			end,
		},
		{
			clientside = true,
			async = true,
			timeout = 30,
			name = "Select multiple entities on the next client tick",
			func = function()
				local unselecting = true
				RagdollPoser.Selection:Unselect()
				unselecting = false

				timer.Simple(0, function()
					local clientEntities = RagdollPoser.Entity:GetClientEntities()
					for i, clientEntity in ipairs(clientEntities) do
						RagdollPoser.Selection:SelectOne(i, clientEntity, true)
					end
					---@diagnostic disable-next-line: undefined-global
					done()
				end)
				hook.Add("RagdollPoser_Selection_Selected", "RagdollPoser_Test_Selection", function(selection)
					if RagdollPoser.Selection:IsRefreshing() or unselecting then
						return
					end
					-- Selection is always filled with an even number of entities
					expect(#selection * 0.5).to.equal(4)
					for i = 1, #selection - 1, 2 do
						local bone = selection[i]
						local client = selection[i + 1] --[[@as ClientEntity]]
						local entity = RagdollPoser.Entity:GetEntityFromClient(client)

						expect(selection).to.equal(RagdollPoser.Selection:GetSelection())
						expect(bone).to.equal(i)
						expect(client).to.beValid()
						expect(entity).to.beValid()
					end
				end)

				net.Start(requestMultipleMessage)
				net.SendToServer()
			end,
			cleanup = function()
				hook.Remove("RagdollPoser_Selection_Selected", "RagdollPoser_Test_Selection")
				RagdollPoser.Selection:Unselect()

				net.Start(cleanupRefreshMessage)
				net.SendToServer()
			end,
		},
	},
}
