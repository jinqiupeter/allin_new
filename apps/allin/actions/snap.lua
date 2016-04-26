local Snap       = cc.class("Snap")
local Constants  = cc.import(".Constants", "..")

local string_split       = string.split
local _handleGameState, _handleTable, _handleCards, _handleWinAmount, _handleWinPot, _handleOddChips, _handlePlayerAction, _handlePlayerCurrent, _handlePlayerShow, _handleFoyer, _handleERR


-- to support playing more than one game, we need to put these info in a table
function Snap:_getHand (game_id, table_id)
    local inspect = require("inspect")
    local key = "" .. game_id .. "_" .. table_id
    if self.hands == nil then 
        return nil
    end
    
    return self.hands[key]
end

function Snap:_getDealer(game_id, table_id)
    if self.dealers == nil then 
        return nil
    end
    
    local key = "" .. game_id .. "_" .. table_id
    return self.dealers[key]
end

function Snap:_getBetRound(game_id, table_id)
    if self.bet_rounds == nil then 
        return nil
    end
    
    local key = "" .. game_id .. "_" .. table_id
    return self.bet_rounds[key]
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
    local mysql = instance:getMysql()
    local self = args.self

    local sql = ""
    if game_state == Constants.Snap.GameState.SnapGameStateNewHand then
        value.hand_no = snap_value[2]
        local key = "" .. game_id .. "_" .. table_id
        self.hands = {[key] = value.hand_no}
    elseif game_state == Constants.Snap.GameState.SnapGameStateBroke then
        value.broken_player_id = snap_value[2]
        value.broken_player_position = snap_value[3]  -- TODO: what does this mean?
    elseif game_state == Constants.Snap.GameState.SnapGameStateStart then
        -- record is inserted in _updateUserGameHistory 
        sql = " UPDATE user_game_history SET started_at = NOW() "
             .. " WHERE game_id = " .. game_id
             .. " AND user_id = " .. instance:getCid()
    elseif game_state == Constants.Snap.GameState.SnapGameStateEnd then
        sql = " UPDATE user_game_history SET ended_at = NOW() "
             .. " WHERE game_id = " .. game_id
             .. " AND user_id = " .. instance:getCid()
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
    local self = args.self

    -- table state and bet round
    local head = table.remove(snap_value, 1)  -- same as head = array.shift()
    local tmp = string_split(head, ":")
    local table_state = tonumber(tmp[1])
    value.table_state = table_state

    -- table chat support
    if table_state == Constants.Snap.TableState.NewRound then
    -- subscribe to table channel to receive table chat
        cc.printdebug("subscribing to table channel " .. Constants.TABLE_CHAT_CHANNEL_PREFIX .. tostring(game_id) .. "_" .. tostring(table_id))
        instance:subscribe(Constants.TABLE_CHAT_CHANNEL_PREFIX .. tostring(game_id) .. "_" .. tostring(table_id))
    elseif table_state == Constants.Snap.TableState.EndRound then
    -- unsubscribe
        instance:unsubscribe(Constants.TABLE_CHAT_CHANNEL_PREFIX .. tostring(game_id) .. "_" .. tostring(table_id))
    end
        
    local bet_round    = tmp[2]
    value.bet_round = bet_round
    local key = "" .. game_id .. "_" .. table_id
    self.bet_rounds = {[key] = value.bet_round}
    --[[ bet round:
    Not in bet round = -1
    Preflop     = 0,
    Flop        = 1,
    Turn        = 2,
    River       = 3
    --]]

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
        value.last_bet_player   = tmp[5]
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
            in_round = 0
        end
        local sit_out = 0
        if bit.band(0x02 ,tonumber(player_state)) > 0 then 
            sit_out = 0
        end
        local player_stake          = tmp[4]
        local player_stake          = tmp[4]
        local bet_amount            = tmp[5] -- bet amount
        local last_action           = tmp[6] -- 0: None, 1: ResetAction, 2: Check, 3: Fold, 4: Call, 5: Bet, 6: Raise, 7: Allin, 8: Show, 9: Muck, 10: Sitout, 11: Back
        local hole_cards            = tmp[7] or ""

        if (seat_no == value.dealer) then
            local key = "" .. game_id .. "_" .. table_id
            self.dealers = {[key] = player_id}
        end

        occupied_seats[i] = {seat_no = seat_no, player_id = player_id, in_round = in_round, sit_out = sit_out, player_stake = player_stake, bet_amount = bet_amount, last_action = last_action, hole_cards = hole_cards}

        head = table.remove(snap_value, 1)
        i = i + 1
    end
    value.occupied_seats = occupied_seats

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

    -- minimum bet amount
    value.minimus_bet = head

    return value
