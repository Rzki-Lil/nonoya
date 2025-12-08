-- Minimal fishing utilities: detector, selling, and render toggle only
local services = {
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService"),
    HttpService = game:GetService("HttpService"),
    RS = game:GetService("ReplicatedStorage"),
    PG = game:GetService("Players").LocalPlayer.PlayerGui,
    Camera = workspace.CurrentCamera,
    VIM = game:GetService("VirtualInputManager")
}

local player = services.Players.LocalPlayer
if not player then
    return
end

if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
    player.CharacterAdded:Wait():WaitForChild("HumanoidRootPart")
end

local modules = {
    Net = services.RS.Packages._Index["sleitnick_net@0.2.0"].net,
    Replion = require(services.RS.Packages.Replion),
    ItemUtility = require(services.RS.Shared.ItemUtility)
}

local remoteEndpoints = {
    Events = {
        REEquip = modules.Net["RE/EquipToolFromHotbar"],
        REFishDone = modules.Net["RE/FishingCompleted"]
    },
    Functions = {
        Cancel = modules.Net["RF/CancelFishingInputs"]
    }
}

local gameResources = {
    Data = modules.Replion.Client:WaitReplion("Data"),
    Items = services.RS:WaitForChild("Items")
}

local state = {
    player = player,
    char = player.Character or player.CharacterAdded:Wait(),
    stuckThreshold = 15,
    supportEnabled = false,
    autoSellEnabled = false,
    inputSellCount = 50,
    fishingTimer = 0,
    savedCFrame = nil
}

_G.Celestial = _G.Celestial or {}
_G.Celestial.DetectorCount = _G.Celestial.DetectorCount or 0

local function nonoyaNotify(message, duration)
    print("[nonoya]", message)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "nonoya",
            Text = tostring(message),
            Duration = duration or 3
        })
    end)
end

local function getFishCount()
    local bagLabel = state.player.PlayerGui:WaitForChild("Inventory"):WaitForChild("Main"):WaitForChild("Top")
        :WaitForChild("Options"):WaitForChild("Fish"):WaitForChild("Label"):WaitForChild("BagSize")
    return tonumber((bagLabel.Text or "0/???"):match("(%d+)/")) or 0
end

local function getSellableFishCount()
    local data = gameResources.Data
    if not data then
        return 0
    end

    local ok, inventoryItems = pcall(function()
        return data:GetExpect({ "Inventory", "Items" })
    end)

    if not ok or type(inventoryItems) ~= "table" then
        return 0
    end

    local thresholdValue = data:Get("AutoSellThreshold")
    local thresholdTier = tonumber(thresholdValue) or 0
    local sellableCount = 0

    for _, entry in ipairs(inventoryItems) do
        if typeof(entry) == "table" and not entry.Favorited then
            local itemData = modules.ItemUtility.GetItemDataFromItemType("Items", entry.Id)
            if itemData and itemData.Data and itemData.Data.Type == "Fish" then
                local fishTier = tonumber(itemData.Data.Tier) or 0
                if thresholdTier <= 0 or fishTier <= thresholdTier then
                    local qty = tonumber(entry.Quantity)
                    if qty and qty > 1 then
                        sellableCount = sellableCount + qty
                    else
                        sellableCount = sellableCount + 1
                    end
                end
            end
        end
    end

    return sellableCount
end

local function runSellingWithBlatantSync()
    local ok, err = pcall(function()
        local packages = services.RS:WaitForChild("Packages")
        local indexFolder = packages:WaitForChild("_Index")
        local sleitnickFolder = indexFolder:WaitForChild("sleitnick_net@0.2.0")
        local netFolder = sleitnickFolder:WaitForChild("net")
        local sellRemote = netFolder:WaitForChild("RF/SellAllItems")
        sellRemote:InvokeServer()
    end)

    if not ok then
        warn("[nonoya] SellAllItems failed:", err)
    end
end

-- UI
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/Rzki-Lil/nonoya/refs/heads/main/ui.lua"))()
local window = Library:Window({
    Title = "nonoya",
    Footer = "Fishing Only",
    Color = Color3.fromRGB(204, 75, 42),
    TabWidth = 120,
    TabTransparency = 0.2,
    Size = Vector2.new(560, 350)
})

local tab = window:AddTab({ Name = "Fishing" })

-- Fishing detector
local detectorSection = tab:AddSection("Stuck Detector")
local detectorParagraph = detectorSection:AddParagraph({
    Title = "Detector",
    Content = "Status = Idle\nTime = 0.0s\nBag = 0"
})

detectorSection:AddSlider({
    Title = "Wait (s)",
    Default = state.stuckThreshold,
    Min = 10,
    Max = 30,
    Rounding = 0,
    Callback = function(value)
        state.stuckThreshold = value
    end
})

