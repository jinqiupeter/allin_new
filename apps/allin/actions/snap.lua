local Snap       = cc.class("Snap")
local Constants  = cc.import(".Constants", "..")
local Game_Runtime = cc.import("#game_runtime")
local User_Runtime = cc.import("#user_runtime")
local Helper = cc.import(".Helper", "..")

local string_split       = string.split
local _handleGameState, _handleTable, _handleCards, _handleWinAmount, _handleStakeChange, _handleWinPot, _handleOddChips, _handlePlayerAction, _handlePlayerCurrent, _handlePlayerShow, _handleFoyer, _handleERR, _handleRespite, _handleWantToStraddleNextRound, _handleBuyInsurance, _handleInsuranceBenefits


-- to support playing more than one game, we need to put these info in a table
function Snap:_getHand (instance, redis, game_id, table_id)
    local game_runtime = Game_Runtime:new(instance, redis)
    local table_hand = game_runtime:getGameInfo(game_id, "TableHand_" .. table_id)
    local hand_no = -1
    if table_hand ~= nil then
        local info = string_split(table_hand, ":")
        hand_no = info[2]
    end
     
    return hand_no
end

function Snap:_getDealer(instance, redis, game_id, table_id)
    local game_runtime = Game_Runtime:new(instance, redis)
    local table_dealer = game_runtime:getGameInfo(game_id, "TableDealer_" .. table_id)
    local dealer = -1
    if table_dealer ~= nil then
        local info = string_split(table_dealer, ":")
        dealer = info[2]
    end
     
    return dealer
end


function Snap:_updateBuying(occupied_seats, args)
    local game_id = args.game_id
    local table_id = args.table_id
    local mysql = args.mysql
    local redis = args.redis
    local instance = args.instance

    for key, value in pairs(occupied_seats) do
        local rebuy_stake = value.rebuy_stake
        local stake = value.player_stake
        local user_id = value.player_id
        -- update stake_available in buying
        local sub_query = "SELECT id FROM buying WHERE "
         .. " game_id = " .. game_id 
         .. " AND user_id = " .. user_id
         .. " ORDER BY bought_at DESC LIMIT 1"
        cc.printdebug("executing sql: %s", sub_query)
        local dbres, err, errno, sqlstate = mysql:query(sub_query)
        if not dbres then
            cc.throw("db err: %s", err)
        end
        local last_id = dbres[1].id
        local sql = " UPDATE buying SET stake_available = " .. tonumber(stake) + tonumber(rebuy_stake)
                    .. " , updated_at = now() "
                    .. " WHERE id =  " .. last_id 
        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            cc.throw("db err: %s", err)
        end
    end
end

function Snap:_updateGameStake(player_stakes, args)
    local game_id = args.game_id
    local table_id = args.table_id
    local mysql = args.mysql
    local redis = args.redis
    local instance = args.instance

    for key, value in pairs(player_stakes) do
        local user_id = value.player_id
        local stake = value.player_stake
        local stake_change = value.stake_change

        cc.printdebug("updating stake: %s and stake_change: %s for user: %s", stake, stake_change, user_id)
        local sql = "INSERT INTO game_stake (game_id, table_id, hand_id, user_id, stake, stake_change ) "
                    .. " VALUES ( " .. game_id .. ", "
                    .. table_id .. ", "
                    .. self:_getHand(instance, redis, game_id, table_id) .. ", "
                    .. user_id .. ", "
                    .. stake .. ", "
                    .. stake_change .. ")"
                    .. " ON DUPLICATE KEY UPDATE stake = " .. stake .. ", "
                                              .. "updated_at = NOW()" 
        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            cc.throw("db err: %s", err)
        end

    end
end

function Snap:_exchangeSitNGo(args)
    local game_id = args.game_id
    local table_id = args.table_id
    local mysql = args.mysql

    local sql  = " SELECT user_id, stake_available as stake_ended FROM buying WHERE updated_at IN ( "
               .. " SELECT  MAX(updated_at) AS updated_at FROM buying WHERE game_id = " .. game_id .. " GROUP BY user_id " 
               .. " ) "
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.throw("db err: %s", err)
        return
    end

    local index = 1
    while index <= #dbres do
        local user_found = dbres[index].user_id
        local stake_ended = dbres[index].stake_ended

        -- update user.gold
        local sql = "UPDATE user SET gold = gold + " .. stake_ended / buying_rate .. " WHERE id = " .. user_found
        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            cc.throw("db err: %s", err)
            return 
        end

        index = index + 1
    end
