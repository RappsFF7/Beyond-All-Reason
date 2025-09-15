---@class Widget
---@field Initialize function
---@field Shutdown function
---@field KeyPress function
local widget = widget

function widget:GetInfo()
    return {
        name = "Keybind Custom Config",
        desc = "GUI for customizing keyboard shortcuts",
        author = "Your Name",
        date = "September 2025",
        license = "GNU GPL, v2 or later",
        layer = 0,
        enabled = false,
    }
end

-- Forward declarations
local RefreshBindingsList

-- Chili elements
local Chili
local window
local bindingsList
local keyInput
local commandInput
local addButton
local commandSuggestMenu

-- State
local currentBindings = {}
local captureKeys = false

-- Common key modifiers and commands for suggestions
local keyModifiers = {
    'Any', 'Alt', 'Ctrl', 'Shift',
    'Ctrl+Alt', 'Shift+Alt', 'Ctrl+Shift',
    'Ctrl+Shift+Alt'
}

local commonKeys = {
    "sc_a", "sc_b", "sc_c", "sc_d", "sc_e", "sc_f", "sc_g", "sc_h", "sc_i", "sc_j",
    "sc_k", "sc_l", "sc_m", "sc_n", "sc_o", "sc_p", "sc_q", "sc_r", "sc_s", "sc_t",
    "sc_u", "sc_v", "sc_w", "sc_x", "sc_y", "sc_z",
    "sc_1", "sc_2", "sc_3", "sc_4", "sc_5", "sc_6", "sc_7", "sc_8", "sc_9", "sc_0",
    "sc_[", "sc_]", "sc_;", "sc_'", "sc_`", "sc_-", "sc_=",
    "numpad0", "numpad1", "numpad2", "numpad3", "numpad4",
    "numpad5", "numpad6", "numpad7", "numpad8", "numpad9",
    "numpad+", "numpad-", "numpad*", "numpad/",
    "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12"
}

local commonCommands = {
    "attack", "stop", "fight", "patrol", "guard", "reclaim", "repair",
    "move", "resurrect", "capture", "wait", "onoff", "selfd",
    "areaattack", "manualfire", "manuallaunch", "loadunits", "unloadunits",
    "cloak", "stockpile", "repeat", "settarget", "canceltarget",
    "increasespeed", "decreasespeed", "movefast", "buildfacing",
    "togglelos", "toggleoverview", "viewta", "viewspring"
}

local function GetPressedModifiers()
    local alt, ctrl, meta, shift = Spring.GetModKeyState()
    local mods = {}
    if alt then table.insert(mods, "Alt") end
    if ctrl then table.insert(mods, "Ctrl") end
    if shift then table.insert(mods, "Shift") end
    if #mods == 0 then
        return ""
    end
    return table.concat(mods, "+") .. "+"
end

local function GetKeyName(key)
    if key >= 97 and key <= 122 then
        return "sc_" .. string.char(key)
    elseif key >= 48 and key <= 57 then
        return "sc_" .. string.char(key)
    elseif key >= 282 and key <= 293 then
        return "f" .. (key - 281)
    elseif key >= 256 and key <= 265 then
        return "numpad" .. (key - 256)
    end
    return Spring.GetKeySymbol(key)
end

local function LoadCurrentBindings()
    local bindings = Spring.GetKeyBindings()
    currentBindings = {}
    for _, binding in ipairs(bindings) do
        table.insert(currentBindings, {
            key = binding.key,
            command = binding.command,
            boundWith = binding.boundWith
        })
    end
    return currentBindings
end

local function SaveBinding(key, command)
    if key and command and key ~= "" and command ~= "" then
        Spring.SendCommands({"bind " .. key .. " " .. command})
        LoadCurrentBindings() -- Refresh the list
        RefreshBindingsList()
    end
end

local function RemoveBinding(key, command)
    if key and command then
        Spring.SendCommands({"unbind " .. key .. " " .. command})
        LoadCurrentBindings() -- Refresh the list
        RefreshBindingsList()
    end
end

local function RefreshBindingsList()
    bindingsList:ClearChildren()
    
    for i, binding in ipairs(currentBindings) do
        local row = Chili.Grid:New{
            parent = bindingsList,
            columns = 3,
            padding = {0, 0, 0, 0},
            margin = {0, 2, 0, 2},
            itemPadding = {5, 0, 5, 0},
            itemMargin = {0, 0, 0, 0},
            width = "100%",
            height = 25,
            children = {
                Chili.Label:New{
                    caption = binding.key,
                    width = "30%",
                },
                Chili.Label:New{
                    caption = binding.command,
                    width = "50%",
                },
                Chili.Button:New{
                    caption = Spring.I18N('ui.keybindConfig.remove'),
                    width = "20%",
                    OnClick = { function() 
                        RemoveBinding(binding.key, binding.command)
                    end },
                }
            }
        }
    end
end

