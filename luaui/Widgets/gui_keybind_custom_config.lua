---@class Widget
---@field GetInfo function
---@field Initialize function
---@field Shutdown function
---@field ViewResize function
---@field DrawScreen function
---@field MouseMove function
---@field MousePress function
---@field MouseWheel function
---@field KeyPress function
---@field TextInput function
---@field IsAbove function
---@field Toggle function
---@field GetConfigData function
---@field SetConfigData function
local widget = widget

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

-- Forward declarations for dropdowns
local keySelector
local commandSelector

-- Constants
local BUTTON_HEIGHT = 24
local INPUT_HEIGHT = 24
local PADDING = 8
local FONT_SIZE = 14
local HEADER_SIZE = 18
local SCROLL_HEIGHT = 480  -- Will be updated based on window height

-- Colors
local colors = {
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

-- Helper functions
local math_isInRect = math.isInRect

local function log(...)
    print(...)
    Spring.Echo(...)
end

local function WidgetPCall(func, callback, ...)
    local success, result = pcall(func, ...)
    if not success then
        log("Error:", result) -- result will contain the error message
    end
    if callback then
        callback()
    end
end

-- Mouse state
local mx, my = 0, 0
function widget:MouseMove(x, y, dx, dy, button)
    mx, my = x, y
end

-- Classes
local KeySelector = {}
KeySelector.__index = KeySelector

function KeySelector.new(options)
    local self = setmetatable({}, KeySelector)

    self.selectedValue = options.initialValue or "New Key"
    self.isActive = false
    self.x = 0
    self.y = 0
    self.width = 0
    self.height = 0
    self.options = options.options or {}
    self.onChange = options.onChange
    self.isCapturing = false
    
    local font = WG['fonts'].getFont()

    function KeySelector:setDimensions(x, y, width, height)
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    end
    
    function KeySelector:draw()
        -- Draw main button
        UiButton(
            self.x,
            self.y,
            self.x + self.width,
            self.y + self.height,
            1,1,1,1, 1,1,1,1, nil,
            self.isActive and colors.buttonActive or colors.buttonBackground
        )
        
        -- Draw selected text
        font:Begin()
        font:SetTextColor(1,1,1,1)
        font:Print(self.selectedValue,
            self.x + elementPadding * 2,
            self.y + elementPadding,
            FONT_SIZE, "n"
        )
    end
    
    function KeySelector:handleMousePress(x, y)
        if math_isInRect(x, y, self.x, self.y, self.x + self.width, self.y + self.height) then
            if not self.isActive and not self.isCapturing then
                self:startCapture()
                return true
            end
            self.isActive = not self.isActive
            return true
        end
        
        if self.isActive then
            local dropdownY = self.y + self.height
            local itemHeight = self.height - elementPadding
            
            for i, option in ipairs(self.options) do
                local optionY = dropdownY + ((i-1) * itemHeight)
                if math_isInRect(x, y,
                    self.x,
                    optionY, 
                    self.x + self.width,
                    optionY + itemHeight
                ) then
                    self.selectedValue = option
                    if self.onChange then self.onChange(option) end
                    self.isActive = false
                    return true
                end
            end
        end
        self.isActive = false
        return false
    end
    
    function KeySelector:startCapture()
        self.isCapturing = true
        self.selectedValue = "Press a key..."
    end
    
    function KeySelector:handleKeyCapture(key, mods)
        if not self.isCapturing then return false end
        
        local modstring = ""
        if Spring.GetModKeyState() then
            local alt, ctrl, meta, shift = Spring.GetModKeyState()
            if alt then modstring = modstring .. "Alt+" end
            if ctrl then modstring = modstring .. "Ctrl+" end
            if shift then modstring = modstring .. "Shift+" end
        end
        
        local keySymbol = Spring.GetKeySymbol(key)
        if keySymbol then
            self.selectedValue = modstring .. keySymbol
            self.isCapturing = false
            if self.onChange then self.onChange(self.selectedValue) end
            return true
        end
        return false
    end

    return self
end

local CommandSelector = {}
CommandSelector.__index = CommandSelector

function CommandSelector.new(options)
    local self = setmetatable({}, CommandSelector)
    self.selectedValue = options.initialValue or "New Command"
    self.isActive = false
    self.x = 0
    self.y = 0
    self.width = 0
    self.height = 0
    self.options = options.options or {}
    self.onChange = options.onChange
    self.filter = ""
    
    local font = WG['fonts'].getFont()

    function CommandSelector:setDimensions(x, y, width, height)
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    end

    function CommandSelector:updateFilteredOptions()
        if self.filter == "" then
            return self.options
        end
        
        local filtered = {}
        for _, cmd in ipairs(self.options) do
            if cmd:lower():find(self.filter:lower(), 1, true) then
                table.insert(filtered, cmd)
            end
        end
        return filtered
    end

    function CommandSelector:draw()
        -- Draw main button
        UiButton(
            self.x,
            self.y,
            self.x + self.width,
            self.y + self.height,
            1,1,1,1, 1,1,1,1, nil,
            self.isActive and colors.buttonActive or colors.buttonBackground
        )
        
        -- Draw selected text/filter
        font:Begin()
        font:SetTextColor(1,1,1,1)
        font:Print(self.isActive and self.filter or self.selectedValue,
            self.x + elementPadding * 2,
            self.y + elementPadding,
            FONT_SIZE, "n"
        )
        
        -- Draw dropdown arrow
        local arrowSize = FONT_SIZE
        local arrowX = self.x + self.width - elementPadding * 3 - arrowSize
        local arrowY = self.y + elementPadding
        font:Print("▼", arrowX, arrowY, arrowSize, "n")
        font:End()
        
        -- Draw dropdown if active
        if self.isActive then
            local filteredOptions = self:updateFilteredOptions()
            local dropdownY = self.y + self.height
            local itemHeight = self.height - elementPadding
            local maxItems = math.min(10, #filteredOptions)
            
            UiSelector(
                self.x,
                dropdownY,
                self.x + self.width,
                dropdownY + (maxItems * itemHeight)
            )
            
            font:Begin()
            for i = 1, maxItems do
                local option = filteredOptions[i]
                local optionY = dropdownY + ((i-1) * itemHeight)
                
                if math_isInRect(mx, my, 
                    self.x,
                    optionY,
                    self.x + self.width,
                    optionY + itemHeight
                ) then
                    UiSelectHighlight(
                        self.x,
                        optionY,
                        self.x + self.width,
                        optionY + itemHeight
                    )
                end
                
                font:Print(option,
                    self.x + elementPadding * 2,
                    optionY + elementPadding,
                    FONT_SIZE, "n"
                )
            end
            font:End()
        end
    end

    function CommandSelector:handleMousePress(x, y)
        if math_isInRect(x, y, self.x, self.y, self.x + self.width, self.y + self.height) then
            self.isActive = not self.isActive
            if self.isActive then self.filter = "" end
            return true
        end
        
        if self.isActive then
            local filteredOptions = self:updateFilteredOptions()
            local dropdownY = self.y + self.height
            local itemHeight = self.height - elementPadding
            local maxItems = math.min(10, #filteredOptions)
            
            for i = 1, maxItems do
                local optionY = dropdownY + ((i-1) * itemHeight)
                if math_isInRect(x, y,
                    self.x,
                    optionY,
                    self.x + self.width,
                    optionY + itemHeight
                ) then
                    self.selectedValue = filteredOptions[i]
                    if self.onChange then self.onChange(self.selectedValue) end
                    self.isActive = false
                    return true
                end
            end
        end
        self.isActive = false
        return false
    end

    function CommandSelector:handleTextInput(char)
        if not self.isActive then return false end
        
        self.filter = self.filter .. char
        return true
    end

    function CommandSelector:handleKeyPress(key)
        if not self.isActive then return false end
        
        if key == 8 then -- Backspace
            if #self.filter > 0 then
                self.filter = self.filter:sub(1, -2)
            end
            return true
        elseif key == 13 then -- Enter
            local filteredOptions = self:updateFilteredOptions()
            if #filteredOptions > 0 then
                self.selectedValue = filteredOptions[1]
                if self.onChange then self.onChange(self.selectedValue) end
                self.isActive = false
            end
            return true
        end
        return false
    end

    return self
end

-- Create BindingList class after the dropdown classes
local BindingList = {}
BindingList.__index = BindingList

function BindingList.new(options)
    local self = setmetatable({}, BindingList)
    self.x = 0
    self.y = 0
    self.width = 0
    self.height = 0
    self.scrollOffset = 0
    self.minScrollOffset = 0
    self.maxScrollOffset = 0
    self.removeHover = -1
    self.bindings = {}
    self.onRemove = options.onRemove
    
    local font = WG['fonts'].getFont()

    function BindingList:setDimensions(x, y, width, height)
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    end
    
    function BindingList:setBindings(bindings)
        self.bindings = bindings
        self.maxScrollOffset = math.max(self.minScrollOffset, (#bindings * (BUTTON_HEIGHT + elementPadding)) - SCROLL_HEIGHT)
    end
    
    function BindingList:draw()
        gl.PushMatrix()
        gl.Translate(self.x, self.y + self.height, 0)
        gl.Scissor(self.x, self.y, self.width, self.height)
    
        for i, binding in ipairs(self.bindings) do
            local yPos = -((i-1) * (BUTTON_HEIGHT + elementPadding)) + self.scrollOffset
            
            if yPos > -SCROLL_HEIGHT and yPos < BUTTON_HEIGHT then
                -- Draw binding row
                UiElement(0, yPos, self.width - 60, yPos + BUTTON_HEIGHT, 0,0,0,0, 1)
                
                -- Draw text
                font:Begin()
                font:SetTextColor(1,1,1,1)
                font:SetOutlineColor(0,0,0,0.4)
                font:Print(binding.boundWith or "", elementPadding, yPos + elementPadding, FONT_SIZE, "n")
                font:Print(binding.command or "", self.width * (1/3), yPos + elementPadding, FONT_SIZE, "n")
                font:Print(binding.extra or "", self.width * (2/3), yPos + elementPadding, FONT_SIZE, "n")
                font:End()
                
                -- Draw remove button
                UiButton(
                    self.width - 50, 
                    yPos, 
                    self.width, 
                    yPos + BUTTON_HEIGHT,
                    self.removeHover == i and colors.removeButtonHover or colors.removeButton
                )
                
                font:Begin()
                font:SetTextColor(1,1,1,1)
                font:Print("Del", self.width - 45, yPos + elementPadding, FONT_SIZE, "n")
                font:End()
            end
        end
        
        gl.Scissor(false)
        gl.PopMatrix()
    end
    
    function BindingList:handleMouseWheel(up, value)
        local mouseX, mouseY = Spring.GetMouseState()

        if math_isInRect(mouseX, mouseY, self.x, self.y, self.x + self.width, self.y + self.height) then
            local newOffset = self.scrollOffset - value * 50
            self.scrollOffset = math.max(self.minScrollOffset, math.min(self.maxScrollOffset, newOffset))
            return true
        end

        return false
    end
    
    function BindingList:handleMousePress(x, y)
        -- Translate coordinates to binding list space
        local localX = x - self.x
        local localY = y - self.y
        
        -- Check if clicked on a remove button
        local relativeY = -localY + self.scrollOffset
        local index = math.floor(relativeY / (BUTTON_HEIGHT + elementPadding)) + 1
        if index > 0 and index <= #self.bindings and
           localX > self.width - 50 and localX < self.width then
            if self.onRemove then 
                self.onRemove(self.bindings[index].boundWith, self.bindings[index].command)
            end
            return true
        end
        return false
    end

    return self
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
local bindingList
local currentBindings = {}
local keyInput = "New Key"
local commandInput = "New Command"
local buttonHover = false
local showSuggestions = false
local suggestions = {}
local selectedSuggestion = 1
local MAX_SUGGESTIONS = 5

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
    
    -- Update dropdown options
    local keyOptions = {}
    for key in pairs(availableKeys) do
        table.insert(keyOptions, key)
    end
    table.sort(keyOptions)
    keySelector.options = keyOptions
    
    local cmdOptions = {}
    for cmd in pairs(availableCommands) do
        table.insert(cmdOptions, cmd)
    end
    table.sort(cmdOptions)
    commandSelector.options = cmdOptions
end

local function LoadCurrentBindings()
    currentBindings = Spring.GetKeyBindings() or {}
    if bindingList then
        bindingList:setBindings(currentBindings)
    end
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

local function DrawInputs()
    keySelector:draw()
    commandSelector:draw()
    
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

    WidgetPCall(function()
        DrawBackground()
        
        -- Draw title
        gl.Color(colors.text)
        font:Begin()
        font:Print("Keybinding Configuration", window.x + PADDING, 
                window.y + window.height - HEADER_SIZE - PADDING, HEADER_SIZE, "n")
        font:End()
        
        bindingList:draw()
        DrawInputs()
        DrawSuggestions()
        
    end, function()
        gl.PopMatrix()
    end)
end

function widget:MouseWheel(up, value)
    if not show then return false end
    
    return bindingList:handleMouseWheel(up, value)
end

function widget:MousePress(x, y, button)
    if not show then return false end
    
    -- Check if clicked on the add button
    if x > window.x + window.width - elementPadding - 50 and x < window.x + window.width - elementPadding and
       y > window.y + elementPadding + INPUT_HEIGHT + elementPadding and y < window.y + elementPadding + INPUT_HEIGHT*2 + elementPadding then
        SaveBinding(keyInput, commandInput)
        keySelector.selectedValue = "New Key"
        commandSelector.selectedValue = "New Command"
        return true
    end
    
    -- Handle dropdown clicks
    if keySelector:handleMousePress(x, y) then
        commandSelector.isActive = false
        return true
    end
    
    if commandSelector:handleMousePress(x, y) then
        keySelector.isActive = false
        return true
    end
    
    -- Handle binding list clicks
    if bindingList:handleMousePress(x, y) then
        return true
    end
    
    -- Close dropdowns when clicking elsewhere
    keySelector.isActive = false
    commandSelector.isActive = false
    return false
end

function widget:KeyPress(key, mods, isRepeat, label)
    if not show then return false end
    
    if key == 27 then -- Escape
        if keySelector.isCapturing then
            keySelector.isCapturing = false
            keySelector.selectedValue = "New Key"
            return true
        end
        if keySelector.isActive or commandSelector.isActive then
            keySelector.isActive = false
            commandSelector.isActive = false
            return true
        end
        widget:Toggle()
        return true
    end
    
    -- Handle key capture for key selector
    if keySelector.isCapturing then
        return keySelector:handleKeyCapture(key, mods)
    end
    
    -- Handle command selector input
    if commandSelector.isActive then
        return commandSelector:handleKeyPress(key)
    end
    
    return false
end

function widget:TextInput(char)
    if not show then return false end
    
    if commandSelector.isActive then
        return commandSelector:handleTextInput(char)
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
	UiSlider = WG.FlowUI.Draw.Slider
	UiSliderKnob = WG.FlowUI.Draw.SliderKnob
	UiToggle = WG.FlowUI.Draw.Toggle
	UiSelector = WG.FlowUI.Draw.Selector
	UiSelectHighlight = WG.FlowUI.Draw.SelectHighlight

    -- Font
    font = WG['fonts'].getFont()
    
    -- Dropdowns
    keySelector = KeySelector.new({
        initialValue = "New Key",
        options = {},  -- Will be populated from availableKeys
        onChange = function(value)
            keyInput = value
        end
    })
    keySelector:setDimensions(
        window.x + elementPadding,
        window.y + elementPadding + INPUT_HEIGHT + elementPadding,
        window.width/2 - 2*elementPadding,
        INPUT_HEIGHT
    )

    commandSelector = CommandSelector.new({
        initialValue = "New Command",
        options = {},  -- Will be populated from availableCommands
        onChange = function(value)
            commandInput = value
            showSuggestions = false
        end
    })
    commandSelector:setDimensions(
        window.x + window.width/2 + elementPadding,
        window.y + elementPadding + INPUT_HEIGHT + elementPadding,
        window.width/2 - elementPadding - 60,
        INPUT_HEIGHT
    )

    -- Create binding list
    bindingList = BindingList.new({
        onRemove = RemoveBinding
    })
    bindingList:setDimensions(
        window.x + elementPadding,
        window.y + elementPadding + INPUT_HEIGHT + elementPadding + HEADER_SIZE + elementPadding,
        window.width - 2*elementPadding,
        SCROLL_HEIGHT
    )
end

function widget:Initialize()
    WidgetPCall(function()
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
    end)
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