end

function Snap:_exchangeSNGMTT(args)
    local game_id = args.game_id
    local table_id = args.table_id
    local mysql = args.mysql

    local sql  = " SELECT user_id, stake_available as stake_ended FROM buying WHERE updated_at IN ( "
               .. " SELECT  MAX(updated_at) AS updated_at FROM buying WHERE game_id = " .. game_id .. " GROUP BY user_id " 
               .. " ) "
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.throw("db err: %s", err)
        return
    end

    local index = 1
    while index <= #dbres do
        local user_found = dbres[index].user_id
        local stake_ended = dbres[index].stake_ended

        -- update user.gold
        local sql = "UPDATE user SET gold = gold + " .. stake_ended / buying_rate .. " WHERE id = " .. user_found
        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            cc.throw("db err: %s", err)
            return 
        end

        index = index + 1
    end
end

function Snap:_exchangeStakeToGold(args)
    local game_id = args.game_id
    local table_id = args.table_id
    local mysql = args.mysql

    local sql = "SELECT game_mode, buying_gold, buying_stake FROM game WHERE id = " .. game_id 
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.throw("db err: %s", err)
        return 
    end
    local game_mode = dbres[1].game_mode
    local buying_gold = dbres[1].buying_gold
    local buying_stake = dbres[1].buying_stake
    local buying_rate = buying_stake / buying_gold
    if game_mode ~= Constants.GameMode.GameModeRingGame then
        self:_exchangeSitNGo({game_id = game_id, mysql = mysql, buying_rate = buying_rate})   
    else
        self:_exchangeSNGMTT({game_id = game_id, mysql = mysql, buying_rate = buying_rate})   
    end
end

_handleGameState = function (snap_value, args)
    local self = args.self
    --tcp: SNAP 1:0 1 <<1>>
    local value = {}
    local game_state = tonumber(snap_value[1])
    value.game_state = game_state
    local game_id = args.game_id
    local table_id = args.table_id

    local instance = args.instance
    local mysql = args.mysql
    local redis = args.redis
    local self = args.self

    local sql = ""
    if game_state == Constants.Snap.GameState.SnapGameStateNewHand then
        value.hand_no = snap_value[2]
        local key = "" .. game_id .. "_" .. table_id

        -- save current hand so later if a player joins the game after Constants.Snap.GameState.SnapGameStateNewHand,
        -- hand_no can still be fetched
        local game_runtime = Game_Runtime:new(instance, redis)
        game_runtime:setGameInfo(game_id, "TableHand_" .. table_id, "" .. table_id .. ":" .. value.hand_no)
    elseif game_state == Constants.Snap.GameState.SnapGameStateBroke then
        value.broken_player_id = snap_value[2]
        value.broken_player_position = snap_value[3]  -- TODO: what does this mean?
    elseif game_state == Constants.Snap.GameState.SnapGameStateBlinds then
        value.small_blind = snap_value[2] 
        value.big_blind = snap_value[3]
        value.blind_level = snap_value[4]
        value.next_level = snap_value[5]
        value.next_amount = snap_value[6]
        value.last_blind_time = snap_value[7]
        -- update game.blind_amount
        if tonumber(instance:getCid()) == tonumber(self:_getDealer(instance, redis, game_id, table_id)) then
            local game_runtime = Game_Runtime:new(instance, redis)
            game_runtime:setGameInfo(game_id, "BlindAmount", value.big_blind)
            game_runtime:setGameInfo(game_id, "BlindLevel", value.blind_level)
            game_runtime:setGameInfo(game_id, "NextLevel", value.next_level or 0)
            game_runtime:setGameInfo(game_id, "NextAmount", value.next_amount or 0)
            game_runtime:setGameInfo(game_id, "LastBlindTime", value.last_blind_time)
        end
    elseif game_state == Constants.Snap.GameState.SnapGameStateStart then
        -- record is inserted in _updateUserGameHistory 
        sql = " UPDATE user_game_history SET started_at = NOW() "
             .. " WHERE game_id = " .. game_id
             .. " AND user_id = " .. instance:getCid()
             
        -- set game state to Start. SnapGameStateStart is send in PlaceTable(), so only 
        local game_runtime = Game_Runtime:new(instance, redis)
        game_runtime:setGameInfo(game_id, "GameState", Constants.GameState.GameStateStarted)
        game_runtime:setGameInfo(game_id, "StartedAt", os.time())


    elseif game_state == Constants.Snap.GameState.SnapGameStateEnd then
        sql = " UPDATE user_game_history SET ended_at = NOW() "
             .. " WHERE game_id = " .. game_id
             .. " AND user_id = " .. instance:getCid()

        local game_runtime = Game_Runtime:new(instance, redis)
        game_runtime:setGameInfo(game_id, "GameState", Constants.GameState.GameStateEnded)
        game_runtime:setGameInfo(game_id, "EndedAt", os.time())

        if tonumber(instance:getCid()) == tonumber(self:_getDealer(instance, redis, game_id, table_id)) then
            -- exchange user stake back to gold
            self:_exchangeStakeToGold({game_id = game_id, table_id = table_id, mysql = mysql})

            -- delete game info because it's not needed anymore
            local game_runtime = Game_Runtime:new(instance, redis)
            game_runtime:deleteInfo(game_id)
        end
    elseif game_state == Constants.Snap.GameState.SnapGameStateTableSuspend then
        value.reason = snap_value[2]
        value.tick = snap_value[3]
    end

    if sql ~= "" then
        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            cc.throw("db err: %s", err)
        end
    end

    return value
