---@class Widget
---@field DrawScreen function
---@field MouseWheel function
---@field MousePress function
---@field KeyPress function
---@field TextInput function
---@field Initialize function
---@field Shutdown function
---@field ViewResize function
---@field GetConfigData function
---@field SetConfigData function
---@field IsAbove function
local widget = widget ---@type Widget

function widget:GetInfo()
    return {
        name = "Keybind Custom Config",
        desc = "GUI for customizing keyboard shortcuts",
        author = "Your Name",
        date = "September 2025",
        license = "GNU GPL, v2 or later",
        layer = -99999,
        enabled = false,
    }
end

-- State
local vsx, vsy = Spring.GetViewGeometry()
local show = false
local centerPosX = 0.5
local centerPosY = 0.5
local window = {
    width = 800,
    height = 600
}
window.x = math.floor((vsx * centerPosX) - (window.width / 2))
window.y = math.floor((vsy * centerPosY) - (window.height / 2))

-- UI Elements state
local backgroundGuishader
local currentBindings = {}
local keyInput = "New Key"
local commandInput = "New Command"
local isCapturingKeys = false
local scrollOffset = 0
local minScrollOffset = -150
local maxScrollOffset = 0
local buttonHover = false
local removeHover = -1

-- Command suggestions
local showSuggestions = false
local suggestions = {}
local selectedSuggestion = 1
local MAX_SUGGESTIONS = 5

-- Constants
local BUTTON_HEIGHT = 24
local INPUT_HEIGHT = 24
local PADDING = 8
local SCROLL_HEIGHT = window.height - 120
local FONT_SIZE = 14
local HEADER_SIZE = 18

-- Colors
local colors = {
    windowBackground = {0.1, 0.1, 0.1, 0.8},
    buttonBackground = {0.2, 0.2, 0.2, 1},
    buttonHover = {0.3, 0.3, 0.3, 1},
    buttonActive = {0.4, 0.4, 0.4, 1},
    text = {1, 1, 1, 1},
    input = {0.15, 0.15, 0.15, 1},
    inputActive = {0.25, 0.25, 0.25, 1},
    removeButton = {0.7, 0.3, 0.3, 1},
    removeButtonHover = {0.8, 0.4, 0.4, 1}
}

local RectRound
local font

-- Available commands and keys
local availableCommands = {}
local availableKeys = {}

local function LoadHotkeyConfigs()
    -- Load available commands and keys from hotkey config files
    local gridKeys = VFS.LoadFile("luaui/configs/hotkeys/grid_keys.txt")
    if gridKeys then
        for line in gridKeys:gmatch("[^\r\n]+") do
            if line:match("^bind%s+") then
                local _, _, key, command = line:find("^bind%s+([^%s]+)%s+([^%s]+)")
                if key and command then
                    availableKeys[key] = true
                    availableCommands[command] = true
                end
            end
        end
    end
    
    -- Add common modifiers
    local modifiers = {"Alt+", "Ctrl+", "Shift+", "Any+"}
    local baseKeys = {}
    for key in pairs(availableKeys) do
        if not key:find("+") then
            baseKeys[key] = true
        end
    end
    
    -- Generate modified keys
    for key in pairs(baseKeys) do
        for _, modifier in ipairs(modifiers) do
            availableKeys[modifier .. key] = true
        end
    end
end

