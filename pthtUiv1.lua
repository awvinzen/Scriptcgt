local me = nil
local startX = nil
local endX = nil
local endY = 0
local startPos = nil
local curX = 0
local curY = 0
local startY = 0
local startPosX = 0
local startPosY = 0
MAGPLANT_EMPTY = false
LastMagDialog = {x = nil, y = nil, stock = 0, isEmpty = true, active = false}
CurrentMag = nil
RUNNING = false
INITED = false
CYCLE = 0
local mags = {}
local magIndex = 0

Script.On("OnVariant", "magplant_tracker", function(v)
    if v[0] == "OnTalkBubble" then
        local text = tostring(v[2] or "")
        if text:find("MAGPLANT 5000 is empty") then
            MAGPLANT_EMPTY = true
        end
        return false
    end
    if v[0] == "OnDialogRequest" then
        local dialog = tostring(v[1] or "")
        if dialog:find("magplant_edit") then
            local mx = tonumber(dialog:match("embed_data|x|(%d+)"))
            local my = tonumber(dialog:match("embed_data|y|(%d+)"))

            -- BARU: pengkondisian dari Planting mode
            -- ACTIVE = true, DISABLED = false
            local active = false
            if dialog:find("DISABLED") then
                active = false
            elseif dialog:find("ACTIVE") then
                active = true
            end

            -- Stock: "$61600 items." atau "EMPTY!"
            local isEmpty = false
            local stock = 0
            if dialog:find("Stock:%s*`?%d?EMPTY") or dialog:find("EMPTY!") or dialog:find("currently empty") then
                isEmpty = true
                stock = 0
            else
                local stockStr = dialog:match("Stock:%s*`?%d?%$?([%d,]+)")
                    or dialog:match("contains%s*([%d,]+)")
                    or "0"
                stockStr = stockStr:gsub(",", "")
                stock = tonumber(stockStr) or 0
                if stock == 0 then isEmpty = true end
            end

            LastMagDialog = {x = mx, y = my, stock = stock, isEmpty = isEmpty, active = active}
            if stock > 0 then
                MAGPLANT_EMPTY = false
            end
        end
    end
    return false
end)

function SetStatus(t)
    Proton.Set("status", {text = "Status: " .. t})
end
function SetMag(x, y, stock)
    if x == nil then
        Proton.Set("mag", {text = "Magplant: -"})
    else
        Proton.Set("mag", {text = "Magplant: x=" .. tostring(x) .. " y=" .. tostring(y) .. " stock=" .. tostring(stock)})
    end
end
function SetCycle(c)
    Proton.Set("cycle", {text = "Cycle: " .. tostring(c)})
end
function SetTile(t)
    Proton.Set("tile", {text = "Tile: " .. t})
end

function Init()
    me = GetLocal()
    startX = 0
    endX = GetWorld().width - 1
    endY = 0
    startPos = GetLocal().pos
    curX = math.floor(startPos.x / 32)
    curY = math.floor(startPos.y / 32)
    startY = curY
    startPosX = curX
    startPosY = curY
    MAGPLANT_EMPTY = false
    LastMagDialog = {x = nil, y = nil, stock = 0, isEmpty = true, active = false}
    CurrentMag = nil
    CYCLE = 0
    magIndex = 0
    mags = ScanMagplants()
    for _, m in ipairs(mags) do
        m.dead = false
        m.remoteTaken = false
    end
    INITED = true
    SetCycle(0)
    SetMag(nil, nil, nil)
    SetTile("-")
end

function DoStart()
    if RUNNING then return end
    Init()
    RUNNING = true
    SetStatus("RUNNING")
end

function DoStop()
    if not RUNNING then return end
    RUNNING = false
    INITED = false
    SetStatus("OFF - TOGGLE ON/OFF")
end

