local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local gameName = tostring(game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name)
gameName = gameName:gsub("[^%w_ ]", "")
gameName = gameName:gsub("%s+", "_")

local configFolder = "nonoya/Config/" .. gameName
local legacyConfigFile = "nonoya/Config/nonoya_" .. gameName .. ".json"
local configIndexFile = configFolder .. "/_config_index.json"
local defaultConfigName = "autosave"
local currentConfigName = defaultConfigName

ConfigData = {}
Elements = {}
CURRENT_VERSION = nil

local autoSaveEnabled = true
local autoLoadEnabled = true

local function sanitizeConfigName(name)
    if not name then
        return nil
    end
    local trimmed = tostring(name):gsub("^%s*(.-)%s*$", "%1")
    trimmed = trimmed:gsub("[^%w%._%- ]", "")
    trimmed = trimmed:gsub("%s+", "_")
    if trimmed == "" then
        return nil
    end
    return trimmed
end

local function ensureConfigFolder()
    if not isfolder("nonoya") then
        makefolder("nonoya")
    end
    if not isfolder("nonoya/Config") then
        makefolder("nonoya/Config")
    end
    if not isfolder(configFolder) then
        makefolder(configFolder)
    end
end

ensureConfigFolder()

local function getConfigFilePath(name)
    local safe = sanitizeConfigName(name) or defaultConfigName
    return configFolder .. "/" .. safe .. ".json"
end

local function readConfigIndex()
    if not isfile or not readfile or not isfile(configIndexFile) then
        return {}
    end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(configIndexFile))
    end)
    if ok and type(data) == "table" then
        local list = {}
        local seen = {}
        for _, name in ipairs(data) do
            if type(name) == "string" and name ~= "" and not seen[name] then
                seen[name] = true
                table.insert(list, name)
            end
        end
        return list
    end
    return {}
end

local function writeConfigIndex(list)
    if not writefile then
        return false
    end
    ensureConfigFolder()
    local ok = pcall(function()
        writefile(configIndexFile, HttpService:JSONEncode(list or {}))
    end)
    return ok
end

local function updateConfigIndex(configName, remove)
    local safe = sanitizeConfigName(configName)
    if not safe then
        return
    end
    local list = readConfigIndex()
    local exists = false
    for i, name in ipairs(list) do
        if name == safe then
            exists = true
            if remove then
                table.remove(list, i)
            end
            break
        end
    end
    if not remove and not exists then
        table.insert(list, safe)
    end
    table.sort(list, function(a, b)
        return tostring(a):lower() < tostring(b):lower()
    end)
    writeConfigIndex(list)
end

function SaveConfig(configName, opts)
    opts = opts or {}
    local targetName = sanitizeConfigName(configName) or currentConfigName or defaultConfigName
    currentConfigName = targetName
    ConfigData._version = CURRENT_VERSION

    if not autoSaveEnabled and not opts.force then
        return false, "autosave disabled"
    end

    if not writefile then
        return false, "writefile unavailable"
    end

    ensureConfigFolder()
    local path = getConfigFilePath(targetName)
    writefile(path, HttpService:JSONEncode(ConfigData))
    updateConfigIndex(targetName, false)
    return true, path
end

function LoadConfigFromFile(configName, opts)
    opts = opts or {}
    if not CURRENT_VERSION then
        return false
    end

    local targetName = sanitizeConfigName(configName) or currentConfigName or defaultConfigName
    local path = getConfigFilePath(targetName)
    local pathToUse = path

    if opts.allowLegacy ~= false and (not (isfile and isfile(path))) and isfile and isfile(legacyConfigFile) then
        pathToUse = legacyConfigFile
    end

    currentConfigName = targetName

    if isfile and isfile(pathToUse) then
        local success, result = pcall(function()
            return HttpService:JSONDecode(readfile(pathToUse))
        end)
        if success and type(result) == "table" and result._version == CURRENT_VERSION then
            ConfigData = result
            return true, targetName
        end
    end

    ConfigData = { _version = CURRENT_VERSION }
    return false, targetName
end

function ListConfigs()
    local configs = {}
    if listfiles and isfolder and isfolder(configFolder) then
        for _, filePath in ipairs(listfiles(configFolder)) do
            local name = filePath:match("([^/\\]+)%.json$")
            if name and name ~= "_config_index" then
                table.insert(configs, name)
            end
        end
    end
    if #configs == 0 then
        configs = readConfigIndex()
    else
        writeConfigIndex(configs)
    end
    table.sort(configs, function(a, b)
        return tostring(a):lower() < tostring(b):lower()
    end)
    return configs
end

function DeleteConfig(configName)
    local targetName = sanitizeConfigName(configName)
    if not targetName then
        return false
    end
    local path = getConfigFilePath(targetName)
    if delfile and isfile and isfile(path) then
        delfile(path)
        updateConfigIndex(targetName, true)
        return true
    end
    return false
end

function SetConfigName(configName)
    local safe = sanitizeConfigName(configName)
    if safe then
        currentConfigName = safe
    end
    return currentConfigName
end

function GetCurrentConfigName()
    return currentConfigName
end

function LoadConfigElements()
    for key, element in pairs(Elements) do
        if ConfigData[key] ~= nil and element.Set then
            element:Set(ConfigData[key], true)
        end
    end
end


local UserInputService = game:GetService("UserInputService")
local LocalPlayer = game:GetService("Players").LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local CoreGui = game:GetService("CoreGui")
local function isMobileDevice()
    return UserInputService.TouchEnabled
        and not UserInputService.KeyboardEnabled
        and not UserInputService.MouseEnabled
end

local isMobile = isMobileDevice()

local activeDragCaptures = 0
local function updateModalState()
    UserInputService.ModalEnabled = activeDragCaptures > 0
end

local function beginInputCapture()
    activeDragCaptures = activeDragCaptures + 1
    updateModalState()
end

local function endInputCapture()
    if activeDragCaptures > 0 then
        activeDragCaptures = activeDragCaptures - 1
    end
    if activeDragCaptures < 0 then
        activeDragCaptures = 0
    end
    updateModalState()
end

local function getWindowDimensions()
    if isMobile then
        return 360, 290
    end
    return 640, 420
end

local function centerWindowOnScreen(holder)
    if not holder then
        return
    end
    holder.AnchorPoint = Vector2.new(0.5, 0.5)
    holder.Position = UDim2.new(0.5, 0, 0.5, 0)
end

local function MakeDraggable(topbarobject, object, onMove)
    local function CustomPos(topbarobject, object)
        local Dragging, DragInput, DragStart, StartPosition

        local function UpdatePos(input)
            local Delta = input.Position - DragStart
            local pos = UDim2.new(
                StartPosition.X.Scale,
                StartPosition.X.Offset + Delta.X,
                StartPosition.Y.Scale,
                StartPosition.Y.Offset + Delta.Y
            )
            object.Position = pos
            if onMove then
                onMove(pos)
            end
        end

        topbarobject.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                Dragging = true
                DragStart = input.Position
                StartPosition = object.Position
                beginInputCapture()
                local releaseConnection
                releaseConnection = input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        Dragging = false
                        endInputCapture()
                        if releaseConnection then
                            releaseConnection:Disconnect()
                            releaseConnection = nil
                        end
                    end
                end)
            end
        end)

        topbarobject.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                DragInput = input
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if input == DragInput and Dragging then
                UpdatePos(input)
            end
        end)
    end

    local function CustomSize(object)
        local Dragging, DragInput, DragStart, StartSize

        local minSizeX, minSizeY
        local defSizeX, defSizeY

        if isMobile then
            minSizeX, minSizeY = 100, 100
            defSizeX, defSizeY = 470, 270
        else
            minSizeX, minSizeY = 100, 100
            defSizeX, defSizeY = 640, 400
        end

        object.Size = UDim2.new(0, defSizeX, 0, defSizeY)

        local changesizeobject = Instance.new("Frame")
        changesizeobject.AnchorPoint = Vector2.new(1, 1)
        changesizeobject.BackgroundTransparency = 1
        changesizeobject.Size = UDim2.new(0, 40, 0, 40)
        changesizeobject.Position = UDim2.new(1, 20, 1, 20)
        changesizeobject.Name = "changesizeobject"
        changesizeobject.Parent = object

        local function UpdateSize(input)
            local Delta = input.Position - DragStart
            local newWidth = StartSize.X.Offset + Delta.X
            local newHeight = StartSize.Y.Offset + Delta.Y

            newWidth = math.max(newWidth, minSizeX)
            newHeight = math.max(newHeight, minSizeY)

            object.Size = UDim2.new(0, newWidth, 0, newHeight)
        end

        changesizeobject.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                Dragging = true
                DragStart = input.Position
                StartSize = object.Size
                beginInputCapture()
                local releaseConnection
                releaseConnection = input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        Dragging = false
                        endInputCapture()
                        if releaseConnection then
                            releaseConnection:Disconnect()
                            releaseConnection = nil
                        end
                    end
                end)
            end
        end)

        changesizeobject.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                DragInput = input
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if input == DragInput and Dragging then
                UpdateSize(input)
            end
        end)
    end

    CustomSize(object)
    CustomPos(topbarobject, object)
end

function CircleClick()
    -- intentionally left blank to keep interactions snappy without extra effects
end

local nonoya = {}
function nonoya:MakeNotify(NotifyConfig)
    local NotifyConfig = NotifyConfig or {}
    NotifyConfig.Title = NotifyConfig.Title or "nonoya"
    NotifyConfig.Description = NotifyConfig.Description or "Notification"
    NotifyConfig.Content = NotifyConfig.Content or "Content"
    NotifyConfig.Color = NotifyConfig.Color or Color3.fromRGB(255, 0, 255)
    NotifyConfig.Delay = NotifyConfig.Delay or 5

    local NotifyFunction = {}

    spawn(function()
        if not CoreGui:FindFirstChild("NotifyGui") then
            local NotifyGui = Instance.new("ScreenGui")
            NotifyGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            NotifyGui.Name = "NotifyGui"
            NotifyGui.Parent = CoreGui
        end

        if not CoreGui.NotifyGui:FindFirstChild("NotifyLayout") then
            local NotifyLayout = Instance.new("Frame")
            NotifyLayout.AnchorPoint = Vector2.new(1, 1)
            NotifyLayout.BackgroundTransparency = 1
            NotifyLayout.BorderSizePixel = 0
            NotifyLayout.Position = UDim2.new(1, -30, 1, -30)
            NotifyLayout.Size = UDim2.new(0, 320, 1, 0)
            NotifyLayout.Name = "NotifyLayout"
            NotifyLayout.Parent = CoreGui.NotifyGui

            local function realign()
                local Count = 0
                for _, child in ipairs(CoreGui.NotifyGui.NotifyLayout:GetChildren()) do
                    if child:IsA("Frame") then
                        child.Position = UDim2.new(0, 0, 1, -((child.Size.Y.Offset + 12) * Count))
                        Count = Count + 1
                    end
                end
            end

            NotifyLayout.ChildAdded:Connect(realign)
            NotifyLayout.ChildRemoved:Connect(realign)
        end

        local NotifyPosHeight = 0
        for _, v in CoreGui.NotifyGui.NotifyLayout:GetChildren() do
            if v:IsA("Frame") then
                NotifyPosHeight = -(v.Position.Y.Offset) + v.Size.Y.Offset + 12
            end
        end

        local NotifyFrame = Instance.new("Frame")
        NotifyFrame.BackgroundTransparency = 1
        NotifyFrame.BorderSizePixel = 0
        NotifyFrame.Size = UDim2.new(1, 0, 0, 90)
        NotifyFrame.Name = "NotifyFrame"
        NotifyFrame.Parent = CoreGui.NotifyGui.NotifyLayout
        NotifyFrame.AnchorPoint = Vector2.new(0, 1)
        NotifyFrame.Position = UDim2.new(0, 0, 1, -(NotifyPosHeight))

        local Card = Instance.new("Frame")
        Card.BackgroundColor3 = Color3.fromRGB(26, 30, 43)
        Card.BorderSizePixel = 0
        Card.Position = UDim2.new(0, 4, 0, 0)
        Card.Size = UDim2.new(1, -8, 1, -4)
        Card.Name = "NotifyCard"
        Card.Parent = NotifyFrame

        local CardCorner = Instance.new("UICorner")
        CardCorner.CornerRadius = UDim.new(0, 8)
        CardCorner.Parent = Card

        local Header = Instance.new("Frame")
        Header.BackgroundColor3 = Color3.fromRGB(34, 39, 54)
        Header.BorderSizePixel = 0
        Header.Size = UDim2.new(1, 0, 0, 40)
        Header.Name = "Header"
        Header.Parent = Card

        local Title = Instance.new("TextLabel")
        Title.Font = Enum.Font.GothamBold
        Title.Text = NotifyConfig.Title
        Title.TextColor3 = Color3.fromRGB(248, 248, 248)
        Title.TextSize = 14
        Title.TextXAlignment = Enum.TextXAlignment.Left
        Title.BackgroundTransparency = 1
        Title.Size = UDim2.new(1, -80, 0, 20)
        Title.Position = UDim2.new(0, 10, 0, 4)
        Title.Parent = Header

        local Subtitle = Instance.new("TextLabel")
        Subtitle.Font = Enum.Font.Gotham
        Subtitle.Text = NotifyConfig.Description
        Subtitle.TextColor3 = NotifyConfig.Color
        Subtitle.TextSize = 12
        Subtitle.TextXAlignment = Enum.TextXAlignment.Left
        Subtitle.BackgroundTransparency = 1
        Subtitle.Size = UDim2.new(1, -80, 0, 16)
        Subtitle.Position = UDim2.new(0, 10, 0, 20)
        Subtitle.Parent = Header

        local Close = Instance.new("TextButton")
        Close.Font = Enum.Font.GothamBold
        Close.Text = "×"
        Close.TextColor3 = Color3.fromRGB(230, 230, 230)
        Close.TextSize = 18
        Close.AnchorPoint = Vector2.new(1, 0.5)
        Close.BackgroundColor3 = Color3.fromRGB(42, 48, 63)
        Close.BackgroundTransparency = 0.3
        Close.BorderSizePixel = 0
        Close.Position = UDim2.new(1, -8, 0.5, 0)
        Close.Size = UDim2.new(0, 32, 0, 26)
        Close.Name = "Close"
        Close.Parent = Header

        local CloseCorner = Instance.new("UICorner")
        CloseCorner.CornerRadius = UDim.new(0, 6)
        CloseCorner.Parent = Close

        local Body = Instance.new("TextLabel")
        Body.Font = Enum.Font.Gotham
        Body.Text = NotifyConfig.Content
        Body.TextColor3 = Color3.fromRGB(224, 224, 224)
        Body.TextSize = 13
        Body.TextXAlignment = Enum.TextXAlignment.Left
        Body.TextYAlignment = Enum.TextYAlignment.Top
        Body.BackgroundTransparency = 1
        Body.Position = UDim2.new(0, 10, 0, 48)
        Body.Size = UDim2.new(1, -20, 0, 40)
        Body.AutomaticSize = Enum.AutomaticSize.Y
        Body.TextWrapped = true
        Body.RichText = true
        Body.Name = "Body"
        Body.Parent = Card

        local function resize()
            local totalHeight = math.max(64, Body.AbsoluteSize.Y + 58)
            NotifyFrame.Size = UDim2.new(1, 0, 0, totalHeight)
            Card.Size = UDim2.new(1, -8, 0, totalHeight - 4)
        end

        resize()
        Body:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)

        local waitbruh = false
        function NotifyFunction:Close()
            if waitbruh then
                return false
            end
            waitbruh = true
            if NotifyFrame then
                NotifyFrame:Destroy()
            end
        end

        Close.Activated:Connect(function()
            NotifyFunction:Close()
        end)

        local delayTime = tonumber(NotifyConfig.Delay) or 5
        task.delay(delayTime, function()
            NotifyFunction:Close()
        end)
    end)

    return NotifyFunction