local function LoadCurrentBindings()
    currentBindings = Spring.GetKeyBindings() or {}
		Spring.Echo("currentBindings", currentBindings[0])
    maxScrollOffset = math.max(minScrollOffset, (#currentBindings * (BUTTON_HEIGHT + PADDING)) - SCROLL_HEIGHT)
end

local function SaveBinding(key, command)
    if key and command and key ~= "" and command ~= "" then
        Spring.SendCommands({"bind " .. key .. " " .. command})
        LoadCurrentBindings()
    end
end

local function RemoveBinding(key, command)
    if key and command then
        Spring.SendCommands({"unbind " .. key .. " " .. command})
        LoadCurrentBindings()
    end
end

local function UpdateSuggestions()
    suggestions = {}
    if commandInput ~= "" then
        for command in pairs(availableCommands) do
            if command:lower():find(commandInput:lower(), 1, true) then
                table.insert(suggestions, command)
                if #suggestions >= MAX_SUGGESTIONS then
                    break
                end
            end
        end
        table.sort(suggestions)
    end
    showSuggestions = #suggestions > 0
    selectedSuggestion = 1
end

local function DrawBackground()
    -- Add guishader effect
    if WG['guishader'] then
        if not backgroundGuishader then
            backgroundGuishader = gl.CreateList(function()
                RectRound(window.x, window.y, window.x + window.width, window.y + window.height, elementCorner)
            end)
        end
        WG['guishader'].InsertDlist(backgroundGuishader, 'keybindconfig')
    end
    
    UiElement(window.x, window.y, window.x + window.width, window.y + window.height, 1,1,1,1, 1)
end

local function DrawBindingsList()
    gl.PushMatrix()
    gl.Translate(window.x + elementPadding, window.y + window.height - elementPadding - HEADER_SIZE - elementPadding, 0)
    gl.Scissor(window.x + elementPadding, window.y + HEADER_SIZE + elementPadding, window.width - 2*elementPadding, SCROLL_HEIGHT)

    for i, binding in ipairs(currentBindings) do
        local yPos = -((i-1) * (BUTTON_HEIGHT + elementPadding)) + scrollOffset
        
        if yPos > -SCROLL_HEIGHT and yPos < BUTTON_HEIGHT then
            -- Draw binding row
            UiElement(0, yPos, window.width - 2*elementPadding - 60, yPos + BUTTON_HEIGHT, 0,0,0,0, 1)
            
            -- Draw text
            font:Begin()
            font:SetTextColor(1,1,1,1)
            font:SetOutlineColor(0,0,0,0.4)
            font:Print(binding.boundWith or "", elementPadding, yPos + elementPadding, FONT_SIZE, "n")
            font:Print(binding.command or "", window.width * (1/3), yPos + elementPadding, FONT_SIZE, "n")
            font:Print(binding.extra or "", window.width * (2/3), yPos + elementPadding, FONT_SIZE, "n")
            font:End()
            
            -- Draw remove button
            UiButton(
                window.width - 2*elementPadding - 50, 
                yPos, 
                window.width - 2*elementPadding, 
                yPos + BUTTON_HEIGHT,
                removeHover == i and colors.removeButtonHover or colors.removeButton
            )
            
            font:Begin()
            font:SetTextColor(1,1,1,1)
            font:Print("Del", window.width - 2*elementPadding - 45, yPos + elementPadding, FONT_SIZE, "n")
            font:End()
        end
    end
    
    gl.Scissor(false)
    gl.PopMatrix()
end

local function DrawInputs()
    -- Key input field
    UiElement(
        window.x + elementPadding, 
        window.y + elementPadding + INPUT_HEIGHT + elementPadding,
        window.x + window.width/2 - elementPadding, 
        window.y + elementPadding + INPUT_HEIGHT*2 + elementPadding,
        0,0,0,0,
        1
    )
    
    -- Command input field
    UiElement(
        window.x + window.width/2 + elementPadding,
        window.y + elementPadding + INPUT_HEIGHT + elementPadding,
        window.x + window.width - elementPadding - 60,
        window.y + elementPadding + INPUT_HEIGHT*2 + elementPadding,
        0,0,0,0,
        1
    )
    
    font:Begin()
    font:SetTextColor(1,1,1,1)
    font:SetOutlineColor(0,0,0,0.4)
    font:Print(keyInput,
        window.x + 2*elementPadding,
        window.y + elementPadding + INPUT_HEIGHT + 2*elementPadding,
        FONT_SIZE, "n"
    )
    font:Print(commandInput,
        window.x + window.width/2 + 2*elementPadding,
        window.y + elementPadding + INPUT_HEIGHT + 2*elementPadding,
        FONT_SIZE, "n"
    )
    font:End()
    
    -- Add button
    UiButton(
        window.x + window.width - elementPadding - 50,
        window.y + elementPadding + INPUT_HEIGHT + elementPadding,
        window.x + window.width - elementPadding,
        window.y + elementPadding + INPUT_HEIGHT*2 + elementPadding,
        buttonHover and colors.buttonHover or colors.buttonBackground
    )
    
    font:Begin()
    font:SetTextColor(1,1,1,1)
    font:Print("Add",
        window.x + window.width - elementPadding - 45,
        window.y + elementPadding + INPUT_HEIGHT + 2*elementPadding,
        FONT_SIZE, "n"
    )
    font:End()
end

local function DrawSuggestions()
    if not showSuggestions then return end
    
    local x = window.x + window.width/2 + elementPadding
    local y = window.y + elementPadding + INPUT_HEIGHT*3 + elementPadding
    
    for i, suggestion in ipairs(suggestions) do
        local isSelected = i == selectedSuggestion
        
        UiElement(
            x, y,
            x + window.width/2 - elementPadding - 60,
            y + INPUT_HEIGHT,
            0,0,0,0,
            1,
            isSelected and colors.buttonHover or colors.buttonBackground
        )
        
        font:Begin()
        font:SetTextColor(1,1,1,1)
        font:Print(suggestion, x + elementPadding, y + elementPadding, FONT_SIZE, "n")
        font:End()
        
        y = y - (INPUT_HEIGHT + 2)
    end
end

function widget:DrawScreen()
    if not show then return end
    
    if not font then return end
    
    gl.PushMatrix()
    
    DrawBackground()
    
    -- Draw title
    gl.Color(colors.text)
		font:Begin()
    font:Print("Keybinding Configuration", window.x + PADDING, 
              window.y + window.height - HEADER_SIZE - PADDING, HEADER_SIZE, "n")
		font:End()
    
    DrawBindingsList()
    DrawInputs()
    DrawSuggestions()
    
    gl.PopMatrix()
end

function widget:MouseWheel(up, value)
    if not show then return false end
    
    local mouseX, mouseY = Spring.GetMouseState()
    if mouseX > window.x + PADDING and mouseX < window.x + window.width - PADDING and
       mouseY > window.y + HEADER_SIZE + PADDING and mouseY < window.y + window.height - PADDING then
        scrollOffset = math.max(minScrollOffset, math.min(maxScrollOffset, scrollOffset - value * 50))
        return true
    end
    return false
end

function widget:MousePress(x, y, button)
    if not show then return false end
    
    -- Check if clicked on the add button
    if x > window.x + window.width - PADDING - 50 and x < window.x + window.width - PADDING and
       y > window.y + PADDING + INPUT_HEIGHT + PADDING and y < window.y + PADDING + INPUT_HEIGHT*2 + PADDING then
        SaveBinding(keyInput, commandInput)
        keyInput = "New Key"
        commandInput = "New Command"
        return true
    end
    
    -- Check if clicked on a remove button
    local relativeY = window.height - (y - window.y) - HEADER_SIZE - 2*PADDING + scrollOffset
    local index = math.floor(relativeY / (BUTTON_HEIGHT + PADDING)) + 1
    if index > 0 and index <= #currentBindings and
       x > window.x + window.width - 2*PADDING - 50 and x < window.x + window.width - 2*PADDING then
        RemoveBinding(currentBindings[index].key, currentBindings[index].command)
        return true
    end
    
    -- Check if clicked in key input
    if x > window.x + PADDING and x < window.x + window.width/2 - PADDING and
       y > window.y + PADDING + INPUT_HEIGHT + PADDING and y < window.y + PADDING + INPUT_HEIGHT*2 + PADDING then
        isCapturingKeys = true
        keyInput = "Press a key..."
        return true
    end
    
    -- Check if clicked in command input
    if x > window.x + window.width/2 + PADDING and x < window.x + window.width - PADDING - 60 and
       y > window.y + PADDING + INPUT_HEIGHT + PADDING and y < window.y + PADDING + INPUT_HEIGHT*2 + PADDING then
        isCapturingKeys = false
        return true
    end
    
    return false
end

function widget:KeyPress(key, mods, isRepeat, label)
    if not show then return false end
    
    -- Handle escape key to close the window
    if key == 27 and show == true then -- Esc
        widget:Toggle()
    end
    
    if isCapturingKeys then
        local modstring = ""
        if Spring.GetModKeyState() then
            local alt, ctrl, meta, shift = Spring.GetModKeyState()
            if alt then modstring = modstring .. "Alt+" end
            if ctrl then modstring = modstring .. "Ctrl+" end
            if shift then modstring = modstring .. "Shift+" end
        end
        
        local keyname = Spring.GetKeySymbol(key)
        if keyname then
            keyInput = modstring .. keyname
            isCapturingKeys = false
            return true
        end
    else
        -- Handle command suggestions navigation
        if showSuggestions then
            if key == 273 then -- Up arrow
                selectedSuggestion = math.max(1, selectedSuggestion - 1)
                return true
            elseif key == 274 then -- Down arrow
                selectedSuggestion = math.min(#suggestions, selectedSuggestion + 1)
                return true
            elseif key == 13 then -- Enter
                if suggestions[selectedSuggestion] then
                    commandInput = suggestions[selectedSuggestion]
                    showSuggestions = false
                    return true
                end
            end
        end
        
        if key == 8 then -- Backspace
            if commandInput ~= "" then
                commandInput = commandInput:sub(1, -2)
                UpdateSuggestions()
                return true
            end
        end
    end
    
    return false
end

function widget:TextInput(utf8char)
    if not show or isCapturingKeys then return false end
    
    if utf8char then
        commandInput = commandInput .. utf8char
        UpdateSuggestions()
        return true
    end
    return false
end

function widget:IsAbove(x, y)
    if not show then return false end
    
    return x > window.x and x < window.x + window.width and
           y > window.y and y < window.y + window.height
end

function widget:Toggle()
    show = not show
    if show then
        LoadCurrentBindings()
    else
        if WG['guishader'] then
            WG['guishader'].DeleteDlist('keybindconfig')
        end
        if backgroundGuishader then
            gl.DeleteList(backgroundGuishader)
            backgroundGuishader = nil
        end
    end
end

local function InitializeUI()
    -- Get FlowUI elements
    bgpadding = WG.FlowUI.elementPadding
    elementCorner = WG.FlowUI.elementCorner 
    elementPadding = WG.FlowUI.elementPadding

    RectRound = WG.FlowUI.Draw.RectRound
    UiElement = WG.FlowUI.Draw.Element
    UiButton = WG.FlowUI.Draw.Button

    -- Update colors to match FlowUI
    colors = {
        windowBackground = {0, 0, 0, math.max(0.75, Spring.GetConfigFloat("ui_opacity", 0.7))},
        buttonBackground = {0.15, 0.15, 0.15, 1},
        buttonHover = {0.25, 0.25, 0.25, 1}, 
        buttonActive = {0.3, 0.3, 0.3, 1},
        text = {1, 1, 1, 1},
        input = {0.12, 0.12, 0.12, 1},
        inputActive = {0.2, 0.2, 0.2, 1},
        removeButton = {0.7, 0.2, 0.2, 0.8},
        removeButtonHover = {0.8, 0.3, 0.3, 0.9}
    }

    -- Use FlowUI font
    font = WG['fonts'].getFont()
end

function widget:Initialize()
    InitializeUI()
    
    -- Register toggle hotkey
    Spring.SendCommands({"bind f9 luaui keybind_custom_config_toggle"})
    --Spring.Echo("Press F9 to toggle keybinding configuration")
    
    -- Add command handler
    widgetHandler:AddAction("keybind_custom_config_toggle", function()
        widget:Toggle()
    end, nil, "t")
    
    LoadHotkeyConfigs()
    LoadCurrentBindings()

		WG['keybind_custom_config'] = widget
end

function widget:ViewResize()
    vsx, vsy = Spring.GetViewGeometry()
    window.x = math.floor((vsx * centerPosX) - (window.width / 2))
    window.y = math.floor((vsy * centerPosY) - (window.height / 2))
    
    if backgroundGuishader then
        gl.DeleteList(backgroundGuishader)
        backgroundGuishader = nil
    end
    
    InitializeUI() -- Refresh UI elements on resize
end

-- Add cleanup of hotkey on shutdown
function widget:Shutdown()
    Spring.SendCommands({"unbind f9 luaui keybind_custom_config_toggle"})
    widgetHandler:RemoveAction("keybind_custom_config_toggle")
    
    if backgroundGuishader then
        if WG['guishader'] then
            WG['guishader'].DeleteDlist('keybindconfig')
        end
        gl.DeleteList(backgroundGuishader)
    end
    end

function widget:GetConfigData()
    return {
        show = show,
    }
end

function widget:SetConfigData(data)
    if data.show ~= nil then
        show = data.show
    end
end