detectorSection:AddToggle({
    Title = "Start Detector",
    Content = "Monitor fishing; respawn + re-equip if stuck.",
    Default = false,
    Callback = function(enabled)
        state.supportEnabled = enabled
        if enabled then
            state.char = state.player.Character or state.player.CharacterAdded:Wait()
            state.savedCFrame = state.char:WaitForChild("HumanoidRootPart").CFrame
            _G.Celestial.DetectorCount = getFishCount()
            state.fishingTimer = 0
            task.spawn(function()
                local statusText, statusColor = "Idle", "255,255,255"
                while state.supportEnabled do
                    local okCount, bagCount = pcall(getFishCount)
                    if not okCount then
                        detectorParagraph:SetContent("<font color='rgb(255,69,0)'>Status = Error Reading Count</font>\nTime = 0.0s\nBag = 0")
                        state.fishingTimer = 0
                        task.wait(1)
                    else
                        task.wait(0.1)
                        state.fishingTimer = state.fishingTimer + 0.1
                        if not state.char or not state.char.Parent then
                            state.char = state.player.Character or state.player.CharacterAdded:Wait()
                        end

                        if _G.Celestial.DetectorCount < bagCount then
                            _G.Celestial.DetectorCount = bagCount
                            state.fishingTimer = 0
                            statusText, statusColor = "Fishing Normally", "0,255,127"
                        elseif bagCount < _G.Celestial.DetectorCount then
                            _G.Celestial.DetectorCount = bagCount
                            statusText, statusColor = "Bag Update", "173,216,230"
                        elseif state.fishingTimer >= (state.stuckThreshold or 10) then
                            statusText, statusColor = "STUCK! Resetting...", "255,69,0"
                            nonoyaNotify("Fishing Stuck! Resetting...", 3)
                            local root = state.char and state.char:FindFirstChild("HumanoidRootPart")
                            if root then
                                state.savedCFrame = root.CFrame
                            end
                            state.player.Character:BreakJoints()
                            state.char = state.player.CharacterAdded:Wait()
                            local newRoot = state.char:WaitForChild("HumanoidRootPart")
                            if state.savedCFrame then
                                newRoot.CFrame = state.savedCFrame
                            end
                            task.wait(0.2)
                            pcall(function()
                                remoteEndpoints.Events.REEquip:FireServer(1)
                            end)
                            state.fishingTimer = 0
                            _G.Celestial.DetectorCount = getFishCount()
                            statusText, statusColor = "Idle", "255,255,255"
                        end

                        detectorParagraph:SetContent(string.format(
                            "<font color='rgb(%s)'>Status = %s</font>\n<font color='rgb(0,191,255)'>Time = %.1fs</font>\n<font color='rgb(173,216,230)'>Bag = %d</font>",
                            statusColor,
                            statusText,
                            state.fishingTimer,
                            bagCount
                        ))
                    end
                end
                detectorParagraph:SetContent("<font color='rgb(200,200,200)'>Status = Detector Offline</font>\nTime = 0.0s\nBag = 0")
            end)
        else
            detectorParagraph:SetContent("<font color='rgb(200,200,200)'>Status = Detector Offline</font>\nTime = 0.0s\nBag = 0")
        end
    end
})

-- Selling
local sellSection = tab:AddSection("Selling")
local sellProgressParagraph = sellSection:AddParagraph({
    Title = "Selling Progress",
    Content = string.format("0/%d", state.inputSellCount)
})

sellSection:AddInput({
    Default = tostring(state.inputSellCount),
    Title = "Sell Count Threshold",
    Content = "Auto sell when sellable fish reach this amount",
    Callback = function(value)
        local desired = tonumber(value) or 0
        if desired < 0 then desired = 0 end
        state.inputSellCount = math.floor(desired)
    end
})

sellSection:AddToggle({
    Title = "Start Selling",
    Default = false,
    Callback = function(enabled)
        state.autoSellEnabled = enabled
        if enabled then
            task.spawn(function()
                while state.autoSellEnabled do
                    local sellable = getSellableFishCount()
                    local target = tonumber(state.inputSellCount) or 0

                    -- try to use bag max as fallback target
                    local bagLabel = state.player:FindFirstChild("PlayerGui")
                    bagLabel = bagLabel and bagLabel:FindFirstChild("Inventory")
                    bagLabel = bagLabel and bagLabel:FindFirstChild("Main")
                    bagLabel = bagLabel and bagLabel:FindFirstChild("Top")
                    bagLabel = bagLabel and bagLabel:FindFirstChild("Options")
                    bagLabel = bagLabel and bagLabel:FindFirstChild("Fish")
                    bagLabel = bagLabel and bagLabel:FindFirstChild("Label")
                    bagLabel = bagLabel and bagLabel:FindFirstChild("BagSize")
                    if bagLabel and bagLabel:IsA("TextLabel") then
                        local _, max = (bagLabel.Text or ""):match("(%d+)%s*/%s*(%d+)")
                        target = target > 0 and target or (tonumber(max) or sellable)
                    end

                    local progress = math.min(sellable, target)
                    if sellProgressParagraph and sellProgressParagraph.SetContent then
                        sellProgressParagraph:SetContent(string.format(
                            "<font color='rgb(173,216,230)'>%d</font>/<font color='rgb(204,75,42)'>%d</font>",
                            progress,
                            target
                        ))
                    end

                    if sellable > 0 and target > 0 and sellable >= target then
                        runSellingWithBlatantSync()
                        task.wait(1.5)
                        local after = getSellableFishCount()
                        if after < progress and sellProgressParagraph and sellProgressParagraph.SetContent then
                            sellProgressParagraph:SetContent(string.format(
                                "<font color='rgb(0,255,127)'>0</font>/<font color='rgb(204,75,42)'>%d</font>",
                                target
                            ))
                        end
                    end

                    task.wait(1)
                end
            end)
        end
    end
})

-- Performance
local renderSection = tab:AddSection("Performance")
local disable3DRendering = false
local function apply3DRendering()
    pcall(function()
        if typeof(services.RunService.Set3dRenderingEnabled) == "function" then
            services.RunService:Set3dRenderingEnabled(not disable3DRendering)
        end
    end)
end

renderSection:AddToggle({
    Title = "Disable 3D Render",
    Content = "Turn off 3D rendering to boost FPS",
    Default = false,
    Callback = function(value)
        disable3DRendering = value
        apply3DRendering()
    end
})

nonoyaNotify("Minimal fishing tab loaded!")
