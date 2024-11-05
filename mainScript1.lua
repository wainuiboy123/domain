local Window = Rayfield:CreateWindow({
        Name = "Domain",
        LoadingTitle = "Domain Script Hub",
        LoadingSubtitle = "by rinsin.",
        ConfigurationSaving = {
           Enabled = true,
           FolderName = nil, -- Create a custom folder for your hub/game
           FileName = "Domain Hub"
        },
        Discord = {
           Enabled = true,
           Invite = "wCQqsdYBCJ", -- The Discord invite code, do not include discord.gg/. E.g. discord.gg/ABCD would be ABCD
           RememberJoins = false -- Set this to false to make them join the discord every time they load it up
        },
        KeySystem = true, -- Set this to true to use our key system
        KeySettings = {
           Title = "Domain",
           Subtitle = "Key System",
           Note = "Join our discord for free weekly keys!",
           FileName = "domain_start_key", -- It is recommended to use something unique as other scripts using Rayfield may overwrite your key file
           SaveKey = false, -- The user's key will be saved, but if you change the key, they will be unable to use your script
           GrabKeyFromSite = false, -- If this is true, set Key below to the RAW site you would like Rayfield to get the key from
           Key = {"indev", "congrats if you managed to guess this key ig","iWantFreePremium"} -- List of keys that will be accepted by the system, can be RAW file links (pastebin, github etc) or simple strings ("hello","key22")
        }
     })
    
    local HomeTab = Window:CreateTab("Home", 4483362458) -- Title, Image
    local Paragraph = HomeTab:CreateParagraph({Title = "About Domain", Content = "This is Domain, we're a script that is determinded to make scripts for all of your favourite games without being detected by Roblox and Game Creators."})
    local ore_tree_finder = "it broke"
    local glacier_tree_finder = "it broke"
    
    local GLabel = HomeTab:CreateLabel("Glacier: ")
    local GButton = HomeTab:CreateButton({
        Name = "Teleport to Glacier",
        Callback = function()
                game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = game.Workspace.WorldSpawn.Trees:FindFirstChild("Glacier").CFrame
        end,
     })
    local OLabel = HomeTab:CreateLabel("Orewood: ")
    local OButton = HomeTab:CreateButton({
        Name = "Teleport to Orewood",
        Callback = function()
            game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = game.Workspace.WorldSpawn.Trees:FindFirstChild("OreTree").CFrame
        end,
     })
     if game.Workspace.WorldSpawn.Trees:FindFirstChild("Glacier") then
        GLabel:Set("Glacier: Found")
        GButton.Visible = true
        else
            GLabel:Set("Glacier: Not Found")
        GButton.Visible = false
        end
    
        if game.Workspace.WorldSpawn.Trees:FindFirstChild("OreTree") then
           OLabel:Set("Oretree: Found")
           OButton.Visible = true
        else
            OLabel:Set("Oretree: Not Found")
           OButton.Visible = false
        end
    
    
     local RefLabel = HomeTab:CreateLabel("Rare Wood Finder")
    
     local refresh_rare_wood_button = HomeTab:CreateButton({
         Name = "Press to refresh",
         Callback = function()
             RefLabel:Set("Refreshing.")
             wait(1)
             RefLabel:Set("Refreshing..")
             wait(1)
             RefLabel:Set("Refreshing...")
             wait(.5)
             if game.Workspace.WorldSpawn.Trees:FindFirstChild("Glacier") then
                GLabel:Set("Glacier: Found")
                GButton.Visible = true
                else
                    GLabel:Set("Glacier: Not Found")
                GButton.Visible = false
                end
    
             if game.Workspace.WorldSpawn.Trees:FindFirstChild("OreTree") then
                OLabel:Set("Oretree: Found")
                OButton.Visible = true
             else
                 OLabel:Set("Oretree: Not Found")
                OButton.Visible = false
             end
             RefLabel:Set("Refreshed!")
             wait(3)
             RefLabel:Set("Rare Wood Finder")
         end,
      })
    
    local ItemTab = Window:CreateTab("Item", 4483362458)
    local select_item = ItemTab:CreateLabel("error code 100", 4483362458)
    
    
    local TeleportTab = Window:CreateTab("Teleports", 4483362458)
    local Button = TeleportTab:CreateButton({
       Name = "Spawn",
       Callback = function()
            game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(1894.87415, 3.16217184, -221.322571, 0.544688165, 5.3039928e-09, 0.838638663, -2.40275e-09, 1, -4.76396256e-09, -0.838638663, 5.79834958e-10, 0.544688165)
       end,
    })
    local Button = TeleportTab:CreateButton({
       Name = "UCS",
       Callback = function()
            game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(1932.45105, 3.2811749, -180.08017, -0.559249282, -6.27776231e-08, -0.828999579, 5.76886094e-09, 1, -7.96186796e-08, 0.828999579, -4.93090724e-08, -0.559249282)
       end,
    })
    local Button = TeleportTab:CreateButton({
       Name = "Land Agency",
       Callback = function()
            game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(1854.95312, 3.28119349, -83.8844604, -0.870373487, 2.58139945e-08, -0.492392093, 7.85782106e-10, 1, 5.10367073e-08, 0.492392093, 4.40340848e-08, -0.870373487)
       end,
    })
    local Button = TeleportTab:CreateButton({
       Name = "Sell Zone",
       Callback = function()
            game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(1432.44348, 3.16216636, 161.156815, 0.489058405, -8.69805135e-08, 0.872251034, 2.81000485e-08, 1, 8.39643022e-08, -0.872251034, -1.655315e-08, 0.489058405)
       end,
    })
    local Button = TeleportTab:CreateButton({
       Name = "Marble Valley",
       Callback = function()
            game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(501.825623, 104.16188, 1389.01233, -0.642857552, 1.05355982e-08, -0.765985787, -2.97316749e-09, 1, 1.62495457e-08, 0.765985787, 1.27235467e-08, -0.642857552)
       end,
    })
    local Button = TeleportTab:CreateButton({
       Name = "Nova Dock",
       Callback = function()
            game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(2227.29175, 3.27575135, -809.046204, 0.655975401, 2.76054788e-08, -0.754782319, -9.54838768e-08, 1, -4.64101966e-08, 0.754782319, 1.02513489e-07, 0.655975401)
       end,
    })
    
    
    local EspTab = Window:CreateTab("ESP", 4483362458)
    local Section = EspTab:CreateSection("Rocks")
    local Toggle = EspTab:CreateToggle({
        Name = "Sandstone",
        CurrentValue = false,
        Flag = "rock_Sandstone_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Clay",
        CurrentValue = false,
        Flag = "rock_Clay_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Sand",
        CurrentValue = false,
        Flag = "rock_Sand_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Stone",
        CurrentValue = false,
        Flag = "rock_Stone_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Salt",
        CurrentValue = false,
        Flag = "rock_Salt_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Cloudnite",
        CurrentValue = false,
        Flag = "rock_Cloudnite_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Section = EspTab:CreateSection("Ores")
     local Toggle = EspTab:CreateToggle({
        Name = "Granite",
        CurrentValue = false,
        Flag = "ore_Granite_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Marble",
        CurrentValue = false,
        Flag = "ore_Marble_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Coal",
        CurrentValue = false,
        Flag = "ore_Coal_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Copper",
        CurrentValue = false,
        Flag = "ore_Copper_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Iron",
        CurrentValue = false,
        Flag = "ore_Iron_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Aluminium",
        CurrentValue = false,
        Flag = "ore_Aluminium_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Amber",
        CurrentValue = false,
        Flag = "ore_Amber_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Silver",
        CurrentValue = false,
        Flag = "ore_Silver_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Tin",
        CurrentValue = false,
        Flag = "ore_Tin_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Scarlet",
        CurrentValue = false,
        Flag = "ore_Scarlet_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Gold",
        CurrentValue = false,
        Flag = "ore_Gold_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Jade",
        CurrentValue = false,
        Flag = "ore_Jade_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Voltshard",
        CurrentValue = false,
        Flag = "ore_Voltshard_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Blastshard",
        CurrentValue = false,
        Flag = "ore_Blastshard_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Section = EspTab:CreateSection("Trees")
     local Toggle = EspTab:CreateToggle({
        Name = "Oak",
        CurrentValue = false,
        Flag = "tree_Oak_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Birch",
        CurrentValue = false,
        Flag = "tree_Birch_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Maple",
        CurrentValue = false,
        Flag = "tree_Maple_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Cherry",
        CurrentValue = false,
        Flag = "tree_Cherry_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Clay",
        CurrentValue = false,
        Flag = "tree_Clay_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Palm",
        CurrentValue = false,
        Flag = "tree_Palm_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Redwood",
        CurrentValue = false,
        Flag = "tree_Redwood_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Pine",
        CurrentValue = false,
        Flag = "tree_Pine_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Fir",
        CurrentValue = false,
        Flag = "tree_Fir_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Lush Oak",
        CurrentValue = false,
        Flag = "tree_LushOak_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Silverwood",
        CurrentValue = false,
        Flag = "tree_Silverwood_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Goldwood",
        CurrentValue = false,
        Flag = "tree_Goldwood_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Orewood",
        CurrentValue = false,
        Flag = "tree_Orewood_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Toggle = EspTab:CreateToggle({
        Name = "Glacier",
        CurrentValue = false,
        Flag = "tree_Glacier_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
     local Section = EspTab:CreateSection("Other")
     local Toggle = EspTab:CreateToggle({
        Name = "Ancient Rune",
        CurrentValue = false,
        Flag = "other_Rune_esp", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
        Callback = function(Value)
        -- The function that takes place when the toggle is pressed
        -- The variable (Value) is a boolean on whether the toggle is true or false
        end,
     })
