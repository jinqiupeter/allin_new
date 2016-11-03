local _M = {}

-- redis channels
_M.TABLE_CHAT_CHANNEL_PREFIX            = "_TABLE_CHAT_"

_M.MESSAGE_FORMAT_JSON                  = "json"


_M.Snap = {
    SnapType = {
        SnapGameState       = 0x01,
        SnapTable           = 0x02,
        SnapCards           = 0x03,
        SnapWinAmount       = 0x06,
        SnapWinPot          = 0x07,
        SnapOddChips        = 0x08,
        SnapPlayerAction    = 0x0a,
        SnapPlayerCurrent   = 0x0b,
        SnapPlayerShow      = 0x0c,
        SnapRespite         = 0x11,
        SnapStakeChange     = 0x12,
        SnapWantToStraddleNextRound = 0x13,
        SnapBuyInsurance    = 0x14,
        SnapInsuranceBenefits = 0x15
    },

    GameState = {
        SnapGameStateStart      = 0x01,
        SnapGameStateEnd        = 0x02,
        SnapGameStateSeat       = 0x03, 
        SnapGameStateNewHand    = 0x04,
        SnapGameStateBlinds     = 0x05,
        SnapGameStateWon        = 0x10,
        SnapGameStateBroke      = 0x11,
        SnapGameStateExpire     = 0x12,
        SnapGameStatePause      = 0x13,
        SnapGameStateResume     = 0x14,
        SnapGameStateTableSuspend = 0x15,
        SnapGameStateTableResume = 0x16
    },

    TableState = {
        GameStart       = 0,
        ElectDealer     = 1,
        NewRound        = 2,
        Blinds          = 3,
        Betting         = 4,
        BettingEnd      = 5, -- pseudo-state 
        AskShow         = 6,
        AllFolded       = 7,
        Showdown        = 8,
        EndRound        = 9,
        Suspend         = 10,
        Resume          = 11
    },

    CardType = {
        SnapCardsHole       = 0x1,
        SnapCardsFlop       = 0x2,
        SnapCardsTurn       = 0x3,
        SnapCardsRiver      = 0x4,
        SnapCardsCommunity  = 0x5,
    },

    PlayerAction = {
        SnapPlayerActionFolded  = 0x01,  
        SnapPlayerActionChecked = 0x02, 
        SnapPlayerActionCalled  = 0x03,
        SnapPlayerActionBet     = 0x04,
        SnapPlayerActionRaised  = 0x05,
        SnapPlayerActionAllin   = 0x06,
    },

    BetRound = {
        Preflop     = 0,
        Flop        = 1,
        Turn        = 2,
        River       = 3
    },
}

_M.OK = 0
_M.Error = {
    ArgumentNotSet      = 1,
    AllinError          = 2,
    RedisError          = 3,
    MysqlError          = 4,
    DataBaseError       = 5,
    PermissionDenied    = 6,
    NotExist            = 7,
    LogicError          = 8,
    LeanCloudError      = 9,
    InternalError       = 100
}

_M.Message = {
    AllinMessage        = 1
}

_M.GameMode = {
    GameModeRingGame    = 0x01, -- Cash game
    GameModeFreezeOut   = 0x02, -- MTT
    GameModeSNG         = 0x03  -- SNG
}

_M.GameState = {
    GameStateWaiting     = 0x01, 
    GameStateStarted   = 0x02,
    GameStateEnded         = 0x03  
}

_M.Limit = {
    ListClubLimit = 50,
    ListGameLimit = 20,
    ListClubApplicationListLimit = 20,
    ListDataLimit = 20,
    ListFriendRequestLimit = 20,
    ListFriendsLimit = 20,
    ListUnreadMessage = 20,
}

_M.Config = {
    GoldToStakeRate = 10
}

_M.IAP_SANDBOX_URL                  = "https://sandbox.itunes.apple.com/verifyReceipt"
_M.IAP_BUY_URL                      = "https://buy.itunes.apple.com/verifyReceipt"

_M.MessageType = {
    Club_LevelExpiring              = 1,
    Club_Annoucement                = 2,
    Club_NewMemberApply             = 3,
    Club_NewMemberHandled           = 4,
    Club_TransferFunds              = 5,
    Club_JoinGameApply              = 6,
    Club_JoinGameHandled            = 7,
    
    Personal_PrivateMessage         = 8,
    Personal_FriendRequest          = 9,
    Personal_FriendHandled          = 10,

    System_Broadcase                = 11,
    Game_RebuyApplied               = 12,
    Game_RebuyHandled               = 13,
}

_M.ErrorMsg = {
    FailedToBuy                     = "买入失败",
    FailedToBuyAnimation            = "购买表情失败",
    FailedToBuyTimeout              = "购买加时失败",
    GoldNotEnough                   = "您的剩余金币(%s) 不足以支付本次买入(%s), 请充值！",
    GoldNotEnoughAnimation          = "您的剩余金币(%s) 不足以购买本表情(%s金币), 请充值！",
    GoldNotEnoughTime               = "您的剩余金币(%s) 不足以购买本次加时(%s金币), 请充值！",
    GoldNotEnoughClubFunds          = "您的剩余金币(%s) 不足以增加基金(%s金币), 请充值！",
    GoldNotEnoughClubMonthlyFee     = "您的剩余金币(%s) 不足以支付本次购买(%s金币), 请充值！",
    WrongPassword                   = "密码错误，请确认密码是否正确",
    GameNotStarted                  = "游戏尚未开始",
    GameNotFound                    = "游戏不存在",
    RespiteCountExceeded            = "一次下注最多能购买两次加时",
    RebuyNotAllowed                 = "本游戏不允许Rebuy",
    RebuyLimitExceeded              = "您已Rebuy达到%s次，不能再Rebuy了",
    RebuyMaxExceeded                = "超过单次最大Rebuy额度",
    RebuyNotAllowedInCurrentLevel   = "当前级别(%s)不再允许Rebuy",
    StillHaveStake                  = "您当前还有剩余筹码%s，筹码不为零时不允许Rebuy",
    CannotStraddle                  = "不允许Straddle",
    CannotBuyInsurance              = "当前阶段不允许购买保险",
    MaxAdminExceeded                = "管理员人数（%s）已达到当前俱乐部级别（%s）的最大管理员人数限制，请升级俱乐部!",
    MaxMembersExceeded              = "俱乐部人数（%s）已达到当前俱乐部级别（%s）的最大人数限制，请升级俱乐部!",
    MaxClubExceeded                 = "您当前创建的俱乐部个数（%s）已经达到最大限制（%s）!",
    CurrentMembersMoreThanTarget    = "当前俱乐部人数（%s）大于目标级别（%s）允许的最大人数（%s），请删除部分成员后重试",
    YouAreNotAdmin                  = "您不是该俱乐部的管理员，无法进行此次操作！",
    YouAreNotOwner                  = "您不是该俱乐部的创建者，无法进行此次操作！",
    FundsNotEnough                  = "俱乐部剩余基金（%s）不足，请联系俱乐部创建人充值基金后操作！",
    StakeLeftNotEnough              = "您的剩余筹码(%s)小于当前牌局大盲(%s)，请Rebuy!",
}

return table.readonly(_M)
