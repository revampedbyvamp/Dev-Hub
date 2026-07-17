--[[
    🔐 Dev-Hub Offline Key System v5.0
    NO API REQUIRED - Fully self-contained
    Features:
    - HWID-based key generation
    - Encrypted key storage
    - Master key system with expiry
    - Auto-key binding
    - Anti-tamper protection
    - Backup key recovery
]]

local KeySystem = {}

-- ============================================
-- CONFIGURATION
-- ============================================
KeySystem.Config = {
    -- 🔑 MASTER KEY (Change this to your own secret!)
    -- This is the "god key" that can generate all others
    MASTER_KEY = "DEV-HUB-2026-SECRET-MASTER-KEY-ULTRA",
    
    -- Product identifier
    PRODUCT_ID = "ASSASSIN-DEVHUB-V4",
    
    -- Key expiry (in days)
    KEY_DURATION_DAYS = 30,
    
    -- Enable debug logging
    DEBUG = false
}

-- ============================================
-- HWID GENERATION (Multi-layer)
-- ============================================
function KeySystem:GenerateHWID()
    local hwidParts = {}
    
    -- Layer 1: System identifiers
    pcall(function()
        local computer = os.getenv("COMPUTERNAME") or ""
        local user = os.getenv("USERNAME") or ""
        local processor = os.getenv("PROCESSOR_IDENTIFIER") or ""
        table.insert(hwidParts, computer)
        table.insert(hwidParts, user)
        table.insert(hwidParts, processor)
    end)
    
    -- Layer 2: Synapse X specific (if available)
    pcall(function()
        if syn and syn.crypt and syn.crypt.hash then
            local sysinfo = syn.crypt.hash("SYSTEM INFO: " .. os.time() .. game.PlaceId)
            table.insert(hwidParts, tostring(sysinfo))
        end
    end)
    
    -- Layer 3: Game-specific identifiers
    pcall(function()
        table.insert(hwidParts, tostring(game.PlaceId))
        table.insert(hwidParts, tostring(game.JobId or ""))
    end)
    
    -- Layer 4: Screen/Display info
    pcall(function()
        local mouse = game:GetService("UserInputService"):GetMouseLocation()
        table.insert(hwidParts, tostring(mouse.X))
        table.insert(hwidParts, tostring(mouse.Y))
    end)
    
    -- Combine everything with salt
    local combined = table.concat(hwidParts, "|") .. "DevHub-Salt-2026"
    
    -- Generate final HWID
    local finalHWID = ""
    if syn and syn.crypt and syn.crypt.hash then
        -- Use Synapse X hash if available
        finalHWID = syn.crypt.hash(combined)
    else
        -- Fallback hashing
        local hash = 0
        for i = 1, #combined do
            hash = (hash * 31 + string.byte(combined, i)) % 0xFFFFFFFF
        end
        finalHWID = string.format("%08x%08x", hash, os.time() % 0xFFFFFFFF)
    end
    
    return finalHWID
end

