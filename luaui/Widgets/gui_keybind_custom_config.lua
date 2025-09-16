---@class Widget
local widget = widget
local VFS = VFS
local LOG = LOG

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

-- Constants
local BUTTON_HEIGHT = 24
local INPUT_HEIGHT = 24
local PADDING = 8
local FONT_SIZE = 14
local HEADER_SIZE = 18
local SCROLL_HEIGHT = 480  -- Will be updated based on window height
local LOG_SECTION = 'gui_keybind_custom_config.lua'

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

-- Forward declarations for dropdowns
local hotkeyManager
local bindingList
local keySelector
local commandSelector
local addButton

-- Mouse state
local mx, my

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
local keyInput = "New Key"
local commandInput = "New Command"

-- Helper functions
local math_isInRect = math.isInRect

local function log(...)
    print(...)
    Spring.Echo(...)
    Spring.Log(LOG_SECTION, LOG.INFO, ...)
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

-- Classes
local UiButtonInteractable = {}
UiButtonInteractable.__index = UiButtonInteractable

--[[
    px, py, sx, sy,  tl, tr, br, bl,  ptl, ptr, pbr, pbl,  opacity, color1, color2, bgpadding, glossMult,
    text
]]--
function UiButtonInteractable.new(options)
    local self = setmetatable(options or {}, UiButtonInteractable)
    self.state = ''
    self.onClickCallback = nil -- Store callback as instance variable
    
    function self:draw()
        -- Draw button
        UiButton(
            self.px, self.py, self.sx, self.sy,
            1,1,1,1, 1,1,1,1, nil,
            self.state == 'active' and colors.buttonActive or
            self.state == 'hover' and colors.buttonHover or
            colors.buttonBackground
        )
        
        -- Draw text
        font:Begin()
        font:SetTextColor(1,1,1,1)
        font:Print(
            self.text,
            self.px + elementPadding,
            self.py + elementPadding,
            FONT_SIZE, "n"
        )
        font:End()
    end

    function self:handleMouseMove(x, y, dx, dy, button)
        if math_isInRect(x, y, self.px, self.py, self.sx, self.sy) then
            self.state = 'hover'
        else
            if self.state == 'hover' then
                self.state = ''
            end
        end
    end
    
    function self:handleMousePress(x, y, button)
        if not (x and y and self.px and self.py and self.sx and self.sy) then
            return false
        end

        if math_isInRect(x, y, self.px, self.py, self.sx, self.sy) then
            self.state = 'active'
            if self.onClickCallback then
               self.onClickCallback()
            end
            return true
        end

        return false
    end

    function self:handleMouseRelease(x, y, button)
        if not math_isInRect(x, y, self.px, self.py, self.sx, self.sy) then
            self.state = ''
        end
    end

    function self:onClick(func)
        self.onClickCallback = func
    end

    return self
end

local KeySelector = {}
KeySelector.__index = KeySelector

