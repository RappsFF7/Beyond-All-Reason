--[[
    Notable related issues:
    - https://github.com/beyond-all-reason/Beyond-All-Reason/issues/396
]]--

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

local utf8 = VFS.Include('common/luaUtilities/utf8.lua')
local keyLayouts = VFS.Include("luaui/configs/keyboard_layouts.lua")

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
    buttonBackgroundDark = {0.05, 0.05, 0.05, 1},
    buttonHover = {0.25, 0.25, 0.25, 0.7},
    buttonActive = {0.3, 0.3, 0.3, 0.7},
    text = {1, 1, 1, 1},
    textGold = {171/255, 141/255, 107/255, 1},
    textGoldBright = {245/255, 196/255, 136/255, 1},
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
local resetButton

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
    local function errorHandler(err)
        -- The '2' argument skips the errorHandler frame itself
        log("Error:", debug.traceback(err, 2))
        return err
    end

    local _, result = xpcall(func, errorHandler, ...)

    if callback then
        callback()
    end

    return result
end 

-- #endregion local variables

-- Classes

-- #region Classes

local WidgetLifecycleRegistry = {}
WidgetLifecycleRegistry.__index = WidgetLifecycleRegistry

function WidgetLifecycleRegistry.new()
    local self = setmetatable({}, WidgetLifecycleRegistry)

    self.components = {}

    function self:wrap(component)
        -- Automatically hook into widget lifecycle methods
        -- gadgets.lua and barwidgets.lua has callInLists, but they're local so we can't use them
        local methods = {
            'Initialize', 'Update', 'Shutdown', 'DrawScreen', 'ViewResize',
            'MouseWheel', 'MouseMove', 'MousePress', 'MouseRelease',
            'KeyPress', 'TextInput'
        }
        for _, method in ipairs(methods) do
            local original = component[method]
            
            component[method] = function(componentSelf, ...)
                local args = {...}
                return WidgetPCall(function()
                    if not show and method ~= 'Initialize' then return false end
    
                    local result
                    if original then
                        result = original(component, unpack(args))
                    end
    
                    local resultDispatch = self:dispatchEvent(method, unpack(args))
    
                    return result or resultDispatch
                end)
            end
        end

        return component
    end

    function self:register(component)
        table.insert(self.components, component)
    end
    
    function self:unregister(component)
        for i, comp in ipairs(self.components) do
            if comp == component then
                table.remove(self.components, i)
                break
            end
        end
    end
    
    function self:dispatchEvent(eventName, ...)
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
    text - Displayed text
]]--
function UiButtonInteractable.new(options)
    local self = setmetatable(options or {}, UiButtonInteractable)

    self.isActive = false
    self.isHover = false
   
    local font = WG['fonts'].getFont()

    local function isInRect(x, y)      
        return math_isInRect(
            x, y,
            self.px, self.py,
            self.sx, self.sy
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
        if self.text then
            font:Begin()
            font:SetTextColor(1,1,1,1)
            font:Print(
                self.text,
                self.px + elementPadding,
                self.py + elementPadding + (self.sy - self.py) / 2 - FONT_SIZE / 2,
                FONT_SIZE, "n"
            )
            font:End()
        end
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

    return self
end

local UiTextboxInteractable = {}
UiTextboxInteractable.__index = UiTextboxInteractable

--[[
    px, py, sx, sy,  tl, tr, br, bl,  ptl, ptr, pbr, pbl,  opacity, color1, color2, bgpadding, glossMult,
    text - Displayed text
]]--
function UiTextboxInteractable.new(options)
    local self = setmetatable(options, UiTextboxInteractable)

    self.isActive = false
    self.text = self.placeholder or ""
    self.value = self.value or ""
    
    local totalDeltaTime = 0
    local font = WG['fonts'].getFont()
    local subwidgets = WidgetLifecycleRegistry.new()

    local button = UiButtonInteractable.new({
        px = self.px, py = self.py, sx = self.sx, sy = self.sy,
        tl = 1, tr = 1, bl = 1, br = 1,
        ptl = 1, ptr = 1, pbl = 1, pbr = 1,
        text = self.text,
        onClick = function()
            self.isActive = true
            self.text = self.value
            if self.onClick then
                self.onClick()
            end
            return true
        end
    })
    subwidgets:register(button)

    function self:SetValue(value)
        self.value = value
        self.text = value
        if self.placeholder and self.value == '' then
            self.text = self.placeholder
        end
    end

    function self:DrawScreen()
        button.text = self.text

        -- Draw text beam
        if self.isActive then
            local color = colors.text
            local duration = 1 -- 1s
            local textEndPos = math.floor(font:GetTextWidth(utf8.sub(self.text, 1, self.px)) * FONT_SIZE)
            color[4] = 1 - (totalDeltaTime * (1 / duration)) + 0.15

            font:Begin()
            font:SetTextColor(color)
            font:Print("|", self.px + textEndPos + elementPadding, self.py + FONT_SIZE / 2, FONT_SIZE, "n")
            font:End()
        end
    end

    function self:Update(dt)
        totalDeltaTime = totalDeltaTime + dt
    end

    function self:MousePress(x, y)
        if self.isActive then
            self.isActive = false
            if self.placeholder and self.value == '' then
                self.text = self.placeholder
            end
            if self.onBlur then
                self.onBlur()
            end
        end

        return false
    end

    function self:TextInput(char)
        if not self.isActive then return false end
        
        self.value = self.value .. char
        self.text = self.value
        if self.onChange then
            self.onChange(self.value)
        end

        return true
    end

    function self:KeyPress(key)
        if not self.isActive then return false end
        
        if key == 8 then -- Backspace
            if #self.value > 0 then
                self.value = self.value:sub(1, -2)
                self.text = self.value
                if self.onChange then
                    self.onChange(self.value)
                end
            end
            return true
        elseif key == 13 then -- Enter
            self.isActive = false
            return true
        end
        return false
    end

    return subwidgets:wrap(self)
end

--[[
    Note that items are drawn TOP to BOTTOM, which means elements should be drawn DOWN from their x,y position provided in onDrawRow.

    rowHeight, elementCount, onDrawRow
]]--
local UiScrollInteractable = {}
UiScrollInteractable.__index = UiScrollInteractable

function UiScrollInteractable.new(options)
    local self = setmetatable({}, UiScrollInteractable)
    
    -- Configuration
    self.isActive = true
    self.x = 0
    self.y = 0
    self.width = 0
    self.height = 0
    self.rowHeight = options.rowHeight
    self.elementCount = options.elementCount
    self.onDrawRow = options.onDrawRow
    self.scrollOffset = 0
    self.scrollGutter = 10
    self.minScrollOffset = 0
    self.maxScrollOffset = 0
    
    -- Calculate how many rows are visible
    function self:getVisibleRows()
        return math.floor(self.height / self.rowHeight)
    end
    
    function self:updateScrollBounds()
        local totalHeight = self.elementCount * self.rowHeight
        self.maxScrollOffset = math.max(0, totalHeight - self.height)
        self.scrollOffset = math.max(self.minScrollOffset, math.min(self.maxScrollOffset, self.scrollOffset))
    end
    
    function self:setDimensions(x, y, width, height)
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self:updateScrollBounds()
    end
    
    function self:setElementCount(count)
        self.elementCount = count
        self:updateScrollBounds()
    end
    
    function self:setActive(isActive)
        self.isActive = isActive
    end
    
    function self:DrawScreen()
        -- Setup scissor to clip content
        gl.PushMatrix()
        gl.Scissor(self.x, self.y, self.width, self.height)
        
        -- Calculate visible range
        local startRow = math.floor(self.scrollOffset / self.rowHeight)
        local visibleRows = self:getVisibleRows()
        local endRow = math.min(startRow + visibleRows + 1, self.elementCount - 1)
        
        -- Draw visible rows
        for i = startRow, endRow do
            local yPos = -(i * self.rowHeight) + self.scrollOffset
            
            -- Only draw if row will be visible
            if yPos > -self.height and yPos < self.rowHeight then
                if self.onDrawRow then
                    -- Call draw callback with row index and position info
                    self.onDrawRow(i + 1, {
                        x = self.x,
                        y = self.y + self.height + yPos - self.rowHeight,
                        width = self.width,
                        height = self.rowHeight
                    })
                end
            end
        end
        
        -- Draw scrollbar if needed
        if self.maxScrollOffset > 0 then
            gl.Scissor(self.x, self.y, self.width + self.scrollGutter, self.height)

            -- Since we draw from top to bottom, the bottom y is -height
            local sliderHeight = self.height * (self.height / self.maxScrollOffset)
            WG.FlowUI.Draw.Scroller(
                self.x + self.width,
                self.y + (sliderHeight * 0.65),
                self.x + self.width + self.scrollGutter,
                self.y + self.height,
                self.maxScrollOffset,
                self.scrollOffset
            )
        end
        
        gl.Scissor(false)
        gl.PopMatrix()
    end
    
    function self:MouseWheel(up, value)
        if not self.isActive then return end

        local mouseX, mouseY = Spring.GetMouseState()
        
        if math_isInRect(mouseX, mouseY, self.x, self.y, self.x + self.width, self.y + self.height) then
            local newOffset = self.scrollOffset - value * 50
            self.scrollOffset = math.max(self.minScrollOffset, math.min(self.maxScrollOffset, newOffset))
            return true
        end
        return false
    end
    
    return self
end

--[[
    px, py, sx, sy,  tl, tr, br, bl,  ptl, ptr, pbr, pbl,  opacity, color1, color2, bgpadding, glossMult,
    placeholder - Displayed text when the currently selected value is empty
]]--
local UiDropdownInteractable = {}
UiDropdownInteractable.__index = UiDropdownInteractable

function UiDropdownInteractable.new(options)
    local self = setmetatable({}, UiDropdownInteractable)

    self.placeholder = options.placeholder or ""
    self.x = options.px or 0
    self.y = options.py or 0
    self.width = (options.sx or 0) - self.x
    self.height = (options.sy or 0) - self.y
    self.options = options.options or {}
    self.onFocus = options.onFocus
    self.onBlur = options.onBlur
    self.onChange = options.onChange
    self.isActive = false
    self.isSearchable = options.isSearchable or true
    self.filter = ""

    local font = WG['fonts'].getFont()
    local subwidgets = WidgetLifecycleRegistry.new()
    
    local filteredOptions = self.options

    -- Create scroll component for dropdown options
    local optionRowHeight = 25
    local optionsScroll = UiScrollInteractable.new({
        rowHeight = optionRowHeight,
        elementCount = 0,
        onDrawRow = function(rowIndex, pos)
            local option = filteredOptions[rowIndex]
            if not option then return end
            
            if math_isInRect(mx, my,
                self.x,
                pos.x,
                self.x + self.width,
                pos.y + pos.height
            ) then
                UiSelectHighlight(
                    pos.x,
                    pos.y,
                    pos.x + pos.width,
                    pos.y + pos.height
                )
            end
            
            font:Begin()
            font:Print(option,
                pos.x + elementPadding,
                pos.y + elementPadding,
                FONT_SIZE,
                "n"
            )
            font:End()
        end
    })
    optionsScroll:setActive(false)
    subwidgets:register(optionsScroll)

    -- UiSelector button
    local button = UiButtonInteractable.new({
        tl = 1, tr = 1, bl = 1, br = 1,
        ptl = 1, ptr = 1, pbl = 1, pbr = 1,
                color1 = self.isActive and colors.buttonActive or colors.buttonBackground,
        text = self.placeholder,
        onClick = function()
            self:SetActive(not self.isActive)
        end
    })
    subwidgets:register(button)

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
            filteredOptions = self.options
        else
            filteredOptions = {}
            for _, cmd in ipairs(self.options) do
                if cmd:lower():find(self.filter:lower(), 1, true) then
                    table.insert(filteredOptions, cmd)
                end
            end
        end
        optionsScroll:setElementCount(#filteredOptions)
    end

    function self:SetActive(isActive)
        local isChanging = (self.isActive ~= isActive)
        self.isActive = isActive
        if isChanging then
            if isActive then
                if self.onFocus then self.onFocus() end
                self:updateFilteredOptions()
                optionsScroll:setActive(true)
            else
                if self.onBlur then self.onBlur() end
                optionsScroll:setActive(false)
                optionsScroll:setElementCount(0)
            end
        end
    end

    function self:DrawScreen()
        if self.isActive and self.isSearchable then
            button.text = self.filter ~= "" and self.filter or 'Search...'
        else
            button.text = self.value or self.placeholder
        end

        -- Draw dropdown indicator
        RectRound(
            self.x + self.width * 9/10,
            self.y,
            self.x + self.width,
            self.y + self.height,
            1, 2, 2, 2, 2, { 0.7, 0.7, 0.7, 0.3 }, { 0.7, 0.7, 0.7, 0.3 }
        )
        
        -- Draw dropdown if active
        if self.isActive then
            local dropdownY = self.y + self.height
            local dropdownHeight = math.min(self.height * 10, #filteredOptions * optionRowHeight)
        
            -- Draw dropdown background
            RectRound(
                self.x,
                dropdownY,
                self.x + self.width,
                dropdownY + dropdownHeight,
                1, 2, 2, 2, 2, { 0.5, 0.5, 0.5, 0.95 }
            )
            
            -- Update scroll dimensions and draw options
            optionsScroll:setDimensions(
                self.x,
                dropdownY,
                self.width,
                dropdownHeight
            )
        end
    end

    function self:MousePress(x, y)
        if self.isActive then
            local dropdownY = self.y + self.height
            local dropdownHeight = math.min(self.height * 10, #filteredOptions * optionRowHeight)
            
            if math_isInRect(x, y,
                self.x,
                dropdownY,
                self.x + self.width,
                dropdownY + dropdownHeight
            ) then
                -- Find which option was clicked
                local relativeY = dropdownHeight - (y - dropdownY) + optionsScroll.scrollOffset
                local clickedIndex = math.floor(relativeY / optionRowHeight) + 1
                
                if clickedIndex >= 1 and clickedIndex <= #filteredOptions then
                    self.value = filteredOptions[clickedIndex]
                    if self.onChange then self.onChange(self.value) end
                    self:SetActive(false)
                end
                return true
            end
        end
        self:SetActive(false)
        return false
    end

    function self:TextInput(char)
        if not (self.isActive and self.isSearchable) then return false end
        
        self.filter = self.filter .. char
        self:updateFilteredOptions()
        return true
    end

    function self:KeyPress(key)
        if not (self.isActive and self.isSearchable) then return false end
        
        if key == 8 then -- Backspace
            if #self.filter > 0 then
                self.filter = self.filter:sub(1, -2)
                self:updateFilteredOptions()
            end
            return true
        elseif key == 13 then -- Enter
            if #filteredOptions > 0 then
                self.value = filteredOptions[1]
                if self.onChange then self.onChange(self.value) end
                self:SetActive(false)
            end
            return true
        end
        
        self:updateFilteredOptions()

        return false
    end

    return subwidgets:wrap(self)
end

local KeySelector = {}
KeySelector.__index = KeySelector

function KeySelector.new(options)
    local self = setmetatable(options, KeySelector)

    local subwidgets = WidgetLifecycleRegistry.new()

    self.placeholder = options.placeholder or 'New Key'
    self.text = self.placeholder
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
    subwidgets:register(button)

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
    subwidgets:register(buttonAdd)

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

    function self:clear()
        self.value = ''
        self.text = self.placeholder
    end
    
    function self:DrawScreen()
        button.text = self.text
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
            self:clear()
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
                local divider = ''
                if self.value ~= '' then
                    divider = ','
                end
                self.value = self.value .. divider .. modstring .. springSymbol
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

    return subwidgets:wrap(self)
end

local CommandSelector = {}
CommandSelector.__index = CommandSelector

function CommandSelector.new(options)
    local self = setmetatable(options or {}, CommandSelector)

    local subwidgets = WidgetLifecycleRegistry.new()

    -- UiSelector
    local button = UiDropdownInteractable.new({
        tl = 1, tr = 1, bl = 1, br = 1,
        ptl = 1, ptr = 1, pbl = 1, pbr = 1,
        color1 = self.isActive and colors.buttonActive or colors.buttonBackground,
        placeholder = "New Command",
        options = options.options,
        onFocus = options.onFocus,
        onBlur = options.onBlur,
        onChange = options.onChange
    })
    subwidgets:register(button)

    function self:setDimensions(x, y, width, height)
        button:setDimensions(x, y, width, height)
    end

    function self:setOptions(options)
        button.options = options
    end

    function self:getSelectedValue()
        return button.value
    end

    function self:setSelectedValue(value)
        button.value = value
    end

    return subwidgets:wrap(self)
end

-- Create BindingList class after the dropdown classes
local BindingList = {}
BindingList.__index = BindingList

function BindingList.new(options)
    local self = setmetatable({}, BindingList)
    self.isActive = true
    self.x = 0
    self.y = 0
    self.width = 0
    self.height = 0
    self.filterText = ""
    self.bindings = {}
    self.filteredBindings = {}
    self.deleteButtons = {}
    self.filteredDeleteButtons = {}
    self.onRemove = options.onRemove

    local font = WG['fonts'].getFont()
    local subwidgets = WidgetLifecycleRegistry.new()

    -- Create scroll component
    local scroll = UiScrollInteractable.new({
        rowHeight = BUTTON_HEIGHT + elementPadding,
        elementCount = 0,
        onDrawRow = function(rowIndex, pos)
            local binding = self.filteredBindings[rowIndex]
            if not binding then return end

            local isRowActive = (self.isActive and math_isInRect(mx, my, pos.x, pos.y, pos.x + pos.width, pos.y + pos.height))

            -- TODO ui scroll relies on scissor (is there a better way? the stencil buffer is complicated), 
            -- so we can't use scissor. How can we clip the text? Instead we'll just limit by size.

            -- Check if text will overflow
            local limitText = function(text, maxPosX)
                local textRelativeEndPos = math.floor(font:GetTextWidth(utf8.sub(text, 1, pos.x)) * FONT_SIZE)
                local isTextOverflow = textRelativeEndPos > maxPosX
                local limitedText = (isTextOverflow and string.sub(text, 1, 15) .. '...' or text)
                return limitedText, isTextOverflow
            end
            local boundWith, isBoundWithOverflow = limitText(binding.boundWith, pos.width - pos.x)
            local command, isCommandOverflow = limitText(binding.command, pos.width - pos.x)
            local extra, isExtraOverflow = limitText(binding.extra, pos.width - pos.x)
            local isTextOverflow = isBoundWithOverflow or isCommandOverflow or isExtraOverflow

            -- Draw binding row highlight
            if isRowActive then
                UiElement(pos.x, pos.y, pos.x + pos.width, pos.y + pos.height, 0,0,0,0, 0,0,0,0, 0, colors.buttonHover)
            end

            -- Draw text
            font:Begin()
            font:SetTextColor(1,1,1,1)
            font:SetOutlineColor(0,0,0,0.4)

            -- Draw boundWith
            font:Print(boundWith or "", pos.x + elementPadding, pos.y + elementPadding, FONT_SIZE, "n")
            
            -- Draw command
            font:Print(command or "", pos.x + pos.width * (1/3), pos.y + elementPadding, FONT_SIZE, "n")
            
            -- Draw extra
            font:Print(extra or "", pos.x + pos.width * (2/3), pos.y + elementPadding, FONT_SIZE, "n")
            font:End()
            
            -- Position and draw delete button
            local deleteButton = self.filteredDeleteButtons[rowIndex]
            if deleteButton then
                deleteButton.px = pos.x + pos.width - 30
                deleteButton.py = pos.y - elementPadding
                deleteButton.sx = pos.x + pos.width - 15
                deleteButton.sy = pos.y + pos.height - elementPadding
                deleteButton:DrawScreen()
            end

            if isRowActive and isTextOverflow then
                local tooltip =
                    'Keys: ' .. binding.boundWith .. '\n' ..
                    'Command: ' .. binding.command .. '\n' ..
                    'Extra: ' .. binding.extra
                WG.tooltip.ShowTooltip('keybind_description', tooltip, pos.x + 20, pos.y, 'Keybind')
            end
        end
    })
    subwidgets:register(scroll)

    function self:setFilter(text)
        self.filterText = text:lower()
        self:updateFilteredBindings()
    end

    function self:updateFilteredBindings()
        if self.filterText == "" then
            self.filteredBindings = self.bindings
            self.filteredDeleteButtons = self.deleteButtons
        else
            self.filteredBindings = {}
            self.filteredDeleteButtons = {}
            for i, binding in ipairs(self.bindings) do
                if binding.boundWith:lower():find(self.filterText, 1, true) or
                   binding.command:lower():find(self.filterText, 1, true) or
                   (binding.extra and binding.extra:lower():find(self.filterText, 1, true)) then
                    table.insert(self.filteredBindings, binding)
                    table.insert(self.filteredDeleteButtons, self.deleteButtons[i])
                end
            end
        end
        scroll:setElementCount(#self.filteredBindings)
    end

    function self:setDimensions(x, y, width, height)
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        scroll:setDimensions(x, y + PADDING, width, height - HEADER_SIZE - 3*PADDING)
    end

    function self:setActive(isActive)
        self.isActive = isActive
        scroll:setActive(isActive)
    end

    function self:setBindings(bindings)
        self.bindings = bindings

        -- Create/update delete buttons
        self.deleteButtons = {}
        for i = 1, #self.bindings do
            local button = UiButtonInteractable.new({
                text = "X",
                color1 = colors.removeButton,
                color2 = colors.removeButtonHover,
                onClick = function()
                    if self.onRemove then
                        local binding = self.bindings[i]
                        self.onRemove(binding.boundWith, binding.command, binding.extra)
                    end
                end
            })
            self.deleteButtons[i] = button
        end
        
        self:updateFilteredBindings()
    end
    
    function self:DrawScreen()
        gl.PushMatrix()
        WidgetPCall(function()
            -- Draw header
            font:Begin()
            font:SetTextColor(colors.textGoldBright)
            font:Print("Keys", self.x, self.y + self.height - HEADER_SIZE - PADDING, HEADER_SIZE, "n")
            font:Print("Command", self.x + self.width * 1/3, self.y + self.height - HEADER_SIZE - PADDING, HEADER_SIZE, "n")
            font:Print("Command Extras", self.x + self.width * 2/3, self.y + self.height - HEADER_SIZE - PADDING, HEADER_SIZE, "n")
            font:End()
        end, function()
            gl.PopMatrix()
        end)
    end
    
    function self:MouseWheel(up, value)
        if not self.isActive then return false end
        return true
    end
    
    function self:MousePress(x, y)
        -- Check all visible buttons if they are clicked
        for _, button in ipairs(self.filteredDeleteButtons) do
            if button:MousePress(x, y, nil, true) then
                return true
            end
        end
        return false
    end

    return subwidgets:wrap(self)
end

local HotkeyManager = {}
HotkeyManager.__index = HotkeyManager

function HotkeyManager.new(options)
    local self = setmetatable(options or {}, HotkeyManager)

    self.file = keyLayouts.keybindingLayoutFiles[#keyLayouts.keybindingLayoutFiles]
    self.currentBindings = {}
    self.availableKeys = {}
    self.availableCommands = {}

    local function caseInsensitiveCompare(a, b)
        return string.lower(a) < string.lower(b)
    end

    function self:LoadDefaultConfig()
        Spring.SetConfigString("KeybindingFile", keyLayouts.keybindingLayoutFiles[1])

        if WG['bar_hotkeys'] and WG['bar_hotkeys'].reloadBindings then
            WG['bar_hotkeys'].reloadBindings()
        end

        self:LoadCurrentBindings()
    end

    function self:LoadHotkeyConfigs()
        -- Load available commands and keys from hotkey config files
        for _, file in pairs(keyLayouts.keybindingLayoutFiles) do
            local gridKeys = VFS.LoadFile(file)
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
        table.sort(keyOptions, caseInsensitiveCompare)
        if self.onChangeAvailableKeys then
            self.onChangeAvailableKeys(keyOptions)
        end
        
        local cmdOptions = {}
        for cmd in pairs(self.availableCommands) do
            table.insert(cmdOptions, cmd)
        end
        table.sort(cmdOptions, caseInsensitiveCompare)
        if self.onChangeAvailableCommands then
            self.onChangeAvailableCommands(cmdOptions)
        end
    end

    function self:LoadCurrentBindings()
        self.currentBindings = Spring.GetKeyBindings() or {}
        if (self.onChange) then
            self.onChange(self.currentBindings)
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
                RectRound(window.x, window.y + FOOTER_SIZE + PADDING*2, window.x + window.width, window.y + window.height, elementCorner)
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
    UiElement(window.x, window.y + FOOTER_SIZE + 2*PADDING, window.x + window.width, window.y + window.height, 1,1,1,1, 1,nil,nil,nil, 0.85)

    -- Footer
    UiElement(window.x, window.y, window.x + window.width * 1/3 + PADDING, window.y + FOOTER_SIZE + 2*PADDING + elementPadding, 1,1,1,1, 1,nil,nil,nil, 0.85, nil,colors.buttonBackgroundDark)
    UiElement(window.x + window.width * 2.5/3, window.y, window.x + window.width, window.y + FOOTER_SIZE + 2*PADDING + elementPadding, 1,1,1,1, 1,nil,nil,nil, 0.85, nil,colors.buttonBackgroundDark)
end

local function InitializeUI()
    -- Key selector
    widgetLifecycleRegistry:unregister(keySelector)
    keySelector = KeySelector.new({
        placeholder = "New Key"
    })
    keySelector:setDimensions(
        window.x + elementPadding + PADDING,
        window.y + elementPadding + PADDING * 1/2 + INPUT_HEIGHT + FOOTER_SIZE,
        math.floor(window.width * 1/3) - 2*elementPadding - PADDING,
        INPUT_HEIGHT
    )
    widgetLifecycleRegistry:register(keySelector)

    -- Command selector
    widgetLifecycleRegistry:unregister(commandSelector)
    commandSelector = CommandSelector.new({
        placeholder = "New Command",
        options = {},  -- Will be populated from availableCommands
        onFocus = function()
            bindingList:setActive(false)
        end,
        onBlur = function()
            bindingList:setActive(true)
        end,
    })
    commandSelector:setDimensions(
        window.x + math.floor(window.width * 1/3) + elementPadding,
        window.y + elementPadding + PADDING * 1/2 + INPUT_HEIGHT + FOOTER_SIZE,
        math.floor(window.width * 1/3) - elementPadding,
        INPUT_HEIGHT
    )
    widgetLifecycleRegistry:register(commandSelector)
    
    -- Extra command selector
    widgetLifecycleRegistry:unregister(extraSelector)
    extraSelector = UiTextboxInteractable.new({
        placeholder = 'New Command Extras',
        px = window.x + math.floor(window.width * 2/3) + elementPadding,
        py = window.y + elementPadding + PADDING * 1/2 + INPUT_HEIGHT + FOOTER_SIZE,
        sx = window.x + math.floor(window.width * 3/3) + elementPadding - PADDING - 70,
        sy = window.y + elementPadding + PADDING * 1/2 + INPUT_HEIGHT*2 + FOOTER_SIZE
    })
    widgetLifecycleRegistry:register(extraSelector)

    -- Add button
    widgetLifecycleRegistry:unregister(addButton)
    addButton = UiButtonInteractable.new({
        px = window.x + window.width - elementPadding + PADDING - 70,
        py = window.y + elementPadding + PADDING * 1/2 + INPUT_HEIGHT + FOOTER_SIZE,
        sx = window.x + window.width - 2*elementPadding - PADDING,
        sy = window.y + elementPadding + PADDING * 1/2 + INPUT_HEIGHT*2 + FOOTER_SIZE,
        text = 'Add',
        onClick = function()
            hotkeyManager:SaveBinding(keySelector.value, commandSelector:getSelectedValue(), extraSelector.value)
    
            keySelector:clear()
            commandSelector:setSelectedValue(nil)
            extraSelector:SetValue("")
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
        window.width - 2*elementPadding - 2*PADDING - PADDING,
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
    widgetLifecycleRegistry:unregister(resetButton)
    resetButton = UiButtonInteractable.new({
        px = window.x + window.width - elementPadding + PADDING - 120,
        py = window.y + 2*elementPadding,
        sx = window.x + window.width - 2*elementPadding - PADDING,
        sy = window.y + 2*elementPadding + INPUT_HEIGHT,
        text = 'Reset All',
        onClick = function()
            hotkeyManager:LoadDefaultConfig()
        end
    })
    widgetLifecycleRegistry:register(resetButton)
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
        Spring.SetMouseCursor('cursornormal')

        DrawBackground()
        
    end, function()
        gl.PopMatrix()
    end)
end

function widget:MouseMove(x, y, dx, dy, button)
    if not show then return false end
    if x == mx and y == my then return end
    mx, my = x, y
end

function widget:MousePress(x, y, button)
    if not show then return false end

    -- Close if clicking outside the drawn widget
    if not math_isInRect(x, y, window.x, window.y, window.x + window.width, window.y + window.height + HEADER_SIZE + PADDING*2) then
        widget:Toggle()
    end
    
    -- Prevent mouse press from passing through to the game
    return true
end

function widget:MouseRelease(x, y, button)
    if not show then return false end

    return true
end

function widget:KeyPress(key, mods, isRepeat, label)
    if not show then return false end
    
    -- Special handling for ESC key
    if key == 27 then -- Escape
        -- Check if any component wants to handle it first
        --local result = widgetLifecycleRegistry:dispatchEvent('KeyPress', key, mods, isRepeat, label)
        --if result then return true end
        
        -- If not handled, close the widget
        widget:Toggle()
        return true
    end
end

function widget:Toggle(isShow)
    show = isShow or not show
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
        
        -- Initialize UI
        InitializeUI()
        
        -- Register widget toggle hotkey
        Spring.SendCommands({"bind f9 luaui keybind_custom_config_toggle"})
        widgetHandler:AddAction("keybind_custom_config_toggle", function()
            widget:Toggle()
        end, nil, "t")
        
        -- Initialize hotkey manager
        hotkeyManager = HotkeyManager.new({
            onChange = function(bindings)
                if bindingList then
                    bindingList:setBindings(bindings)
                end
            end,
            onChangeAvailableKeys = function(keys)
                keySelector.options = keys
            end,
            onChangeAvailableCommands = function(commands)
                commandSelector:setOptions(commands)
            end
        })
        hotkeyManager:LoadHotkeyConfigs()
        hotkeyManager:LoadCurrentBindings()
    
        -- Register widget in global table
        WG['keybind_custom_config'] = widget

        widgetLifecycleRegistry:dispatchEvent('Initialize')

        return false
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

-- Initialize widget lifecycle registry (must do before Initialize is called by widgetHandler)
widgetLifecycleRegistry = WidgetLifecycleRegistry.new()
widgetLifecycleRegistry:wrap(widget)
