local widget = widget ---@type Widget

function widget:GetInfo()
    return {
        name = "Keybind Custom Config",
        desc = "A basic GUI for custom keybind configuration",
        author = "YourName",
        date = "September 2025",
        license = "GNU GPL, v2 or later",
        layer = 0,
        enabled = false,
    }
end

local vsx, vsy = Spring.GetViewGeometry()
local windowWidth, windowHeight = 400, 300
local windowX, windowY = (vsx - windowWidth) / 2, (vsy - windowHeight) / 2
local closeButton = {x = windowX + windowWidth - 50, y = windowY + 10, width = 40, height = 20}

local function DrawWindow()
    -- Draw the window background
    gl.Color(0, 0, 0, 0.8)
    gl.Rect(windowX, windowY, windowX + windowWidth, windowY + windowHeight)

    -- Draw the window title
    gl.Color(1, 1, 1, 1)
    gl.Text("Keybind Custom Config", windowX + 20, windowY + windowHeight - 30, 16, "n")

    -- Draw the close button
    gl.Color(0.8, 0.2, 0.2, 1)
    gl.Rect(closeButton.x, closeButton.y, closeButton.x + closeButton.width, closeButton.y + closeButton.height)
    gl.Color(1, 1, 1, 1)
    gl.Text("Close", closeButton.x + 5, closeButton.y + 5, 12, "n")
end

function widget:DrawScreen()
    DrawWindow()
end

function widget:MousePress(x, y, button)
    if button == 1 then
        -- Check if the close button is clicked
        if x >= closeButton.x and x <= closeButton.x + closeButton.width and
           y >= closeButton.y and y <= closeButton.y + closeButton.height then
            widgetHandler:RemoveWidget(self)
            return true
        end
    end
    return false
end