function KeySelector.new(options)
    local self = setmetatable(options, KeySelector)

    self.isCapturing = false

    local button = UiButtonInteractable.new({
        tl = 1, tr = 1, bl = 1, br = 1,
        ptl = 1, ptr = 1, pbl = 1, pbr = 1,
        color1 = self.isCapturing and colors.buttonActive or colors.buttonBackground,
        text = options.initialValue or "New Key"
    })
    button:onClick(function()
        if not self.isCapturing then
            self:startCapture()
            return
        end
    end)

    function self:setDimensions(x, y, width, height)
        button.px = x
        button.py = y
        button.sx = x + width
        button.sy = y + height
    end
    
    function self:draw()
        button:draw()
    end
    
    function self:handleMousePress(x, y)
        button:handleMousePress(x, y)
    end
    
    function self:startCapture()
        self.isCapturing = true
        self.selectedValue = "Press a key..."
        button.text = "Press a key..."
    end
    
    function self:handleKeyCapture(key, mods)
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
            button.text = modstring .. keySymbol
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

    local button = UiButtonInteractable.new({
        tl = 1, tr = 1, bl = 1, br = 1,
        ptl = 1, ptr = 1, pbl = 1, pbr = 1,
        color1 = self.isActive and colors.buttonActive or colors.buttonBackground,
        text = options.initialValue or "New Command"
    })
    button:onClick(function()
        self.isActive = not self.isActive
        if self.isActive then
            self.filter = ""
        end
    end)

    function self:setDimensions(x, y, width, height)
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        button.px = x
        button.py = y
        button.sx = x + width
        button.sy = y + height
    end

    function self:updateFilteredOptions()
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

    function self:draw()
        button.text = self.isActive and self.filter or self.selectedValue
        button:draw()
        
        -- Draw dropdown arrow
        local arrowSize = FONT_SIZE
        local arrowX = self.x + self.width - elementPadding * 3 - arrowSize
        local arrowY = self.y + elementPadding
        font:Begin()
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

    function self:handleMousePress(x, y)
        local wasClicked = button:handleMousePress(x, y)

        if wasClicked then
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

    function self:handleTextInput(char)
        if not self.isActive then return false end
        
        self.filter = self.filter .. char
        return true
    end

    function self:handleKeyPress(key)
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
    self.deleteButtons = {}
    self.onRemove = options.onRemove

    local font = WG['fonts'].getFont()

    function self:setDimensions(x, y, width, height)
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    end
    
    function self:setBindings(bindings)
        self.bindings = bindings
        self.maxScrollOffset = math.max(self.minScrollOffset, (#bindings * (BUTTON_HEIGHT + elementPadding)) - SCROLL_HEIGHT)
        
        -- Create/update delete buttons
        self.deleteButtons = {}
        for i = 1, #bindings do
            local button = UiButtonInteractable.new({
                text = "Del" .. i,
                color1 = colors.removeButton,
                color2 = colors.removeButtonHover
            })
            -- Fix: Call onClick through instance rather than as a function
            button:onClick(function()
                if self.onRemove then
                    self.onRemove(bindings[i].boundWith, bindings[i].command)
                    -- Update max scroll offset
                    self.maxScrollOffset = math.max(self.minScrollOffset, (#self.bindings * (BUTTON_HEIGHT + elementPadding)) - SCROLL_HEIGHT)
                end
            end)
            self.deleteButtons[i] = button
        end
    end
    
    function self:draw()
        gl.PushMatrix()
        gl.Translate(self.x, self.y + self.height, 0)
        gl.Scissor(self.x, self.y, self.width, self.height)
    
        for i, binding in ipairs(self.bindings) do
            local yPos = -((i-1) * (BUTTON_HEIGHT + elementPadding)) + self.scrollOffset
            
            if yPos > -SCROLL_HEIGHT and yPos < BUTTON_HEIGHT then
                -- Draw binding row background
                UiElement(0, yPos, self.width - 60, yPos + BUTTON_HEIGHT, 0,0,0,0, 1)
                
                -- Draw text
                font:Begin()
                font:SetTextColor(1,1,1,1)
                font:SetOutlineColor(0,0,0,0.4)
                font:Print(binding.boundWith or "", elementPadding, yPos + elementPadding, FONT_SIZE, "n")
                font:Print(binding.command or "", self.width * (1/3), yPos + elementPadding, FONT_SIZE, "n")
                font:Print(binding.extra or "", self.width * (2/3), yPos + elementPadding, FONT_SIZE, "n")
                font:End()
                
                -- Position and draw delete button
                local deleteButton = self.deleteButtons[i]
                -- The button is positioned relative to the binding list's coordinate space
                deleteButton.px = self.width - 50
                deleteButton.py = yPos
                deleteButton.sx = self.width - 10
                deleteButton.sy = yPos + BUTTON_HEIGHT
                deleteButton:draw()
            end
        end
        
        gl.Scissor(false)
        gl.PopMatrix()
    end
    
    function self:handleMouseWheel(up, value)
        local mouseX, mouseY = Spring.GetMouseState()

        if math_isInRect(mouseX, mouseY, self.x, self.y, self.x + self.width, self.y + self.height) then
            local newOffset = self.scrollOffset - value * 50
            self.scrollOffset = math.max(self.minScrollOffset, math.min(self.maxScrollOffset, newOffset))
            return true
        end

        return false
    end
    
    function self:handleMousePress(x, y)
        -- Convert global coordinates to local binding list coordinates
        local localX = x - self.x
        local localY = y - self.y

        -- Get button y (because we draw from the top down)
        local buttonY = localY - self.height
        
        -- Check all visible buttons if they are clicked
        for index, button in ipairs(self.deleteButtons) do
            local isVisible = button.py and button.py < 0 and button.py > -self.height
            if isVisible then
                if button:handleMousePress(localX, buttonY, nil, true) then
                    return true
                end
            end
        end
        
        return false
    end

    return self
end

local HotkeyManager = {}
HotkeyManager.__index = HotkeyManager

function HotkeyManager.new(options)
    local self = setmetatable(options or {}, HotkeyManager)

    self.currentBindings = {}
    self.availableCommands = {}
    self.availableKeys = {}

    function self:LoadHotkeyConfigs()
        -- Load available commands and keys from hotkey config files
        local gridKeys = VFS.LoadFile("luaui/configs/hotkeys/grid_keys.txt")
        if gridKeys then
            for line in gridKeys:gmatch("[^\r\n]+") do
                if line:match("^bind%s+") then
                    local _, _, key, command = line:find("^bind%s+([^%s]+)%s+([^%s]+)")
                    if key and command then
                        self.availableKeys[key] = true
                        self.availableCommands[command] = true
                    end
                end
            end
        end
        
        -- Add common modifiers
        local modifiers = {"Alt+", "Ctrl+", "Shift+", "Any+"}
        local baseKeys = {}
        for key in pairs(self.availableKeys) do
            if not key:find("+") then
                baseKeys[key] = true
            end
        end
        
        -- Generate modified keys
        for key in pairs(baseKeys) do
            for _, modifier in ipairs(modifiers) do
                self.availableKeys[modifier .. key] = true
            end
        end
        
        -- Update dropdown options
        local keyOptions = {}
        for key in pairs(self.availableKeys) do
            table.insert(keyOptions, key)
        end
        table.sort(keyOptions)
        keySelector.options = keyOptions
        
        local cmdOptions = {}
        for cmd in pairs(self.availableCommands) do
            table.insert(cmdOptions, cmd)
        end
        table.sort(cmdOptions)
        commandSelector.options = cmdOptions
    end

    function self:LoadCurrentBindings()
        self.currentBindings = Spring.GetKeyBindings() or {}
        if bindingList then
            bindingList:setBindings(self.currentBindings)
        end
    end

    function self:SaveBinding(key, command)
        if key and command and key ~= "" and command ~= "" then
            Spring.SendCommands({"bind " .. key .. " " .. command})
            self:LoadCurrentBindings()
        end
    end

    function self:RemoveBinding(key, command)
        if key and command then
            Spring.SendCommands({"unbind " .. key .. " " .. command})
            self:LoadCurrentBindings()
        end
    end

    return self
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

function widget:DrawScreen()
    if not show then return end
    if not font then return end
    
    gl.PushMatrix()

    WidgetPCall(function()
        -- MouseMove only triggers when the mouse is down, but we want it always captured
        local x, y, l = Spring.GetMouseState()
        self:MouseMove(x, y)

        DrawBackground()
        
        -- Draw title
        gl.Color(colors.text)
        font:Begin()
        font:Print("Keybinding Configuration", window.x + PADDING, 
                window.y + window.height - HEADER_SIZE - PADDING, HEADER_SIZE, "n")
        font:End()
        
        bindingList:draw()
        keySelector:draw()
        commandSelector:draw()
        addButton:draw()
        
    end, function()
        gl.PopMatrix()
    end)
end

function widget:MouseWheel(up, value)
    if not show then return false end
    
    return bindingList:handleMouseWheel(up, value)
end

function widget:MouseMove(x, y, dx, dy, button)
    -- Does this ever get called without us triggering in this class?
    --log('MouseMove')
    if x == mx and y == my then
        return
    end

    mx, my = x, y
    addButton:handleMouseMove(x, y, dx, dy, button)
end

function widget:MousePress(x, y, button)
    if not show then return false end

    addButton:handleMousePress(x, y, button)
    keySelector:handleMousePress(x, y, button)
    
    -- Handle dropdown clicks
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

function widget:MouseRelease(x, y, button)
    addButton:handleMouseRelease(x, y, button)
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
        hotkeyManager:LoadCurrentBindings()
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

    hotkeyManager = HotkeyManager.new()

    -- Add button
    addButton = UiButtonInteractable.new({
        px = window.x + window.width - elementPadding - 50,
        py = window.y + elementPadding + INPUT_HEIGHT + elementPadding,
        sx = window.x + window.width - elementPadding,
        sy = window.y + elementPadding + INPUT_HEIGHT*2 + elementPadding,
        text = 'Add'
    })
    addButton:onClick(function()
        hotkeyManager:SaveBinding(keyInput, commandInput)
        keySelector.selectedValue = "New Key"
        commandSelector.selectedValue = "New Command"
    end)
    
    -- Dropdowns
    keySelector = KeySelector.new({
        initialValue = "New Key",
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
        onRemove = function(...) 
            hotkeyManager:RemoveBinding(...)
        end
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
        
        hotkeyManager:LoadHotkeyConfigs()
        hotkeyManager:LoadCurrentBindings()
    
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