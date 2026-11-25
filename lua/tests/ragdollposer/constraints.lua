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
	groupName = "RagdollPoser: Constraints",

	cases = {
		{
			clientside = true,
			async = true,
			timeout = 30,
			name = "Add and move base constraints",
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

					local types = { "ik", "lockpos", "lockang", "lockscale" }
					local bones = {
						"ValveBiped.Bip01_L_Foot",
						"ValveBiped.Bip01_Head1",
						"ValveBiped.Bip01_Spine2",
						"ValveBiped.Bip01_Neck1",
					}

					-- Add a bunch of constraints
					local cm = RagdollPoser.Constraints
					for i = 1, 4 do
						---@type ConstraintState
						local state = {
							bone = entity:LookupBone(bones[i]),
							enabled = true,
							influence = 1,
							key = 0,
							target = entity,
						}
						expect(cm.Push, cm, entity, types[i], state).to.succeed()
					end

					-- Expect the stack to have constraints
					-- if not, then the constraint construction has failed
					local stack = cm:GetConstraintStack(entity)
					expect(#stack).to.equal(4)
					for i = 1, 4 do
						expect(stack[i]).to.exist()
						expect(stack[i].Owner).to.equal(entity)
						expect(stack[i].Properties.type).to.equal(types[i])
					end

					-- Finally, check that the constraints work
					local gizmo = RagdollPoser.Gizmo
					gizmo._gizmoIndex = 1 -- Hover over the first gizmo
					expect(gizmo.OnModeChanged, gizmo, gizmo.Mode.Translation).to.succeed()
					expect(gizmo.PreTransform, gizmo).to.succeed()
					expect(gizmo.Transform, gizmo).to.succeed()
					expect(gizmo.PostTransform, gizmo).to.succeed()

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
		-- {
		-- 	clientside = true,
		-- 	async = true,
		-- 	timeout = 30,
		-- 	name = "Add and move bonemerge constraint",
		-- 	func = function()
		-- 		local unselecting = true
		-- 		RagdollPoser.Selection:Unselect()
		-- 		unselecting = false

		-- 		hook.Add("RagdollPoser_Selection_Selected", "RagdollPoser_Test_Selection", function(selection)
		-- 			if RagdollPoser.Selection:IsRefreshing() or unselecting then
		-- 				return
		-- 			end
		-- 			local bone = selection[1]
		-- 			local client = selection[2] --[[@as ClientEntity]]
		-- 			local entity = RagdollPoser.Entity:GetEntityFromClient(client)

		-- 			expect(selection).to.equal(RagdollPoser.Selection:GetSelection())
		-- 			expect(bone).to.equal(5)
		-- 			expect(client).to.beValid()
		-- 			expect(entity).to.beValid()

		-- 			local cm = RagdollPoser.Constraints
		-- 			---@type ConstraintState
		-- 			local state = {
		-- 				bone = 0,
		-- 				enabled = true,
		-- 				influence = 1,
		-- 				key = 0,
		-- 				target = entity,
		--                 otherTarget = bonemergeEntity
		-- 			}
		-- 			expect(cm.Push, cm, entity, "bonemerge", state).to.succeed()

		-- 			local gizmo = RagdollPoser.Gizmo
		-- 			gizmo._gizmoIndex = 1 -- Hover over the first gizmo
		-- 			expect(gizmo.OnModeChanged, gizmo, gizmo.Mode.Translation).to.succeed()
		-- 			expect(gizmo.PreTransform, gizmo).to.succeed()
		-- 			expect(gizmo.Transform, gizmo).to.succeed()
		-- 			expect(gizmo.PostTransform, gizmo).to.succeed()

		-- 			---@diagnostic disable-next-line: undefined-global
		-- 			done()
		-- 		end)

		-- 		net.Start(requestSingleMessage)
		-- 		net.SendToServer()
		-- 	end,
		-- 	cleanup = function()
		-- 		hook.Remove("RagdollPoser_Selection_Selected", "RagdollPoser_Test_Selection")
		-- 		RagdollPoser.Selection:Unselect()

		-- 		net.Start(cleanupRefreshMessage)
		-- 		net.SendToServer()
		-- 	end,
		-- },
	},
}