local function CreateCommandDropdown()
    local menu = Chili.Window:New{
        parent = Chili.Screen0,
        x = commandInput.x,
        y = commandInput.y + commandInput.height,
        width = 200,
        height = 300,
        draggable = false,
        resizable = false,
        borderSize = 0,
        children = {
            Chili.ScrollPanel:New{
                x = 0,
                y = 0,
                right = 0,
                bottom = 0,
                horizontalScrollbar = false,
                children = {
                    Chili.StackPanel:New{
                        x = 0,
                        y = 0,
                        width = "100%",
                        resizeItems = false,
                        itemMargin = {0, 0, 0, 0},
                    }
                }
            }
        }
    }
    return menu
end

local function ShowCommandSuggestions(text)
    if not commandSuggestMenu then
        commandSuggestMenu = CreateCommandDropdown()
    end
    
    local stackPanel = commandSuggestMenu.children[1].children[1]
    stackPanel:ClearChildren()
    
    local matched = {}
    text = text:lower()
    for _, cmd in ipairs(commonCommands) do
        if cmd:lower():find(text, 1, true) then
            table.insert(matched, cmd)
        end
    end
    
    for _, cmd in ipairs(matched) do
        Chili.Button:New{
            parent = stackPanel,
            caption = cmd,
            width = "100%",
            height = 25,
            OnClick = { function()
                commandInput:SetText(cmd)
                commandSuggestMenu:Hide()
            end },
        }
    end
    
    if #matched > 0 then
        commandSuggestMenu:Show()
    else
        commandSuggestMenu:Hide()
    end
end

local function CreateWindow()
    window = Chili.Window:New{
        parent = Chili.Screen0,
        x = "30%",
        y = "20%",
        width = 500,
        height = 600,
        draggable = true,
        resizable = false,
        caption = Spring.I18N('ui.keybindConfig.title'),
        children = {
            Chili.Label:New{
                x = 15,
                y = 20,
                caption = Spring.I18N('ui.keybindConfig.currentBindings'),
            },
            -- Scrolling list of current bindings
            Chili.ScrollPanel:New{
                x = 15,
                y = 45,
                right = 15,
                bottom = 100,
                horizontalScrollbar = false,
                children = {
                    bindingsList = Chili.StackPanel:New{
                        x = 0,
                        y = 0,
                        width = "100%",
                        resizeItems = false,
                        itemMargin = {0, 0, 0, 0},
                    }
                }
            },
            -- Add new binding section
            Chili.Label:New{
                x = 15,
                bottom = 70,
                caption = Spring.I18N('ui.keybindConfig.addNewBinding'),
            },
            keyInput = Chili.EditBox:New{
                x = 15,
                bottom = 45,
                width = "40%",
                height = 25,
                text = "",
                hint = Spring.I18N('ui.keybindConfig.keyInputHint'),
                tooltip = Spring.I18N('ui.keybindConfig.keyInputTooltip'),
                OnFocus = { function(self)
                    captureKeys = true
                    self:SetText("Press a key...")
                end },
                OnFocusUpdate = { function(self)
                    if not self.focused then
                        captureKeys = false
                    end
                end },
            },
            commandInput = Chili.EditBox:New{
                x = "45%",
                bottom = 45,
                right = 85,
                height = 25,
                text = "",
                hint = Spring.I18N('ui.keybindConfig.commandInputHint'),
                tooltip = Spring.I18N('ui.keybindConfig.commandInputTooltip'),
                OnTextInput = { function(self)
                    ShowCommandSuggestions(self.text)
                end },
                OnFocusUpdate = { function(self)
                    if not self.focused and commandSuggestMenu then
                        commandSuggestMenu:Hide()
                    end
                end },
            },
            addButton = Chili.Button:New{
                caption = Spring.I18N('ui.keybindConfig.add'),
                x = -70,
                bottom = 45,
                width = 60,
                height = 25,
                OnClick = { function()
                    SaveBinding(keyInput.text, commandInput.text)
                    keyInput:SetText("")
                    commandInput:SetText("")
                end },
            },
            -- Close button
            Chili.Button:New{
                caption = Spring.I18N('ui.keybindConfig.close'),
                x = -70,
                bottom = 10,
                width = 60,
                height = 25,
                OnClick = { function() 
                    window:Dispose()
                end },
            },
        }
    }
end

function widget:Initialize()
    if not WG.Chili then
        Spring.Echo("Chili UI not present")
        widgetHandler:RemoveWidget(self)
        return
    end
    
    Chili = WG.Chili
    LoadCurrentBindings()
    CreateWindow()
    RefreshBindingsList()
end

function widget:Shutdown()
    if window then
        window:Dispose()
    end
end

function widget:KeyPress(key, mods, isRepeat, label)
    if captureKeys and not isRepeat then
        local modString = GetPressedModifiers()
        local keyName = GetKeyName(key)
        if keyName then
            keyInput:SetText(modString .. keyName)
            keyInput:Unfocus()
            return true
        end
    end
    return false
end