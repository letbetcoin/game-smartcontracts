pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import './LetBetCreditManager.sol';

contract LetBetSportGameOverUnderBetting is Ownable {

    using SafeMath for uint256;
    
    enum OUBetOption { UNKNOWN, OVER, UNDER }
    enum GameResult { UNKNOWN, WIN, DRAW, LOSE, CANCEL }
    enum GameState { UNKNOWN, IN_BET, IN_GAME, END }
    
    struct OUBetPlayer {
        address addr;
        OUBetOption betOption;
        uint256 betAmount;
        uint256 winAmount;
        
        uint16[2] ouRate;
        uint16[2] winRateOver;
        uint16[2] winRateUnder;
    }
    
    struct Game {
        uint256 gameId;
        uint16[2] gameScore;
        GameResult result;
        GameState status;
        uint256 betLimit; // 0: no limit
        uint256 betTotalLimit; // 0: no limit
        
        uint16[2][] ouRate;
        uint16[2][] winRateOver;
        uint16[2][] winRateUnder;
        OUBetPlayer[] ouBetPlayers;
        uint256 ouBetTotal;
    }
    
    uint8 constant MAGIC_NUMBER = 4;
    
    address public creditManager; // address of credit manager
    
    mapping (uint256 => Game) public games;
    
    uint256[] public gameList;
    
    event RefundAll(uint256 gameId);
    event PerformOUBet(uint256 gameId, uint16[2] gameScore);
    event BetWithOUDealer(address player, uint256 gameId, uint8 option, uint256 amount, uint16[2] ouRate, uint16[2] winRateOver, uint16[2] winRateUnder);
    
    function LetBetSportGameOverUnderBetting(address _creditManager) public {
        creditManager = _creditManager;
    }
    
    function getInfo(uint256 _gameId) public constant returns (uint16[2] gameScore, uint8 result, uint8 status, uint256 betLimit, uint256 betTotalLimit, uint16[2][] ouRate, uint16[2][] winRateOver, uint16[2][] winRateUnder, uint numOfOUBetPlayers, uint256 ouBetTotal) {
        Game memory game = games[_gameId];
        return (game.gameScore, uint8(game.result), uint8(game.status), game.betLimit, game.betTotalLimit, game.ouRate, game.winRateOver, game.winRateUnder, game.ouBetPlayers.length, game.ouBetTotal);
    }
    
    function getPlayerOUBet(uint256 _gameId, uint _index) public constant returns (address addr, uint8 betOption, uint256 betAmount, uint256 winAmount, uint16[2] ouRate, uint16[2] winRateOver, uint16[2] winRateUnder) {
        require(_index < games[_gameId].ouBetPlayers.length);
        
        OUBetPlayer memory player = games[_gameId].ouBetPlayers[_index];
        return (player.addr, uint8(player.betOption), player.betAmount, player.winAmount, player.ouRate, player.winRateOver, player.winRateUnder);
    }
    
    function getGameList() public constant returns (uint256[] gameIds) {
        return gameList;
    }
    
    function start(uint256 _gameId, uint256 _betLimit, uint256 _betTotalLimit, uint16[2][] _ouRate, uint16[2][] _winRateOver, uint16[2][] _winRateUnder) onlyOwner public returns (bool success) {
        require(games[_gameId].status != GameState.END);
        
        if (games[_gameId].status == GameState.UNKNOWN) {
            games[_gameId].gameId        = _gameId;
            games[_gameId].gameScore     = [0, 0];
            games[_gameId].result        = GameResult.UNKNOWN;
            games[_gameId].status        = GameState.IN_BET;
            games[_gameId].betLimit      = _betLimit;
            games[_gameId].betTotalLimit = _betTotalLimit;
            
            games[_gameId].ouRate       = _ouRate;
            games[_gameId].winRateOver  = _winRateOver;
            games[_gameId].winRateUnder = _winRateUnder;
            delete games[_gameId].ouBetPlayers;
            games[_gameId].ouBetTotal = 0;
            
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
            if (!performOUBet(_gameId, _gameScore)) revert();
        }
        
        games[_gameId].status = GameState.END;
        
        return true;
    }
    
    function refundAll(uint256 _gameId) internal returns (bool success) {
        uint i = 0;
        LetBetCreditManager lbcm = LetBetCreditManager(creditManager);
        
        for (i = 0; i < games[_gameId].ouBetPlayers.length; ++i) {
            if (!lbcm.increaseCredit(games[_gameId].ouBetPlayers[i].addr, games[_gameId].ouBetPlayers[i].betAmount)) revert();
            games[_gameId].ouBetPlayers[i].winAmount = games[_gameId].ouBetPlayers[i].betAmount;
        }
        
        RefundAll(_gameId);
        
        return true;
    }
    
    function performOUBet(uint256 _gameId, uint16[2] _gameScore) internal returns (bool success) {
        uint i = 0;
        uint256 amount = 0;
        uint256 betAmount = 0;
        uint16 ouRateNatural = 0;
        uint16 ouRateDecimal = 0;
        int16 delta = 0;
        LetBetCreditManager lbcm = LetBetCreditManager(creditManager);
        
        for (i = 0; i < games[_gameId].ouBetPlayers.length; ++i) {
            ouRateNatural = games[_gameId].ouBetPlayers[i].ouRate[0] / MAGIC_NUMBER;
            ouRateDecimal = games[_gameId].ouBetPlayers[i].ouRate[0] % MAGIC_NUMBER;
            if (ouRateDecimal == 3) { // over/under: 0.5/1, 1.5/2, 2.5/3,...
                ouRateNatural = ouRateNatural + 1;
            }
            delta = int16(_gameScore[0]) + int16(_gameScore[1]) - int16(ouRateNatural);
            amount = 0;
            betAmount = games[_gameId].ouBetPlayers[i].betAmount;
            
            if (delta > 0 && games[_gameId].ouBetPlayers[i].betOption == OUBetOption.OVER) { // over win -> bet over win
                amount = betAmount.add(betAmount.mul(games[_gameId].ouBetPlayers[i].winRateOver[0]).div(games[_gameId].ouBetPlayers[i].winRateOver[1]));
            } else if (delta < 0 && games[_gameId].ouBetPlayers[i].betOption == OUBetOption.UNDER) { // under win -> bet under win
                amount = betAmount.add(betAmount.mul(games[_gameId].ouBetPlayers[i].winRateUnder[0]).div(games[_gameId].ouBetPlayers[i].winRateUnder[1]));
            } else if (delta == 0) { // draw
                if (ouRateDecimal == 0) { // over/under: 1, 2, 3,... -> stake refund
                    amount = betAmount;
                } else if (ouRateDecimal == 2 && games[_gameId].ouBetPlayers[i].betOption == OUBetOption.UNDER) { // over/under: 0.5, 1.5, 2.5,... -> bet under win
                    amount = betAmount.add(betAmount.mul(games[_gameId].ouBetPlayers[i].winRateUnder[0]).div(games[_gameId].ouBetPlayers[i].winRateUnder[1]));
                } else if (ouRateDecimal == 1) { // over/under: 1/1.5, 2/2.5, 3/3.5,... -> bet over half lose, bet under half win
                    if (games[_gameId].ouBetPlayers[i].betOption == OUBetOption.OVER) {
                        amount = betAmount.div(2);
                    } else if (games[_gameId].ouBetPlayers[i].betOption == OUBetOption.UNDER) {
                        amount = betAmount.add(betAmount.mul(games[_gameId].ouBetPlayers[i].winRateUnder[0]).div(games[_gameId].ouBetPlayers[i].winRateUnder[1] * 2));
                    }
                } else if (ouRateDecimal == 3) { // over/under: 0.5/1, 1.5/2, 2.5/3,... -> bet over half win, bet under half lose
                    if (games[_gameId].ouBetPlayers[i].betOption == OUBetOption.OVER) {
                        amount = betAmount.add(betAmount.mul(games[_gameId].ouBetPlayers[i].winRateOver[0]).div(games[_gameId].ouBetPlayers[i].winRateOver[1] * 2));
                    } else if (games[_gameId].ouBetPlayers[i].betOption == OUBetOption.UNDER) {
                        amount = betAmount.div(2);
                    }
                }
            }
            
            if (amount > 0) {
                if (!lbcm.increaseCredit(games[_gameId].ouBetPlayers[i].addr, amount)) revert();
                games[_gameId].ouBetPlayers[i].winAmount = amount;
            }
        }
        
        PerformOUBet(_gameId, _gameScore);
    
        return true;
    }
    
    function closeBet(uint256 _gameId) onlyOwner public returns (bool success) {
        require(games[_gameId].status == GameState.IN_BET);
        
        games[_gameId].status = GameState.IN_GAME;
        
        return true;
    }
    
    function setOUBetRate(uint256 _gameId, uint16[2][] _ouRate, uint16[2][] _winRateOver, uint16[2][] _winRateUnder) onlyOwner public returns (bool success) {
        require(games[_gameId].status == GameState.IN_BET || games[_gameId].status == GameState.IN_GAME);
        require(_ouRate.length == _winRateOver.length && _ouRate.length == _winRateUnder.length);
        
        games[_gameId].ouRate       = _ouRate;
        games[_gameId].winRateOver  = _winRateOver;
        games[_gameId].winRateUnder = _winRateUnder;
        
        return true;
    }
    
    function setBetLimit(uint256 _gameId, uint256 _betLimit, uint256 _betTotalLimit) onlyOwner public returns (bool success) {
        require(games[_gameId].status == GameState.IN_BET || games[_gameId].status == GameState.IN_GAME);
        
        games[_gameId].betLimit      = _betLimit;
        games[_gameId].betTotalLimit = _betTotalLimit;
        
        return true;
    }
    
    function betWithOUDealer(uint256 _gameId, uint8 _betOption, uint256 _betAmount, uint _ouRateIndex) public returns (bool success) {
        require(games[_gameId].status == GameState.IN_BET);
        require(games[_gameId].ouRate.length == games[_gameId].winRateOver.length && games[_gameId].ouRate.length == games[_gameId].winRateUnder.length);
        require(_ouRateIndex < games[_gameId].ouRate.length && games[_gameId].ouRate[_ouRateIndex][1] == MAGIC_NUMBER && games[_gameId].winRateOver[_ouRateIndex][1] > 0 && games[_gameId].winRateUnder[_ouRateIndex][1] > 0);
        require(_betOption >= uint8(OUBetOption.OVER) && _betOption <= uint8(OUBetOption.UNDER));
        require(_betAmount > 0);
        require(games[_gameId].betLimit == 0 || _betAmount <= games[_gameId].betLimit);
        require(games[_gameId].betTotalLimit == 0 || games[_gameId].ouBetTotal.add(_betAmount) <= games[_gameId].betTotalLimit);
        
        LetBetCreditManager lbcm = LetBetCreditManager(creditManager);
        
        uint256 currentCredit = lbcm.getCredit(msg.sender);
        if (currentCredit < _betAmount) revert();
        
        if (!lbcm.decreaseCredit(msg.sender, _betAmount)) revert();
        
        games[_gameId].ouBetPlayers.push(OUBetPlayer(msg.sender, OUBetOption(_betOption), _betAmount, 0, games[_gameId].ouRate[_ouRateIndex], games[_gameId].winRateOver[_ouRateIndex], games[_gameId].winRateUnder[_ouRateIndex]));
        games[_gameId].ouBetTotal = games[_gameId].ouBetTotal.add(_betAmount);
        
        BetWithOUDealer(msg.sender, _gameId, _betOption, _betAmount, games[_gameId].ouRate[_ouRateIndex], games[_gameId].winRateOver[_ouRateIndex], games[_gameId].winRateUnder[_ouRateIndex]);
        
        return true;
    }
    
}
