---@class Widget
local widget = widget
local VFS = VFS
local LOG = LOG
local gl = gl

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

-- Local variables and helper functions

-- #region Local variables and helper functions

-- Constants
local BUTTON_HEIGHT = 24
local INPUT_HEIGHT = 24
local PADDING = 8
local FONT_SIZE = 14
local HEADER_SMALL_SIZE = 16
local HEADER_SIZE = 18
local FOOTER_SIZE = 18
local LOG_SECTION = 'gui_keybind_custom_config.lua'

-- Colors
local colors = {
    windowBackground = {0, 0, 0, math.max(0.75, Spring.GetConfigFloat("ui_opacity", 0.7))},
    windowBackgroundGold1 = {77/255, 59/255, 37/255, math.max(0.75, Spring.GetConfigFloat("ui_opacity", 0.7))},
    windowBackgroundGold2 = {32/255, 24/255, 11/255, math.max(0.75, Spring.GetConfigFloat("ui_opacity", 0.7))},
    buttonBackground = {0.15, 0.15, 0.15, 0.3},
    buttonHover = {0.25, 0.25, 0.25, 1},
    buttonActive = {0.3, 0.3, 0.3, 1},
    text = {1, 1, 1, 1},
    textGold = {171/255, 141/255, 107/255, 1},
    input = {0.12, 0.12, 0.12, 1},
    inputActive = {0.2, 0.2, 0.2, 1},
    removeButton = {0.7, 0.2, 0.2, 0.8},
    removeButtonHover = {0.8, 0.3, 0.3, 0.9}
}

-- Get FlowUI elements
local bgpadding = WG.FlowUI.elementPadding
local elementCorner = WG.FlowUI.elementCorner
local elementPadding = WG.FlowUI.elementPadding

local RectRound = WG.FlowUI.Draw.RectRound
local UiElement = WG.FlowUI.Draw.Element
local UiButton = WG.FlowUI.Draw.Button
local UiSlider = WG.FlowUI.Draw.Slider
local UiSliderKnob = WG.FlowUI.Draw.SliderKnob
local UiToggle = WG.FlowUI.Draw.Toggle
local UiSelector = WG.FlowUI.Draw.Selector
local UiSelectHighlight = WG.FlowUI.Draw.SelectHighlight

-- Font
local font

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

-- Widget-like
local hotkeyManager
local bindingList
local keySelector
local commandSelector
local extraSelector
local addButton
local filterTextbox
local defaultButton

local widgetLifecycleRegistry

-- UI Elements state
local backgroundGuishader

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

-- #endregion local variables

-- Classes

-- #region Classes

--[[
    Widget Lifecycle Registry System

    Events: 
        MouseWheel, MouseMove, MousePress, MouseRelease
        KeyPress,
        TextInput
]]--
local WidgetLifecycleRegistry = {}
WidgetLifecycleRegistry.__index = WidgetLifecycleRegistry

function WidgetLifecycleRegistry.new()
    local self = setmetatable({}, WidgetLifecycleRegistry)

    self.components = {}

    function WidgetLifecycleRegistry:register(component)
        table.insert(self.components, component)
    end
    
    function WidgetLifecycleRegistry:unregister(component)
        for i, comp in ipairs(self.components) do
            if comp == component then
                table.remove(self.components, i)
                break
            end
        end
    end
    
    function WidgetLifecycleRegistry:dispatchEvent(eventName, ...)
        for i = #self.components, 1, -1 do  -- Reverse order so last added (top) component gets first chance
            local component = self.components[i]
            if component[eventName] then
                local result = component[eventName](component, ...)
                if result then
                    return true
                end
            end
        end
        return false
    end

    return self
end

local UiButtonInteractable = {}
UiButtonInteractable.__index = UiButtonInteractable