end

_handleCards = function (snap_value, args)
    -- tcp: SNAP 1:0 3 <1 Kc 3s>
    local instance = args.instance
    local mysql = instance:getMysql()
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

    cc.printdebug("cid: %s, dealer: %s", instance:getCid(), self:_getDealer(game_id, table_id))
    if tonumber(instance:getCid()) == tonumber(self:_getDealer(game_id, table_id)) then
        cc_sql = "INSERT INTO game_cc_cards (game_id, table_id, hand_id) " 
                .. "VALUES (" .. game_id .. ", " 
                .. table_id .. ", " 
                .. self:_getHand(game_id, table_id) .. ") "
                .. " ON DUPLICATE KEY UPDATE "

        if tonumber(card_type) == Constants.Snap.CardType.SnapCardsFlop then
            cc_sql = "INSERT INTO game_cc_cards (game_id, table_id, hand_id, flop_card) "
                .. "VALUES (" .. game_id .. ", " 
                .. table_id .. ", " 
                .. self:_getHand(game_id, table_id) .. ", "
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
                    .. self:_getHand(game_id, table_id) .. ", "
                    .. instance:getCid() .. ", "
                    .. instance:sqlQuote(table.concat(value.cards, " ")) .. ") "

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
    local mysql = instance:getMysql()

    local value = {}
    local player_id = snap_value[1]
    value.player_id = player_id

    -- snap_value[2] is reserved
    local amount_won = snap_value[3]
    value.amount_won = amount_won

    if tonumber(instance:getCid()) == tonumber(self:_getDealer(game_id, table_id)) then
        local sql = "INSERT INTO game_winners (game_id, table_id, hand_id, winner_id, amount_won) " 
                .. "VALUES (" .. game_id .. ", " 
                .. table_id .. ", " 
                .. self:_getHand(game_id, table_id) .. ", "
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

_handleWinPot = function (snap_value, args)
    -- tcp: SNAP 1:0 7 <1 0 120> ==><1=cid, 0=pot id, 120=amount received>
    local game_id = args.game_id
    local table_id = args.table_id
    local self = args.self
    local instance = args.instance
    local mysql = instance:getMysql()

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
    if tonumber(instance:getCid()) == tonumber(self:_getDealer(game_id, table_id)) then
        local sql = "INSERT INTO game_pot_dist (game_id, table_id, hand_id, user_id, pot_id, pot_type, amount_received) " 
                .. "VALUES (" .. game_id .. ", " 
                .. table_id .. ", " 
                .. self:_getHand(game_id, table_id) .. ", "
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
    local mysql = instance:getMysql()
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
    if tonumber(instance:getCid()) == tonumber(self:_getDealer(game_id, table_id)) then
        local sql = "INSERT INTO game_pot_dist (game_id, table_id, hand_id, user_id, pot_id, pot_type, amount_received) " 
                .. "VALUES (" .. game_id .. ", " 
                .. table_id .. ", " 
                .. self:_getHand(game_id, table_id) .. ", "
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
    local mysql = instance:getMysql()

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
                .. self:_getHand(game_id, table_id) .. ", "
                .. self:_getBetRound(game_id, table_id) .. ", "
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
    local mysql = instance:getMysql()

    -- tcp: SNAP 1:0 12 <0 Jh 4c 5c 2d Th 9c 9h> ==><0=cid, Jh 4c 5c 2d Th 9c 9h=player cards>
    local value = {}
    local player_id = table.remove(snap_value, 1)
    value.player_id = player_id

    -- snap_value[2] is reserved
    local cards = snap_value
    value.cards = cards

    return value
end

local _snapHandler = {
    [Constants.Snap.SnapType.SnapGameState]           = _handleGameState,
    [Constants.Snap.SnapType.SnapTable]               = _handleTable,
    [Constants.Snap.SnapType.SnapCards]               = _handleCards,
    [Constants.Snap.SnapType.SnapWinAmount]           = _handleWinAmount,
    [Constants.Snap.SnapType.SnapWinPot]              = _handleWinPot,
    [Constants.Snap.SnapType.SnapOddChips]            = _handleOddChips,
    [Constants.Snap.SnapType.SnapPlayerAction]        = _handlePlayerAction,
    [Constants.Snap.SnapType.SnapPlayerCurrent]       = _handlePlayerCurrent,
    [Constants.Snap.SnapType.SnapPlayerShow]          = _handlePlayerShow
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

    return result
end

return Snap