Proton.Panel("main", {x = 60, y = 100, width = 740, height = 460})
Proton.Text("title", {parent = "main", x = 30, y = 24, text = "PROTON PTHT", fontScale = 1.8})
Proton.Text("status", {parent = "main", x = 30, y = 80, text = "Status: OFF - TOGGLE ON/OFF", fontScale = 1.4})
Proton.Text("cycle", {parent = "main", x = 30, y = 130, text = "Cycle: 0", fontScale = 1.4})
Proton.Text("mag", {parent = "main", x = 30, y = 180, text = "Magplant: -", fontScale = 1.4})
Proton.Text("tile", {parent = "main", x = 30, y = 230, text = "Tile: -", fontScale = 1.4})
Proton.Checkbox("toggle", {parent = "main", x = 30, y = 290, text = "ON / OFF", checked = false})

function GetTileFresh(x, y)
    local w = GetWorld()
    if not w then return nil end
    if x < 0 or y < 0 or x >= w.width or y >= w.height then
        return nil
    end
    local ok, tile = pcall(GetTile, x, y)
    if ok then return tile end
    return nil
end
function CacheColumn(x)
    local col = {}
    for y = endY, startY + 1, 1 do
        local t = GetTileFresh(x, y)
        if t then
            col[y] = t.fg
        else
            col[y] = nil
        end
    end
    return col
end
function Pkt(x, y, id)
    SendPacketRaw(false, {
        type = 3,
        state = 32,
        value = id,
        netid = me.netid,
        px = x,
        py = y,
        x = x * 32,
        y = y * 32
    })
end
function Path(x, y)
    SendVariantList({[0] = "OnSetPos", [1] = {[0] = x * 32, [1] = y * 32}}, GetLocal().netid)
    curX = x
    curY = y
end
function MoveTo(targetX, targetY)
    while curX ~= targetX or curY ~= targetY do
        if not RUNNING then return end
        local nextX = curX
        local nextY = curY
        if curX ~= targetX then
            local dx = targetX - curX
            local step = 2
            if math.abs(dx) < 2 then step = math.abs(dx) end
            if dx > 0 then nextX = curX + step else nextX = curX - step end
        elseif curY ~= targetY then
            local dy = targetY - curY
            local step = 2
            if math.abs(dy) < 2 then step = math.abs(dy) end
            if dy > 0 then nextY = curY + step else nextY = curY - step end
        end
        Path(nextX, nextY)
        Sleep(200)
    end
end
function GoToPlant(x, y)
    if curX ~= x or curY ~= y then MoveTo(x, y) end
    if not RUNNING then return end
    Path(x, y)
    Sleep(20)
end
function GoToHarvest(x, y)
    if curX ~= x or curY ~= y then MoveTo(x, y) end
    if not RUNNING then return end
    Path(x, y)
    Sleep(100)
    Path(x, y)
    Sleep(200)
end
function PlantColumn(x, goingUp)
    local col = CacheColumn(x)
    local yStart, yEnd, yStep
    if goingUp then yStart = startY; yEnd = endY; yStep = -1
    else yStart = endY; yEnd = startY; yStep = 1 end
    for y = yStart, yEnd, yStep do
        if not RUNNING then return false end
        if MAGPLANT_EMPTY then
            return false
        end
        local fg = col[y]
        local belowFg = col[y + 1]
        if fg ~= nil and belowFg ~= nil then
            if fg == 0 and belowFg ~= 0 and belowFg % 2 == 0 then
                SetTile("x=" .. x .. " y=" .. y .. " PLANT")
                GoToPlant(x, y)
                Pkt(x, y, 5640)
                GoToPlant(x, y)
                Pkt(x, y, 5640)
                col[y] = 5640
                if MAGPLANT_EMPTY then
                    return false
                end
            end
        end
    end
    return true
end
function FindLeftEmptyColumn()
    for x = startX, endX, 1 do
        local col = CacheColumn(x)
        for y = endY, startY, 1 do
            local fg = col[y]
            local belowFg = col[y + 1]
            if fg ~= nil and belowFg ~= nil then
                if fg == 0 and belowFg ~= 0 and belowFg % 2 == 0 then
                    return x
                end
            end
        end
    end
    return startX
