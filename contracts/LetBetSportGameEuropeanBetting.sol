pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import './LetBetCreditManager.sol';

contract LetBetSportGameEuropeanBetting is Ownable {

    using SafeMath for uint256;
    
    enum EuropeanBetOption { UNKNOWN, WIN, DRAW, LOSE }
    enum GameResult { UNKNOWN, WIN, DRAW, LOSE, CANCEL }
    enum GameState { UNKNOWN, IN_BET, IN_GAME, END }
    
    struct EuropeanBetPlayer {
        address addr;
        EuropeanBetOption betOption;
        uint256 betAmount;
        uint256 winAmount;
        uint256 betTimestamp;
        
        uint16[2] winRate;
        uint16[2] drawRate;
        uint16[2] loseRate;
    }
    
    struct Game {
        uint256 gameId;
        uint16[2] gameScore;
        GameResult result;
        GameState status;
        uint256 betLimit; // 0: no limit
        uint256 betTotalLimit; // 0: no limit
        uint256 beginTimestamp;
        
        uint16[2] winRate;
        uint16[2] drawRate;
        uint16[2] loseRate;
        EuropeanBetPlayer[] europeanBetPlayers;
        uint256 europeanBetTotal;
    }
    
    address public creditManager; // address of credit manager
    
    mapping (uint256 => Game) public games;
    
    uint256[] public gameList;
    
    event RefundAll(uint256 gameId);
    event PerformEuropeanBet(uint256 gameId, uint8 result);
    event BetWithEuropeanDealer(address player, uint256 gameId, uint8 option, uint256 amount, uint256 betTimestamp, uint16[2] winRate, uint16[2] drawRate, uint16[2] loseRate);
    
    function LetBetSportGameEuropeanBetting(address _creditManager) public {
        creditManager = _creditManager;
    }
    
    function getInfo(uint256 _gameId) public constant returns (uint16[2] gameScore, uint8 result, uint8 status, uint256 betLimit, uint256 betTotalLimit, uint256 beginTimestamp, uint16[2] winRate, uint16[2] drawRate, uint16[2] loseRate, uint numOfEuropeanBetPlayers, uint256 europeanBetTotal) {
        Game memory game = games[_gameId];
        return (game.gameScore, uint8(game.result), uint8(game.status), game.betLimit, game.betTotalLimit, game.beginTimestamp, game.winRate, game.drawRate, game.loseRate, game.europeanBetPlayers.length, game.europeanBetTotal);
    }
    
    function getPlayerEuropeanBet(uint256 _gameId, uint _index) public constant returns (address addr, uint8 betOption, uint256 betAmount, uint256 winAmount, uint256 betTimestamp, uint16[2] winRate, uint16[2] drawRate, uint16[2] loseRate) {
        require(_index < games[_gameId].europeanBetPlayers.length);
        
        EuropeanBetPlayer memory player = games[_gameId].europeanBetPlayers[_index];
        return (player.addr, uint8(player.betOption), player.betAmount, player.winAmount, player.betTimestamp, player.winRate, player.drawRate, player.loseRate);
    }
    
    function getGameList() public constant returns (uint256[] gameIds) {
        return gameList;
    }
    
    function start(uint256 _gameId, uint256 _betLimit, uint256 _betTotalLimit, uint256 _beginTimestamp, uint16[2] _winRate, uint16[2] _drawRate, uint16[2] _loseRate) onlyOwner public returns (bool success) {
        require(games[_gameId].status != GameState.END);
        
        if (games[_gameId].status == GameState.UNKNOWN) {
            games[_gameId].gameId         = _gameId;
            games[_gameId].gameScore      = [0, 0];
            games[_gameId].result         = GameResult.UNKNOWN;
            games[_gameId].status         = GameState.IN_BET;
            games[_gameId].betLimit       = _betLimit;
            games[_gameId].betTotalLimit  = _betTotalLimit;
            games[_gameId].beginTimestamp = _beginTimestamp;
            
            games[_gameId].winRate  = _winRate;
            games[_gameId].drawRate = _drawRate;
            games[_gameId].loseRate = _loseRate;
            delete games[_gameId].europeanBetPlayers;
            games[_gameId].europeanBetTotal = 0;
            
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
            if (!performEuropeanBet(_gameId, _result)) revert();
        }
        
        games[_gameId].status = GameState.END;
        
        return true;
    }
    
    function refundAll(uint256 _gameId) internal returns (bool success) {
        uint i = 0;
        LetBetCreditManager lbcm = LetBetCreditManager(creditManager);
        
        for (i = 0; i < games[_gameId].europeanBetPlayers.length; ++i) {
            if (!lbcm.increaseCredit(games[_gameId].europeanBetPlayers[i].addr, games[_gameId].europeanBetPlayers[i].betAmount)) revert();
            games[_gameId].europeanBetPlayers[i].winAmount = games[_gameId].europeanBetPlayers[i].betAmount;
        }
        
        RefundAll(_gameId);
        
        return true;
    }
    
    function performEuropeanBet(uint256 _gameId, uint8 _result) internal returns (bool success) {
        uint i = 0;
        uint256 amount = 0;
        EuropeanBetOption result = EuropeanBetOption(_result);
        LetBetCreditManager lbcm = LetBetCreditManager(creditManager);
        
        for (i = 0; i < games[_gameId].europeanBetPlayers.length; ++i) {
            if (games[_gameId].europeanBetPlayers[i].betOption == result) {
                amount = 0;
                
                if (result == EuropeanBetOption.WIN) {
                    amount = games[_gameId].europeanBetPlayers[i].betAmount.mul(games[_gameId].europeanBetPlayers[i].winRate[0]).div(games[_gameId].europeanBetPlayers[i].winRate[1]);
                } else if (result == EuropeanBetOption.DRAW) {
                    amount = games[_gameId].europeanBetPlayers[i].betAmount.mul(games[_gameId].europeanBetPlayers[i].drawRate[0]).div(games[_gameId].europeanBetPlayers[i].drawRate[1]);
                } else if (result == EuropeanBetOption.LOSE) {
                    amount = games[_gameId].europeanBetPlayers[i].betAmount.mul(games[_gameId].europeanBetPlayers[i].loseRate[0]).div(games[_gameId].europeanBetPlayers[i].loseRate[1]);
                }
                
                if (amount > 0) {
                    if (!lbcm.increaseCredit(games[_gameId].europeanBetPlayers[i].addr, amount)) revert();
                    games[_gameId].europeanBetPlayers[i].winAmount = amount;
                }
            }
        }
        
        PerformEuropeanBet(_gameId, _result);
        
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
    
    function setEuropeanBetRate(uint256 _gameId, uint16[2] _winRate, uint16[2] _drawRate, uint16[2] _loseRate) onlyOwner public returns (bool success) {
        require(games[_gameId].status == GameState.IN_BET || games[_gameId].status == GameState.IN_GAME);
        require(_winRate[1] > 0 && _drawRate[1] > 0 && _loseRate[1] > 0);
        
        games[_gameId].winRate  = _winRate;
        games[_gameId].drawRate = _drawRate;
        games[_gameId].loseRate = _loseRate;
        
        return true;
    }
    
    function setBetLimit(uint256 _gameId, uint256 _betLimit, uint256 _betTotalLimit) onlyOwner public returns (bool success) {
        require(games[_gameId].status == GameState.IN_BET || games[_gameId].status == GameState.IN_GAME);
        
        games[_gameId].betLimit      = _betLimit;
        games[_gameId].betTotalLimit = _betTotalLimit;
        
        return true;
    }
    
    function betWithEuropeanDealer(uint256 _gameId, uint8 _betOption, uint256 _betAmount) public returns (bool success) {
        require(games[_gameId].status == GameState.IN_BET);
        require(now < games[_gameId].beginTimestamp);
        require(games[_gameId].winRate[1] > 0 && games[_gameId].drawRate[1] > 0 && games[_gameId].loseRate[1] > 0);
        require(_betOption >= uint8(EuropeanBetOption.WIN) && _betOption <= uint8(EuropeanBetOption.LOSE));
        require(_betAmount > 0);
        require(games[_gameId].betLimit == 0 || _betAmount <= games[_gameId].betLimit);
        require(games[_gameId].betTotalLimit == 0 || games[_gameId].europeanBetTotal.add(_betAmount) <= games[_gameId].betTotalLimit);
        
        LetBetCreditManager lbcm = LetBetCreditManager(creditManager);
        
        uint256 currentCredit = lbcm.getCredit(msg.sender);
        if (currentCredit < _betAmount) revert();
        
        if (!lbcm.decreaseCredit(msg.sender, _betAmount)) revert();
        
        games[_gameId].europeanBetPlayers.push(EuropeanBetPlayer(msg.sender, EuropeanBetOption(_betOption), _betAmount, 0, now, games[_gameId].winRate, games[_gameId].drawRate, games[_gameId].loseRate));
        games[_gameId].europeanBetTotal = games[_gameId].europeanBetTotal.add(_betAmount);
        
        BetWithEuropeanDealer(msg.sender, _gameId, _betOption, _betAmount, now, games[_gameId].winRate, games[_gameId].drawRate, games[_gameId].loseRate);
        
        return true;
    }
    
}
