print("success")
local players = game:GetService("Players")
local player = players.LocalPlayer
local playerui = player:WaitForChild("PlayerGui")
local debounce = false
--screengui
local gui = Instance.new("ScreenGui")
gui.Parent = playerui


--mainframe
local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(0,0)
frame.Position = UDim2.new(0.783, 0,0.501, 0)
frame.Size = UDim2.new(0, 203, 0, 364)
frame.BackgroundColor3 = Color3.fromRGB(44, 44, 44)
frame.Name = "Frame"
frame.Visible = true
frame.Parent = gui
-- frame ui corner
local uicor1 = Instance.new("UICorner")
uicor1.Parent = frame
uicor1.CornerRadius = UDim.new(0,8)


-- userinput
local userinput = Instance.new("TextBox")
userinput.PlaceholderText = "Username"
userinput.Parent = frame
userinput.Name = "user"
userinput.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
userinput.AnchorPoint = Vector2.new(0,0)
userinput.Position = UDim2.new(0.103,0,0.066,0)
userinput.Size = UDim2.new(0,161,0,50)
userinput.Font = "Ubuntu"
userinput.TextColor3 = Color3.fromRGB(178,178,178)
userinput.PlaceholderColor3 = Color3.fromRGB(178,178,178)
userinput.TextSize = 30
userinput.TextWrapped = true
userinput.TextScaled = true
--userinput uicorner
local uicor2 = Instance.new("UICorner")
uicor2.Parent = userinput
uicor2.CornerRadius = UDim.new(0,8)


--teleport button
local tpbut = Instance.new("TextButton")
tpbut.Parent = frame
tpbut.AnchorPoint = Vector2.new(0,0)
tpbut.Size = UDim2.new(0,161,0,50)
tpbut.Position = UDim2.new(0.103,0,0.249,0)
tpbut.BackgroundColor3 = Color3.fromRGB(22,22,22)
tpbut.Text = "Teleport"
tpbut.TextColor3 = Color3.fromRGB(170,0,0)
tpbut.TextSize = 30
tpbut.Font = "Ubuntu"
--tpbut uicorner
local uicor3 = Instance.new("UICorner")
uicor3.Parent = tpbut
uicor3.CornerRadius = UDim.new(0,8)


--rape button
local rape = Instance.new("TextButton")
rape.Parent = frame
rape.AnchorPoint = Vector2.new(0,0)
rape.Size = UDim2.new(0,161,0,50)
rape.Position = UDim2.new(0.103,0,0.431,0)
rape.BackgroundColor3 = Color3.fromRGB(22,22,22)
rape.Text = "Rape"
rape.TextColor3 = Color3.fromRGB(170,0,0)
rape.TextSize = 30
rape.Font = "Ubuntu"
--tpbut uicorner
local uicor4 = Instance.new("UICorner")
uicor4.Parent = rape
uicor4.CornerRadius = UDim.new(0,8)


--bypass button
local bypass = Instance.new("TextButton")
bypass.Parent = frame
bypass.AnchorPoint = Vector2.new(0,0)
bypass.Size = UDim2.new(0,161,0,50)
bypass.Position = UDim2.new(0.103,0,0.616,0)
bypass.BackgroundColor3 = Color3.fromRGB(22,22,22)
bypass.Text = "Bypasser"
bypass.TextColor3 = Color3.fromRGB(170,0,0)
bypass.TextSize = 30
bypass.Font = "Ubuntu"
--tpbut uicorner
local uicor5 = Instance.new("UICorner")
uicor5.Parent = bypass
uicor5.CornerRadius = UDim.new(0,8)


--fisch button
local fisch = Instance.new("TextButton")
fisch.Parent = frame
fisch.AnchorPoint = Vector2.new(0,0)
fisch.Size = UDim2.new(0,161,0,50)
fisch.Position = UDim2.new(0.103,0,0.8,0)
fisch.BackgroundColor3 = Color3.fromRGB(22,22,22)
fisch.Text = "Fisch"
fisch.TextColor3 = Color3.fromRGB(170,0,0)
fisch.TextSize = 30
fisch.Font = "Ubuntu"
--tpbut uicorner
local uicor6 = Instance.new("UICorner")
uicor6.Parent = fisch
uicor6.CornerRadius = UDim.new(0,8)

wait(1)

--teleport function
tpbut.MouseButton1Click:Connect(function()
	local victimInput = userinput.Text
	local localplr = game.Players.LocalPlayer.Name
	local target = game.Workspace[localplr].HumanoidRootPart
	local victim = game.Workspace[victimInput].HumanoidRootPart
	wait(1)
	target.CFrame = victim.CFrame - Vector3.new(0,0,3)
end)

--sexually molest and rape someone until they cum and bust all over the walls then do it over and over again molesting
--them over and over again against their will
--[[tpbut.MouseButton1Click:Connect(function()
	if debounce == false then
		debounce = true
		local victimInput = userinput.Text
		local localplr = game.Players.LocalPlayer.Name
		local target = game.Workspace[localplr].HumanoidRootPart
		local victim = game.Workspace[victimInput].HumanoidRootPart
		repeat until debounce == false do
			target.CFrame = victim.CFrame - Vector3.new(0,0,3)
			wait(0.1)
			target.CFrame = victim.CFrame - Vector3.new(0,0,1)
		end
		
	else
		local debounce = false
	end
end)]]--
