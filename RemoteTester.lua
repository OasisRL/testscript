--[[
    RemoteTester.lua
    ------------------------------------------------------------
    A Studio/dev-only tool for testing YOUR OWN game's remotes.

    Put this in StarterPlayerScripts as a LocalScript (or run it
    from the Studio command bar while testing) in a place you own.

    What it does:
      * Recursively scans ReplicatedStorage for RemoteEvents and
        RemoteFunctions
      * Builds a simple GUI listing them
      * Lets you type arguments as a Lua table literal, e.g.
            {1, "hello", true}
        and fire the remote with those args
      * Logs what you sent, what a RemoteFunction returned, and
        any OnClientEvent traffic on remotes you've selected to
        watch, into an on-screen console

    This is NOT meant to run against games you don't own/operate.
    It only introspects ReplicatedStorage in the current place.
------------------------------------------------------------------]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------
-- GUI setup
--------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RemoteTesterGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 520, 0, 380)
mainFrame.Position = UDim2.new(0, 20, 0, 20)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 24)
title.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.SourceSansBold
title.TextSize = 16
title.Text = "Remote Tester (own-game dev tool)"
title.Parent = mainFrame

-- Left: scrolling list of remotes
local listFrame = Instance.new("ScrollingFrame")
listFrame.Size = UDim2.new(0, 200, 1, -24)
listFrame.Position = UDim2.new(0, 0, 0, 24)
listFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
listFrame.BorderSizePixel = 0
listFrame.ScrollBarThickness = 6
listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
listFrame.Parent = mainFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Parent = listFrame
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 2)

-- Right: args box, fire button, console
local rightFrame = Instance.new("Frame")
rightFrame.Size = UDim2.new(0, 320, 1, -24)
rightFrame.Position = UDim2.new(0, 200, 0, 24)
rightFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
rightFrame.BorderSizePixel = 0
rightFrame.Parent = mainFrame

local selectedLabel = Instance.new("TextLabel")
selectedLabel.Size = UDim2.new(1, -10, 0, 20)
selectedLabel.Position = UDim2.new(0, 5, 0, 4)
selectedLabel.BackgroundTransparency = 1
selectedLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
selectedLabel.Font = Enum.Font.SourceSansBold
selectedLabel.TextSize = 14
selectedLabel.TextXAlignment = Enum.TextXAlignment.Left
selectedLabel.Text = "Selected: (none)"
selectedLabel.Parent = rightFrame

local argsBox = Instance.new("TextBox")
argsBox.Size = UDim2.new(1, -10, 0, 28)
argsBox.Position = UDim2.new(0, 5, 0, 26)
argsBox.PlaceholderText = 'Args table, e.g. {1, "hello", true}'
argsBox.Text = "{}"
argsBox.ClearTextOnFocus = false
argsBox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
argsBox.TextColor3 = Color3.fromRGB(255, 255, 255)
argsBox.Font = Enum.Font.Code
argsBox.TextSize = 14
argsBox.Parent = rightFrame

local fireButton = Instance.new("TextButton")
fireButton.Size = UDim2.new(0.48, -8, 0, 28)
fireButton.Position = UDim2.new(0, 5, 0, 58)
fireButton.BackgroundColor3 = Color3.fromRGB(60, 120, 60)
fireButton.TextColor3 = Color3.fromRGB(255, 255, 255)
fireButton.Font = Enum.Font.SourceSansBold
fireButton.TextSize = 14
fireButton.Text = "Fire"
fireButton.Parent = rightFrame

local watchButton = Instance.new("TextButton")
watchButton.Size = UDim2.new(0.48, -8, 0, 28)
watchButton.Position = UDim2.new(0.52, 3, 0, 58)
watchButton.BackgroundColor3 = Color3.fromRGB(60, 90, 130)
watchButton.TextColor3 = Color3.fromRGB(255, 255, 255)
watchButton.Font = Enum.Font.SourceSansBold
watchButton.TextSize = 14
watchButton.Text = "Watch OnClientEvent"
watchButton.Parent = rightFrame

local consoleFrame = Instance.new("ScrollingFrame")
consoleFrame.Size = UDim2.new(1, -10, 1, -96)
consoleFrame.Position = UDim2.new(0, 5, 0, 92)
consoleFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
consoleFrame.BorderSizePixel = 0
consoleFrame.ScrollBarThickness = 6
consoleFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
consoleFrame.Parent = rightFrame

local consoleLayout = Instance.new("UIListLayout")
consoleLayout.Parent = consoleFrame
consoleLayout.SortOrder = Enum.SortOrder.LayoutOrder
consoleLayout.Padding = UDim.new(0, 1)