end

_handleTable = function (snap_value, args)
    --tcp: SNAP 1:0 2 <<0:-1 -1 cc: s4:0:0:1500:0:0: s9:1:0:1500:0:0:   0>>
    local value = {}
    local game_id = args.game_id
    local table_id = args.table_id
    local instance = args.instance
    local mysql = args.mysql
    local redis = args.redis
    local self = args.self

    -- table state and bet round
    local head = table.remove(snap_value, 1)  -- same as head = array.shift()
    local tmp = string_split(head, ":")
    local table_state = tonumber(tmp[1])
    value.table_state = table_state
    if tonumber(value.table_state) == Constants.Snap.TableState.NewRound then
        -- subscribe to table channel
        local channel = Constants.TABLE_CHAT_CHANNEL_PREFIX .. tostring(game_id) .. "_" .. tostring(table_id)
        cc.printdebug("user %s subscribing to table channel %s" , instance:getCid(),  channel)
        instance:subscribeChannel(channel)
    end

    local bet_round    = tmp[2]
    value.bet_round = bet_round
    local key = "" .. game_id .. "_" .. table_id

    -- clear user_runtime RespiteCount if a new betting round started
    local user_runtime = User_Runtime:new(instance, redis)
    local game_runtime = Game_Runtime:new(instance, redis)
    local previous_betround = Helper:_getBetRound(instance, redis, game_id, table_id)
    if tonumber(previous_betround) ~= tonumber(value.bet_round) then
        -- whoever receives the new betround snap is responsible for clearing respite count for all players in the game
        local players = game_runtime:getPlayers(game_id)
        local inspect = require("inspect")
        cc.printdebug("players for game %s: %s", game_id, inspect(players))
        for key, player in pairs(players) do
            user_runtime:setRespiteCount(game_id, 0, player)
        end
        game_runtime:setGameInfo(game_id, "TableBetround_" .. table_id, "" .. table_id .. ":" .. value.bet_round)
    end
        
    -- turn
    local head = table.remove(snap_value, 1)
    local turn = head
    value.turn = turn
    -- if table state is (Table::GameStart|Table::ElectDealer), then turn is -1
    -- otherwise turn is: %d:%d:%d:%d:%d, t->dealer:t->sb:t->bb:(t->cur_player == -1) ? -1 : (int)t->seats[t->cur_player].seat_no:t->last_bet_player
    if turn ~= "-1" then 
        value.turn = nil

        local tmp = string_split(turn, ":")
        value.dealer            = tmp[1]
        value.sb                = tmp[2]
        value.bb                = tmp[3]


        value.current_player    = tmp[4]
        value.current_player_time_left    = tmp[5]
        value.last_bet_player   = tmp[6]
    end

    local head = table.remove(snap_value, 1)
    -- community cards, looks like: cc:5c:2d:Th:9c:9h or cc:
    local tmp  = string_split(head, ":")
    local community_cards = table.subrange(tmp, 2, #tmp)
    value.community_cards = community_cards


    -- occupied seats' info
    local occupied_seats = {}
    local i = 1
    local head = table.remove(snap_value, 1)
    while string.byte(head) == 115 do -- 115 = char 's'
        -- seat info looks like: s4:0:0:1500:0:0:
        local tmp = string_split(head, ":")
        local sseat_no              = tmp[1]
        local seat_no               = string.sub(sseat_no, 2)
        local player_id             = tmp[2]
        local player_state          = tmp[3]  -- PlayerInRound(0x01) | PlayerSitout(0x02) 
        local in_round = 0
        if bit.band(0x01 ,tonumber(player_state)) > 0 then 
            in_round = 1
        end
        local sit_out = 0
        if bit.band(0x02 ,tonumber(player_state)) > 0 then 
            sit_out = 1
        end
        local player_stake          = tmp[4]
        local rebuy_stake           = tmp[5]
        local bet_amount            = tmp[6] -- bet amount
        local last_action           = tmp[7] -- 0: None, 1: ResetAction, 2: Check, 3: Fold, 4: Call, 5: Bet, 6: Raise, 7: Allin, 8: Show, 9: Muck, 10: Sitout, 11: Back
        local hole_cards_str            = tmp[8] or ""
        local hole_cards = table.concat(string_split(hole_cards_str, "_"), " ")

        if (seat_no == value.dealer) then
            local game_runtime = Game_Runtime:new(instance, redis)
            game_runtime:setGameInfo(game_id, "TableDealer_" .. table_id, "" .. table_id .. ":" .. player_id)
        end

        occupied_seats[i] = {seat_no = seat_no, player_id = player_id, in_round = in_round, sit_out = sit_out, player_stake = player_stake, rebuy_stake = rebuy_stake, bet_amount = bet_amount, last_action = last_action, hole_cards = hole_cards}


        head = table.remove(snap_value, 1)
        i = i + 1
    end
    value.occupied_seats = occupied_seats

    -- update game_holecards.hole_cards_to_show
    if tonumber(value.table_state) == Constants.Snap.TableState.EndRound then
        for i= 1, table.getn(occupied_seats) do
            local seat_holecards = occupied_seats[i].hole_cards
            local seat_player_id = occupied_seats[i].player_id
            local sql = "UPDATE game_holecards SET hole_cards_to_show = " .. instance:sqlQuote(seat_holecards)
                     .. " WHERE game_id = " .. game_id
                     .. " AND table_id = " .. table_id
                     .. " AND hand_id = " .. self:_getHand(instance, redis, game_id, table_id)
                     .. " AND user_id = " .. seat_player_id

            cc.printdebug("executing sql: %s", sql)
            local dbres, err, errno, sqlstate = mysql:query(sql)
            if not dbres then
                cc.printdebug("db err: %s", err)
                value.state = Constants.Error.MysqlError
                value.msg = "数据库错误: " .. err
                return value
            end
        end
    end

    -- only dealer should update buying.stake_available table at the end of current hand
    if tonumber(value.table_state) == Constants.Snap.TableState.EndRound
      and tonumber(instance:getCid()) == tonumber(self:_getDealer(instance, redis, game_id, table_id)) then
          self:_updateBuying(occupied_seats, {game_id = game_id, table_id = table_id, mysql = args.mysql, instance = instance, redis = redis})
    end

    -- pots
    local pots = {}
    local i = 1
    while string.byte(head) == 112 do -- 112 = char 'p'
        -- pot info looks like: p1:30
        local tmp = string_split(head, ":")
        local spot_no              = tmp[1]
        local pot_no               = string.sub(spot_no, 2)
        local pot_amount           = tmp[2]

        pots[i] = {pot_no = pot_no, pot_amount = pot_amount}

        head = table.remove(snap_value, 1)
        i = i + 1
    end
    value.pots = pots 

    -- current blind amount
    value.current_amount = head
    value.blind_amount = head

    -- current blind level
    head = table.remove(snap_value, 1)
    value.current_level = head

    -- next blind amount
    head = table.remove(snap_value, 1)
    value.next_amount = head

    -- next blind level
    head = table.remove(snap_value, 1)
    value.next_level = head

    -- last blind time
    head = table.remove(snap_value, 1)
    value.last_blind_time = head

    -- minimum bet amount
    head = table.remove(snap_value, 1)
    value.minimus_bet = head



    return value
end

_handleCards = function (snap_value, args)
    -- tcp: SNAP 1:0 3 <1 Kc 3s>
    local instance = args.instance
    local mysql = args.mysql
    local redis = args.redis
    local game_id = args.game_id
    local table_id = args.table_id
    local self = args.self

    local value = {}
    local card_type = snap_value[1]
    value.card_type = card_type
    local cards = table.subrange(snap_value, 2, #snap_value)
    value.cards = cards

    -- update community card
    -- only dealer should update database
    local cc_sql = nil

    if tonumber(instance:getCid()) == tonumber(self:_getDealer(instance, redis, game_id, table_id)) then
        cc_sql = "INSERT INTO game_cc_cards (game_id, table_id, hand_id) " 
                .. "VALUES (" .. game_id .. ", " 
                .. table_id .. ", " 
                .. self:_getHand(instance, redis, game_id, table_id) .. ") "
                .. " ON DUPLICATE KEY UPDATE "

        if tonumber(card_type) == Constants.Snap.CardType.SnapCardsFlop then
            cc_sql = "INSERT INTO game_cc_cards (game_id, table_id, hand_id, flop_card) "
                .. "VALUES (" .. game_id .. ", " 
                .. table_id .. ", " 
                .. self:_getHand(instance, redis, game_id, table_id) .. ", "
                .. instance:sqlQuote(table.concat(value.cards, " ")) .. ") "
        elseif tonumber(card_type) == Constants.Snap.CardType.SnapCardsTurn then
            cc_sql = cc_sql .. "turn_card = " .. instance:sqlQuote(table.concat(value.cards, " "))
        elseif tonumber(card_type) == Constants.Snap.CardType.SnapCardsRiver then
            cc_sql = cc_sql .. "river_card = " .. instance:sqlQuote(table.concat(value.cards, " "))
        end
    end
    
    -- hole cards are sent to one user only
    local hole_sql = "INSERT INTO game_holecards (game_id, table_id, hand_id, user_id, hole_cards) "
                    .. " VALUES (" .. game_id .. ", " 
                    .. table_id .. ", "
                    .. self:_getHand(instance, redis, game_id, table_id) .. ", "
                    .. instance:getCid() .. ", "
                    .. instance:sqlQuote(table.concat(value.cards, " ")) .. ") "
                    .. " ON DUPLICATE KEY UPDATE hole_cards = " .. instance:sqlQuote(table.concat(value.cards, " "))

    local sql = nil
    if tonumber(card_type) == Constants.Snap.CardType.SnapCardsHole then
        sql = hole_sql
    else 
        sql = cc_sql
    end

    if sql ~= nil then
        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            cc.printdebug("db err: %s", err)
            value.state = Constants.Error.MysqlError
            value.msg = "数据库错误: " .. err
            return value
        end
    end

    return value
end

_handleWinAmount = function (snap_value, args)
    -- tcp: SNAP 1:0 6 <1 -1 60> ==><1=cid, -1=reserved, 60==>amount won>
    local game_id = args.game_id
    local table_id = args.table_id
    local self = args.self
    local instance = args.instance
    local mysql = args.mysql
    local redis = args.redis

    local value = {}
    local player_id = snap_value[1]
    value.player_id = player_id

    -- snap_value[2] is reserved
    local amount_won = snap_value[3]
    value.amount_won = amount_won

    if tonumber(instance:getCid()) == tonumber(self:_getDealer(instance, redis, game_id, table_id)) then
        local sql = "INSERT INTO game_winners (game_id, table_id, hand_id, winner_id, amount_won) " 
                .. "VALUES (" .. game_id .. ", " 
                .. table_id .. ", " 
                .. self:_getHand(instance, redis, game_id, table_id) .. ", "
                .. value.player_id .. ", "
                .. value.amount_won .. ") "
                .. " ON DUPLICATE KEY UPDATE amount_won = " .. value.amount_won

        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            cc.printdebug("db err: %s", err)
            value.state = Constants.Error.MysqlError
            value.msg = "数据库错误: " .. err
            return value
        end
    end

    return value
end

_handleStakeChange = function (snap_value, args)
    -- tcp: SNAP 1:0 6 <1 2 60> ==><1=cid, 2==> player id, 60==>stake change>
    local game_id = args.game_id
    local table_id = args.table_id
    local self = args.self
    local instance = args.instance
    local mysql = args.mysql
    local redis = args.redis

    local index = 1
    local player_stakes = {}
    while index <= #snap_value do
        local info = string_split(snap_value[index], ":")
        local player_id = info[1]
        local player_stake = info[2]
        local stake_change = info[3]
        player_stakes[index] = {player_id = player_id, player_stake = player_stake, stake_change = stake_change}
        index = index + 1
    end

    local value = {}
    value.player_stakes = player_stakes


    -- only dealer should update game_stake table
    if tonumber(instance:getCid()) == tonumber(self:_getDealer(instance, redis, game_id, table_id)) then
        self:_updateGameStake(player_stakes, {game_id = game_id, table_id = table_id, mysql = args.mysql, instance = instance, redis = redis})
    end 

    return value
end

_handleWinPot = function (snap_value, args)
    -- tcp: SNAP 1:0 7 <1 0 120> ==><1=cid, 0=pot id, 120=amount received>
    local game_id = args.game_id
    local table_id = args.table_id
    local self = args.self
    local instance = args.instance
    local mysql = args.mysql
    local redis = args.redis

    local value = {}
    local player_id = snap_value[1]
    value.player_id = player_id

    -- snap_value[2] is reserved
    local pod_id = snap_value[2]
    value.pod_id = pod_id

    local amount_received = snap_value[3]
    value.amount_received = amount_received

    local pot_type = 0 -- 0: normal pot, 1: odd pot

    -- only dealer should update db
    if tonumber(instance:getCid()) == tonumber(self:_getDealer(instance, redis, game_id, table_id)) then
        local sql = "INSERT INTO game_pot_dist (game_id, table_id, hand_id, user_id, pot_id, pot_type, amount_received) " 
                .. "VALUES (" .. game_id .. ", " 
                .. table_id .. ", " 
                .. self:_getHand(instance, redis, game_id, table_id) .. ", "
                .. value.player_id .. ", "
                .. value.pod_id  .. ", "
                .. pot_type  .. ", "
                .. value.amount_received .. ") "

        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            cc.printdebug("db err: %s", err)
            value.state = Constants.Error.MysqlError
            value.msg = "数据库错误: " .. err
            return value
        end
    end

    return value
end

_handleOddChips = function (snap_value, args)
    local game_id = args.game_id
    local table_id = args.table_id
    local self = args.self
    local instance = args.instance
    local mysql = args.mysql
    local redis = args.redis

    -- tcp: SNAP 1:0 8 <1 0 120> ==><1=cid, 0=>pot id, 120=amount received>
    local value = {}
    local player_id = snap_value[1]
    value.player_id = player_id

    -- snap_value[2] is reserved
    local pod_id = snap_value[2]
    value.pod_id = pod_id

    local odd_chips_received = snap_value[3]
    value.odd_chips_received = odd_chips_received

    local pot_type = 1 -- 0: normal pot, 1: odd pot

    -- only dealer should update db
    if tonumber(instance:getCid()) == tonumber(self:_getDealer(instance, redis, game_id, table_id)) then
        local sql = "INSERT INTO game_pot_dist (game_id, table_id, hand_id, user_id, pot_id, pot_type, amount_received) " 
                .. "VALUES (" .. game_id .. ", " 
                .. table_id .. ", " 
                .. self:_getHand(instance, redis, game_id, table_id) .. ", "
                .. value.player_id .. ", "
                .. value.pod_id  .. ", "
                .. pot_type  .. ", "
                .. value.amount_received .. ") "

        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            cc.printdebug("db err: %s", err)
            value.state = Constants.Error.MysqlError
            value.msg = "数据库错误: " .. err
            return value
        end
    end

    return value
end

_handlePlayerAction = function (snap_value, args)
    -- tcp: SNAP 1:0 10 <3 1 10> ==><3=action_type, 1=cid, c=[auto_action?1:0] if action is Fold or Check, [amount] otherwise>
    local game_id = args.game_id
    local table_id = args.table_id
    local self = args.self
    local instance = args.instance
    local mysql = args.mysql
    local redis = args.redis

    local value = {}
    local action_type = tonumber(snap_value[1])
 --[[ player action type:
 SnapPlayerActionFolded  = 0x01,  // cid, auto=0|1
 SnapPlayerActionChecked = 0x02,  // cid, auto=0|1
 SnapPlayerActionCalled  = 0x03,  // cid, amount
 SnapPlayerActionBet = 0x04,      // cid, amount
 SnapPlayerActionRaised  = 0x05,  // cid, amount
 SnapPlayerActionAllin   = 0x06,  // cid, amount
 --]]
    value.action_type = action_type

    -- snap_value[2] is reserved
    local player_id = snap_value[2]
    value.player_id = player_id

    if action_type == Constants.Snap.PlayerAction.SnapPlayerActionFolded 
        or 
       action_type == Constants.Snap.PlayerAction.SnapPlayerActionChecked then
        value.auto_action = snap_value[3]
    else
        value.amount = snap_value[3]
    end

    local is_auto = 0
    if value.auto_action then
        is_auto = value.auto_action
    end

    local amount = 0
    if value.amount then 
        amount = value.amount
    end
    -- the player performed the action is responsible for updating db
    if tonumber(instance:getCid()) == tonumber(value.player_id) then
        local sql = "INSERT INTO user_action (user_id, game_id, table_id, hand_id, bet_round, action_type, auto_action, amount) " 
                .. "VALUES (" .. instance:getCid() .. ", " 
                .. game_id .. ", " 
                .. table_id .. ", " 
                .. self:_getHand(instance, redis, game_id, table_id) .. ", "
                .. Helper:_getBetRound(instance, redis, game_id, table_id) .. ", "
                .. action_type .. ", "
                .. is_auto .. ", "
                .. amount .. ") "

        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            cc.printdebug("db err: %s", err)
            value.state = Constants.Error.MysqlError
            value.msg = "数据库错误: " .. err
            return value
        end
    end
    
    return value
end

_handlePlayerCurrent = function (snap_value, args)
    -- tcp: SNAP 1:0 11
    local value = {msg = "not implemented"}

    return value
end

_handlePlayerShow = function (snap_value, args)
    local game_id = args.game_id
    local table_id = args.table_id
    local self = args.self
    local instance = args.instance
    local mysql = args.mysql

    -- tcp: SNAP 1:0 12 <0 Jh 4c 5c 2d Th 9c 9h> ==><0=cid, Jh 4c 5c 2d Th 9c 9h=player cards>
    local value = {}
    local player_id = table.remove(snap_value, 1)
    value.player_id = player_id

    -- snap_value[2] is reserved
    local cards = snap_value
    value.cards = cards

    return value
end

_handleRespite = function (snap_value, args)
    local game_id = args.game_id
    local table_id = args.table_id
    local self = args.self
    local instance = args.instance
    local mysql = args.mysql

    -- tcp: SNAP 1:0 5 10 12
    local value = {}
    value.player_id = snap_value[1]
    value.time_bought = snap_value[2]
    value.time_left   = snap_value[3]

    return value
end

_handleWantToStraddleNextRound = function (snap_value, args)
    local game_id = args.game_id
    local table_id = args.table_id
    local self = args.self
    local value = {}
    value.round = snap_value[1]
    return value
end

_handleBuyInsurance = function (snap_value, args)
    -- tcp: SNAP 1:0 14 
    local game_id = args.game_id
    local table_id = args.table_id
    local self = args.self
    local value = {}
    value.max_payment = snap_value[1]
    value.outs = string_split(snap_value[2], ":")
    if (snap_value[3] ~= "0") then
        value.outs_divided = string_split(snap_value[3], ":")
    else
        value.outs_divided = {}
    end

    value.opponent = {}
    
    local opponent = string_split(snap_value[4], "-")

    for i= 1, table.getn(opponent) do
        local cards = string_split(opponent[i],":")
        local opponent_val = {}
        opponent_val.seat = table.remove(cards, 1)
        opponent_val.outs_amount = table.remove(cards, 1)
        opponent_val.hole = cards
        value.opponent[i] = opponent_val
    end

    cc.printdebug("_handleBuyInsurance called")
    return value
end

_handleInsuranceBenefits = function (snap_value, args)
    -- tcp: SNAP 1:0 0x15
    
    cc.printdebug("_handleInsuranceBenefits called")
    local game_id = args.game_id
    local table_id = args.table_id
    local self = args.self
    local value = {}
    value.benefits = snap_value[1];

    local instance = args.instance
    local mysql = args.mysql
    local redis = args.redis
    local sql = "INSERT INTO insurance_benefits (user_id, game_id, table_id, hand_id, benefits) " 
             .. "VALUES (" .. instance:getCid() .. ", " 
             .. game_id .. ", " 
             .. table_id .. ", " 
             .. self:_getHand(instance, redis, game_id, table_id) .. ", "
             .. value.benefits .. ") "

    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.printdebug("db err: %s", err)
        value.state = Constants.Error.MysqlError
        value.msg = "数据库错误: " .. err
        return value
    end
    return value
end

local _snapHandler = {
    [Constants.Snap.SnapType.SnapGameState]           = _handleGameState,
    [Constants.Snap.SnapType.SnapTable]               = _handleTable,
    [Constants.Snap.SnapType.SnapCards]               = _handleCards,
    [Constants.Snap.SnapType.SnapWinAmount]           = _handleWinAmount,
    [Constants.Snap.SnapType.SnapStakeChange]         = _handleStakeChange,
    [Constants.Snap.SnapType.SnapWinPot]              = _handleWinPot,
    [Constants.Snap.SnapType.SnapOddChips]            = _handleOddChips,
    [Constants.Snap.SnapType.SnapPlayerAction]        = _handlePlayerAction,
    [Constants.Snap.SnapType.SnapPlayerCurrent]       = _handlePlayerCurrent,
    [Constants.Snap.SnapType.SnapPlayerShow]          = _handlePlayerShow,
    [Constants.Snap.SnapType.SnapRespite]             = _handleRespite,
    [Constants.Snap.SnapType.SnapWantToStraddleNextRound] = _handleWantToStraddleNextRound,
    [Constants.Snap.SnapType.SnapBuyInsurance]        = _handleBuyInsurance,
    [Constants.Snap.SnapType.SnapInsuranceBenefits]   = _handleInsuranceBenefits,
}

Snap.snapHandler = _snapHandler

function Snap:handleSNAP(parts, args)
    if tonumber(parts[1]) ~= nil then
        table.remove(parts, 1)
    end

    local result = {state_type = "snap_state", data = {}}

    --tcp: SNAP 1:0 1 <1>   ---SNAP game_id:table_id snap_type snap_value
    local game_table = string_split(parts[2], ":")
    result.data.game_id = game_table[1]
    result.data.table_id = game_table[2]
    local snap_type = parts[3]
    result.data.snap_type = snap_type

    if not self.snapHandler[tonumber(snap_type)] then
        result.data.state = 3
        result.data.msg = "unknown snap type: " .. snap_type
        return result
    end

    args.game_id = result.data.game_id
    args.table_id = result.data.table_id
    args.self = self
    result.data.snap_value = self.snapHandler[tonumber(snap_type)](table.subrange(parts, 4, #parts), args)
    
    local inspect = require("inspect")

    return result
end

return Snap