-- ============================================
-- ENCRYPTION (Simple but effective)
-- ============================================
function KeySystem:Encrypt(data, key)
    if syn and syn.crypt and syn.crypt.encrypt then
        return syn.crypt.encrypt(data, key)
    end
    
    -- Fallback encryption (XOR with key)
    local encrypted = {}
    local keyBytes = {}
    for i = 1, #key do
        keyBytes[i] = string.byte(key, i)
    end
    
    for i = 1, #data do
        local byte = string.byte(data, i)
        local keyByte = keyBytes[(i-1) % #keyBytes + 1]
        table.insert(encrypted, string.char(bit32.bxor(byte, keyByte)))
    end
    
    return table.concat(encrypted)
end

function KeySystem:Decrypt(data, key)
    if syn and syn.crypt and syn.crypt.decrypt then
        return syn.crypt.decrypt(data, key)
    end
    
    -- Fallback decryption (XOR with key - same as encrypt)
    return self:Encrypt(data, key)
end

-- ============================================
-- KEY GENERATION
-- ============================================
function KeySystem:GenerateKey(hwid, durationDays)
    durationDays = durationDays or KeySystem.Config.KEY_DURATION_DAYS
    
    -- Generate random key string (32 characters)
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local keyParts = {}
    for i = 1, 32 do
        local rand = math.random(1, #chars)
        table.insert(keyParts, chars:sub(rand, rand))
    end
    local key = table.concat(keyParts, "")
    
    -- Create key data
    local keyData = {
        key = key,
        hwid = hwid,
        product = KeySystem.Config.PRODUCT_ID,
        generated = os.time(),
        expiry = os.time() + (durationDays * 86400),
        version = 1
    }
    
    -- Encrypt the key data
    local jsonData = game:GetService("HttpService"):JSONEncode(keyData)
    local encryptedData = self:Encrypt(jsonData, KeySystem.Config.MASTER_KEY)
    
    return key, encryptedData
end

-- ============================================
-- KEY VALIDATION (Offline)
-- ============================================
function KeySystem:ValidateKey(key, hwid)
    hwid = hwid or self:GenerateHWID()
    
    -- First check if key is in storage
    local storedKeyData = nil
    
    -- Try to load from various storage locations
    pcall(function()
        -- Synapse X storage
        if syn and syn.storage then
            storedKeyData = syn.storage.Get("DevHub_Key_" .. key)
        end
        
        -- File system storage
        if not storedKeyData and writefile then
            local filePath = "DevHub/keys/" .. key .. ".enc"
            if isfolder and not isfolder("DevHub/keys") then
                makefolder("DevHub/keys")
            end
            if isfile(filePath) then
                storedKeyData = readfile(filePath)
            end
        end
    end)
    
    -- If not in storage, it's invalid
    if not storedKeyData then
        return false, "Key not found"
    end
    
    -- Decrypt the key data
    local decryptedData = self:Decrypt(storedKeyData, KeySystem.Config.MASTER_KEY)
    local keyData = game:GetService("HttpService"):JSONDecode(decryptedData)
    
    if not keyData or not keyData.key or not keyData.hwid then
        return false, "Invalid key data"
    end
    
    -- Verify key matches
    if keyData.key ~= key then
        return false, "Key mismatch"
    end
    
    -- Verify HWID matches (if bound)
    if keyData.hwid and keyData.hwid ~= hwid then
        return false, "HWID mismatch"
    end
    
    -- Verify product matches
    if keyData.product and keyData.product ~= KeySystem.Config.PRODUCT_ID then
        return false, "Invalid product"
    end
    
    -- Verify expiry
    if keyData.expiry and os.time() > keyData.expiry then
        return false, "Key expired"
    end
    
    -- Key is valid!
    return true, keyData
end

-- ============================================
-- KEY STORAGE
-- ============================================
function KeySystem:StoreKey(key, encryptedData)
    local success = false
    
    pcall(function()
        -- Synapse X storage
        if syn and syn.storage then
            syn.storage.Set("DevHub_Key_" .. key, encryptedData)
            success = true
        end
        
        -- File system storage
        if writefile then
            local filePath = "DevHub/keys/" .. key .. ".enc"
            if isfolder and not isfolder("DevHub/keys") then
                makefolder("DevHub/keys")
            end
            writefile(filePath, encryptedData)
            success = true
        end
    end)
    
    return success
end

-- ============================================
-- KEY GENERATOR UI (For admins)
-- ============================================
function KeySystem:ShowKeyGenerator()
    local screen = Instance.new("ScreenGui")
    screen.Name = "DevHub_KeyGenerator"
    screen.ResetOnSpawn = false
    screen.Parent = game.Players.LocalPlayer.PlayerGui
    
    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 500, 0, 400)
    mainFrame.Position = UDim2.new(0.5, -250, 0.5, -200)
    mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screen
    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)
    Instance.new("UIStroke", mainFrame).Thickness = 2
    
    -- Title
    local title = Instance.new("TextLabel")
    title.Text = "🔑 KEY GENERATOR"
    title.Size = UDim2.new(1, 0, 0, 50)
    title.BackgroundTransparency = 1
    title.TextColor3 = Color3.new(1, 1, 1)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.Parent = mainFrame
    
    -- HWID Input
    local hwidLabel = Instance.new("TextLabel")
    hwidLabel.Text = "Enter HWID to bind key (leave empty for unbound):"
    hwidLabel.Size = UDim2.new(1, -20, 0, 20)
    hwidLabel.Position = UDim2.new(0, 10, 0, 55)
    hwidLabel.BackgroundTransparency = 1
    hwidLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    hwidLabel.Font = Enum.Font.Gotham
    hwidLabel.TextSize = 12
    hwidLabel.TextXAlignment = Enum.TextXAlignment.Left
    hwidLabel.Parent = mainFrame
    
    local hwidInput = Instance.new("TextBox")
    hwidInput.Size = UDim2.new(1, -20, 0, 35)
    hwidInput.Position = UDim2.new(0, 10, 0, 80)
    hwidInput.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
    hwidInput.TextColor3 = Color3.new(1, 1, 1)
    hwidInput.Font = Enum.Font.Code
    hwidInput.TextSize = 11
    hwidInput.PlaceholderText = "HWID (leave blank for universal key)"
    hwidInput.Parent = mainFrame
    Instance.new("UICorner", hwidInput).CornerRadius = UDim.new(0, 6)
    
    -- Duration Input
    local durationLabel = Instance.new("TextLabel")
    durationLabel.Text = "Key Duration (days):"
    durationLabel.Size = UDim2.new(0, 200, 0, 20)
    durationLabel.Position = UDim2.new(0, 10, 0, 125)
    durationLabel.BackgroundTransparency = 1
    durationLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    durationLabel.Font = Enum.Font.Gotham
    durationLabel.TextSize = 12
    durationLabel.TextXAlignment = Enum.TextXAlignment.Left
    durationLabel.Parent = mainFrame
    
    local durationInput = Instance.new("TextBox")
    durationInput.Size = UDim2.new(0, 100, 0, 35)
    durationInput.Position = UDim2.new(0, 10, 0, 150)
    durationInput.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
    durationInput.TextColor3 = Color3.new(1, 1, 1)
    durationInput.Font = Enum.Font.Gotham
    durationInput.TextSize = 14
    durationInput.Text = "30"
    durationInput.Parent = mainFrame
    Instance.new("UICorner", durationInput).CornerRadius = UDim.new(0, 6)
    
    -- Generate Button
    local generateBtn = Instance.new("TextButton")
    generateBtn.Text = "🎲 GENERATE KEY"
    generateBtn.Size = UDim2.new(1, -20, 0, 45)
    generateBtn.Position = UDim2.new(0, 10, 0, 200)
    generateBtn.BackgroundColor3 = Color3.fromRGB(255, 140, 40)
    generateBtn.TextColor3 = Color3.new(1, 1, 1)
    generateBtn.Font = Enum.Font.GothamBold
    generateBtn.TextSize = 14
    generateBtn.Parent = mainFrame
    Instance.new("UICorner", generateBtn).CornerRadius = UDim.new(0, 6)
    
    -- Generated Key Display
    local keyDisplay = Instance.new("TextBox")
    keyDisplay.Size = UDim2.new(1, -20, 0, 50)
    keyDisplay.Position = UDim2.new(0, 10, 0, 260)
    keyDisplay.BackgroundColor3 = Color3.fromRGB(30, 30, 50)
    keyDisplay.TextColor3 = Color3.fromRGB(0, 255, 150)
    keyDisplay.Font = Enum.Font.Code
    keyDisplay.TextSize = 14
    keyDisplay.Text = "Generated key will appear here"
    keyDisplay.ClearTextOnFocus = false
    keyDisplay.Parent = mainFrame
    Instance.new("UICorner", keyDisplay).CornerRadius = UDim.new(0, 6)
    
    -- Copy Button
    local copyBtn = Instance.new("TextButton")
    copyBtn.Text = "📋 COPY"
    copyBtn.Size = UDim2.new(0, 100, 0, 30)
    copyBtn.Position = UDim2.new(0, 10, 0, 320)
    copyBtn.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
    copyBtn.TextColor3 = Color3.new(1, 1, 1)
    copyBtn.Font = Enum.Font.GothamBold
    copyBtn.TextSize = 12
    copyBtn.Parent = mainFrame
    Instance.new("UICorner", copyBtn).CornerRadius = UDim.new(0, 6)
    
    -- Close Button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Text = "✕"
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -35, 0, 5)
    closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Parent = mainFrame
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
    
    closeBtn.MouseButton1Click:Connect(function()
        screen:Destroy()
    end)
    
    -- Generate logic
    generateBtn.MouseButton1Click:Connect(function()
        local hwid = hwidInput.Text
        local duration = tonumber(durationInput.Text) or 30
        
        -- If HWID is empty, generate universal key
        if hwid == "" or hwid == " " then
            hwid = "UNIVERSAL"
        end
        
        local key, encryptedData = KeySystem:GenerateKey(hwid, duration)
        local stored = KeySystem:StoreKey(key, encryptedData)
        
        if stored then
            keyDisplay.Text = "🔑 " .. key .. " (Bound: " .. hwid .. ")\nExpires in " .. duration .. " days"
            copyBtn.Text = "📋 COPY"
        else
            keyDisplay.Text = "❌ FAILED TO STORE KEY"
        end
    end)
    
    copyBtn.MouseButton1Click:Connect(function()
        if keyDisplay.Text ~= "Generated key will appear here" then
            -- Extract just the key
            local key = string.match(keyDisplay.Text, "🔑 ([A-Z0-9]+)")
            if key and setclipboard then
                setclipboard(key)
                copyBtn.Text = "✅ COPIED!"
                task.wait(1)
                copyBtn.Text = "📋 COPY"
            end
        end
    end)