end

function nonoyaNotify(msg, delay, color, title, desc)
    return nonoya:MakeNotify({
        Title = title or "nonoya",
        Description = desc or "Notification",
        Content = msg or "Content",
        Color = color or Color3.fromRGB(204, 75, 42),
        Delay = delay or 4
    })
end

function nonoya:Window(GuiConfig)
    GuiConfig              = GuiConfig or {}
    GuiConfig.Title       = GuiConfig.Title or "nonoya"
    GuiConfig.Footer      = GuiConfig.Footer or "nonoya"
    GuiConfig.Color       = GuiConfig.Color or Color3.fromRGB(255, 0, 255)
    GuiConfig.Version     = GuiConfig.Version or 1
    GuiConfig.ToggleText  = GuiConfig.ToggleText or "NN"
    GuiConfig.TabWidth    = GuiConfig.TabWidth or 180
    GuiConfig.MainTransparency = GuiConfig.MainTransparency or 0
    GuiConfig.TabTransparency = GuiConfig.TabTransparency or 0
    GuiConfig.ContentTransparency = GuiConfig.ContentTransparency or 0
    GuiConfig.Size = GuiConfig.Size or nil
    GuiConfig.Width = GuiConfig.Width or nil
    GuiConfig.Height = GuiConfig.Height or nil
    GuiConfig.AutoSave = GuiConfig.AutoSave ~= false
    GuiConfig.AutoLoad = GuiConfig.AutoLoad ~= false

    CURRENT_VERSION = GuiConfig.Version
    Elements = {}
    autoSaveEnabled = GuiConfig.AutoSave
    autoLoadEnabled = GuiConfig.AutoLoad
    if GuiConfig.ConfigName then
        SetConfigName(GuiConfig.ConfigName)
    end

    if autoLoadEnabled then
        LoadConfigFromFile(nil, { allowLegacy = true })
    else
        ConfigData = { _version = CURRENT_VERSION }
    end

    local GuiFunc = {}
    local toggleElements = {}

    local Nonoyaa = Instance.new("ScreenGui");
    local DropShadowHolder = Instance.new("Frame");
    local Main = Instance.new("Frame");
    local UICorner = Instance.new("UICorner");
    local Top = Instance.new("Frame");
    local TextLabel = Instance.new("TextLabel");
    local UICorner1 = Instance.new("UICorner");
    local TextLabel1 = Instance.new("TextLabel");
    local Close = Instance.new("TextButton");
    local Min = Instance.new("TextButton");
    local LayersTab = Instance.new("Frame");
    local UICorner2 = Instance.new("UICorner");
    local DecideFrame = Instance.new("Frame");
    local Layers = Instance.new("Frame");
    local UICorner6 = Instance.new("UICorner");
    local NameTab = Instance.new("TextLabel");
    local LayersReal = Instance.new("Frame");
    local LayersFolder = Instance.new("Folder");
    local LayersPageLayout = Instance.new("UIPageLayout");

    Nonoyaa.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    Nonoyaa.Name = "Nonoyaa"
    Nonoyaa.ResetOnSpawn = false
    Nonoyaa.Parent = game:GetService("CoreGui")

    DropShadowHolder.BackgroundTransparency = 1
    DropShadowHolder.BorderSizePixel = 0
    local winWidth, winHeight = getWindowDimensions()
    if GuiConfig.Size then
        if typeof(GuiConfig.Size) == "Vector2" then
            winWidth = GuiConfig.Size.X
            winHeight = GuiConfig.Size.Y
        elseif type(GuiConfig.Size) == "table" then
            winWidth = GuiConfig.Size.x or GuiConfig.Size[1] or winWidth
            winHeight = GuiConfig.Size.y or GuiConfig.Size[2] or winHeight
        end
    end
    if GuiConfig.Width then winWidth = GuiConfig.Width end
    if GuiConfig.Height then winHeight = GuiConfig.Height end
    DropShadowHolder.Size = UDim2.new(0, winWidth, 0, winHeight)
    DropShadowHolder.ZIndex = 0
    DropShadowHolder.Name = "DropShadowHolder"
    DropShadowHolder.Parent = Nonoyaa

    Main.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
    Main.BackgroundTransparency = GuiConfig.MainTransparency
    Main.AnchorPoint = Vector2.new(0, 0)
    Main.BorderSizePixel = 0
    Main.Position = UDim2.new(0, 0, 0, 0)
    Main.Size = UDim2.new(1, 0, 1, 0)
    Main.Name = "Main"
    Main.Active = true
    Main.Selectable = true
    Main.Parent = DropShadowHolder

    UICorner.Parent = Main

    Top.BackgroundColor3 = Color3.fromRGB(27, 34, 48)
    Top.BackgroundTransparency = 0
    Top.BorderColor3 = Color3.fromRGB(27, 34, 48)
    Top.BorderSizePixel = 0
    Top.Size = UDim2.new(1, 0, 0, 44)
    Top.Name = "Top"
    Top.Parent = Main
    Top.Active = true
    Top.Selectable = true

    TextLabel.Font = Enum.Font.GothamBold
    TextLabel.Text = GuiConfig.Title
    TextLabel.TextColor3 = Color3.fromRGB(245, 245, 245)
    TextLabel.TextSize = 16
    TextLabel.TextXAlignment = Enum.TextXAlignment.Left
    TextLabel.BackgroundTransparency = 1
    TextLabel.Size = UDim2.new(1, -180, 0, 20)
    TextLabel.Position = UDim2.new(0, 16, 0, 4)
    TextLabel.Parent = Top

    UICorner1.Parent = Top

    TextLabel1.Font = Enum.Font.GothamBold
    TextLabel1.Text = GuiConfig.Footer
    TextLabel1.TextColor3 = GuiConfig.Color
    TextLabel1.TextSize = 13
    TextLabel1.TextXAlignment = Enum.TextXAlignment.Left
    TextLabel1.BackgroundTransparency = 1
    TextLabel1.Size = UDim2.new(1, -180, 0, 18)
    TextLabel1.Position = UDim2.new(0, 16, 0, 22)
    TextLabel1.Parent = Top

    Close.Font = Enum.Font.GothamBold
    Close.Text = "×"
    Close.TextColor3 = Color3.fromRGB(230, 230, 230)
    Close.TextSize = 20
    Close.AnchorPoint = Vector2.new(1, 0.5)
    Close.BackgroundColor3 = Color3.fromRGB(40, 47, 63)
    Close.BackgroundTransparency = 0.2
    Close.BorderSizePixel = 0
    Close.Position = UDim2.new(1, -10, 0.5, 0)
    Close.Size = UDim2.new(0, 34, 0, 30)
    Close.Name = "Close"
    Close.Parent = Top

    local CloseCorner = Instance.new("UICorner")
    CloseCorner.CornerRadius = UDim.new(0, 6)
    CloseCorner.Parent = Close

    Min.Font = Enum.Font.GothamBold
    Min.Text = "-"
    Min.TextColor3 = Color3.fromRGB(230, 230, 230)
    Min.TextSize = 20
    Min.AnchorPoint = Vector2.new(1, 0.5)
    Min.BackgroundColor3 = Color3.fromRGB(40, 47, 63)
    Min.BackgroundTransparency = 0.2
    Min.BorderSizePixel = 0
    Min.Position = UDim2.new(1, -52, 0.5, 0)
    Min.Size = UDim2.new(0, 34, 0, 30)
    Min.Name = "Min"
    Min.Parent = Top

    local MinCorner = Instance.new("UICorner")
    MinCorner.CornerRadius = UDim.new(0, 6)
    MinCorner.Parent = Min

    local CloseConfirm = Instance.new("Frame")
    local CloseConfirmCorner = Instance.new("UICorner")
    local CloseConfirmStroke = Instance.new("UIStroke")
    local CloseConfirmTitle = Instance.new("TextLabel")
    local CloseConfirmMessage = Instance.new("TextLabel")
    local CloseConfirmYes = Instance.new("TextButton")
    local CloseConfirmNo = Instance.new("TextButton")

    CloseConfirm.AnchorPoint = Vector2.new(0.5, 0.5)
    CloseConfirm.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
    CloseConfirm.BorderSizePixel = 0
    CloseConfirm.ClipsDescendants = true
    CloseConfirm.Position = UDim2.new(0.5, 0, 0.5, 0)
    CloseConfirm.Size = UDim2.new(0, 320, 0, 140)
    CloseConfirm.Visible = false
    CloseConfirm.ZIndex = 50
    CloseConfirm.Name = "CloseConfirm"
    CloseConfirm.Parent = Main

    CloseConfirmCorner.CornerRadius = UDim.new(0, 8)
    CloseConfirmCorner.Parent = CloseConfirm

    CloseConfirmStroke.Color = GuiConfig.Color
    CloseConfirmStroke.Transparency = 0.5
    CloseConfirmStroke.Thickness = 1.5
    CloseConfirmStroke.Parent = CloseConfirm

    CloseConfirmTitle.BackgroundTransparency = 1
    CloseConfirmTitle.Font = Enum.Font.GothamBold
    CloseConfirmTitle.Text = "Confirm Close"
    CloseConfirmTitle.TextColor3 = Color3.fromRGB(244, 244, 244)
    CloseConfirmTitle.TextSize = 16
    CloseConfirmTitle.TextXAlignment = Enum.TextXAlignment.Center
    CloseConfirmTitle.Position = UDim2.new(0, 0, 0, 12)
    CloseConfirmTitle.Size = UDim2.new(1, 0, 0, 24)
    CloseConfirmTitle.Parent = CloseConfirm

    CloseConfirmMessage.BackgroundTransparency = 1
    CloseConfirmMessage.Font = Enum.Font.Gotham
    CloseConfirmMessage.Text = "Are you sure you want to close the UI?"
    CloseConfirmMessage.TextColor3 = Color3.fromRGB(190, 190, 190)
    CloseConfirmMessage.TextSize = 14
    CloseConfirmMessage.TextWrapped = true
    CloseConfirmMessage.TextXAlignment = Enum.TextXAlignment.Center
    CloseConfirmMessage.TextYAlignment = Enum.TextYAlignment.Center
    CloseConfirmMessage.Position = UDim2.new(0, 16, 0, 46)
    CloseConfirmMessage.Size = UDim2.new(1, -32, 0, 48)
    CloseConfirmMessage.Parent = CloseConfirm

    CloseConfirmYes.Font = Enum.Font.GothamBold
    CloseConfirmYes.Text = "Close"
    CloseConfirmYes.TextColor3 = Color3.fromRGB(255, 255, 255)
    CloseConfirmYes.TextSize = 14
    CloseConfirmYes.BackgroundColor3 = GuiConfig.Color
    CloseConfirmYes.BorderSizePixel = 0
    CloseConfirmYes.Position = UDim2.new(0.55, 0, 1, -40)
    CloseConfirmYes.Size = UDim2.new(0.4, 0, 0, 32)
    CloseConfirmYes.Name = "CloseConfirmYes"
    CloseConfirmYes.Parent = CloseConfirm

    CloseConfirmNo.Font = Enum.Font.GothamBold
    CloseConfirmNo.Text = "Cancel"
    CloseConfirmNo.TextColor3 = Color3.fromRGB(245, 245, 245)
    CloseConfirmNo.TextSize = 14
    CloseConfirmNo.BackgroundColor3 = Color3.fromRGB(45, 53, 69)
    CloseConfirmNo.BorderSizePixel = 0
    CloseConfirmNo.Position = UDim2.new(0.05, 0, 1, -40)
    CloseConfirmNo.Size = UDim2.new(0.4, 0, 0, 32)
    CloseConfirmNo.Name = "CloseConfirmNo"
    CloseConfirmNo.Parent = CloseConfirm

    local tabWidth = GuiConfig.TabWidth
    local leftMargin = 12
    local gapBetween = 15
    local rightMargin = 12

    LayersTab.BackgroundColor3 = Color3.fromRGB(24, 28, 39)
    LayersTab.BackgroundTransparency = GuiConfig.TabTransparency
    LayersTab.BorderSizePixel = 0
    LayersTab.Position = UDim2.new(0, leftMargin, 0, 61)
    LayersTab.Size = UDim2.new(0, tabWidth, 1, -73)
    LayersTab.Name = "LayersTab"
    LayersTab.Parent = Main

    UICorner2.CornerRadius = UDim.new(0, 2)
    UICorner2.Parent = LayersTab

    DecideFrame.AnchorPoint = Vector2.new(0, 0)
    DecideFrame.BackgroundColor3 = Color3.fromRGB(36, 42, 58)
    DecideFrame.BackgroundTransparency = 0
    DecideFrame.BorderSizePixel = 0
    DecideFrame.Position = UDim2.new(0, leftMargin + tabWidth + 4, 0, 61)
    DecideFrame.Size = UDim2.new(0, 1, 1, -73)
    DecideFrame.Name = "DecideFrame"
    DecideFrame.Parent = Main

    Layers.BackgroundColor3 = Color3.fromRGB(20, 24, 35)
    Layers.BackgroundTransparency = GuiConfig.ContentTransparency
    Layers.BorderSizePixel = 0
    Layers.Position = UDim2.new(0, leftMargin + tabWidth + gapBetween, 0, 61)
    Layers.Size = UDim2.new(1, -(tabWidth + leftMargin + gapBetween + rightMargin), 1, -73)
    Layers.Name = "Layers"
    Layers.Parent = Main

    UICorner6.CornerRadius = UDim.new(0, 2)
    UICorner6.Parent = Layers

    NameTab.Font = Enum.Font.GothamBold
    NameTab.Text = ""
    NameTab.TextColor3 = Color3.fromRGB(240, 240, 240)
    NameTab.TextSize = 20
    NameTab.TextWrapped = true
    NameTab.TextXAlignment = Enum.TextXAlignment.Left
    NameTab.TextYAlignment = Enum.TextYAlignment.Center
    NameTab.BackgroundTransparency = 1
    NameTab.BorderSizePixel = 0
    NameTab.Size = UDim2.new(1, -24, 0, 32)
    NameTab.AnchorPoint = Vector2.new(0, 0)
    NameTab.Position = UDim2.new(0, 12, 0, 0)
    NameTab.Name = "NameTab"
    NameTab.Parent = Layers

    LayersReal.AnchorPoint = Vector2.new(0, 1)
    LayersReal.BackgroundTransparency = 1
    LayersReal.BorderSizePixel = 0
    LayersReal.ClipsDescendants = true
    LayersReal.Position = UDim2.new(0, 0, 1, 0)
    LayersReal.Size = UDim2.new(1, 0, 1, -36)
    LayersReal.Name = "LayersReal"
    LayersReal.Parent = Layers

    LayersFolder.Name = "LayersFolder"
    LayersFolder.Parent = LayersReal

    LayersPageLayout.SortOrder = Enum.SortOrder.LayoutOrder
    LayersPageLayout.Name = "LayersPageLayout"
    LayersPageLayout.Parent = LayersFolder
    LayersPageLayout.TweenTime = 0
    LayersPageLayout.EasingDirection = Enum.EasingDirection.InOut
    LayersPageLayout.EasingStyle = Enum.EasingStyle.Linear

    local ScrollTab = Instance.new("ScrollingFrame");
    local UIListLayout = Instance.new("UIListLayout");

    ScrollTab.CanvasSize = UDim2.new(0, 0, 0, 0)
    ScrollTab.ScrollBarImageColor3 = GuiConfig.Color
    ScrollTab.ScrollBarThickness = 5
    ScrollTab.ScrollingDirection = Enum.ScrollingDirection.Y
    ScrollTab.Active = true
    ScrollTab.BackgroundTransparency = 1
    ScrollTab.BorderSizePixel = 0
    ScrollTab.Size = UDim2.new(1, 0, 1, 0)
    ScrollTab.Name = "ScrollTab"
    ScrollTab.Parent = LayersTab

    UIListLayout.Padding = UDim.new(0, 8)
    UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    UIListLayout.FillDirection = Enum.FillDirection.Vertical
    UIListLayout.Parent = ScrollTab

    local function UpdateSize1()
        local offsetY = 0
        for _, child in ScrollTab:GetChildren() do
            if child:IsA("Frame") and child.Name == "Tab" then
                offsetY = offsetY + child.Size.Y.Offset + 8
            end
        end
        ScrollTab.CanvasSize = UDim2.new(0, 0, 0, math.max(0, offsetY))
    end
    ScrollTab.ChildAdded:Connect(UpdateSize1)
    ScrollTab.ChildRemoved:Connect(UpdateSize1)

    function GuiFunc:DestroyGui()
        if CoreGui:FindFirstChild("Nonoyaa") then
            Nonoyaa:Destroy()
        end
    end

    local function resetTogglesWithoutSaving()
        for _, toggle in pairs(toggleElements) do
            if toggle and toggle.Set then
                toggle:Set(false, true)
            end
        end
    end

    local function closeWindow()
        CloseConfirm.Visible = false
        resetTogglesWithoutSaving()
        GuiFunc:DestroyGui()
        local toggleUi = game.CoreGui:FindFirstChild("ToggleUIButton")
        if toggleUi then
            toggleUi:Destroy()
        end
    end

    Min.Activated:Connect(function()
        CircleClick(Min, Mouse.X, Mouse.Y)
        DropShadowHolder.Visible = false
    end)
    Close.Activated:Connect(function()
        CircleClick(Close, Mouse.X, Mouse.Y)
        CloseConfirm.Visible = true
    end)

    CloseConfirmYes.Activated:Connect(closeWindow)

    CloseConfirmNo.Activated:Connect(function()
        CloseConfirm.Visible = false
    end)

    local ToggleKey = Enum.KeyCode.F3
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == ToggleKey then
            if DropShadowHolder then
                DropShadowHolder.Visible = not DropShadowHolder.Visible
            end
        end
    end)

    function GuiFunc:ToggleUI()
        local ScreenGui = Instance.new("ScreenGui")
        ScreenGui.Parent = game:GetService("CoreGui")
        ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        ScreenGui.Name = "ToggleUIButton"

        local MainButton = Instance.new("Frame")
        MainButton.Parent = ScreenGui
        MainButton.Size = UDim2.new(0, 46, 0, 46)
        MainButton.AnchorPoint = Vector2.new(0.5, 0)
        MainButton.Position = UDim2.new(0.5, 0, 0.06, 0)
        MainButton.BackgroundColor3 = Color3.fromRGB(27, 34, 48)
        MainButton.BackgroundTransparency = 0.1

        local UICorner = Instance.new("UICorner")
        UICorner.CornerRadius = UDim.new(0, 6)
        UICorner.Parent = MainButton

        local Label = Instance.new("TextLabel")
        Label.Parent = MainButton
        Label.Size = UDim2.new(1, 0, 1, 0)
        Label.BackgroundTransparency = 1
        Label.Font = Enum.Font.GothamBold
        Label.Text = GuiConfig.ToggleText
        Label.TextColor3 = GuiConfig.Color
        Label.TextScaled = true
        Label.TextXAlignment = Enum.TextXAlignment.Center

        local Button = Instance.new("TextButton")
        Button.Parent = MainButton
        Button.Size = UDim2.new(1, 0, 1, 0)
        Button.BackgroundTransparency = 1
        Button.Text = ""

        local dragging = false
        local dragStart, startPos
        local didDrag = false
        local dragThreshold = 6

        local function toggleUiVisibility()
            if DropShadowHolder then
                local willShow = not DropShadowHolder.Visible
                DropShadowHolder.Visible = willShow
                if willShow then
                    centerWindowOnScreen(DropShadowHolder)
                end
            end
        end

        local function update(input)
            local delta = input.Position - dragStart
            MainButton.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end

        Button.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                didDrag = false
                dragStart = input.Position
                startPos = MainButton.Position
                beginInputCapture()
                local releaseConnection
                releaseConnection = input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        if dragging then
                            dragging = false
                            endInputCapture()
                            if not didDrag then
                                toggleUiVisibility()
                            end
                        end
                        if releaseConnection then
                            releaseConnection:Disconnect()
                            releaseConnection = nil
                        end
                    end
                end)
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - dragStart
                if delta.Magnitude > dragThreshold then
                    didDrag = true
                end
                update(input)
            end
        end)
    end

    GuiFunc:ToggleUI()

    local requiredWidth = 160 + TextLabel.TextBounds.X + TextLabel1.TextBounds.X
    if DropShadowHolder.Size.X.Offset < requiredWidth then
        DropShadowHolder.Size = UDim2.new(0, requiredWidth, 0, DropShadowHolder.Size.Y.Offset)
    end
    centerWindowOnScreen(DropShadowHolder)
    MakeDraggable(Top, DropShadowHolder)

    local MoreBlur = Instance.new("Frame");
    local UICorner28 = Instance.new("UICorner");
    local ConnectButton = Instance.new("TextButton");

    MoreBlur.AnchorPoint = Vector2.new(0.5, 0.5)
    MoreBlur.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
    MoreBlur.BackgroundTransparency = 1
    MoreBlur.BorderSizePixel = 0
    MoreBlur.ClipsDescendants = true
    MoreBlur.Position = UDim2.new(0.5, 0, 0.5, 0)
    MoreBlur.Size = UDim2.new(1, 0, 1, 0)
    MoreBlur.Visible = false
    MoreBlur.Name = "MoreBlur"
    MoreBlur.ZIndex = 30
    MoreBlur.Parent = Layers

    UICorner28.Parent = MoreBlur

    ConnectButton.Font = Enum.Font.SourceSans
    ConnectButton.Text = ""
    ConnectButton.TextColor3 = Color3.fromRGB(0, 0, 0)
    ConnectButton.TextSize = 14
    ConnectButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    ConnectButton.BackgroundTransparency = 0.999
    ConnectButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
    ConnectButton.BorderSizePixel = 0
    ConnectButton.Size = UDim2.new(1, 0, 1, 0)
    ConnectButton.Name = "ConnectButton"
    ConnectButton.Parent = MoreBlur
    ConnectButton.ZIndex = 31

    local DropdownSelect = Instance.new("Frame");
    local UICorner36 = Instance.new("UICorner");
    local UIStroke14 = Instance.new("UIStroke");
    local DropdownSelectReal = Instance.new("Frame");
    local DropdownFolder = Instance.new("Folder");
    local DropdownUIScale = Instance.new("UIScale")

    DropdownSelect.AnchorPoint = Vector2.new(0.5, 0.5)
    DropdownSelect.BackgroundColor3 = Color3.fromRGB(24, 28, 39)
    DropdownSelect.BorderSizePixel = 0
    DropdownSelect.LayoutOrder = 1
    DropdownSelect.Position = UDim2.new(0.5, 0, 0.5, 0)
    DropdownSelect.Size = UDim2.new(0, 280, 0, 260)
    DropdownSelect.Name = "DropdownSelect"
    DropdownSelect.ClipsDescendants = true
    DropdownSelect.Visible = false
    DropdownSelect.ZIndex = 35
    DropdownSelect.Parent = MoreBlur

    DropdownUIScale.Scale = 0.92
    DropdownUIScale.Parent = DropdownSelect

    UICorner36.CornerRadius = UDim.new(0, 6)
    UICorner36.Parent = DropdownSelect

    UIStroke14.Color = GuiConfig.Color
    UIStroke14.Thickness = 1.5
    UIStroke14.Transparency = 0.4
    UIStroke14.Parent = DropdownSelect

    DropdownSelectReal.AnchorPoint = Vector2.new(0.5, 0.5)
    DropdownSelectReal.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
    DropdownSelectReal.BackgroundTransparency = 0.7
    DropdownSelectReal.BorderColor3 = Color3.fromRGB(0, 0, 0)
    DropdownSelectReal.BorderSizePixel = 0
    DropdownSelectReal.LayoutOrder = 1
    DropdownSelectReal.Position = UDim2.new(0.5, 0, 0.5, 0)
    DropdownSelectReal.Size = UDim2.new(1, -24, 1, -24)
    DropdownSelectReal.Name = "DropdownSelectReal"
    DropdownSelectReal.ZIndex = 36
    DropdownSelectReal.Parent = DropdownSelect

    DropdownFolder.Name = "DropdownFolder"
    DropdownFolder.Parent = DropdownSelectReal

    local defaultArrowColor = Color3.fromRGB(230, 230, 230)
    local dropdownOpen = false
    local dropdownBlurTween
    local dropdownScaleTween
    local activeDropdownArrow
    local arrowTweens = {}
    local activeDropdownContainer
    local function setActiveDropdownContainer(container)
        if activeDropdownContainer and activeDropdownContainer ~= container then
            activeDropdownContainer.Visible = false
        end
        activeDropdownContainer = container
        if activeDropdownContainer then
            activeDropdownContainer.Visible = true
        end
    end
    local overlayShowTime = 0.25
    local overlayHideTime = 0.2
    local overlayShowInfo = TweenInfo.new(overlayShowTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local overlayHideInfo = TweenInfo.new(overlayHideTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    local dropdownScaleShowInfo = TweenInfo.new(overlayShowTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    local dropdownScaleHideInfo = TweenInfo.new(overlayHideTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    local arrowTweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    local function UpdateDropdownSize()
        local holderSize = DropShadowHolder.AbsoluteSize
        local width = math.clamp(holderSize.X - 160, 220, 360)
        local height = math.clamp(holderSize.Y - 160, 200, 320)
        DropdownSelect.Size = UDim2.new(0, width, 0, height)
    end

    UpdateDropdownSize()
    DropShadowHolder:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateDropdownSize)

    local function animateArrowState(arrow, shouldOpen)
        if not (arrow and arrow.Parent) then return end
        if arrowTweens[arrow] then
            arrowTweens[arrow]:Cancel()
            arrowTweens[arrow] = nil
        end
        local tween = TweenService:Create(arrow, arrowTweenInfo, {
            Rotation = shouldOpen and 90 or 0,
            TextColor3 = shouldOpen and GuiConfig.Color or defaultArrowColor
        })
        arrowTweens[arrow] = tween
        tween.Completed:Connect(function()
            if arrowTweens[arrow] == tween then
                arrowTweens[arrow] = nil
            end
        end)
        tween:Play()
    end

    local function closeDropdownOverlay()
        if activeDropdownArrow then
            animateArrowState(activeDropdownArrow, false)
            activeDropdownArrow = nil
        end
        setActiveDropdownContainer(nil)
        if not MoreBlur.Visible then
            dropdownOpen = false
            return
        end
        dropdownOpen = false
        if dropdownBlurTween then dropdownBlurTween:Cancel() end
        if dropdownScaleTween then dropdownScaleTween:Cancel() end
        dropdownBlurTween = TweenService:Create(MoreBlur, overlayHideInfo, { BackgroundTransparency = 1 })
        dropdownScaleTween = TweenService:Create(DropdownUIScale, dropdownScaleHideInfo, { Scale = 0.9 })
        dropdownBlurTween:Play()
        dropdownScaleTween:Play()
        task.delay(overlayHideTime + 0.02, function()
            if not dropdownOpen then
                MoreBlur.Visible = false
                DropdownSelect.Visible = false
            end
        end)
    end

    local function openDropdownOverlay(container, arrowLabel)
        if activeDropdownArrow and activeDropdownArrow ~= arrowLabel then
            animateArrowState(activeDropdownArrow, false)
        end
        activeDropdownArrow = arrowLabel
        if activeDropdownArrow then
            animateArrowState(activeDropdownArrow, true)
        end
        setActiveDropdownContainer(container)
        dropdownOpen = true
        UpdateDropdownSize()
        MoreBlur.Visible = true
        DropdownSelect.Visible = true
        MoreBlur.BackgroundTransparency = 1
        DropdownUIScale.Scale = 0.9
        if dropdownBlurTween then dropdownBlurTween:Cancel() end
        if dropdownScaleTween then dropdownScaleTween:Cancel() end
        dropdownBlurTween = TweenService:Create(MoreBlur, overlayShowInfo, { BackgroundTransparency = 0.35 })
        dropdownScaleTween = TweenService:Create(DropdownUIScale, dropdownScaleShowInfo, { Scale = 1 })
        dropdownBlurTween:Play()
        dropdownScaleTween:Play()
    end

    ConnectButton.Activated:Connect(closeDropdownOverlay)
    --// Tabs
    local Tabs = {}
    local CountTab = 0
    local ActiveTab = nil
    function Tabs:AddTab(TabConfig)
        local TabConfig = TabConfig or {}
        TabConfig.Name = TabConfig.Name or "Tab"
        TabConfig.Icon = TabConfig.Icon or ""

        local ScrolLayers = Instance.new("ScrollingFrame");
        local UIListLayout1 = Instance.new("UIListLayout");

        ScrolLayers.ScrollBarImageColor3 = GuiConfig.Color
        ScrolLayers.ScrollBarThickness = 2
        ScrolLayers.Active = true
        ScrolLayers.LayoutOrder = CountTab
        ScrolLayers.BackgroundTransparency = 1
        ScrolLayers.BorderSizePixel = 0
        ScrolLayers.Size = UDim2.new(1, 0, 1, 0)
        ScrolLayers.Name = "ScrolLayers"
        ScrolLayers.Parent = LayersFolder

        UIListLayout1.Padding = UDim.new(0, 3)
        UIListLayout1.SortOrder = Enum.SortOrder.LayoutOrder
        UIListLayout1.Parent = ScrolLayers

        local Tab = Instance.new("Frame");
        local UICorner3 = Instance.new("UICorner");
        local TabButton = Instance.new("TextButton");
        local TabName = Instance.new("TextLabel")
        local IconLabel = Instance.new("TextLabel");
        local TabIndicator = Instance.new("Frame");

        Tab.BackgroundColor3 = Color3.fromRGB(33, 39, 54)
        Tab.BackgroundTransparency = CountTab == 0 and 0.08 or 0.55
        Tab.BorderSizePixel = 0
        Tab.LayoutOrder = CountTab
        Tab.Size = UDim2.new(1, 0, 0, 42)
        Tab.Name = "Tab"
        Tab.Parent = ScrollTab

        UICorner3.CornerRadius = UDim.new(0, 4)
        UICorner3.Parent = Tab

        TabButton.Font = Enum.Font.GothamBold
        TabButton.Text = ""
        TabButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        TabButton.TextSize = 13
        TabButton.BackgroundTransparency = 1
        TabButton.BorderSizePixel = 0
        TabButton.Size = UDim2.new(1, 0, 1, 0)
        TabButton.Name = "TabButton"
        TabButton.Parent = Tab

        TabName.Font = Enum.Font.GothamBold
        TabName.Text = tostring(TabConfig.Name)
        TabName.TextColor3 = CountTab == 0 and Color3.fromRGB(245, 245, 245) or Color3.fromRGB(180, 186, 202)
        TabName.TextSize = 13
        TabName.TextXAlignment = Enum.TextXAlignment.Left
        TabName.TextYAlignment = Enum.TextYAlignment.Center
        TabName.BackgroundTransparency = 1
        TabName.BorderSizePixel = 0
        TabName.AnchorPoint = Vector2.new(0, 0.5)
        TabName.Position = UDim2.new(0, 12, 0.5, 0)
        TabName.Size = UDim2.new(1, -24, 1, -8)
        TabName.Name = "TabName"
        TabName.Parent = Tab

        IconLabel.Font = Enum.Font.GothamBold
        IconLabel.Text = TabConfig.Icon
        IconLabel.TextColor3 = Color3.fromRGB(210, 210, 210)
        IconLabel.TextSize = 13
        IconLabel.TextXAlignment = Enum.TextXAlignment.Center
        IconLabel.TextYAlignment = Enum.TextYAlignment.Center
        IconLabel.BackgroundTransparency = 1
        IconLabel.Size = UDim2.new(0, 20, 0, 20)
        IconLabel.AnchorPoint = Vector2.new(0, 0.5)
        IconLabel.Position = UDim2.new(0, 12, 0.5, 0)
        IconLabel.Name = "IconLabel"
        IconLabel.Visible = TabConfig.Icon ~= ""
        IconLabel.Parent = Tab

        if IconLabel.Visible then
            TabName.AnchorPoint = Vector2.new(0, 0.5)
            TabName.Position = UDim2.new(0, 40, 0.5, 0)
            TabName.Size = UDim2.new(1, -52, 1, -8)
            TabName.TextXAlignment = Enum.TextXAlignment.Left
        end

        TabIndicator.BackgroundColor3 = GuiConfig.Color
        TabIndicator.BorderSizePixel = 0
        TabIndicator.Size = UDim2.new(0, 3, 1, 0)
        TabIndicator.Position = UDim2.new(0, 0, 0, 0)
        TabIndicator.Name = "TabIndicator"
        TabIndicator.Visible = CountTab == 0
        TabIndicator.Parent = Tab

        if CountTab == 0 then
            ActiveTab = Tab
            LayersPageLayout:JumpToIndex(0)
            NameTab.Text = TabConfig.Name
        end

        local function deactivate(tabFrame)
            if not tabFrame then return end
            tabFrame.BackgroundTransparency = 0.55
            local tabText = tabFrame:FindFirstChild("TabName")
            if tabText then
                tabText.TextColor3 = Color3.fromRGB(180, 186, 202)
            end
            local indicator = tabFrame:FindFirstChild("TabIndicator")
            if indicator then
                indicator.Visible = false
            end
        end

        local function activate()
            if ActiveTab == Tab then return end
            deactivate(ActiveTab)
            ActiveTab = Tab
            Tab.BackgroundTransparency = 0.08
            TabName.TextColor3 = Color3.fromRGB(245, 245, 245)
            TabIndicator.Visible = true
            NameTab.Text = TabConfig.Name
            LayersPageLayout:JumpToIndex(Tab.LayoutOrder)
        end

        TabButton.Activated:Connect(function()
            activate()
        end)
        --// Section
        local Sections = {}
        local CountSection = 0
        function Sections:AddSection(Title, AlwaysOpen)
            local Title = Title or "Title"
            local Section = Instance.new("Frame");
            local SectionDecideFrame = Instance.new("Frame");

            Section.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            Section.BackgroundTransparency = 0.9990000128746033
            Section.BorderColor3 = Color3.fromRGB(0, 0, 0)
            Section.BorderSizePixel = 0
            Section.LayoutOrder = CountSection
            Section.ClipsDescendants = true
            Section.LayoutOrder = 1
            Section.Size = UDim2.new(1, 0, 0, 30)
            Section.Name = "Section"
            Section.Parent = ScrolLayers

            local SectionReal = Instance.new("Frame");
            local UICorner = Instance.new("UICorner");
            local UIStroke = Instance.new("UIStroke");
            local SectionButton = Instance.new("TextButton");
            local FeatureFrame = Instance.new("Frame");
            local ArrowLabel = Instance.new("TextLabel");
            local SectionTitle = Instance.new("TextLabel");

            SectionReal.AnchorPoint = Vector2.new(0.5, 0)
            SectionReal.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            SectionReal.BackgroundTransparency = 0.9350000023841858
            SectionReal.BorderColor3 = Color3.fromRGB(0, 0, 0)
            SectionReal.BorderSizePixel = 0
            SectionReal.LayoutOrder = 1
            SectionReal.Position = UDim2.new(0.5, 0, 0, 0)
            SectionReal.Size = UDim2.new(1, 1, 0, 30)
            SectionReal.Name = "SectionReal"
            SectionReal.Parent = Section

            UICorner.CornerRadius = UDim.new(0, 4)
            UICorner.Parent = SectionReal

            SectionButton.Font = Enum.Font.SourceSans
            SectionButton.Text = ""
            SectionButton.TextColor3 = Color3.fromRGB(0, 0, 0)
            SectionButton.TextSize = 14
            SectionButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            SectionButton.BackgroundTransparency = 0.9990000128746033
            SectionButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
            SectionButton.BorderSizePixel = 0
            SectionButton.Size = UDim2.new(1, 0, 1, 0)
            SectionButton.Name = "SectionButton"
            SectionButton.Parent = SectionReal

            FeatureFrame.AnchorPoint = Vector2.new(1, 0.5)
            FeatureFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
            FeatureFrame.BackgroundTransparency = 0.9990000128746033
            FeatureFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
            FeatureFrame.BorderSizePixel = 0
            FeatureFrame.Position = UDim2.new(1, -5, 0.5, 0)
            FeatureFrame.Size = UDim2.new(0, 20, 0, 20)
            FeatureFrame.Name = "FeatureFrame"
            FeatureFrame.Parent = SectionReal

            ArrowLabel.Font = Enum.Font.GothamBold
            ArrowLabel.Text = AlwaysOpen and "" or ">"
            ArrowLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
            ArrowLabel.TextSize = 13
            ArrowLabel.BackgroundTransparency = 1
            ArrowLabel.Size = UDim2.new(1, 0, 1, 0)
            ArrowLabel.Name = "ArrowLabel"
            ArrowLabel.Parent = FeatureFrame

            SectionTitle.Font = Enum.Font.GothamBold
            SectionTitle.Text = Title
            SectionTitle.TextColor3 = Color3.fromRGB(230.77499270439148, 230.77499270439148, 230.77499270439148)
            SectionTitle.TextSize = 13
            SectionTitle.TextXAlignment = Enum.TextXAlignment.Left
            SectionTitle.TextYAlignment = Enum.TextYAlignment.Top
            SectionTitle.AnchorPoint = Vector2.new(0, 0.5)
            SectionTitle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            SectionTitle.BackgroundTransparency = 0.9990000128746033
            SectionTitle.BorderColor3 = Color3.fromRGB(0, 0, 0)
            SectionTitle.BorderSizePixel = 0
            SectionTitle.Position = UDim2.new(0, 10, 0.5, 0)
            SectionTitle.Size = UDim2.new(1, -50, 0, 13)
            SectionTitle.Name = "SectionTitle"
            SectionTitle.Parent = SectionReal

            SectionDecideFrame.BackgroundColor3 = Color3.fromRGB(70, 75, 86)
            SectionDecideFrame.BackgroundTransparency = 0.35
            SectionDecideFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
            SectionDecideFrame.AnchorPoint = Vector2.new(0.5, 0)
            SectionDecideFrame.BorderSizePixel = 0
            SectionDecideFrame.Position = UDim2.new(0.5, 0, 0, 33)
            SectionDecideFrame.Size = UDim2.new(0, 0, 0, 1)
            SectionDecideFrame.Name = "SectionDecideFrame"
            SectionDecideFrame.Parent = Section

            --// Section Add
            local SectionAdd = Instance.new("Frame");
            local UICorner8 = Instance.new("UICorner");
            local UIListLayout2 = Instance.new("UIListLayout");

            SectionAdd.AnchorPoint = Vector2.new(0.5, 0)
            SectionAdd.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            SectionAdd.BackgroundTransparency = 0.9990000128746033
            SectionAdd.BorderColor3 = Color3.fromRGB(0, 0, 0)
            SectionAdd.BorderSizePixel = 0
            SectionAdd.ClipsDescendants = true
            SectionAdd.LayoutOrder = 1
            SectionAdd.Position = UDim2.new(0.5, 0, 0, 38)
            SectionAdd.Size = UDim2.new(1, 0, 0, 100)
            SectionAdd.Name = "SectionAdd"
            SectionAdd.Parent = Section
            SectionAdd.Visible = false

            UICorner8.CornerRadius = UDim.new(0, 2)
            UICorner8.Parent = SectionAdd

            UIListLayout2.Padding = UDim.new(0, 3)
            UIListLayout2.SortOrder = Enum.SortOrder.LayoutOrder
            UIListLayout2.Parent = SectionAdd

            local OpenSection = false

            local function UpdateSizeScroll()
                local OffsetY = 0
                for _, child in ScrolLayers:GetChildren() do
                    if child.Name ~= "UIListLayout" then
                        OffsetY = OffsetY + 3 + child.Size.Y.Offset
                    end
                end
                ScrolLayers.CanvasSize = UDim2.new(0, 0, 0, OffsetY)
            end

            local function getSectionContentHeight()
                local SectionSizeYWitdh = 38
                for _, v in SectionAdd:GetChildren() do
                    if v.Name ~= "UIListLayout" and v.Name ~= "UICorner" then
                        SectionSizeYWitdh = SectionSizeYWitdh + v.Size.Y.Offset + 3
                    end
                end
                return SectionSizeYWitdh
            end

            local function animateArrowState()
                if AlwaysOpen == true or not ArrowLabel or not ArrowLabel.Parent then
                    return
                end
                ArrowLabel.Text = ">"
                local targetRotation = OpenSection and 90 or 0
                local targetColor = OpenSection and GuiConfig.Color or Color3.fromRGB(220, 220, 220)
                ArrowLabel.Rotation = targetRotation
                ArrowLabel.TextColor3 = targetColor
            end

            local function UpdateSizeSection()
                local sectionTargetHeight = OpenSection and getSectionContentHeight() or 30
                local sectionAddHeight = math.max(0, sectionTargetHeight - 38)
                local decideSize = OpenSection and UDim2.new(1, 0, 0, 1) or UDim2.new(0, 0, 0, 1)

                Section.Size = UDim2.new(1, 1, 0, sectionTargetHeight)
                SectionAdd.Size = UDim2.new(1, 0, 0, OpenSection and sectionAddHeight or 0)
                SectionAdd.Visible = OpenSection
                SectionDecideFrame.Size = decideSize
                UpdateSizeScroll()
                animateArrowState()
            end

            local function setSectionState(newState)
                OpenSection = newState
                UpdateSizeSection()
            end

            if AlwaysOpen == true then
                SectionButton:Destroy()
                FeatureFrame:Destroy()
                setSectionState(true)
            elseif AlwaysOpen == false then
                setSectionState(true)
            else
                setSectionState(false)
            end

            if AlwaysOpen ~= true then
                SectionButton.Activated:Connect(function()
                    CircleClick(SectionButton, Mouse.X, Mouse.Y)
                    setSectionState(not OpenSection)
                end)
            end

            SectionAdd.ChildAdded:Connect(function()
                UpdateSizeSection()
            end)
            SectionAdd.ChildRemoved:Connect(function()
                UpdateSizeSection()
            end)

            local layout = ScrolLayers:FindFirstChildOfClass("UIListLayout")
            if layout then
                layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                    ScrolLayers.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
                end)
            end

            local Items = {}
            local CountItem = 0

            function Items:AddParagraph(ParagraphConfig)
                local ParagraphConfig = ParagraphConfig or {}
                ParagraphConfig.Title = ParagraphConfig.Title or "Title"
                ParagraphConfig.Content = ParagraphConfig.Content or "Content"
                local ParagraphFunc = {}

                local Paragraph = Instance.new("Frame")
                local UICorner14 = Instance.new("UICorner")
                local ParagraphTitle = Instance.new("TextLabel")
                local ParagraphContent = Instance.new("TextLabel")

                Paragraph.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                Paragraph.BackgroundTransparency = 0.935
                Paragraph.BorderSizePixel = 0
                Paragraph.LayoutOrder = CountItem
                Paragraph.Size = UDim2.new(1, 0, 0, 46)
                Paragraph.Name = "Paragraph"
                Paragraph.Parent = SectionAdd

                UICorner14.CornerRadius = UDim.new(0, 4)
                UICorner14.Parent = Paragraph

                local iconOffset = 10
                if ParagraphConfig.Icon then
                    local IconImg = Instance.new("ImageLabel")
                    IconImg.Size = UDim2.new(0, 20, 0, 20)
                    IconImg.Position = UDim2.new(0, 8, 0, 12)
                    IconImg.BackgroundTransparency = 1
                    IconImg.Name = "ParagraphIcon"
                    IconImg.Parent = Paragraph

                    if Icons and Icons[ParagraphConfig.Icon] then
                        IconImg.Image = Icons[ParagraphConfig.Icon]
                    else
                        IconImg.Image = ParagraphConfig.Icon
                    end

                    iconOffset = 30
                end

                ParagraphTitle.Font = Enum.Font.GothamBold
                ParagraphTitle.Text = ParagraphConfig.Title
                ParagraphTitle.TextColor3 = Color3.fromRGB(231, 231, 231)
                ParagraphTitle.TextSize = 13
                ParagraphTitle.TextXAlignment = Enum.TextXAlignment.Left
                ParagraphTitle.TextYAlignment = Enum.TextYAlignment.Top
                ParagraphTitle.BackgroundTransparency = 1
                ParagraphTitle.Position = UDim2.new(0, iconOffset, 0, 10)
                ParagraphTitle.Size = UDim2.new(1, -16, 0, 13)
                ParagraphTitle.Name = "ParagraphTitle"
                ParagraphTitle.Parent = Paragraph

                ParagraphContent.Font = Enum.Font.Gotham
                ParagraphContent.Text = ParagraphConfig.Content
                ParagraphContent.TextColor3 = Color3.fromRGB(255, 255, 255)
                ParagraphContent.TextSize = 12
                ParagraphContent.TextXAlignment = Enum.TextXAlignment.Left
                ParagraphContent.TextYAlignment = Enum.TextYAlignment.Top
                ParagraphContent.BackgroundTransparency = 1
                ParagraphContent.Position = UDim2.new(0, iconOffset, 0, 25)
                ParagraphContent.Name = "ParagraphContent"
                ParagraphContent.TextWrapped = false
                ParagraphContent.RichText = true
                ParagraphContent.Parent = Paragraph

                ParagraphContent.Size = UDim2.new(1, -16, 0, ParagraphContent.TextBounds.Y)

                local ParagraphButton
                if ParagraphConfig.ButtonText then
                    ParagraphButton = Instance.new("TextButton")
                    ParagraphButton.Position = UDim2.new(0, 10, 0, 42)
                    ParagraphButton.Size = UDim2.new(1, -22, 0, 28)
                    ParagraphButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                    ParagraphButton.BackgroundTransparency = 0.935
                    ParagraphButton.Font = Enum.Font.GothamBold
                    ParagraphButton.TextSize = 12
                    ParagraphButton.TextTransparency = 0.3
                    ParagraphButton.TextColor3 = Color3.fromRGB(255, 255, 255)
                    ParagraphButton.Text = ParagraphConfig.ButtonText
                    ParagraphButton.Parent = Paragraph

                    local btnCorner = Instance.new("UICorner")
                    btnCorner.CornerRadius = UDim.new(0, 6)
                    btnCorner.Parent = ParagraphButton

                    if ParagraphConfig.ButtonCallback then
                        ParagraphButton.MouseButton1Click:Connect(ParagraphConfig.ButtonCallback)
                    end
                end

                local function UpdateSize()
                    local totalHeight = ParagraphContent.TextBounds.Y + 33
                    if ParagraphButton then
                        totalHeight = totalHeight + ParagraphButton.Size.Y.Offset + 5
                    end
                    Paragraph.Size = UDim2.new(1, 0, 0, totalHeight)
                end

                UpdateSize()

                ParagraphContent:GetPropertyChangedSignal("TextBounds"):Connect(UpdateSize)

                function ParagraphFunc:SetContent(content)
                    content = content or "Content"
                    ParagraphContent.Text = content
                    UpdateSize()
                end

                CountItem = CountItem + 1
                return ParagraphFunc
            end

            function Items:AddPanel(PanelConfig)
                PanelConfig = PanelConfig or {}
                PanelConfig.Title = PanelConfig.Title or "Title"
                PanelConfig.Content = PanelConfig.Content or ""
                PanelConfig.Placeholder = PanelConfig.Placeholder or nil
                PanelConfig.Default = PanelConfig.Default or ""
                PanelConfig.ButtonText = PanelConfig.Button or PanelConfig.ButtonText or "Confirm"
                PanelConfig.ButtonCallback = PanelConfig.Callback or PanelConfig.ButtonCallback or function() end
                PanelConfig.SubButtonText = PanelConfig.SubButton or PanelConfig.SubButtonText or nil
                PanelConfig.SubButtonCallback = PanelConfig.SubCallback or PanelConfig.SubButtonCallback or
                    function() end

                local configKey = "Panel_" .. PanelConfig.Title
                if ConfigData[configKey] ~= nil then
                    PanelConfig.Default = ConfigData[configKey]
                end

                local PanelFunc = { Value = PanelConfig.Default }

                local baseHeight = 50

                if PanelConfig.Placeholder then
                    baseHeight = baseHeight + 40
                end

                if PanelConfig.SubButtonText then
                    baseHeight = baseHeight + 40
                else
                    baseHeight = baseHeight + 36
                end

                local Panel = Instance.new("Frame")
                Panel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                Panel.BackgroundTransparency = 0.935
                Panel.Size = UDim2.new(1, 0, 0, baseHeight)
                Panel.LayoutOrder = CountItem
                Panel.Parent = SectionAdd

                local UICorner = Instance.new("UICorner")
                UICorner.CornerRadius = UDim.new(0, 4)
                UICorner.Parent = Panel

                local Title = Instance.new("TextLabel")
                Title.Font = Enum.Font.GothamBold
                Title.Text = PanelConfig.Title
                Title.TextSize = 13
                Title.TextColor3 = Color3.fromRGB(255, 255, 255)
                Title.TextXAlignment = Enum.TextXAlignment.Left
                Title.BackgroundTransparency = 1
                Title.Position = UDim2.new(0, 10, 0, 10)
                Title.Size = UDim2.new(1, -20, 0, 13)
                Title.Parent = Panel

                local Content = Instance.new("TextLabel")
                Content.Font = Enum.Font.Gotham
                Content.Text = PanelConfig.Content
                Content.TextSize = 12
                Content.TextColor3 = Color3.fromRGB(255, 255, 255)
                Content.TextTransparency = 0
                Content.TextXAlignment = Enum.TextXAlignment.Left
                Content.BackgroundTransparency = 1
                Content.RichText = true
                Content.Position = UDim2.new(0, 10, 0, 28)
                Content.Size = UDim2.new(1, -20, 0, 14)
                Content.Parent = Panel

                local InputBox
                if PanelConfig.Placeholder then
                    local InputFrame = Instance.new("Frame")
                    InputFrame.AnchorPoint = Vector2.new(0.5, 0)
                    InputFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                    InputFrame.BackgroundTransparency = 0.95
                    InputFrame.Position = UDim2.new(0.5, 0, 0, 48)
                    InputFrame.Size = UDim2.new(1, -20, 0, 30)
                    InputFrame.Parent = Panel

                    local inputCorner = Instance.new("UICorner")
                    inputCorner.CornerRadius = UDim.new(0, 4)
                    inputCorner.Parent = InputFrame

                    InputBox = Instance.new("TextBox")
                    InputBox.Font = Enum.Font.GothamBold
                    InputBox.PlaceholderText = PanelConfig.Placeholder
                    InputBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 120)
                    InputBox.Text = PanelConfig.Default
                    InputBox.TextSize = 11
                    InputBox.TextColor3 = Color3.fromRGB(255, 255, 255)
                    InputBox.BackgroundTransparency = 1
                    InputBox.TextXAlignment = Enum.TextXAlignment.Left
                    InputBox.Size = UDim2.new(1, -10, 1, -6)
                    InputBox.Position = UDim2.new(0, 5, 0, 3)
                    InputBox.Parent = InputFrame
                end

                local yBtn = 0
                if PanelConfig.Placeholder then
                    yBtn = 88
                else
                    yBtn = 48
                end

                local ButtonMain = Instance.new("TextButton")
                ButtonMain.Font = Enum.Font.GothamBold
                ButtonMain.Text = PanelConfig.ButtonText
                ButtonMain.TextColor3 = Color3.fromRGB(255, 255, 255)
                ButtonMain.TextSize = 12
                ButtonMain.TextTransparency = 0.3
                ButtonMain.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                ButtonMain.BackgroundTransparency = 0.935
                ButtonMain.Size = PanelConfig.SubButtonText and UDim2.new(0.5, -12, 0, 30) or UDim2.new(1, -20, 0, 30)
                ButtonMain.Position = UDim2.new(0, 10, 0, yBtn)
                ButtonMain.Parent = Panel

                local btnCorner = Instance.new("UICorner")
                btnCorner.CornerRadius = UDim.new(0, 6)
                btnCorner.Parent = ButtonMain

                ButtonMain.MouseButton1Click:Connect(function()
                    PanelConfig.ButtonCallback(InputBox and InputBox.Text or "")
                end)

                if PanelConfig.SubButtonText then
                    local SubButton = Instance.new("TextButton")
                    SubButton.Font = Enum.Font.GothamBold
                    SubButton.Text = PanelConfig.SubButtonText
                    SubButton.TextColor3 = Color3.fromRGB(255, 255, 255)
                    SubButton.TextSize = 12
                    SubButton.TextTransparency = 0.3
                    SubButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                    SubButton.BackgroundTransparency = 0.935
                    SubButton.Size = UDim2.new(0.5, -12, 0, 30)
                    SubButton.Position = UDim2.new(0.5, 2, 0, yBtn)
                    SubButton.Parent = Panel

                    local subCorner = Instance.new("UICorner")
                    subCorner.CornerRadius = UDim.new(0, 6)
                    subCorner.Parent = SubButton

                    SubButton.MouseButton1Click:Connect(function()
                        PanelConfig.SubButtonCallback(InputBox and InputBox.Text or "")
                    end)
                end

                if InputBox then
                    InputBox.FocusLost:Connect(function()
                        PanelFunc.Value = InputBox.Text
                        ConfigData[configKey] = InputBox.Text
                        SaveConfig()
                    end)
                end

                function PanelFunc:GetInput()
                    return InputBox and InputBox.Text or ""
                end

                CountItem = CountItem + 1
                return PanelFunc
            end

            function Items:AddButton(ButtonConfig)
                ButtonConfig = ButtonConfig or {}
                ButtonConfig.Title = ButtonConfig.Title or "Confirm"
                ButtonConfig.Callback = ButtonConfig.Callback or function() end
                ButtonConfig.SubTitle = ButtonConfig.SubTitle or nil
                ButtonConfig.SubCallback = ButtonConfig.SubCallback or function() end

                local Button = Instance.new("Frame")
                Button.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                Button.BackgroundTransparency = 0.935
                Button.Size = UDim2.new(1, 0, 0, 40)
                Button.LayoutOrder = CountItem
                Button.Parent = SectionAdd

                local UICorner = Instance.new("UICorner")
                UICorner.CornerRadius = UDim.new(0, 4)
                UICorner.Parent = Button

                local MainButton = Instance.new("TextButton")
                MainButton.Font = Enum.Font.GothamBold
                MainButton.Text = ButtonConfig.Title
                MainButton.TextSize = 12
                MainButton.TextColor3 = Color3.fromRGB(255, 255, 255)
                MainButton.TextTransparency = 0.3
                MainButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                MainButton.BackgroundTransparency = 0.935
                MainButton.Size = ButtonConfig.SubTitle and UDim2.new(0.5, -8, 1, -10) or UDim2.new(1, -12, 1, -10)
                MainButton.Position = UDim2.new(0, 6, 0, 5)
                MainButton.Parent = Button

                local mainCorner = Instance.new("UICorner")
                mainCorner.CornerRadius = UDim.new(0, 4)
                mainCorner.Parent = MainButton

                MainButton.MouseButton1Click:Connect(ButtonConfig.Callback)

                if ButtonConfig.SubTitle then
                    local SubButton = Instance.new("TextButton")
                    SubButton.Font = Enum.Font.GothamBold
                    SubButton.Text = ButtonConfig.SubTitle
                    SubButton.TextSize = 12
                    SubButton.TextTransparency = 0.3
                    SubButton.TextColor3 = Color3.fromRGB(255, 255, 255)
                    SubButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                    SubButton.BackgroundTransparency = 0.935
                    SubButton.Size = UDim2.new(0.5, -8, 1, -10)
                    SubButton.Position = UDim2.new(0.5, 2, 0, 5)
                    SubButton.Parent = Button

                    local subCorner = Instance.new("UICorner")
                    subCorner.CornerRadius = UDim.new(0, 4)
                    subCorner.Parent = SubButton

                    SubButton.MouseButton1Click:Connect(ButtonConfig.SubCallback)
                end

                CountItem = CountItem + 1
            end

            function Items:AddToggle(ToggleConfig)
                local ToggleConfig = ToggleConfig or {}
                ToggleConfig.Title = ToggleConfig.Title or "Title"
                ToggleConfig.Title2 = ToggleConfig.Title2 or ""
                ToggleConfig.Content = ToggleConfig.Content or ""
                ToggleConfig.Default = ToggleConfig.Default or false
                ToggleConfig.Callback = ToggleConfig.Callback or function() end

                local configKey = "Toggle_" .. ToggleConfig.Title
                if ConfigData[configKey] ~= nil then
                    ToggleConfig.Default = ConfigData[configKey]
                end

                local ToggleFunc = { Value = ToggleConfig.Default }

                local Toggle = Instance.new("Frame")
                local UICorner20 = Instance.new("UICorner")
                local ToggleTitle = Instance.new("TextLabel")
                local ToggleContent = Instance.new("TextLabel")
                local ToggleButton = Instance.new("TextButton")
                local FeatureFrame2 = Instance.new("Frame")
                local UICorner22 = Instance.new("UICorner")
                local UIStroke8 = Instance.new("UIStroke")
                local ToggleCircle = Instance.new("Frame")
                local UICorner23 = Instance.new("UICorner")

                Toggle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                Toggle.BackgroundTransparency = 0.935
                Toggle.BorderSizePixel = 0
                Toggle.LayoutOrder = CountItem
                Toggle.Name = "Toggle"
                Toggle.Parent = SectionAdd

                UICorner20.CornerRadius = UDim.new(0, 4)
                UICorner20.Parent = Toggle

                ToggleTitle.Font = Enum.Font.GothamBold
                ToggleTitle.Text = ToggleConfig.Title
                ToggleTitle.TextSize = 13
                ToggleTitle.TextColor3 = Color3.fromRGB(231, 231, 231)
                ToggleTitle.TextXAlignment = Enum.TextXAlignment.Left
                ToggleTitle.TextYAlignment = Enum.TextYAlignment.Top
                ToggleTitle.BackgroundTransparency = 1
                ToggleTitle.Position = UDim2.new(0, 10, 0, 10)
                ToggleTitle.Size = UDim2.new(1, -140, 0, 13)
                ToggleTitle.Name = "ToggleTitle"
                ToggleTitle.Parent = Toggle

                local ToggleTitle2 = Instance.new("TextLabel")
                ToggleTitle2.Font = Enum.Font.GothamBold
                ToggleTitle2.Text = ToggleConfig.Title2
                ToggleTitle2.TextSize = 12
                ToggleTitle2.TextColor3 = Color3.fromRGB(231, 231, 231)
                ToggleTitle2.TextXAlignment = Enum.TextXAlignment.Left
                ToggleTitle2.TextYAlignment = Enum.TextYAlignment.Top
                ToggleTitle2.BackgroundTransparency = 1
                ToggleTitle2.Position = UDim2.new(0, 10, 0, 23)
                ToggleTitle2.Size = UDim2.new(1, -140, 0, 12)
                ToggleTitle2.Name = "ToggleTitle2"
                ToggleTitle2.Parent = Toggle

                ToggleContent.Font = Enum.Font.GothamBold
                ToggleContent.Text = ToggleConfig.Content
                ToggleContent.TextColor3 = Color3.fromRGB(255, 255, 255)
                ToggleContent.TextSize = 12
                ToggleContent.TextTransparency = 0.6
                ToggleContent.TextXAlignment = Enum.TextXAlignment.Left
                ToggleContent.TextYAlignment = Enum.TextYAlignment.Top
                ToggleContent.BackgroundTransparency = 1
                ToggleContent.Size = UDim2.new(1, -140, 0, 0)
                ToggleContent.AutomaticSize = Enum.AutomaticSize.Y
                ToggleContent.TextWrapped = true
                ToggleContent.Name = "ToggleContent"
                ToggleContent.Parent = Toggle

                if ToggleConfig.Title2 ~= "" then
                    ToggleTitle2.Visible = true
                    ToggleContent.Position = UDim2.new(0, 10, 0, 36)
                else
                    ToggleTitle2.Visible = false
                    ToggleContent.Position = UDim2.new(0, 10, 0, 23)
                end

                local function updateToggleHeight()
                    local contentHeight = math.max(ToggleContent.AbsoluteSize.Y, 12)
                    local baseHeight = ToggleConfig.Title2 ~= "" and 47 or 33
                    Toggle.Size = UDim2.new(1, 0, 0, baseHeight + contentHeight)
                end
                updateToggleHeight()
                ToggleContent:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
                    updateToggleHeight()
                    UpdateSizeSection()
                end)

                ToggleButton.Font = Enum.Font.SourceSans
                ToggleButton.Text = ""
                ToggleButton.BackgroundTransparency = 1
                ToggleButton.Size = UDim2.new(1, 0, 1, 0)
                ToggleButton.Name = "ToggleButton"
                ToggleButton.Parent = Toggle

                FeatureFrame2.AnchorPoint = Vector2.new(1, 0.5)
                FeatureFrame2.BackgroundTransparency = 0.92
                FeatureFrame2.BorderSizePixel = 0
                FeatureFrame2.Position = UDim2.new(1, -15, 0.5, 0)
                FeatureFrame2.Size = UDim2.new(0, 30, 0, 15)
                FeatureFrame2.Name = "FeatureFrame"
                FeatureFrame2.Parent = Toggle

                UICorner22.Parent = FeatureFrame2

                UIStroke8.Color = Color3.fromRGB(255, 255, 255)
                UIStroke8.Thickness = 2
                UIStroke8.Transparency = 0.9
                UIStroke8.Parent = FeatureFrame2

                ToggleCircle.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
                ToggleCircle.BorderSizePixel = 0
                ToggleCircle.Size = UDim2.new(0, 14, 0, 14)
                ToggleCircle.Name = "ToggleCircle"
                ToggleCircle.Parent = FeatureFrame2

                UICorner23.CornerRadius = UDim.new(0, 15)
                UICorner23.Parent = ToggleCircle

                ToggleButton.Activated:Connect(function()
                    ToggleFunc.Value = not ToggleFunc.Value
                    ToggleFunc:Set(ToggleFunc.Value)
                end)

                function ToggleFunc:Set(Value, skipSave)
                    if typeof(ToggleConfig.Callback) == "function" then
                        local ok, err = pcall(function()
                            ToggleConfig.Callback(Value)
                        end)
                        if not ok then warn("Toggle Callback error:", err) end
                    end
                    if not skipSave then
                        ConfigData[configKey] = Value
                        SaveConfig()
                    end
                    if Value then
                        ToggleTitle.TextColor3 = GuiConfig.Color
                        ToggleCircle.Position = UDim2.new(0, 15, 0, 0)
                        UIStroke8.Color = GuiConfig.Color
                        UIStroke8.Transparency = 0
                        FeatureFrame2.BackgroundColor3 = GuiConfig.Color
                        FeatureFrame2.BackgroundTransparency = 0
                    else
                        ToggleTitle.TextColor3 = Color3.fromRGB(230, 230, 230)
                        ToggleCircle.Position = UDim2.new(0, 0, 0, 0)
                        UIStroke8.Color = Color3.fromRGB(255, 255, 255)
                        UIStroke8.Transparency = 0.9
                        FeatureFrame2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                        FeatureFrame2.BackgroundTransparency = 0.92
                    end
                end

                ToggleFunc:Set(ToggleFunc.Value)
                CountItem = CountItem + 1
                Elements[configKey] = ToggleFunc
                toggleElements[configKey] = ToggleFunc
                return ToggleFunc
            end

            function Items:AddSlider(SliderConfig)
                local SliderConfig = SliderConfig or {}
                SliderConfig.Title = SliderConfig.Title or "Slider"
                SliderConfig.Content = SliderConfig.Content or ""
                SliderConfig.Increment = tonumber(SliderConfig.Increment)
                if not SliderConfig.Increment or SliderConfig.Increment == 0 then
                    SliderConfig.Increment = 1
                end
                SliderConfig.Min = tonumber(SliderConfig.Min) or 0
                SliderConfig.Max = tonumber(SliderConfig.Max) or 100
                if SliderConfig.Max < SliderConfig.Min then
                    SliderConfig.Max = SliderConfig.Min
                end
                if SliderConfig.Default == nil then
                    SliderConfig.Default = 50
                end
                SliderConfig.Default = tonumber(SliderConfig.Default) or SliderConfig.Min
                SliderConfig.Callback = SliderConfig.Callback or function() end

                local configKey = "Slider_" .. SliderConfig.Title
                if ConfigData[configKey] ~= nil then
                    local savedValue = tonumber(ConfigData[configKey])
                    if savedValue ~= nil then
                        SliderConfig.Default = savedValue
                    end
                end
                SliderConfig.Default = math.clamp(SliderConfig.Default, SliderConfig.Min, SliderConfig.Max)

                local SliderFunc = { Value = SliderConfig.Default }

                local incrementDecimals = 0
                local incDecimal = tostring(SliderConfig.Increment):match("%.(%d+)")
                if incDecimal then
                    incrementDecimals = #incDecimal
                end

                local function formatValue(val)
                    if incrementDecimals > 0 then
                        return tonumber(string.format("%." .. incrementDecimals .. "f", val)) or val
                    end
                    return val
                end

                local Slider = Instance.new("Frame");
                local UICorner15 = Instance.new("UICorner");
                local SliderTitle = Instance.new("TextLabel");
                local SliderContent = Instance.new("TextLabel");
                local SliderInput = Instance.new("Frame");
                local UICorner16 = Instance.new("UICorner");
                local TextBox = Instance.new("TextBox");
                local SliderFrame = Instance.new("Frame");
                local UICorner17 = Instance.new("UICorner");
                local SliderDraggable = Instance.new("Frame");
                local UICorner18 = Instance.new("UICorner");
                local UIStroke5 = Instance.new("UIStroke");
                local SliderCircle = Instance.new("Frame");
                local UICorner19 = Instance.new("UICorner");
                local UIStroke6 = Instance.new("UIStroke");
                local UIStroke7 = Instance.new("UIStroke");

                Slider.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                Slider.BackgroundTransparency = 0.9350000023841858
                Slider.BorderColor3 = Color3.fromRGB(0, 0, 0)
                Slider.BorderSizePixel = 0
                Slider.LayoutOrder = CountItem
                Slider.Size = UDim2.new(1, 0, 0, 46)
                Slider.Name = "Slider"
                Slider.Parent = SectionAdd

                UICorner15.CornerRadius = UDim.new(0, 4)
                UICorner15.Parent = Slider

                SliderTitle.Font = Enum.Font.GothamBold
                SliderTitle.Text = SliderConfig.Title
                SliderTitle.TextColor3 = Color3.fromRGB(230.77499270439148, 230.77499270439148, 230.77499270439148)
                SliderTitle.TextSize = 13
                SliderTitle.TextXAlignment = Enum.TextXAlignment.Left
                SliderTitle.TextYAlignment = Enum.TextYAlignment.Top
                SliderTitle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                SliderTitle.BackgroundTransparency = 0.9990000128746033
                SliderTitle.BorderColor3 = Color3.fromRGB(0, 0, 0)
                SliderTitle.BorderSizePixel = 0
                SliderTitle.Position = UDim2.new(0, 10, 0, 10)
                SliderTitle.Size = UDim2.new(1, -180, 0, 13)
                SliderTitle.Name = "SliderTitle"
                SliderTitle.Parent = Slider

                SliderContent.Font = Enum.Font.GothamBold
                SliderContent.Text = SliderConfig.Content
                SliderContent.TextColor3 = Color3.fromRGB(255, 255, 255)
                SliderContent.TextSize = 12
                SliderContent.TextTransparency = 0.6000000238418579
                SliderContent.TextXAlignment = Enum.TextXAlignment.Left
                SliderContent.TextYAlignment = Enum.TextYAlignment.Bottom
                SliderContent.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                SliderContent.BackgroundTransparency = 0.9990000128746033
                SliderContent.BorderColor3 = Color3.fromRGB(0, 0, 0)
                SliderContent.BorderSizePixel = 0
                SliderContent.Position = UDim2.new(0, 10, 0, 25)
                SliderContent.Size = UDim2.new(1, -180, 0, 12)
                SliderContent.Name = "SliderContent"
                SliderContent.Parent = Slider
                local lines = math.floor(SliderContent.TextBounds.X / SliderContent.AbsoluteSize.X)
                SliderContent.Size = UDim2.new(1, -180, 0, 12 + (12 * lines))
                SliderContent.TextWrapped = true
                Slider.Size = UDim2.new(1, 0, 0, SliderContent.AbsoluteSize.Y + 33)

                SliderContent:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
                    SliderContent.TextWrapped = false
                    SliderContent.Size = UDim2.new(1, -180, 0, 12 + (12 * lines))
                    Slider.Size = UDim2.new(1, 0, 0, SliderContent.AbsoluteSize.Y + 33)
                    SliderContent.TextWrapped = true
                    UpdateSizeSection()
                end)

                SliderInput.AnchorPoint = Vector2.new(0, 0.5)
                SliderInput.BackgroundColor3 = GuiConfig.Color
                SliderInput.BorderColor3 = Color3.fromRGB(0, 0, 0)
                SliderInput.BackgroundTransparency = 1
                SliderInput.BorderSizePixel = 0
                SliderInput.Position = UDim2.new(1, -155, 0.5, 0)
                SliderInput.Size = UDim2.new(0, 28, 0, 20)
                SliderInput.Name = "SliderInput"
                SliderInput.Parent = Slider

                UICorner16.CornerRadius = UDim.new(0, 2)
                UICorner16.Parent = SliderInput

                TextBox.Font = Enum.Font.GothamBold
                TextBox.Text = "90"
                TextBox.TextColor3 = Color3.fromRGB(255, 255, 255)
                TextBox.TextSize = 13
                TextBox.TextWrapped = true
                TextBox.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
                TextBox.BackgroundTransparency = 0.9990000128746033
                TextBox.BorderColor3 = Color3.fromRGB(0, 0, 0)
                TextBox.BorderSizePixel = 0
                TextBox.Position = UDim2.new(0, -1, 0, 0)
                TextBox.Size = UDim2.new(1, 0, 1, 0)
                TextBox.Parent = SliderInput

                SliderFrame.AnchorPoint = Vector2.new(1, 0.5)
                SliderFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                SliderFrame.BackgroundTransparency = 0.800000011920929
                SliderFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
                SliderFrame.BorderSizePixel = 0
                SliderFrame.Position = UDim2.new(1, -20, 0.5, 0)
                SliderFrame.Size = UDim2.new(0, 100, 0, 3)
                SliderFrame.Name = "SliderFrame"
                SliderFrame.Parent = Slider

                UICorner17.Parent = SliderFrame

                SliderDraggable.AnchorPoint = Vector2.new(0, 0.5)
                SliderDraggable.BackgroundColor3 = GuiConfig.Color
                SliderDraggable.BorderColor3 = Color3.fromRGB(0, 0, 0)
                SliderDraggable.BorderSizePixel = 0
                SliderDraggable.Position = UDim2.new(0, 0, 0.5, 0)
                SliderDraggable.Size = UDim2.new(0.899999976, 0, 0, 1)
                SliderDraggable.Name = "SliderDraggable"
                SliderDraggable.Parent = SliderFrame

                UICorner18.Parent = SliderDraggable

                SliderCircle.AnchorPoint = Vector2.new(1, 0.5)
                SliderCircle.BackgroundColor3 = GuiConfig.Color
                SliderCircle.BorderColor3 = Color3.fromRGB(0, 0, 0)
                SliderCircle.BorderSizePixel = 0
                SliderCircle.Position = UDim2.new(1, 4, 0.5, 0)
                SliderCircle.Size = UDim2.new(0, 8, 0, 8)
                SliderCircle.Name = "SliderCircle"
                SliderCircle.Parent = SliderDraggable

                UICorner19.Parent = SliderCircle

                UIStroke6.Color = GuiConfig.Color
                UIStroke6.Parent = SliderCircle

                local Dragging = false
                local InternalSet = false
                local function Round(Number, Factor)
                    if not Factor or Factor == 0 then
                        return Number
                    end
                    local scaled = Number / Factor
                    local roundedScaled = (math.round and math.round(scaled)) or math.floor(scaled + 0.5)
                    local stepped = roundedScaled * Factor
                    return formatValue(stepped)
                end
                function SliderFunc:Set(Value)
                    local rounded = math.clamp(Round(tonumber(Value) or SliderConfig.Min, SliderConfig.Increment), SliderConfig.Min, SliderConfig.Max)
                    SliderFunc.Value = rounded
                    InternalSet = true
                    TextBox.Text = tostring(formatValue(rounded))
                    InternalSet = false
                    local range = SliderConfig.Max - SliderConfig.Min
                    local scale = 0
                    if range ~= 0 then
                        scale = (rounded - SliderConfig.Min) / range
                    end
                    SliderDraggable.Size = UDim2.fromScale(math.clamp(scale, 0, 1), 1)

                    SliderConfig.Callback(rounded)
                    ConfigData[configKey] = rounded
                    SaveConfig()
                end

                SliderFrame.InputBegan:Connect(function(Input)
                    if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
                        Dragging = true
                        SliderCircle.Size = UDim2.new(0, 14, 0, 14)
                        local SizeScale = math.clamp(
                            (Input.Position.X - SliderFrame.AbsolutePosition.X) / SliderFrame.AbsoluteSize.X,
                            0,
                            1
                        )
                        SliderFunc:Set(SliderConfig.Min + ((SliderConfig.Max - SliderConfig.Min) * SizeScale))
                    end
                end)

                SliderFrame.InputEnded:Connect(function(Input)
                    if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
                        Dragging = false
                        SliderConfig.Callback(SliderFunc.Value)
                        SliderCircle.Size = UDim2.new(0, 8, 0, 8)
                    end
                end)

                UserInputService.InputChanged:Connect(function(Input)
                    if Dragging and (Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch) then
                        local SizeScale = math.clamp(
                            (Input.Position.X - SliderFrame.AbsolutePosition.X) / SliderFrame.AbsoluteSize.X,
                            0,
                            1
                        )
                        SliderFunc:Set(SliderConfig.Min + ((SliderConfig.Max - SliderConfig.Min) * SizeScale))
                    end
                end)

                TextBox:GetPropertyChangedSignal("Text"):Connect(function()
                    if InternalSet then
                        return
                    end
                    local sanitized = TextBox.Text:gsub(",", ".")
                    local number = tonumber(sanitized)
                    if number ~= nil then
                        SliderFunc:Set(number)
                    end
                end)
                SliderFunc:Set(SliderConfig.Default)
                CountItem = CountItem + 1
                Elements[configKey] = SliderFunc
                return SliderFunc
            end

            function Items:AddInput(InputConfig)
                local InputConfig = InputConfig or {}
                InputConfig.Title = InputConfig.Title or "Title"
                InputConfig.Content = InputConfig.Content or ""
                InputConfig.Callback = InputConfig.Callback or function() end
                InputConfig.Default = InputConfig.Default or ""

                local configKey = "Input_" .. InputConfig.Title
                if ConfigData[configKey] ~= nil then
                    InputConfig.Default = ConfigData[configKey]
                end

                local InputFunc = { Value = InputConfig.Default }

                local Input = Instance.new("Frame");
                local UICorner12 = Instance.new("UICorner");
                local InputTitle = Instance.new("TextLabel");
                local InputContent = Instance.new("TextLabel");
                local InputFrame = Instance.new("Frame");
                local UICorner13 = Instance.new("UICorner");
                local InputTextBox = Instance.new("TextBox");

                Input.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                Input.BackgroundTransparency = 0.9350000023841858
                Input.BorderColor3 = Color3.fromRGB(0, 0, 0)
                Input.BorderSizePixel = 0
                Input.LayoutOrder = CountItem
                Input.Size = UDim2.new(1, 0, 0, 46)
                Input.Name = "Input"
                Input.Parent = SectionAdd

                UICorner12.CornerRadius = UDim.new(0, 4)
                UICorner12.Parent = Input

                InputTitle.Font = Enum.Font.GothamBold
                InputTitle.Text = InputConfig.Title or "TextBox"
                InputTitle.TextColor3 = Color3.fromRGB(230.77499270439148, 230.77499270439148, 230.77499270439148)
                InputTitle.TextSize = 13
                InputTitle.TextXAlignment = Enum.TextXAlignment.Left
                InputTitle.TextYAlignment = Enum.TextYAlignment.Top
                InputTitle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                InputTitle.BackgroundTransparency = 0.9990000128746033
                InputTitle.BorderColor3 = Color3.fromRGB(0, 0, 0)
                InputTitle.BorderSizePixel = 0
                InputTitle.Position = UDim2.new(0, 10, 0, 10)
                InputTitle.Size = UDim2.new(1, -180, 0, 13)
                InputTitle.Name = "InputTitle"
                InputTitle.Parent = Input

                InputContent.Font = Enum.Font.GothamBold
                InputContent.Text = InputConfig.Content or "This is a TextBox"
                InputContent.TextColor3 = Color3.fromRGB(255, 255, 255)
                InputContent.TextSize = 12
                InputContent.TextTransparency = 0.6000000238418579
                InputContent.TextWrapped = true
                InputContent.TextXAlignment = Enum.TextXAlignment.Left
                InputContent.TextYAlignment = Enum.TextYAlignment.Bottom
                InputContent.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                InputContent.BackgroundTransparency = 0.9990000128746033
                InputContent.BorderColor3 = Color3.fromRGB(0, 0, 0)
                InputContent.BorderSizePixel = 0
                InputContent.Position = UDim2.new(0, 10, 0, 25)
                InputContent.Size = UDim2.new(1, -180, 0, 12)
                InputContent.Name = "InputContent"
                InputContent.Parent = Input
                local lines = math.floor(InputContent.TextBounds.X / InputContent.AbsoluteSize.X)
                InputContent.Size = UDim2.new(1, -180, 0, 12 + (12 * lines))
                InputContent.TextWrapped = true
                Input.Size = UDim2.new(1, 0, 0, InputContent.AbsoluteSize.Y + 33)

                InputContent:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
                    InputContent.TextWrapped = false
                    InputContent.Size = UDim2.new(1, -180, 0, 12 + (12 * lines))
                    Input.Size = UDim2.new(1, 0, 0, InputContent.AbsoluteSize.Y + 33)
                    InputContent.TextWrapped = true
                    UpdateSizeSection()
                end)

                InputFrame.AnchorPoint = Vector2.new(1, 0.5)
                InputFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                InputFrame.BackgroundTransparency = 0.949999988079071
                InputFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
                InputFrame.BorderSizePixel = 0
                InputFrame.ClipsDescendants = true
                InputFrame.Position = UDim2.new(1, -7, 0.5, 0)
                InputFrame.Size = UDim2.new(0, 148, 0, 30)
                InputFrame.Name = "InputFrame"
                InputFrame.Parent = Input

                UICorner13.CornerRadius = UDim.new(0, 4)
                UICorner13.Parent = InputFrame

                InputTextBox.CursorPosition = -1
                InputTextBox.Font = Enum.Font.GothamBold
                InputTextBox.PlaceholderColor3 = Color3.fromRGB(120.00000044703484, 120.00000044703484,
                    120.00000044703484)
                InputTextBox.PlaceholderText = "Input Here"
                InputTextBox.Text = InputConfig.Default
                InputTextBox.TextColor3 = Color3.fromRGB(255, 255, 255)
                InputTextBox.TextSize = 12
                InputTextBox.TextXAlignment = Enum.TextXAlignment.Left
                InputTextBox.AnchorPoint = Vector2.new(0, 0.5)
                InputTextBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                InputTextBox.BackgroundTransparency = 0.9990000128746033
                InputTextBox.BorderColor3 = Color3.fromRGB(0, 0, 0)
                InputTextBox.BorderSizePixel = 0
                InputTextBox.Position = UDim2.new(0, 5, 0.5, 0)
                InputTextBox.Size = UDim2.new(1, -10, 1, -8)
                InputTextBox.Name = "InputTextBox"
                InputTextBox.Parent = InputFrame
                function InputFunc:Set(Value)
                    InputTextBox.Text = Value
                    InputFunc.Value = Value
                    InputConfig.Callback(Value)
                    ConfigData[configKey] = Value
                    SaveConfig()
                end

                InputFunc:Set(InputFunc.Value)

                InputTextBox.FocusLost:Connect(function()
                    InputFunc:Set(InputTextBox.Text)
                end)
                CountItem = CountItem + 1
                Elements[configKey] = InputFunc
                return InputFunc
            end
            
            function Items:AddDropdown(DropdownConfig)
                local DropdownConfig = DropdownConfig or {}
                DropdownConfig.Title = DropdownConfig.Title or "Title"
                DropdownConfig.Content = DropdownConfig.Content or ""
                DropdownConfig.Multi = DropdownConfig.Multi or false
                DropdownConfig.Options = DropdownConfig.Options or {}
                DropdownConfig.Default = DropdownConfig.Default or (DropdownConfig.Multi and {} or nil)
                DropdownConfig.Callback = DropdownConfig.Callback or function() end

                local configKey = "Dropdown_" .. DropdownConfig.Title
                if ConfigData[configKey] ~= nil then
                    DropdownConfig.Default = ConfigData[configKey]
                end

                local DropdownFunc = { Value = DropdownConfig.Default, Options = DropdownConfig.Options }

                local Dropdown = Instance.new("Frame")
                local DropdownButton = Instance.new("TextButton")
                local UICorner10 = Instance.new("UICorner")
                local DropdownTitle = Instance.new("TextLabel")
                local DropdownContent = Instance.new("TextLabel")
                local SelectOptionsFrame = Instance.new("Frame")
                local UICorner11 = Instance.new("UICorner")
                local OptionSelecting = Instance.new("TextLabel")
                local OptionArrow = Instance.new("TextLabel")

                Dropdown.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                Dropdown.BackgroundTransparency = 0.935
                Dropdown.BorderSizePixel = 0
                Dropdown.LayoutOrder = CountItem
                Dropdown.Size = UDim2.new(1, 0, 0, 46)
                Dropdown.Name = "Dropdown"
                Dropdown.Parent = SectionAdd

                DropdownButton.Text = ""
                DropdownButton.BackgroundTransparency = 1
                DropdownButton.Size = UDim2.new(1, 0, 1, 0)
                DropdownButton.Name = "ToggleButton"
                DropdownButton.Parent = Dropdown

                UICorner10.CornerRadius = UDim.new(0, 4)
                UICorner10.Parent = Dropdown

                DropdownTitle.Font = Enum.Font.GothamBold
                DropdownTitle.Text = DropdownConfig.Title
                DropdownTitle.TextColor3 = Color3.fromRGB(230, 230, 230)
                DropdownTitle.TextSize = 13
                DropdownTitle.TextXAlignment = Enum.TextXAlignment.Left
                DropdownTitle.BackgroundTransparency = 1
                DropdownTitle.Position = UDim2.new(0, 10, 0, 10)
                DropdownTitle.Size = UDim2.new(1, -180, 0, 13)
                DropdownTitle.Name = "DropdownTitle"
                DropdownTitle.Parent = Dropdown

                DropdownContent.Font = Enum.Font.GothamBold
                DropdownContent.Text = DropdownConfig.Content
                DropdownContent.TextColor3 = Color3.fromRGB(255, 255, 255)
                DropdownContent.TextSize = 12
                DropdownContent.TextTransparency = 0.6
                DropdownContent.TextWrapped = true
                DropdownContent.TextXAlignment = Enum.TextXAlignment.Left
                DropdownContent.BackgroundTransparency = 1
                DropdownContent.Position = UDim2.new(0, 10, 0, 25)
                DropdownContent.Size = UDim2.new(1, -180, 0, 12)
                DropdownContent.Name = "DropdownContent"
                DropdownContent.Parent = Dropdown

                SelectOptionsFrame.AnchorPoint = Vector2.new(1, 0.5)
                SelectOptionsFrame.BackgroundTransparency = 0.95
                SelectOptionsFrame.Position = UDim2.new(1, -7, 0.5, 0)
                SelectOptionsFrame.Size = UDim2.new(0, 148, 0, 30)
                SelectOptionsFrame.Name = "SelectOptionsFrame"
                SelectOptionsFrame.Parent = Dropdown

                UICorner11.CornerRadius = UDim.new(0, 4)
                UICorner11.Parent = SelectOptionsFrame


                OptionSelecting.Font = Enum.Font.GothamBold
                OptionSelecting.Text = DropdownConfig.Multi and "Select Options" or "Select Option"
                OptionSelecting.TextColor3 = Color3.fromRGB(255, 255, 255)
                OptionSelecting.TextSize = 12
                OptionSelecting.TextTransparency = 0.6
                OptionSelecting.TextXAlignment = Enum.TextXAlignment.Left
                OptionSelecting.AnchorPoint = Vector2.new(0, 0.5)
                OptionSelecting.BackgroundTransparency = 1
                OptionSelecting.Position = UDim2.new(0, 5, 0.5, 0)
                OptionSelecting.Size = UDim2.new(1, -30, 1, -8)
                OptionSelecting.Name = "OptionSelecting"
                OptionSelecting.Parent = SelectOptionsFrame

                OptionArrow.Font = Enum.Font.GothamBold
                OptionArrow.Text = ">"
                OptionArrow.TextColor3 = defaultArrowColor
                OptionArrow.TextSize = 16
                OptionArrow.AnchorPoint = Vector2.new(1, 0.5)
                OptionArrow.BackgroundTransparency = 1
                OptionArrow.Position = UDim2.new(1, -2, 0.5, 0)
                OptionArrow.Size = UDim2.new(0, 18, 0, 18)
                OptionArrow.Name = "OptionArrow"
                OptionArrow.Parent = SelectOptionsFrame

                local DropdownContainer = Instance.new("Frame")
                DropdownContainer.Size = UDim2.new(1, 0, 1, 0)
                DropdownContainer.BackgroundTransparency = 1
                DropdownContainer.Visible = false
                DropdownContainer.Parent = DropdownFolder

                DropdownButton.Activated:Connect(function()
                    openDropdownOverlay(DropdownContainer, OptionArrow)
                end)

                local SearchBox = Instance.new("TextBox")
                SearchBox.PlaceholderText = "Search"
                SearchBox.Font = Enum.Font.Gotham
                SearchBox.Text = ""
                SearchBox.TextSize = 12
                SearchBox.TextColor3 = Color3.fromRGB(255, 255, 255)
                SearchBox.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
                SearchBox.BackgroundTransparency = 0.9
                SearchBox.BorderSizePixel = 0
                SearchBox.Size = UDim2.new(1, 0, 0, 25)
                SearchBox.Position = UDim2.new(0, 0, 0, 0)
                SearchBox.ClearTextOnFocus = false
                SearchBox.Name = "SearchBox"
                SearchBox.Parent = DropdownContainer

                local ScrollSelect = Instance.new("ScrollingFrame")
                ScrollSelect.Size = UDim2.new(1, 0, 1, -30)
                ScrollSelect.Position = UDim2.new(0, 0, 0, 30)
                ScrollSelect.ScrollBarImageTransparency = 1
                ScrollSelect.BorderSizePixel = 0
                ScrollSelect.BackgroundTransparency = 1
                ScrollSelect.ScrollBarThickness = 0
                ScrollSelect.CanvasSize = UDim2.new(0, 0, 0, 0)
                ScrollSelect.Name = "ScrollSelect"
                ScrollSelect.Parent = DropdownContainer

                local UIListLayout4 = Instance.new("UIListLayout")
                UIListLayout4.Padding = UDim.new(0, 3)
                UIListLayout4.SortOrder = Enum.SortOrder.LayoutOrder
                UIListLayout4.Parent = ScrollSelect

                UIListLayout4:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                    ScrollSelect.CanvasSize = UDim2.new(0, 0, 0, UIListLayout4.AbsoluteContentSize.Y)
                end)

                SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
                    local query = string.lower(SearchBox.Text)
                    for _, option in pairs(ScrollSelect:GetChildren()) do
                        if option.Name == "Option" and option:FindFirstChild("OptionText") then
                            local text = string.lower(option.OptionText.Text)
                            option.Visible = query == "" or string.find(text, query, 1, true)
                        end
                    end
                    ScrollSelect.CanvasSize = UDim2.new(0, 0, 0, UIListLayout4.AbsoluteContentSize.Y)
                end)

                local DropCount = 0

                function DropdownFunc:Clear()
                    for _, DropFrame in ScrollSelect:GetChildren() do
                        if DropFrame.Name == "Option" then
                            DropFrame:Destroy()
                        end
                    end
                    DropdownFunc.Value = DropdownConfig.Multi and {} or nil
                    DropdownFunc.Options = {}
                    OptionSelecting.Text = DropdownConfig.Multi and "Select Options" or "Select Option"
                    DropCount = 0
                end

                function DropdownFunc:AddOption(option)
                    local label, value
                    if typeof(option) == "table" and option.Label and option.Value ~= nil then
                        label = tostring(option.Label)
                        value = option.Value
                    else
                        label = tostring(option)
                        value = option
                    end

                    local Option = Instance.new("Frame")
                    local OptionButton = Instance.new("TextButton")
                    local OptionText = Instance.new("TextLabel")
                    local ChooseFrame = Instance.new("Frame")
                    local UIStroke15 = Instance.new("UIStroke")
                    local UICorner38 = Instance.new("UICorner")
                    local UICorner37 = Instance.new("UICorner")

                    Option.BackgroundTransparency = 1
                    Option.Size = UDim2.new(1, 0, 0, 30)
                    Option.Name = "Option"
                    Option.Parent = ScrollSelect

                    UICorner37.CornerRadius = UDim.new(0, 3)
                    UICorner37.Parent = Option

                    OptionButton.BackgroundTransparency = 1
                    OptionButton.Size = UDim2.new(1, 0, 1, 0)
                    OptionButton.Text = ""
                    OptionButton.Name = "OptionButton"
                    OptionButton.Parent = Option

                    OptionText.Font = Enum.Font.GothamBold
                    OptionText.Text = label
                    OptionText.TextSize = 13
                    OptionText.TextColor3 = Color3.fromRGB(230, 230, 230)
                    OptionText.Position = UDim2.new(0, 8, 0, 8)
                    OptionText.Size = UDim2.new(1, -100, 0, 13)
                    OptionText.BackgroundTransparency = 1
                    OptionText.TextXAlignment = Enum.TextXAlignment.Left
                    OptionText.Name = "OptionText"
                    OptionText.Parent = Option

                    Option:SetAttribute("RealValue", value)

                    ChooseFrame.AnchorPoint = Vector2.new(0, 0.5)
                    ChooseFrame.BackgroundColor3 = GuiConfig.Color
                    ChooseFrame.Position = UDim2.new(0, 2, 0.5, 0)
                    ChooseFrame.Size = UDim2.new(0, 0, 0, 0)
                    ChooseFrame.Name = "ChooseFrame"
                    ChooseFrame.Parent = Option

                    UIStroke15.Color = GuiConfig.Color
                    UIStroke15.Thickness = 1.6
                    UIStroke15.Transparency = 0.999
                    UIStroke15.Parent = ChooseFrame
                    UICorner38.Parent = ChooseFrame

                    OptionButton.Activated:Connect(function()
                        if DropdownConfig.Multi then
                            if not table.find(DropdownFunc.Value, value) then
                                table.insert(DropdownFunc.Value, value)
                            else
                                for i, v in pairs(DropdownFunc.Value) do
                                    if v == value then
                                        table.remove(DropdownFunc.Value, i)
                                        break
                                    end
                                end
                            end
                        else
                            DropdownFunc.Value = value
                        end
                        DropdownFunc:Set(DropdownFunc.Value)
                    end)
                end

                function DropdownFunc:Set(Value)
                    if DropdownConfig.Multi then
                        DropdownFunc.Value = type(Value) == "table" and Value or {}
                    else
                        DropdownFunc.Value = (type(Value) == "table" and Value[1]) or Value
                    end

                    ConfigData[configKey] = DropdownFunc.Value
                    SaveConfig()
                    if not DropdownConfig.Multi then
                        closeDropdownOverlay()
                    end

                    local texts = {}
                    for _, Drop in ScrollSelect:GetChildren() do
                        if Drop.Name == "Option" and Drop:FindFirstChild("OptionText") then
                            local v = Drop:GetAttribute("RealValue")
                            local selected = DropdownConfig.Multi and table.find(DropdownFunc.Value, v) or
                                DropdownFunc.Value == v

                            if selected then
                                Drop.ChooseFrame.Size = UDim2.new(0, 1, 0, 12)
                                Drop.ChooseFrame.UIStroke.Transparency = 0
                                Drop.BackgroundTransparency = 0.935
                                table.insert(texts, Drop.OptionText.Text)
                            else
                                Drop.ChooseFrame.Size = UDim2.new(0, 0, 0, 0)
                                Drop.ChooseFrame.UIStroke.Transparency = 0.999
                                Drop.BackgroundTransparency = 0.999
                            end
                        end
                    end

                    OptionSelecting.Text = (#texts == 0)
                        and (DropdownConfig.Multi and "Select Options" or "Select Option")
                        or table.concat(texts, ", ")

                    if DropdownConfig.Callback then
                        if DropdownConfig.Multi then
                            DropdownConfig.Callback(DropdownFunc.Value)
                        else
                            local str = (DropdownFunc.Value ~= nil) and tostring(DropdownFunc.Value) or ""
                            DropdownConfig.Callback(str)
                        end
                    end
                end

                function DropdownFunc:SetValue(val)
                    self:Set(val)
                end

                function DropdownFunc:GetValue()
                    return self.Value
                end

                function DropdownFunc:SetValues(newList, selecting)
                    newList = newList or {}
                    selecting = selecting or (DropdownConfig.Multi and {} or nil)
                    DropdownFunc:Clear()
                    for _, v in ipairs(newList) do
                        DropdownFunc:AddOption(v)
                    end
                    DropdownFunc.Options = newList
                    DropdownFunc:Set(selecting)
                end

                DropdownFunc:SetValues(DropdownFunc.Options, DropdownFunc.Value)

                CountItem = CountItem + 1
                Elements[configKey] = DropdownFunc
                return DropdownFunc
            end

            function Items:AddDivider()
                local Divider = Instance.new("Frame")
                Divider.Name = "Divider"
                Divider.Parent = SectionAdd
                Divider.AnchorPoint = Vector2.new(0.5, 0)
                Divider.Position = UDim2.new(0.5, 0, 0, 0)
                Divider.Size = UDim2.new(1, 0, 0, 1)
                Divider.BackgroundColor3 = Color3.fromRGB(70, 75, 86)
                Divider.BackgroundTransparency = 0.35
                Divider.BorderSizePixel = 0
                Divider.LayoutOrder = CountItem

                CountItem = CountItem + 1
                return Divider
            end

            function Items:AddSubSection(title)
                title = title or "Sub Section"

                local SubSection = Instance.new("Frame")
                SubSection.Name = "SubSection"
                SubSection.Parent = SectionAdd
                SubSection.BackgroundTransparency = 1
                SubSection.Size = UDim2.new(1, 0, 0, 22)
                SubSection.LayoutOrder = CountItem

                local Background = Instance.new("Frame")
                Background.Parent = SubSection
                Background.Size = UDim2.new(1, 0, 1, 0)
                Background.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                Background.BackgroundTransparency = 0.935
                Background.BorderSizePixel = 0
                Instance.new("UICorner", Background).CornerRadius = UDim.new(0, 6)

                local Label = Instance.new("TextLabel")
                Label.Parent = SubSection
                Label.AnchorPoint = Vector2.new(0.5, 0.5)
                Label.Position = UDim2.new(0.5, 0, 0.5, 0)
                Label.Size = UDim2.new(1, -20, 1, 0)
                Label.BackgroundTransparency = 1
                Label.Font = Enum.Font.GothamBold
                Label.Text = title
                Label.TextColor3 = Color3.fromRGB(230, 230, 230)
                Label.TextSize = 14
                Label.TextXAlignment = Enum.TextXAlignment.Center

                CountItem = CountItem + 1
                return SubSection
            end

            CountSection = CountSection + 1
            return Items
        end

        CountTab = CountTab + 1
        local safeName = TabConfig.Name:gsub("%s+", "_")
        _G[safeName] = Sections
        return Sections
    end

    return Tabs
end

nonoya.SaveConfig = SaveConfig
nonoya.LoadConfigFromFile = LoadConfigFromFile
nonoya.LoadConfigElements = LoadConfigElements
nonoya.ListConfigs = ListConfigs
nonoya.DeleteConfig = DeleteConfig
nonoya.SetConfigName = SetConfigName
nonoya.GetCurrentConfigName = GetCurrentConfigName

return nonoya