--------------------------------------------------------------------
-- Console logging
--------------------------------------------------------------------

local function log(text, color)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -4, 0, 16)
	label.BackgroundTransparency = 1
	label.TextColor3 = color or Color3.fromRGB(200, 200, 200)
	label.Font = Enum.Font.Code
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Text = os.date("[%H:%M:%S] ") .. tostring(text)
	label.Parent = consoleFrame

	consoleFrame.CanvasSize = UDim2.new(0, 0, 0, consoleLayout.AbsoluteContentSize.Y)
	consoleFrame.CanvasPosition = Vector2.new(0, math.huge)
end

--------------------------------------------------------------------
-- Remote discovery
--------------------------------------------------------------------

local selectedRemote = nil
local watchedConnections = {} -- [remote] = connection

local function selectRemote(remote)
	selectedRemote = remote
	selectedLabel.Text = "Selected: " .. remote:GetFullName()
end

local function scanRemotes()
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	local order = 0
	local function visit(instance)
		for _, child in ipairs(instance:GetChildren()) do
			if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
				order += 1
				local btn = Instance.new("TextButton")
				btn.Size = UDim2.new(1, 0, 0, 26)
				btn.LayoutOrder = order
				btn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
				btn.TextColor3 = Color3.fromRGB(255, 255, 255)
				btn.Font = Enum.Font.SourceSans
				btn.TextSize = 13
				btn.TextXAlignment = Enum.TextXAlignment.Left
				btn.Text = "  [" .. child.ClassName .. "] " .. child.Name
				btn.Parent = listFrame

				btn.MouseButton1Click:Connect(function()
					selectRemote(child)
				end)
			end
			visit(child)
		end
	end

	visit(ReplicatedStorage)
	listFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y)
	log("Scan complete: " .. tostring(order) .. " remote(s) found under ReplicatedStorage.")
end

--------------------------------------------------------------------
-- Arg parsing (Lua table literal -> real table)
--------------------------------------------------------------------

local function parseArgs(text)
	local chunk, err = loadstring("return " .. text)
	if not chunk then
		return nil, "Parse error: " .. tostring(err)
	end
	local ok, result = pcall(chunk)
	if not ok then
		return nil, "Eval error: " .. tostring(result)
	end
	if typeof(result) ~= "table" then
		return nil, "Args must be a table, e.g. {1, \"a\"}"
	end
	return result
end

--------------------------------------------------------------------
-- Fire / watch handlers
--------------------------------------------------------------------

fireButton.MouseButton1Click:Connect(function()
	if not selectedRemote then
		log("No remote selected.", Color3.fromRGB(255, 120, 120))
		return
	end

	local args, err = parseArgs(argsBox.Text)
	if not args then
		log(err, Color3.fromRGB(255, 120, 120))
		return
	end

	if selectedRemote:IsA("RemoteEvent") then
		selectedRemote:FireServer(table.unpack(args))
		log("Fired RemoteEvent " .. selectedRemote.Name .. " with " .. argsBox.Text)
	elseif selectedRemote:IsA("RemoteFunction") then
		local ok, resultOrErr = pcall(function()
			return selectedRemote:InvokeServer(table.unpack(args))
		end)
		if ok then
			log("InvokeServer " .. selectedRemote.Name .. " -> " .. tostring(resultOrErr))
		else
			log("InvokeServer " .. selectedRemote.Name .. " errored: " .. tostring(resultOrErr), Color3.fromRGB(255, 120, 120))
		end
	end
end)

watchButton.MouseButton1Click:Connect(function()
	if not selectedRemote then
		log("No remote selected.", Color3.fromRGB(255, 120, 120))
		return
	end
	if not selectedRemote:IsA("RemoteEvent") then
		log("Watching only applies to RemoteEvents.", Color3.fromRGB(255, 120, 120))
		return
	end
	if watchedConnections[selectedRemote] then
		watchedConnections[selectedRemote]:Disconnect()
		watchedConnections[selectedRemote] = nil
		log("Stopped watching " .. selectedRemote.Name .. ".")
		return
	end

	local conn = selectedRemote.OnClientEvent:Connect(function(...)
		local args = {...}
		local parts = {}
		for _, v in ipairs(args) do
			table.insert(parts, tostring(v))
		end
		log(selectedRemote.Name .. " OnClientEvent: " .. table.concat(parts, ", "), Color3.fromRGB(150, 200, 255))
	end)
	watchedConnections[selectedRemote] = conn
	log("Watching " .. selectedRemote.Name .. " for OnClientEvent traffic.")
end)

--------------------------------------------------------------------
-- Init
--------------------------------------------------------------------

scanRemotes()
log("RemoteTester ready. Select a remote on the left, edit args, then Fire.")