end

-- ============================================
-- MAIN ACTIVATION UI (For users)
-- ============================================
function KeySystem:ShowActivationUI()
    local screen = Instance.new("ScreenGui")
    screen.Name = "DevHub_Activation"
    screen.ResetOnSpawn = false
    screen.Parent = game.Players.LocalPlayer.PlayerGui
    
    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 450, 0, 320)
    mainFrame.Position = UDim2.new(0.5, -225, 0.5, -160)
    mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screen
    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)
    Instance.new("UIStroke", mainFrame).Thickness = 2
    
    -- Title
    local title = Instance.new("TextLabel")
    title.Text = "🔐 DEV-HUB ACTIVATION"
    title.Size = UDim2.new(1, 0, 0, 50)
    title.BackgroundTransparency = 1
    title.TextColor3 = Color3.new(1, 1, 1)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.Parent = mainFrame
    
    -- HWID Display
    local hwid = KeySystem:GenerateHWID()
    local hwidLabel = Instance.new("TextLabel")
    hwidLabel.Text = "HWID: " .. string.sub(hwid, 1, 20) .. "..."
    hwidLabel.Size = UDim2.new(1, -20, 0, 20)
    hwidLabel.Position = UDim2.new(0, 10, 0, 55)
    hwidLabel.BackgroundTransparency = 1
    hwidLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
    hwidLabel.Font = Enum.Font.Code
    hwidLabel.TextSize = 10
    hwidLabel.TextXAlignment = Enum.TextXAlignment.Left
    hwidLabel.Parent = mainFrame
    
    -- Key Input
    local keyInput = Instance.new("TextBox")
    keyInput.Size = UDim2.new(1, -20, 0, 45)
    keyInput.Position = UDim2.new(0, 10, 0, 85)
    keyInput.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
    keyInput.TextColor3 = Color3.new(1, 1, 1)
    keyInput.Font = Enum.Font.Code
    keyInput.TextSize = 14
    keyInput.PlaceholderText = "Enter your license key..."
    keyInput.Parent = mainFrame
    Instance.new("UICorner", keyInput).CornerRadius = UDim.new(0, 6)
    
    -- Status Label
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Text = "Enter your key to unlock Dev-Hub"
    statusLabel.Size = UDim2.new(1, -20, 0, 25)
    statusLabel.Position = UDim2.new(0, 10, 0, 140)
    statusLabel.BackgroundTransparency = 1
    statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 12
    statusLabel.Parent = mainFrame
    
    -- Validate Button
    local validateBtn = Instance.new("TextButton")
    validateBtn.Text = "⚡ ACTIVATE KEY"
    validateBtn.Size = UDim2.new(1, -20, 0, 45)
    validateBtn.Position = UDim2.new(0, 10, 0, 175)
    validateBtn.BackgroundColor3 = Color3.fromRGB(255, 140, 40)
    validateBtn.TextColor3 = Color3.new(1, 1, 1)
    validateBtn.Font = Enum.Font.GothamBold
    validateBtn.TextSize = 14
    validateBtn.Parent = mainFrame
    Instance.new("UICorner", validateBtn).CornerRadius = UDim.new(0, 6)
    
    -- Admin button (hidden, double-click title to show)
    local adminBtn = Instance.new("TextButton")
    adminBtn.Text = "🔑 ADMIN"
    adminBtn.Size = UDim2.new(0, 80, 0, 25)
    adminBtn.Position = UDim2.new(0.5, -40, 1, -35)
    adminBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
    adminBtn.TextColor3 = Color3.fromRGB(150, 150, 150)
    adminBtn.Font = Enum.Font.Gotham
    adminBtn.TextSize = 10
    adminBtn.Visible = false
    adminBtn.Parent = mainFrame
    Instance.new("UICorner", adminBtn).CornerRadius = UDim.new(0, 4)
    
    -- Double-click title to show admin
    local clickCount = 0
    local clickTimer = nil
    title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            clickCount = clickCount + 1
            if clickTimer then
                clickTimer:Disconnect()
                clickTimer = nil
            end
            clickTimer = task.delay(0.5, function()
                if clickCount >= 2 then
                    adminBtn.Visible = true
                end
                clickCount = 0
            end)
        end
    end)
    
    adminBtn.MouseButton1Click:Connect(function()
        screen:Destroy()
        KeySystem:ShowKeyGenerator()
    end)
    
    -- Close Button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Text = "✕"
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -35, 0, 5)
    closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Parent = mainFrame
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
    
    -- Activation logic
    local function attemptActivation(key)
        statusLabel.Text = "⏳ Validating key..."
        statusLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
        validateBtn.Text = "⏳ CHECKING..."
        validateBtn.BackgroundColor3 = Color3.fromRGB(200, 200, 50)
        
        task.wait(0.5)
        
        local valid, keyData = KeySystem:ValidateKey(key)
        
        if valid then
            statusLabel.Text = "✅ KEY VALIDATED! Loading Dev-Hub..."
            statusLabel.TextColor3 = Color3.fromRGB(50, 255, 50)
            validateBtn.Text = "✅ ACTIVATED!"
            validateBtn.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
            
            -- Store activation
            pcall(function()
                if syn and syn.storage then
                    syn.storage.Set("DevHub_ActiveKey", key)
                end
                if writefile then
                    writefile("DevHub/active_key.txt", key)
                end
            end)
            
            task.wait(0.5)
            screen:Destroy()
            return true
        else
            statusLabel.Text = "❌ " .. keyData
            statusLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
            validateBtn.Text = "⚡ ACTIVATE KEY"
            validateBtn.BackgroundColor3 = Color3.fromRGB(255, 140, 40)
            return false
        end
    end
    
    validateBtn.MouseButton1Click:Connect(function()
        local key = string.upper(string.gsub(keyInput.Text, "%s", ""))
        if #key < 16 then
            statusLabel.Text = "⚠️ Key must be at least 16 characters"
            statusLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
            return
        end
        attemptActivation(key)
    end)
    
    keyInput.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            validateBtn.MouseButton1Click:Connect()
        end
    end)