--[[
    px, py, sx, sy,  tl, tr, br, bl,  ptl, ptr, pbr, pbl,  opacity, color1, color2, bgpadding, glossMult,
    text - Displayed text,
    tranX - Set to glTransform X, tranY - Set to glTransform Y
]]--
function UiButtonInteractable.new(options)
    local self = setmetatable(options or {}, UiButtonInteractable)

    self.isActive = false
    self.isHover = false
   
    local font = WG['fonts'].getFont()

    local function isInRect(x, y)
        return math_isInRect(
            x, y,
            self.px + (self.tranX or 0), self.py + (self.tranY or 0),
            self.sx + (self.tranX or 0), self.sy + (self.tranY or 0)
        )
    end
    
    function self:DrawScreen()
        -- Draw button
        UiButton(
            self.px, self.py, self.sx, self.sy,
            self.tl, self.tr, self.br, self.bl,
            self.ptl, self.ptr, self.pbr, self.pbl, self.opacity,
            self.isActive and colors.buttonActive or
            self.isHover and colors.buttonHover or
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

    function self:MouseMove(x, y, dx, dy, button)
        self.isHover = isInRect(x, y)
    end
    
    function self:MousePress(x, y, button)
        if not (x and y and self.px and self.py and self.sx and self.sy) then
            return false
        end

        if isInRect(x, y) then
            self.isActive = true
            if self.onClick then
               self.onClick()
            end
            return true
        end

        if self.isActive then
            self.isActive = false
            if self.onBlur then
                self.onBlur()
            end
        end

        return false
    end

    function self:MouseRelease(x, y, button)
        if not isInRect(x, y) then
            self.isActive = false
            if self.onBlur then
                self.onBlur()
            end
        end
    end

    return self
end

local UiTextboxInteractable = {}
UiTextboxInteractable.__index = UiTextboxInteractable

--[[
    px, py, sx, sy,  tl, tr, br, bl,  ptl, ptr, pbr, pbl,  opacity, color1, color2, bgpadding, glossMult,
    text - Displayed text,
    tranX - Set to glTransform X, tranY - Set to glTransform Y
]]--
function UiTextboxInteractable.new(options)
    local self = setmetatable(options, UiTextboxInteractable)

    self.isActive = false
    self.text = options.placeholder or ""
    
    local font = WG['fonts'].getFont()

    local button = UiButtonInteractable.new({
        px = self.px, py = self.py, sx = self.sx, sy = self.sy,
        tl = 1, tr = 1, bl = 1, br = 1,
        ptl = 1, ptr = 1, pbl = 1, pbr = 1,
        text = self.text,
        tranX = self.tranX, tranY = self.tranY
    })

    function self:DrawScreen()
        button.text = self.text
        button:DrawScreen()
    end

    function self:MouseMove(x, y, dx, dy)
        return button:MouseMove(x, y, dx, dy)
    end

    function self:MousePress(x, y)
        local wasClicked = button:MousePress(x, y)
        
        if wasClicked then
            self.isActive = true
            if self.placeholder and self.text == self.placeholder then
                self.text = ''
            end
            if self.onClick then
                self.onClick()
            end
            return true
        end

        if self.isActive then
            self.isActive = false
            if self.placeholder and self.text == '' then
                self.text = self.placeholder
            end
            if self.onBlur then
                self.onBlur()
            end
        end

        return false
    end

    function self:MouseRelease(x, y)
        return button:MouseRelease(x, y)
    end

    function self:TextInput(char)
        if not self.isActive then return false end
        
        self.text = self.text .. char
        if self.onChange then
            self.onChange(self.text)
        end

        return true
    end

    function self:KeyPress(key)
        if not self.isActive then return false end
        
        if key == 8 then -- Backspace
            if #self.text > 0 then
                self.text = self.text:sub(1, -2)
                if self.onChange then
                    self.onChange(self.text)
                end
            end
            return true
        elseif key == 13 then -- Enter
            self.isActive = false
            return true
        end
        return false
    end

    return self
end

local KeySelector = {}
KeySelector.__index = KeySelector

function KeySelector.new(options)
    local self = setmetatable(options, KeySelector)

    self.text = options.placeholder or 'New Key'
    self.value = ''
    self.isActive = false
    self.isAppend = false

    local button = UiButtonInteractable.new({
        tl = 1, tr = 1, bl = 1, br = 1,
        ptl = 1, ptr = 1, pbl = 1, pbr = 1,
        color1 = self.isActive and colors.buttonActive or colors.buttonBackground,
        text = self.text,
        onClick = function()
            if not self.isActive then
                self:SetActive(true)
                return true
            end
        end,
        onBlur = function()
            self:SetActive(false)
        end
    })

    local buttonAdd = UiButtonInteractable.new({
        tl = 1, tr = 1, bl = 1, br = 1,
        ptl = 1, ptr = 1, pbl = 1, pbr = 1,
        color1 = self.isActive and colors.buttonActive or colors.buttonBackground,
        text = "Key++",
        onClick = function()
            if not self.isActive then
                self:SetActive(true, true)
                return true
            end
        end,
        onBlur = function()
            self:SetActive(false)
        end
    })

    local function GetSpringKeySymbol(key)
        local function MatchAnyRaw(text, rawKeyArray)
            for k, _ in pairs(rawKeyArray) do
                if text == k then
                    return k
                end
            end
            return false
        end

        local function MatchAny(text, patterns)
            for _, pattern in ipairs(patterns) do
                local match = string.match(text, pattern)
                if match then
                    return match
                end
            end
            return false
        end

        local keySymbol = Spring.GetKeySymbol(key)

        local rawKeyTranslations = {
            ["96"] = "sc_`" -- backquote
        }
        local ignoredKeysPatterns = {"alt","ctrl","shift","meta"}
        local scKeysPatterns = {"[a-zA-Z-=,.;'[%]]"}

        local transKey = MatchAnyRaw(tostring(key), rawKeyTranslations)
        if transKey then
            return rawKeyTranslations[transKey]
        end
   
        local ignoreKey = MatchAny(keySymbol, ignoredKeysPatterns)
        if ignoreKey then
            return nil
        end

        local scKey = MatchAny(keySymbol, scKeysPatterns)
        if scKey then
            -- Is sc_ needed? It seems to work with just the character
            return "sc_" .. keySymbol
        end

        return keySymbol
    end

    function self:setDimensions(x, y, width, height)
        button.px = x
        button.py = y
        button.sx = x + width * (3/4)
        button.sy = y + height

        buttonAdd.px = x + width * (3/4) + PADDING
        buttonAdd.py = y
        buttonAdd.sx = x + width
        buttonAdd.sy = y + height
    end
    
    function self:DrawScreen()
        button.text = self.text
        button:DrawScreen()
        buttonAdd:DrawScreen()
    end
    
    function self:MouseMove(x, y)
        button:MouseMove(x, y)
        buttonAdd:MouseMove(x, y)
    end
    
    function self:MousePress(x, y)
        local isClicked = button:MousePress(x, y)
        local isClickedAdd = buttonAdd:MousePress(x, y)
        if not isClicked and not isClickedAdd then
            self:SetActive(false)
        end
    end
    
    function self:SetActive(isActive, isAppend)
        self.isActive = isActive
        self.isAppend = isAppend or false
        if isActive then
            if not self.isAppend then
                self.value = ""
            end
            self.text = "Press a key..."
        elseif self.text == "Press a key..." then
            self.value = self.placeholder or ""
            self.text = self.placeholder or "New Key"
        end
    end
    
    function self:KeyPress(key, mods)
        -- If the key is already bound, that binding may take control before we receive the keypress

        if not self.isActive then return false end
        
        local modstring = ""
        if mods.alt then modstring = modstring .. "Alt+" end
        if mods.ctrl then modstring = modstring .. "Ctrl+" end
        if mods.shift then modstring = modstring .. "Shift+" end
        if mods.meta then modstring = modstring .. "Meta+" end
        if mods.alt and mods.ctrl and mods.shift then modstring = "Any+" end
        
        local springSymbol = GetSpringKeySymbol(key)
        if springSymbol then
            if self.isAppend then
                self.value = self.value .. ',' .. modstring .. springSymbol
                self.text = self.value
            else
                self.value = modstring .. springSymbol
                self.text = modstring .. springSymbol
            end

            self:SetActive(false)
            if self.onChange then self.onChange(self.value) end

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

    self.placeholder = options.placeholder or "New Command"
    self.selectedValue = self.placeholder
    self.isActive = false
    self.x = 0
    self.y = 0
    self.width = 0
    self.height = 0
    self.options = options.options or {}
    self.onChange = options.onChange
    self.filter = ""

    local font = WG['fonts'].getFont()

    -- UiSelector
    local button = UiButtonInteractable.new({
        tl = 1, tr = 1, bl = 1, br = 1,
        ptl = 1, ptr = 1, pbl = 1, pbr = 1,
        color1 = self.isActive and colors.buttonActive or colors.buttonBackground,
        text = self.placeholder,
        onClick = function()
            self.isActive = not self.isActive
            if self.isActive then
                self.filter = "Search..."
            end
        end
    })

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
        if self.filter == "" or self.filter == "Search..." then
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

    function self:DrawScreen()
        button.text = self.isActive and self.filter or self.selectedValue
        button:DrawScreen()
        
        -- Draw dropdown arrow
        -- UiSelector
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
            
            RectRound(
                self.x,
                dropdownY,
                self.x + self.width,
                dropdownY + (maxItems * itemHeight),
                1, 2, 2, 2, 2, { 0.5, 0.5, 0.5, 0.95 }
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
    
    function self:MouseMove(x, y)
        button:MouseMove(x, y)
    end

    function self:MousePress(x, y)
        local wasClicked = button:MousePress(x, y)

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

    function self:TextInput(char)
        if not self.isActive then return false end

        if self.filter == "Search..." then
            self.filter = ""
        end
        
        self.filter = self.filter .. char
        return true
    end

    function self:KeyPress(key)
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
    self.filterText = ""

    local font = WG['fonts'].getFont()

    local function isButtonVisible(button)
        return button.py and button.py < 0 and button.py > -self.height
    end

    function self:setFilter(text)
        self.filterText = text:lower()
        self:updateFilteredBindings()
    end

    function self:updateFilteredBindings()
        if self.filterText == "" then
            self.filteredBindings = self.bindings
        else
            self.filteredBindings = {}
            for _, binding in ipairs(self.bindings) do
                if binding.boundWith:lower():find(self.filterText, 1, true) or
                   binding.command:lower():find(self.filterText, 1, true) or
                   (binding.extra and binding.extra:lower():find(self.filterText, 1, true)) then
                    table.insert(self.filteredBindings, binding)
                end
            end
        end
        self.maxScrollOffset = math.max(self.minScrollOffset, (#self.filteredBindings * (BUTTON_HEIGHT + elementPadding)) + HEADER_SIZE + PADDING - self.height)
        self.scrollOffset = math.min(self.scrollOffset, self.maxScrollOffset) -- Adjust scroll if needed
    end

    function self:setDimensions(x, y, width, height)
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    end

    function self:setBindings(bindings)
        self.bindings = bindings
        self:updateFilteredBindings()

        -- Create/update delete buttons
        self.deleteButtons = {}
        for i = 1, #self.filteredBindings do
            local button = UiButtonInteractable.new({
                text = "Del" .. i,
                color1 = colors.removeButton,
                color2 = colors.removeButtonHover,
                onClick = function()
                    if self.onRemove then
                        local binding = self.filteredBindings[i]
                        self.onRemove(binding.boundWith, binding.command, binding.extra)
                        self.maxScrollOffset = math.max(self.minScrollOffset, (#self.filteredBindings * (BUTTON_HEIGHT + elementPadding)) + HEADER_SIZE + PADDING - self.height)
                    end
                end
            })
            self.deleteButtons[i] = button
        end
    end
    
    function self:DrawScreen()
        gl.PushMatrix()
        WidgetPCall(function()
            gl.Translate(self.x, self.y + self.height, 0)
            gl.Scissor(self.x, self.y, self.width, self.height)

            local mouseX, mouseY = Spring.GetMouseState()
            local relMouseX = mouseX - self.x
            local relMouseY = mouseY - (self.y + self.height)
            
            -- Draw header
            font:Begin()
            font:Print("Keys", 0, -HEADER_SIZE, HEADER_SIZE, "n")
            font:Print("Command", self.width * 1/3, -HEADER_SIZE, HEADER_SIZE, "n")
            font:Print("Command Extras", self.width * 2/3, -HEADER_SIZE, HEADER_SIZE, "n")
            font:End()
            
            -- Draw table
            gl.Scissor(self.x, self.y + PADDING, self.width, self.height - HEADER_SIZE - PADDING*2)
            for i, binding in ipairs(self.filteredBindings) do
                local yPos = -(i * (BUTTON_HEIGHT + elementPadding)) - HEADER_SIZE + self.scrollOffset
                
                -- Only draw if visible
                if yPos > -(self.height + BUTTON_HEIGHT) and yPos < BUTTON_HEIGHT then
                    -- Draw binding row highlight
                    if math_isInRect(relMouseX, relMouseY, 0, yPos, self.width, yPos + BUTTON_HEIGHT) then
                        UiElement(0, yPos, self.width, yPos + BUTTON_HEIGHT, 0,0,0,0, 0,0,0,0, 0, colors.buttonHover)
                    end

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
                    deleteButton.tranX = self.x
                    deleteButton.tranY = self.y + self.height
                    deleteButton.px = self.width - 55
                    deleteButton.py = yPos + elementPadding
                    deleteButton.sx = self.width - 15
                    deleteButton.sy = yPos + BUTTON_HEIGHT - elementPadding
                    deleteButton:DrawScreen()
                end
            end
    
            -- Draw scrollbar
            WG.FlowUI.Draw.Scroller(
                self.width - 7,
                self.height - HEADER_SIZE - PADDING - 70,
                self.width,
                -HEADER_SIZE - PADDING,
                self.maxScrollOffset,
                -self.scrollOffset
            )
            
            gl.Scissor(false)
        end, function()
            gl.PopMatrix()
        end)
    end
    
    function self:MouseWheel(up, value)
        local mouseX, mouseY = Spring.GetMouseState()

        if math_isInRect(mouseX, mouseY, self.x, self.y, self.x + self.width, self.y + self.height) then
            local newOffset = self.scrollOffset - value * 50
            self.scrollOffset = math.max(self.minScrollOffset, math.min(self.maxScrollOffset, newOffset))
            return true
        end

        return false
    end
    
    function self:MousePress(x, y)
        -- Check all visible buttons if they are clicked
        for _, button in ipairs(self.deleteButtons) do
            if isButtonVisible(button) then
                if button:MousePress(x, y, nil, true) then
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

    local defaultFile = "luaui/configs/hotkeys/grid_keys.txt"

    self.file = "uikeys.txt"
    self.currentBindings = {}
    self.availableKeys = {}
    self.availableCommands = {}

    function self:LoadDefaultConfig()
        Spring.SetConfigString("KeybindingFile", defaultFile)

        if WG['bar_hotkeys'] and WG['bar_hotkeys'].reloadBindings then
            WG['bar_hotkeys'].reloadBindings()
        end

        self:LoadCurrentBindings()
    end

    function self:LoadHotkeyConfigs()
        -- Load available commands and keys from hotkey config files
        local gridKeys = VFS.LoadFile(defaultFile)
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

    function self:SaveCurrentBindings()
        local file = io.open(self.file, "w")

        if not file then
            log("Failed to open keybind file: " .. self.file)
            return
        end

        local hotkeyBindList = {}
        for _, binding in pairs(self.currentBindings) do
            table.insert(hotkeyBindList, 'bind ' .. binding.boundWith .. " " .. binding.command .. " " .. binding.extra)
        end

        local hotkeyBindString = table.concat(hotkeyBindList, "\n")

        file:write(hotkeyBindString)
        file:close()
    end

    function self:SaveBinding(key, command, extras)
        if key and command and key ~= "" and command ~= "" then
            Spring.SendCommands({"bind " .. key .. " " .. command .. " " .. extras})
            self:LoadCurrentBindings()
            self:SaveCurrentBindings()
            log('Saved: ', self.file)
        end
    end

    function self:RemoveBinding(key, command, extras)
        if key and command then
            -- TODO this fails on sequenced bindings (like sc_a,sc_a command). Is this a bug in Spring?
            -- TODO this deletes all entries for key/command, unbind doesn't understand extras (bug reported in GitHub)
            Spring.SendCommands({"unbind " .. key .. " " .. command})
            log('Binding removed: ', key, command, extras)
            self:LoadCurrentBindings()
            self:SaveCurrentBindings()
            log('Saved: ', self.file)
        end
    end

    return self
end
-- #endregion

-- Local functions

--#region Local functions
local function DrawBackground()
    -- Add guishader (blur) effect
    if WG['guishader'] then
        if not backgroundGuishader then
            backgroundGuishader = gl.CreateList(function()
                RectRound(window.x, window.y, window.x + window.width, window.y + window.height, elementCorner)
            end)
        end
        WG['guishader'].InsertDlist(backgroundGuishader, 'keybindconfig')
    end

    -- Title
    UiElement(window.x, window.y + window.height, window.x + 240, window.y + window.height + HEADER_SIZE + PADDING*2, 
        1,1,1,1, 1,nil,nil,nil, 1, colors.windowBackgroundGold1, colors.windowBackgroundGold2)
    
    font:Begin()
    font:SetTextColor(colors.textGold)
    font:Print("Keybinding Configuration", window.x + PADDING*2,
            window.y + window.height + HEADER_SIZE - PADDING, HEADER_SMALL_SIZE, "n")
    font:End()
    
    -- Main window
    UiElement(window.x, window.y + FOOTER_SIZE + 2*PADDING, window.x + window.width, window.y + window.height, 1,1,1,1, 1, nil, nil, nil, 0.85)

    -- Footer
    UiElement(window.x, window.y, window.x + window.width * 1/3 + PADDING, window.y + FOOTER_SIZE + 2*PADDING + elementPadding, 1,1,1,1, 1)
    UiElement(window.x + window.width * 2.5/3, window.y, window.x + window.width, window.y + FOOTER_SIZE + 2*PADDING + elementPadding, 1,1,1,1, 1)
end

local function InitializeUI()
    -- Key selector
    widgetLifecycleRegistry:unregister(keySelector)
    keySelector = KeySelector.new({
        placeholder = "New Key"
    })
    keySelector:setDimensions(
        window.x + elementPadding + PADDING,
        window.y + elementPadding + INPUT_HEIGHT + FOOTER_SIZE,
        math.floor(window.width * 1/3) - 2*elementPadding - PADDING,
        INPUT_HEIGHT
    )
    widgetLifecycleRegistry:register(keySelector)

    -- Command selector
    widgetLifecycleRegistry:unregister(commandSelector)
    commandSelector = CommandSelector.new({
        placeholder = "New Command",
        options = {},  -- Will be populated from availableCommands
    })
    commandSelector:setDimensions(
        window.x + math.floor(window.width * 1/3) + elementPadding,
        window.y + elementPadding + INPUT_HEIGHT + FOOTER_SIZE,
        math.floor(window.width * 1/3) - elementPadding,
        INPUT_HEIGHT
    )
    widgetLifecycleRegistry:register(commandSelector)
    
    -- Extra command selector
    widgetLifecycleRegistry:unregister(extraSelector)
    extraSelector = UiTextboxInteractable.new({
        placeholder = 'New Command Extras',
        px = window.x + math.floor(window.width * 2/3) + elementPadding,
        py = window.y + elementPadding + INPUT_HEIGHT + FOOTER_SIZE,
        sx = window.x + math.floor(window.width * 3/3) + elementPadding - PADDING - 70,
        sy = window.y + elementPadding + INPUT_HEIGHT*2 + FOOTER_SIZE
    })
    widgetLifecycleRegistry:register(extraSelector)

    -- Add button
    widgetLifecycleRegistry:unregister(addButton)
    addButton = UiButtonInteractable.new({
        px = window.x + window.width - elementPadding + PADDING - 70,
        py = window.y + elementPadding + INPUT_HEIGHT + FOOTER_SIZE,
        sx = window.x + window.width - 2*elementPadding - PADDING,
        sy = window.y + elementPadding + INPUT_HEIGHT*2 + FOOTER_SIZE,
        text = 'Add',
        onClick = function()
            local extra = extraSelector.text
            if extra == "New Command Extras" then extra = "" end
    
            hotkeyManager:SaveBinding(keySelector.value, commandSelector.selectedValue, extra)
    
            keySelector.value = "New Key"
            commandSelector.selectedValue = "New Command"
            extraSelector.text = "New Command Extras"
            filterTextbox.text = "Filter..."
        end
    })
    widgetLifecycleRegistry:register(addButton)

    -- Create binding list
    widgetLifecycleRegistry:unregister(bindingList)
    bindingList = BindingList.new({
        onRemove = function(...) 
            hotkeyManager:RemoveBinding(...)
        end
    })
    bindingList:setDimensions(
        window.x + elementPadding + PADDING,
        window.y + INPUT_HEIGHT + FOOTER_SIZE + 4*PADDING,
        window.width - 2*elementPadding - 2*PADDING,
        window.height - 4*elementPadding - HEADER_SIZE - FOOTER_SIZE - 4*PADDING
    )
    widgetLifecycleRegistry:register(bindingList)

    -- Add filter textbox at the bottom
    widgetLifecycleRegistry:unregister(filterTextbox)
    filterTextbox = UiTextboxInteractable.new({
        placeholder = 'Filter...',
        px = window.x + elementPadding + PADDING,
        py = window.y + 2*elementPadding,
        sx = window.x + window.width * 1/3,
        sy = window.y + 2*elementPadding + INPUT_HEIGHT,
        onChange = function(text)
            if bindingList then
                bindingList:setFilter(text)
            end
        end
    })
    widgetLifecycleRegistry:register(filterTextbox)

    -- Default button
    widgetLifecycleRegistry:unregister(defaultButton)
    defaultButton = UiButtonInteractable.new({
        px = window.x + window.width - elementPadding + PADDING - 120,
        py = window.y + 2*elementPadding,
        sx = window.x + window.width - 2*elementPadding - PADDING,
        sy = window.y + 2*elementPadding + INPUT_HEIGHT,
        text = 'Default',
        onClick = function()
            hotkeyManager:LoadDefaultConfig()
        end
    })
    widgetLifecycleRegistry:register(defaultButton)
end
-- #endregion

-- Widget overrides

-- #region Widget overrides
function widget:DrawScreen()
    if not show then return end
    if not font then return end
    
    gl.PushMatrix()

    WidgetPCall(function()
        -- MouseMove only triggers when the mouse is down, but we want it always captured
        local x, y, l = Spring.GetMouseState()
        self:MouseMove(x, y)

        gl.Color(colors.text)

        DrawBackground()
        
        widgetLifecycleRegistry:dispatchEvent('DrawScreen')
        
    end, function()
        gl.PopMatrix()
    end)
end

function widget:MouseWheel(up, value)
    if not show then return false end
    
    return widgetLifecycleRegistry:dispatchEvent('MouseWheel', up, value)
end

function widget:MouseMove(x, y, dx, dy, button)
    if not show then return false end
    if x == mx and y == my then return end
    mx, my = x, y

    return widgetLifecycleRegistry:dispatchEvent('MouseMove', x, y, dx, dy, button)
end

function widget:MousePress(x, y, button)
    if not show then return false end
    
    return widgetLifecycleRegistry:dispatchEvent('MousePress', x, y, button)
end

function widget:MouseRelease(x, y, button)
    if not show then return false end

    return widgetLifecycleRegistry:dispatchEvent('MouseRelease', x, y, button)
end

function widget:KeyPress(key, mods, isRepeat, label)
    if not show then return false end
    
    -- Special handling for ESC key
    if key == 27 then -- Escape
        -- Check if any component wants to handle it first
        local result = widgetLifecycleRegistry:dispatchEvent('KeyPress', key, mods, isRepeat, label)
        if result then return true end
        
        -- If not handled, close the widget
        widget:Toggle()
        return true
    end
    
    return widgetLifecycleRegistry:dispatchEvent('KeyPress', key, mods, isRepeat, label)
end

function widget:TextInput(char)
    if not show then return false end
    
    return widgetLifecycleRegistry:dispatchEvent('TextInput', char)
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

function widget:Initialize()
    WidgetPCall(function()
        -- Initialize default font
        font = WG['fonts'].getFont()

        -- Initialize widget lifecycle registry
        widgetLifecycleRegistry = WidgetLifecycleRegistry.new()
        
        -- Initialize UI
        InitializeUI()
        
        -- Register widget toggle hotkey
        Spring.SendCommands({"bind f9 luaui keybind_custom_config_toggle"})
        widgetHandler:AddAction("keybind_custom_config_toggle", function()
            widget:Toggle()
        end, nil, "t")
        
        -- Initialize hotkey manager
        hotkeyManager = HotkeyManager.new()
        hotkeyManager:LoadHotkeyConfigs()
        hotkeyManager:LoadCurrentBindings()
    
        -- Register widget in global table
        WG['keybind_custom_config'] = widget
    end)
end

function widget:ViewResize()
    vsx, vsy = Spring.GetViewGeometry()
    window.x = math.floor((vsx * centerPosX) - (window.width / 2))
    window.y = math.floor((vsy * centerPosY) - (window.height / 2))
    
    font = WG['fonts'].getFont()
    
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
-- #endregion