end
function IsAllFull()
    for x = startX, endX, 1 do
        local col = CacheColumn(x)
        for y = endY, startY, 1 do
            local fg = col[y]
            local belowFg = col[y + 1]
            if fg ~= nil and belowFg ~= nil then
                if fg == 0 and belowFg ~= 0 and belowFg % 2 == 0 then
                    return false
                end
            end
        end
    end
    return true
end
function Has16707()
    for x = startX, startX + 9, 1 do
        local col = CacheColumn(x)
        for y = endY, startY, 1 do
            if col[y] == 16707 then
                return true, x, y
            end
        end
    end
    return false, nil, nil
end
function HarvestPass()
    for y = startY, endY, -1 do
        if not RUNNING then return end
        local foundX = nil
        for x = startX, startX + 9, 1 do
            if GetTileFresh(x, y) then
                if GetTileFresh(x, y).fg == 16707 then
                    foundX = x
                    break
                end
            end
        end
        if foundX then
            SetTile("x=" .. foundX .. " y=" .. y .. " HARVEST")
            GoToHarvest(foundX, y)
            Pkt(foundX, y, 18)
        end
    end
end
function ScanMagplants()
    local result = {}
    local worldH = GetWorld().height - 1
    for y = endY, worldH, 1 do
        for x = startX, endX, 1 do
            local tile = GetTileFresh(x, y)
            if tile and tile.fg == 5638 and tile.bg == 12840 then
                table.insert(result, {x = x, y = y, fg = 5638, bg = 12840, checkedEmpty = false, dead = false, remoteTaken = false})
            end
        end
    end
    return result
end
function MarkDead(mag)
    mag.dead = true
    mag.remoteTaken = true
end
function TakeNextRemote()
    if #mags == 0 then
        return nil
    end
    local aliveCount = 0
    for _, m in ipairs(mags) do
        if not m.dead then aliveCount = aliveCount + 1 end
    end
    if aliveCount == 0 then
        return nil
    end
    for attempt = 1, #mags do
        if not RUNNING then return nil end
        magIndex = magIndex + 1
        if magIndex > #mags then magIndex = 1 end
        local mag = mags[magIndex]
        if mag.dead or mag.remoteTaken then
        else
            SetStatus("CHECKING MAGPLANT x=" .. mag.x .. " y=" .. mag.y)
            SetMag(mag.x, mag.y, "?")
            LastMagDialog = {x = nil, y = nil, stock = 0, isEmpty = true, active = false}
            Pkt(mag.x, mag.y, 32)
            Sleep(800)
            if LastMagDialog.x == nil then
                SendPacket(2, "action|dialog_return\ndialog_name|magplant_edit\nx|"..mag.x.."\ny|"..mag.y.."\nbuttonClicked|getRemote")
                Sleep(500)
                if MAGPLANT_EMPTY then
                    MAGPLANT_EMPTY = false
                    MarkDead(mag)
                    SetMag(mag.x, mag.y, "EMPTY")
                else
                    MAGPLANT_EMPTY = false
                    mag.remoteTaken = true
                    CurrentMag = mag
                    SetMag(mag.x, mag.y, "REMOTE")
                    return mag
                end
            elseif LastMagDialog.x ~= mag.x or LastMagDialog.y ~= mag.y then
                SetMag(mag.x, mag.y, "SKIP")
            -- BARU: patokan utama ACTIVE / DISABLED
            elseif LastMagDialog.active == false then
                MarkDead(mag)
                SetMag(mag.x, mag.y, "DISABLED")
            elseif LastMagDialog.isEmpty or LastMagDialog.stock == 0 then
                MarkDead(mag)
                SetMag(mag.x, mag.y, "EMPTY")
            else
                -- active == true, baru ambil remote
                SendPacket(2, "action|dialog_return\ndialog_name|magplant_edit\nx|"..mag.x.."\ny|"..mag.y.."\nbuttonClicked|getRemote")
                Sleep(500)
                MAGPLANT_EMPTY = false
                mag.remoteTaken = true
                CurrentMag = mag
                SetMag(mag.x, mag.y, LastMagDialog.stock)
                return mag
            end
        end
    end
    return nil
