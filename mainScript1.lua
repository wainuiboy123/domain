local deficon = 4483362458

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()



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


local HomeTab = Window:CreateTab("Home", deficon)
local ParagraphHOME = HomeTab:CreateParagraph({Title = "About Domain", Content = "This is Domain, we're a script that is determinded to make scripts for all of your favourite games without being detected by Roblox and Game Creators."})
local TeleportTab = Window:CreateTab("Teleports", 4483362458)
local Button = TeleportTab:CreateButton({
   Name = "Blue Team",
   Callback = function()
        game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(400.351288, -9.70197582, 300.306183, 0.0208735671, -5.64689202e-08, 0.999782145, 2.67149247e-10, 1, 5.64756455e-08, -0.999782145, -9.11757114e-10, 0.0208735671)
   end,
})
local Button = TeleportTab:CreateButton({
    Name = "White Team",
    Callback = function()
         game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-51.027668, -9.70197582, -535.338745, -0.999999642, 1.3800755e-09, 0.000871745055, 1.47944701e-09, 1, 1.13990872e-07, -0.000871745055, 1.13992115e-07, -0.999999642)
    end,
 })
 local Button = TeleportTab:CreateButton({
    Name = "Black Team",
    Callback = function()
         game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-526.457458, -9.70197773, -69.2191315, -0.047294002, 1.38806922e-08, -0.998881042, -3.43729312e-09, 1, 1.40589869e-08, 0.998881042, 4.09835277e-09, -0.047294002)
    end,
 })
 local Button = TeleportTab:CreateButton({
    Name = "Magenta Team",
    Callback = function()
         game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(400.351288, -9.70197582, 300.306183, 0.0208735671, -5.64689202e-08, 0.999782145, 2.67149247e-10, 1, 5.64756455e-08, -0.999782145, -9.11757114e-10, 0.0208735671)
    end,
 })
 local Button = TeleportTab:CreateButton({
    Name = "Yellow Team",
    Callback = function()
        Rayfield:Notify({
            Title = "Domain",
            Content = "Coming Soon...",
            Duration = 10,
            Image = 4483362458,
         })
    end,
 })
 local Button = TeleportTab:CreateButton({
    Name = "Red Team",
    Callback = function()
        Rayfield:Notify({
            Title = "Domain",
            Content = "Coming Soon...",
            Duration = 10,
            Image = 4483362458,
         })
    end,
 })
 local Button = TeleportTab:CreateButton({
    Name = "Green Team",
    Callback = function()
        Rayfield:Notify({
            Title = "Domain",
            Content = "Coming Soon...",
            Duration = 10,
            Image = 4483362458,
         })
    end,
 })
 local Button = TeleportTab:CreateButton({
    Name = "End",
    Callback = function()
        Rayfield:Notify({
            Title = "Domain",
            Content = "Coming Soon...",
            Duration = 10,
            Image = 4483362458,
         })
    end,
 })
