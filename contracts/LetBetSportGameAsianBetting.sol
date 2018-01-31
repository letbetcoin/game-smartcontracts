pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import './LetBetCreditManager.sol';

contract LetBetSportGameAsianBetting is Ownable {

    using SafeMath for uint256;
    
    enum AsianBetOption { UNKNOWN, HOME, AWAY }
    enum GameResult { UNKNOWN, WIN, DRAW, LOSE, CANCEL }
    enum GameState { UNKNOWN, IN_BET, IN_GAME, END }
    
    struct AsianBetPlayer {
        address addr;
        AsianBetOption betOption;
        uint256 betAmount;
        uint256 winAmount;
        uint256 betTimestamp;
        
        int16[2] handicap;
        uint16[2] winRateHome;
        uint16[2] winRateAway;
    }
    
    struct Game {
        uint256 gameId;
        uint16[2] gameScore;
        GameResult result;
        GameState status;
        uint256 betLimit; // 0: no limit
        uint256 betTotalLimit; // 0: no limit
        uint256 beginTimestamp;
        
        int16[2][] handicap;
        uint16[2][] winRateHome;
        uint16[2][] winRateAway;
        AsianBetPlayer[] asianBetPlayers;
        uint256 asianBetTotal;
    }
    
    uint8 constant MAGIC_NUMBER = 4;
    
    address public creditManager; // address of credit manager
    
    mapping (uint256 => Game) public games;
    
    uint256[] public gameList;
    
    event RefundAll(uint256 gameId);
    event PerformAsianBet(uint256 gameId, uint16[2] gameScore);
    event BetWithAsianDealer(address player, uint256 gameId, uint8 option, uint256 amount, uint256 betTimestamp, int16[2] handicap, uint16[2] winRateHome, uint16[2] winRateAway);
    
    function LetBetSportGameAsianBetting(address _creditManager) public {
        creditManager = _creditManager;
    }
    
    function getInfo(uint256 _gameId) public constant returns (uint16[2] gameScore, uint8 result, uint8 status, uint256 betLimit, uint256 betTotalLimit, uint256 beginTimestamp, int16[2][] handicap, uint16[2][] winRateHome, uint16[2][] winRateAway, uint numOfAsianBetPlayers, uint256 asianBetTotal) {
        Game memory game = games[_gameId];
        return (game.gameScore, uint8(game.result), uint8(game.status), game.betLimit, game.betTotalLimit, game.beginTimestamp, game.handicap, game.winRateHome, game.winRateAway, game.asianBetPlayers.length, game.asianBetTotal);
    }
    
    function getPlayerAsianBet(uint256 _gameId, uint _index) public constant returns (address addr, uint8 betOption, uint256 betAmount, uint256 winAmount, uint256 betTimestamp, int16[2] handicap, uint16[2] winRateHome, uint16[2] winRateAway) {
        require(_index < games[_gameId].asianBetPlayers.length);
        
        AsianBetPlayer memory player = games[_gameId].asianBetPlayers[_index];
        return (player.addr, uint8(player.betOption), player.betAmount, player.winAmount, player.betTimestamp, player.handicap, player.winRateHome, player.winRateAway);
    }
    
    function getGameList() public constant returns (uint256[] gameIds) {
        return gameList;
    }
    
    function start(uint256 _gameId, uint256 _betLimit, uint256 _betTotalLimit, uint256 _beginTimestamp, int16[2][] _handicap, uint16[2][] _winRateHome, uint16[2][] _winRateAway) onlyOwner public returns (bool success) {
        require(games[_gameId].status != GameState.END);
        
        if (games[_gameId].status == GameState.UNKNOWN) {
            games[_gameId].gameId         = _gameId;
            games[_gameId].gameScore      = [0, 0];
            games[_gameId].result         = GameResult.UNKNOWN;
            games[_gameId].status         = GameState.IN_BET;
            games[_gameId].betLimit       = _betLimit;
            games[_gameId].betTotalLimit  = _betTotalLimit;
            games[_gameId].beginTimestamp = _beginTimestamp;
            
            games[_gameId].handicap    = _handicap;
            games[_gameId].winRateHome = _winRateHome;
            games[_gameId].winRateAway = _winRateAway;
            delete games[_gameId].asianBetPlayers;
            games[_gameId].asianBetTotal = 0;
            
            gameList.push(_gameId);
        }
        
        return true;
    }
    
    function end(uint256 _gameId, uint16[2] _gameScore, uint8 _result) onlyOwner public returns (bool success) {
        require(games[_gameId].status == GameState.IN_BET || games[_gameId].status == GameState.IN_GAME);
        require(_result >= uint8(GameResult.WIN) && _result <= uint8(GameResult.CANCEL));
        
        GameResult result = GameResult(_result);
        games[_gameId].gameScore = _gameScore;
        games[_gameId].result = result;
        
        if (result == GameResult.CANCEL) {
            if (!refundAll(_gameId)) revert();
        } else {
            if (!performAsianBet(_gameId, _gameScore)) revert();
        }
        
        games[_gameId].status = GameState.END;
        
        return true;
    }
    
    function refundAll(uint256 _gameId) internal returns (bool success) {
        uint i = 0;
        LetBetCreditManager lbcm = LetBetCreditManager(creditManager);
        
        for (i = 0; i < games[_gameId].asianBetPlayers.length; ++i) {
            if (!lbcm.increaseCredit(games[_gameId].asianBetPlayers[i].addr, games[_gameId].asianBetPlayers[i].betAmount)) revert();
            games[_gameId].asianBetPlayers[i].winAmount = games[_gameId].asianBetPlayers[i].betAmount;
        }
        
        RefundAll(_gameId);
        
        return true;
    }
    
    function performAsianBet(uint256 _gameId, uint16[2] _gameScore) internal returns (bool success) {
        uint i = 0;
        uint256 amount = 0;
        uint256 betAmount = 0;
        int16 handicapNatural = 0;
        int16 handicapDecimal = 0;
        int16 delta = 0;
        LetBetCreditManager lbcm = LetBetCreditManager(creditManager);
        
        Game memory game = games[_gameId];
        for (i = 0; i < game.asianBetPlayers.length; ++i) {
            handicapNatural = game.asianBetPlayers[i].handicap[0] / MAGIC_NUMBER;
            handicapDecimal = game.asianBetPlayers[i].handicap[0] % MAGIC_NUMBER;
            if (handicapDecimal == 3) { // handicap 0.75
                handicapNatural = handicapNatural + 1;
            } else if (handicapDecimal == -3) { // handicap -0.75
                handicapNatural = handicapNatural - 1;
            }
            delta = handicapNatural + int16(_gameScore[0]) - int16(_gameScore[1]);
            amount = 0;
            betAmount = game.asianBetPlayers[i].betAmount;
            
            if (delta > 0 && game.asianBetPlayers[i].betOption == AsianBetOption.HOME) { // home win -> bet home win
                amount = betAmount.mul(game.asianBetPlayers[i].winRateHome[0]).div(game.asianBetPlayers[i].winRateHome[1]);
            } else if (delta < 0 && game.asianBetPlayers[i].betOption == AsianBetOption.AWAY) { // away win -> bet away win
                amount = betAmount.mul(game.asianBetPlayers[i].winRateAway[0]).div(game.asianBetPlayers[i].winRateAway[1]);
            } else if (delta == 0) { // draw
                if (handicapDecimal == 0) { // handicap 0 -> stake refund
                    amount = betAmount;
                } else if (handicapDecimal == 2 && game.asianBetPlayers[i].betOption == AsianBetOption.HOME) { // handicap 0.5 -> bet home win
                    amount = betAmount.mul(game.asianBetPlayers[i].winRateHome[0]).div(game.asianBetPlayers[i].winRateHome[1]);
                } else if (handicapDecimal == -2 && game.asianBetPlayers[i].betOption == AsianBetOption.AWAY) { // handicap -0.5 -> bet away win
                    amount = betAmount.mul(game.asianBetPlayers[i].winRateAway[0]).div(game.asianBetPlayers[i].winRateAway[1]);
                } else if (handicapDecimal == 1 || handicapDecimal == -3) { // handicap 0.25, -0.75 -> bet home half win, bet away half lose
                    if (game.asianBetPlayers[i].betOption == AsianBetOption.HOME) {
                        amount = betAmount.add(betAmount.mul(game.asianBetPlayers[i].winRateHome[0] - game.asianBetPlayers[i].winRateHome[1]).div(game.asianBetPlayers[i].winRateHome[1] * 2));
                    } else if (game.asianBetPlayers[i].betOption == AsianBetOption.AWAY) {
                        amount = betAmount.div(2);
                    }
                } else if (handicapDecimal == 3 || handicapDecimal == -1) { // handicap 0.75, -0.25 -> bet home half lose, bet away half win
                    if (game.asianBetPlayers[i].betOption == AsianBetOption.HOME) {
                        amount = betAmount.div(2);
                    } else if (game.asianBetPlayers[i].betOption == AsianBetOption.AWAY) {
                        amount = betAmount.add(betAmount.mul(game.asianBetPlayers[i].winRateAway[0] - game.asianBetPlayers[i].winRateAway[1]).div(game.asianBetPlayers[i].winRateAway[1] * 2));
                    }
                }
            }
            
            if (amount > 0) {
                if (!lbcm.increaseCredit(game.asianBetPlayers[i].addr, amount)) revert();
                game.asianBetPlayers[i].winAmount = amount;
            }
        }
        
        PerformAsianBet(_gameId, _gameScore);
        
        return true;
    }
    
    function closeBet(uint256 _gameId) onlyOwner public returns (bool success) {
        require(games[_gameId].status == GameState.IN_BET);
        
        games[_gameId].status = GameState.IN_GAME;
        
        return true;
    }
    
    function setBeginTimestamp(uint256 _gameId, uint256 _beginTimestamp) onlyOwner public returns (bool success) {
        require(games[_gameId].status == GameState.IN_BET);
        
        games[_gameId].beginTimestamp = _beginTimestamp;
        
        return true;
    }
    
    function setAsianBetRate(uint256 _gameId, int16[2][] _handicap, uint16[2][] _winRateHome, uint16[2][] _winRateAway) onlyOwner public returns (bool success) {
        require(games[_gameId].status == GameState.IN_BET || games[_gameId].status == GameState.IN_GAME);
        require(_handicap.length == _winRateHome.length && _handicap.length == _winRateAway.length);
        
        games[_gameId].handicap    = _handicap;
        games[_gameId].winRateHome = _winRateHome;
        games[_gameId].winRateAway = _winRateAway;
        
        return true;
    }
    
    function setBetLimit(uint256 _gameId, uint256 _betLimit, uint256 _betTotalLimit) onlyOwner public returns (bool success) {
        require(games[_gameId].status == GameState.IN_BET || games[_gameId].status == GameState.IN_GAME);
        
        games[_gameId].betLimit      = _betLimit;
        games[_gameId].betTotalLimit = _betTotalLimit;
        
        return true;
    }
        
    function betWithAsianDealer(uint256 _gameId, uint8 _betOption, uint256 _betAmount, uint _handicapIndex) public returns (bool success) {
        require(games[_gameId].status == GameState.IN_BET);
        require(now < games[_gameId].beginTimestamp);
        require(games[_gameId].handicap.length == games[_gameId].winRateHome.length && games[_gameId].handicap.length == games[_gameId].winRateAway.length);
        require(_handicapIndex < games[_gameId].handicap.length && games[_gameId].handicap[_handicapIndex][1] == MAGIC_NUMBER && games[_gameId].winRateHome[_handicapIndex][1] > 0 && games[_gameId].winRateAway[_handicapIndex][1] > 0);
        require(_betOption >= uint8(AsianBetOption.HOME) && _betOption <= uint8(AsianBetOption.AWAY));
        require(_betAmount > 0);
        require(games[_gameId].betLimit == 0 || _betAmount <= games[_gameId].betLimit);
        require(games[_gameId].betTotalLimit == 0 || games[_gameId].asianBetTotal.add(_betAmount) <= games[_gameId].betTotalLimit);
        
        LetBetCreditManager lbcm = LetBetCreditManager(creditManager);
        
        if (lbcm.getCredit(msg.sender) < _betAmount) revert();
        
        if (!lbcm.decreaseCredit(msg.sender, _betAmount)) revert();
        
        games[_gameId].asianBetPlayers.push(AsianBetPlayer(msg.sender, AsianBetOption(_betOption), _betAmount, 0, now, games[_gameId].handicap[_handicapIndex], games[_gameId].winRateHome[_handicapIndex], games[_gameId].winRateAway[_handicapIndex]));
        games[_gameId].asianBetTotal = games[_gameId].asianBetTotal.add(_betAmount);
        
        BetWithAsianDealer(msg.sender, _gameId, _betOption, _betAmount, now, games[_gameId].handicap[_handicapIndex], games[_gameId].winRateHome[_handicapIndex], games[_gameId].winRateAway[_handicapIndex]);
        
        return true;
    }
    
}
