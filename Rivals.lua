local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
    if player.Name == "PlayerName" then
        player:Kick("go on https://nsense.fun and click on copy loadstring!")
    end
end)