end
function DoPass2()
    local leftEmptyX = FindLeftEmptyColumn()
    local colIndex = 0
    for _, offset in ipairs({0, 1}) do
        for x = leftEmptyX + offset, endX, 2 do
            local col = CacheColumn(x)
            local goingUp = (colIndex % 2 == 0)
            colIndex = colIndex + 1
            local yStart, yEnd, yStep
            if goingUp then yStart = startY; yEnd = endY; yStep = -1
            else yStart = endY; yEnd = startY; yStep = 1 end
            for y = yStart, yEnd, yStep do
                if not RUNNING then return false end
                if MAGPLANT_EMPTY then return false end
                local fg = col[y]
                local belowFg = col[y + 1]
                if fg ~= nil and belowFg ~= nil then
                    if fg == 0 and belowFg ~= 0 and belowFg % 2 == 0 then
                        SetTile("x=" .. x .. " y=" .. y .. " PLANT")
                        GoToPlant(x, y)
                        Pkt(x, y, 5640)
                        GoToPlant(x, y)
                        Pkt(x, y, 5640)
                        col[y] = 5640
                        if MAGPLANT_EMPTY then return false end
                    end
                end
            end
        end
    end
    return true
end

function PollToggle()
    local ok, t = pcall(Proton.Get, "toggle")
    if ok and t ~= nil and t.checked ~= nil then
        if t.checked == true and not RUNNING then
            DoStart()
        elseif t.checked == false and RUNNING then
            DoStop()
        end
    end
end

while true do
    PollToggle()
    if not RUNNING or not INITED then
        Sleep(300)
    else
        CYCLE = CYCLE + 1
        SetCycle(CYCLE)
        SetStatus("CYCLE " .. CYCLE .. " PLANT")
        while true do
            PollToggle()
            if not RUNNING then break end
            local mag = TakeNextRemote()
            if not mag then
                SetStatus("MAGPLANT EMPTY / OUT")
                break
            end
            local pass1Ok = true
            local colIndex = 0
            for x = startX, endX, 10 do
                PollToggle()
                if not RUNNING then break end
                local goingUp = (colIndex % 2 == 0)
                colIndex = colIndex + 1
                if not PlantColumn(x, goingUp) then
                    pass1Ok = false
                    break
                end
            end
            if not pass1Ok then
                SetStatus("MAGPLANT EMPTY - SWITCHING")
            else
                if not RUNNING then break end
                local pass2Ok = DoPass2()
                if not pass2Ok then
                    SetStatus("MAGPLANT EMPTY - SWITCHING")
                end
            end
            if not RUNNING then break end
            if not MAGPLANT_EMPTY then
                break
            end
            Sleep(500)
        end
        if RUNNING then
            SetStatus("CHECKING FULL")
            if IsAllFull() then
                SetStatus("SPRAY + HARVEST")
                SendPacket(2, "action|dialog_return\ndialog_name|ultraworldspray")
                Sleep(500)
                Path(curX, curY)
                Sleep(20)
                HarvestPass()
                local attempt = 1
                while true do
                    PollToggle()
                    if not RUNNING then break end
                    Sleep(500)
                    local stillThere, hx, hy = Has16707()
                    if not stillThere then
                        break
                    end
                    HarvestPass()
                    attempt = attempt + 1
                    if attempt > 5 then
                        break
                    end
                end
                Path(curX, curY)
                Sleep(20)
                SetStatus("BACK TO START")
                MoveTo(startPosX, startPosY)
                Path(startPosX, startPosY)
                Sleep(20)
                for _, m in ipairs(mags) do
                    m.dead = false
                    m.remoteTaken = false
                end
            else
                SetStatus("NOT FULL / MAGPLANT EMPTY")
                Sleep(10000)
                mags = ScanMagplants()
                for _, m in ipairs(mags) do
                    m.dead = false
                    m.remoteTaken = false
                end
                magIndex = 0
            end
        end
        Sleep(1000)
    end
end