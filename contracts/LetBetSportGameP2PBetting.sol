pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import './LetBetCreditManager.sol';

contract LetBetSportGameP2PBetting is Ownable {

    using SafeMath for uint256;
    
    enum BetOption { UNKNOWN, WIN, DRAW, LOSE }
    enum GameResult { UNKNOWN, WIN, DRAW, LOSE, CANCEL }
    enum GameState { UNKNOWN, IN_BET, IN_GAME, END }
    
    struct Player {
        address addr;
        BetOption betOption;
        uint256 betAmount;
        uint256 winAmount;
    }

    struct Game {
        uint256 gameId;
        uint16[2] gameScore;
        GameResult result;
        GameState status;
        
        Player[] betWinPlayers;
        Player[] betDrawPlayers;
        Player[] betLosePlayers;
        uint256 betWinTotal;
        uint256 betDrawTotal;
        uint256 betLoseTotal;
    }
    
    address public creditManager; // address of credit manager
    
    mapping (uint256 => Game) public games;
    
    uint256[] public gameList;
    
    event RefundAll(uint256 gameId);
    event PerformBetWithPlayer(uint256 gameId, uint8 result);
    event BetWithPlayer(address player, uint256 gameId, uint8 option, uint256 amount);
    
    function LetBetSportGameP2PBetting(address _creditManager) public {
        creditManager = _creditManager;
    }
    
    function getInfo(uint256 _gameId) public constant returns (uint16[2] gameScore, uint8 result, uint8 status, uint numOfBetWinPlayers, uint256 betWinTotal, uint numOfBetDrawPlayers, uint256 betDrawTotal, uint numOfBetLosePlayers, uint256 betLoseTotal) {
        Game memory game = games[_gameId];
        return (game.gameScore, uint8(game.result), uint8(game.status), game.betWinPlayers.length, game.betWinTotal, game.betDrawPlayers.length, game.betDrawTotal, game.betLosePlayers.length, game.betLoseTotal);
    }
    
    function getPlayerBetWinWithPlayer(uint256 _gameId, uint _index) public constant returns (address addr, uint8 betOption, uint256 betAmount, uint256 winAmount) {
        require(_index < games[_gameId].betWinPlayers.length);
        
        Player memory player = games[_gameId].betWinPlayers[_index];
        return (player.addr, uint8(player.betOption), player.betAmount, player.winAmount);
    }
    
    function getPlayerBetDrawWithPlayer(uint256 _gameId, uint _index) public constant returns (address addr, uint8 betOption, uint256 betAmount, uint256 winAmount) {
        require(_index < games[_gameId].betDrawPlayers.length);
        
        Player memory player = games[_gameId].betDrawPlayers[_index];
        return (player.addr, uint8(player.betOption), player.betAmount, player.winAmount);
    }
    
    function getPlayerBetLoseWithPlayer(uint256 _gameId, uint _index) public constant returns (address addr, uint8 betOption, uint256 betAmount, uint256 winAmount) {
        require(_index < games[_gameId].betLosePlayers.length);
        
        Player memory player = games[_gameId].betLosePlayers[_index];
        return (player.addr, uint8(player.betOption), player.betAmount, player.winAmount);
    }
    
    function getGameList() public constant returns (uint256[] gameIds) {
        return gameList;
    }
    
    function start(uint256 _gameId) onlyOwner public returns (bool success) {
        require(games[_gameId].status != GameState.END);
        
        if (games[_gameId].status == GameState.UNKNOWN) {
            games[_gameId].gameId        = _gameId;
            games[_gameId].gameScore     = [0, 0];
            games[_gameId].result        = GameResult.UNKNOWN;
            games[_gameId].status        = GameState.IN_BET;
            
            delete games[_gameId].betWinPlayers;
            delete games[_gameId].betDrawPlayers;
            delete games[_gameId].betLosePlayers;
            games[_gameId].betWinTotal  = 0;
            games[_gameId].betDrawTotal = 0;
            games[_gameId].betLoseTotal = 0;
            
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
            if (!performBetWithPlayer(_gameId, _result)) revert();
        }
        
        games[_gameId].status = GameState.END;
        
        return true;
    }
    
    function refundAll(uint256 _gameId) internal returns (bool success) {
        uint i = 0;
        LetBetCreditManager lbcm = LetBetCreditManager(creditManager);
        
        for (i = 0; i < games[_gameId].betWinPlayers.length; ++i) {
            if (!lbcm.increaseCredit(games[_gameId].betWinPlayers[i].addr, games[_gameId].betWinPlayers[i].betAmount)) revert();
            games[_gameId].betWinPlayers[i].winAmount = games[_gameId].betWinPlayers[i].betAmount;
        }
        
        for (i = 0; i < games[_gameId].betDrawPlayers.length; ++i) {
            if (!lbcm.increaseCredit(games[_gameId].betDrawPlayers[i].addr, games[_gameId].betDrawPlayers[i].betAmount)) revert();
            games[_gameId].betDrawPlayers[i].winAmount = games[_gameId].betDrawPlayers[i].betAmount;
        }
        
        for (i = 0; i < games[_gameId].betLosePlayers.length; ++i) {
            if (!lbcm.increaseCredit(games[_gameId].betLosePlayers[i].addr, games[_gameId].betLosePlayers[i].betAmount)) revert();
            games[_gameId].betLosePlayers[i].winAmount = games[_gameId].betLosePlayers[i].betAmount;
        }
        
        RefundAll(_gameId);
        
        return true;
    }
    
    function performBetWithPlayer(uint256 _gameId, uint8 _result) internal returns (bool success) {
        uint i = 0;
        uint256 total = 0;
        uint256 amount = 0;
        GameResult result = GameResult(_result);
        LetBetCreditManager lbcm = LetBetCreditManager(creditManager);
        
        if (result == GameResult.WIN) {
            total = games[_gameId].betDrawTotal.add(games[_gameId].betLoseTotal);
            for (i = 0; i < games[_gameId].betWinPlayers.length; ++i) {
                amount = games[_gameId].betWinPlayers[i].betAmount;
                amount = amount.add(amount.mul(total).div(games[_gameId].betWinTotal));
                if (!lbcm.increaseCredit(games[_gameId].betWinPlayers[i].addr, amount)) revert();
                games[_gameId].betWinPlayers[i].winAmount = amount;
            }
        } else if (result == GameResult.DRAW) {
            total = games[_gameId].betWinTotal.add(games[_gameId].betLoseTotal);
            for (i = 0; i < games[_gameId].betDrawPlayers.length; ++i) {
                amount = games[_gameId].betDrawPlayers[i].betAmount;
                amount = amount.add(amount.mul(total).div(games[_gameId].betDrawTotal));
                if (!lbcm.increaseCredit(games[_gameId].betDrawPlayers[i].addr, amount)) revert();
                games[_gameId].betDrawPlayers[i].winAmount = amount;
            }
        } else if (result == GameResult.LOSE) {
            total = games[_gameId].betWinTotal.add(games[_gameId].betDrawTotal);
            for (i = 0; i < games[_gameId].betLosePlayers.length; ++i) {
                amount = games[_gameId].betLosePlayers[i].betAmount;
                amount = amount.add(amount.mul(total).div(games[_gameId].betLoseTotal));
                if (!lbcm.increaseCredit(games[_gameId].betLosePlayers[i].addr, amount)) revert();
                games[_gameId].betLosePlayers[i].winAmount = amount;
            }
        }
        
        PerformBetWithPlayer(_gameId, _result);
        
        return true;
    }
    
    function closeBet(uint256 _gameId) onlyOwner public returns (bool success) {
        require(games[_gameId].status == GameState.IN_BET);
        
        games[_gameId].status = GameState.IN_GAME;
        
        return true;
    }
    
    function betWithPlayer(uint256 _gameId, uint8 _betOption, uint256 _betAmount) public returns (bool success) {
        require(games[_gameId].status == GameState.IN_BET);
        require(_betOption >= uint8(BetOption.WIN) && _betOption <= uint8(BetOption.LOSE));
        require(_betAmount > 0);
        
        LetBetCreditManager lbcm = LetBetCreditManager(creditManager);
        
        uint256 currentCredit = lbcm.getCredit(msg.sender);
        if (currentCredit < _betAmount) revert();
        
        if (!lbcm.decreaseCredit(msg.sender, _betAmount)) revert();
        
        BetOption betOption = BetOption(_betOption);
        if (betOption == BetOption.WIN) {
            games[_gameId].betWinPlayers.push(Player(msg.sender, betOption, _betAmount, 0));
            games[_gameId].betWinTotal = games[_gameId].betWinTotal.add(_betAmount);
        } else if (betOption == BetOption.DRAW) {
            games[_gameId].betDrawPlayers.push(Player(msg.sender, betOption, _betAmount, 0));
            games[_gameId].betDrawTotal = games[_gameId].betDrawTotal.add(_betAmount);
        } else if (betOption == BetOption.LOSE) {
            games[_gameId].betLosePlayers.push(Player(msg.sender, betOption, _betAmount, 0));
            games[_gameId].betLoseTotal = games[_gameId].betLoseTotal.add(_betAmount);
        }
        
        BetWithPlayer(msg.sender, _gameId, _betOption, _betAmount);
        
        return true;
    }
    
}