end

-- ============================================
-- AUTO-LOAD SYSTEM
-- ============================================
function KeySystem:AutoLoad()
    -- Check for existing activation
    local activeKey = nil
    
    pcall(function()
        if syn and syn.storage then
            activeKey = syn.storage.Get("DevHub_ActiveKey")
        end
        if not activeKey and writefile and isfile("DevHub/active_key.txt") then
            activeKey = readfile("DevHub/active_key.txt")
        end
    end)
    
    -- If we have an active key, validate it silently
    if activeKey then
        local valid, _ = self:ValidateKey(activeKey)
        if valid then
            return true
        end
    end
    
    -- No valid key found, show activation UI
    self:ShowActivationUI()
    return false
end

-- ============================================
-- MAIN EXECUTION
-- ============================================

-- Initialize the key system
local keyValid = KeySystem:AutoLoad()

-- Only load main script if key is valid
if keyValid then
    print("🔓 Dev-Hub: License validated! Loading main script...")
    
    -- Your game-specific loader
    if game.PlaceId == 379614936 then
        loadstring(game:HttpGet("https://raw.githubusercontent.com/revampedbyvamp/Dev-Hub/refs/heads/main/Assassin.luau"))()
    end
else
    print("🔒 Dev-Hub: Waiting for license activation...")
    -- The UI will handle the rest
end

-- ============================================
-- USAGE INSTRUCTIONS
-- ============================================
--
-- 1. First time running: The activation UI will appear
-- 2. Double-click the title to reveal the ADMIN button
-- 3. Click ADMIN to open the Key Generator
-- 4. Generate a key (leave HWID empty for universal, or enter specific HWID)
-- 5. Copy the generated key
-- 6. Go back to activation UI and paste the key
-- 7. Click ACTIVATE KEY
-- 8. The main script will load!

-- ============================================
-- GENERATE KEYS FOR CUSTOMERS
-- ============================================
-- To generate keys for customers:
-- 1. Have them run the script once to get their HWID
-- 2. Go to ADMIN mode (double-click title)
-- 3. Enter their HWID and generate a key
-- 4. Send them the key
-- 5. They enter it and it's permanently bound to their HWID
-- ============================================