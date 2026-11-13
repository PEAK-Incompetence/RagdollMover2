local requestRefreshMessage = "RagdollPoser_Test_RequestRefresh"
local cleanupRefreshMessage = "RagdollPoser_Test_CleanupRefresh"

if SERVER then
	util.AddNetworkString(requestRefreshMessage)
	util.AddNetworkString(cleanupRefreshMessage)

	local testEntities = {}

	net.Receive(requestRefreshMessage, function(_, player)
		local ragdoll = ents.Create("prop_ragdoll")
		ragdoll:SetModel("models/kleiner.mdl")
		ragdoll:Spawn()
		testEntities[player] = ragdoll

		RagdollPoser.Data.RefreshEntities(player, ragdoll, 5, { ragdoll }, {})
	end)

	net.Receive(cleanupRefreshMessage, function(_, player)
		local ragdoll = testEntities[player]
		if IsValid(ragdoll) then
			ragdoll:Remove()
		end
		testEntities[player] = nil
	end)
end

return {
	groupName = "RagdollPoser: Selection refresh",

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
					local entity = RagdollPoser.Entity.GetEntityFromClient(client)

					expect(selection).to.equal(RagdollPoser.Selection:GetSelection())
					expect(bone).to.equal(5)
					expect(client).to.beValid()
					expect(entity).to.beValid()
					---@diagnostic disable-next-line: undefined-global
					done()
				end)

				net.Start(requestRefreshMessage)
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
