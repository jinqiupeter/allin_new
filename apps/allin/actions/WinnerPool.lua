local WinnerPool = cc.class("WinnerPool")
local Constants = cc.import(".Constants", "..")
local string_format = string.format

-- SNG
local players_range_sng = {
    {0, 1}, {2, 6}, {7, 9}
}
local winner_level_sng = {
    {1, 1}, {2, 2}, {3, 3}
}
local winning_percentage_sng = {
    {100}, {65,35}, {50,30,20}
}

-- MTT
local players_range_mtt = {
    {2,10}, {11,20}, {21,30}, {31,40}, {41,50}, {51,60},
    {61,87}, {88,112}, {113,137}, {138,162}, {163,187}, {188,212},
    {213,262}, {263,337}, {338,412}, {413,487}, {488,562}, {563,637},
    {638,712}, {713,787}, {788,862}, {863,937}, {938,1012}, {1013,1087},
    {1088,1162}, {1163,1237}, {1238,10000}
}
local winner_level_mtt = {
    {1,1}, {2,2}, {3,3}, {4,4}, {5,5}, {6,6}, {7,7}, {8,8}, {9,9},
    {10,12}, {13,15}, {16,18}, {19,21}, {22,24}, {25,27}, 
    {28,36}, {37,45}, {46,54}, {55,63}, {64,72}, {73,81},
    {82,90}, {91,99}, {100,108} 
}
local winning_percentage_mtt = {
    {100}, {60,40}, {48,32,20}, {40,28,18,14}, {36,25,16,13,10}, {34,23,15,12,9,7}, {30,21,13.5,10,7.5,6.0,5.0,4.0,3.0},
    {28.15,19.71,12.67,9.39,7.04,5.63,4.69,3.75,2.82,2.05}, {26.8,18.77,12.07,8.94,6.70,5.36,4.46,3.57,2.68,1.95,1.6},
    {25.75,18.03,11.06,8.59,6.44,5.15,4.28,3.43,2.57,1.87,1.54,1.31}, {24.87,17.43,11.21,8.30,6.23,4.98,4.14,3.32,2.48,1.81,1.49,1.27,1.11},
    {24.15,16.93,10.88,8.06,6.05,4.48,4.02,3.22,2.41,1.76,1.45,1.23,1.08,0.96},
    {23.53,16.51,10.62,7.86,5.90,4.72,3.92,3.14,2.35,1.72,1.41,1.20,1.05,0.94,0.83},
    {22.09,15.50,9.97,7.38,5.54,4.43,3.68,2.95,2.21,1.61,1.32,1.13,0.99,0.88,0.78,0.68},
    {21.00,14.70,9.24,7.00,5.25,4.20,3.50,2.80,2.10,1.53,1.25,1.07,0.94,0.84,0.74,0.65,0.56},
    {20.10,14.09,9.06,6.70,5.03,4.03,3.36,2.68,2.01,1.47,1.20,1.03,0.90,0.81,0.71,0.62,0.54,0.46},
    {19.43,13.62,8.76,6.48,4.86,3.90,3.25,2.59,1.95,1.43,1.16,1.00,0.87,0.78,0.69,0.60,0.52,0.44,0.37},
    {18.90,13.25,8.52,6.31,4.73,3.79,3.16,2.52,1.89,1.39,1.13,0.97,0.85,0.76,0.67,0.58,0.50,0.43,0.36,0.31},
    {18.47,12.95,8.35,6.17,4.62,3.73,3.09,2.46,1.85,1.36,1.10,0.95,0.83,0.74,0.65,0.57,0.49,0.42,0.35,0.30,0.25},
    {18.10,12.69,8.16,6.05,4.53,3.66,3.03,2.41,1.81,1.34,1.07,0.93,0.82,0.73,0.64,0.56,0.48,0.41,0.34,0.29,0.25,0.22},              
    {17.76,12.45,8.04,5.95,4.45,3.60,2.98,2.37,1.78,1.31,1.06,0.91,0.81,0.72,0.63,0.55,0.47,0.40,0.33,0.29,0.25,0.22,0.19},                                         
    {17.50,12.26,7.93,5.86,4.38,3.54,2.93,2.33,1.75,1.30,1.05,0.90,0.80,0.71,0.62,0.54,0.46,0.39,0.32,0.28,0.25,0.22,0.19,0.17},
    {17.21,12.06,7.82,5.78,4.31,3.49,2.89,2.30,1.72,1.29,1.04,0.89,0.79,0.70,0.61,0.53,0.45,0.38,0.32,0.28,0.25,0.22,0.19,0.16},
    {17.01,11.92,7.73,5.71,4.26,3.45,2.86,2.28,1.70,1.27,1.02,0.88,0.79,0.70,0.61,0.52,0.45,0.38,0.32,0.28,0.24,0.21,0.18,0.15},
    {16.82,11.79,7.65,5.67,4.23,3.42,2.84,2.27,1.69,1.27,1.02,0.88,0.78,0.69,0.60,0.52,0.45,0.38,0.32,0.27,0.23,0.20,0.17,0.14},
    {16.80,11.78,7.64,5.66,4.22,3.41,2.84,2.26,1.68,1.27,1.02,0.88,0.78,0.69,0.60,0.51,0.44,0.37,0.31,0.26,0.22,0.19,0.16,0.13},
    {16.60,11.64,7.56,5.62,4.19,3.38,2.82,2.25,1.66,1.27,1.01,0.87,0.77,0.68,0.59,0.50,0.43,0.36,0.30,0.25,0.22,0.19,0.16,0.13},
}

function WinnerPool:getPoolingPlan(gamemode, playercount) 
    local game_mode = tonumber(gamemode)
    local player_count = tonumber(playercount)
    if not game_mode == Constants.GameMode.GameModeSNG or not game_mode == Constants.GameMode.GameModeFreezeOut then
        return nil, "wrong game mode: " .. game_mode .. " " .. Constants.GameMode.GameModeSNG .. " " .. Constants.GameMode.GameModeFreezeOut
    end
    
    local range_table = players_range_sng
    local level_table = winner_level_sng
    local percentage_table = winning_percentage_sng
    if game_mode == Constants.GameMode.GameModeFreezeOut then
        range_table = players_range_mtt
        level_table = winner_level_mtt
        percentage_table = winning_percentage_mtt
    end
    
    local range_key = -1
    for key, range in pairs(range_table) do
        if range[1] <= player_count and player_count <= range[2] then
            range_key = key
        end
    end
    if range_key == -1 then
        return nil, string_format("invalid player count: %s for game mode %s", player_count, gamemode)
    end
    local level_key = range_key
    if level_key > #level_table then
        level_key = #level_table
    end
    local max_winner_limit = level_table[level_key][2]

    local pooling = {}
    local range = {}
    local percentages = percentage_table[range_key]
    for i = 1, max_winner_limit do
        for j = 1, level_key do
            if level_table[j][1] <= i and i <= level_table[j][2] then
                local pooling_key = "".. i
                local pooling_range = level_table[j][1] .. "_" .. level_table[j][2]
                local pooling_percentage = percentages[j]
                pooling[pooling_key] = pooling_percentage
                range[pooling_range] = pooling_percentage
                break
            end
        end
    end

    return {player_pooling = pooling, range = range}
end

return WinnerPool
