pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import './LetBetCreditManager.sol';

contract LetBetRouletteGame is Ownable {
    
    using SafeMath for uint256;
    
    enum GameState { UNKNOWN, AVAILABLE, BUSY }
    enum NormalBetType { UNKNOWN, ONE_NUM, TWO_NUM, THREE_NUM, FOUR_NUM, FIVE_NUM, SIX_NUM }
    enum SpecialBetType { UNKNOWN, RED, BLACK, EVEN, ODD, LOW, HIGH, DOZEN_1, DOZEN_2, DOZEN_3, COLUMN_1, COLUMN_2, COLUMN_3 }
    
    struct Player {
        address addr;
        uint256 latestSpinTimestamp;
    }
    
    struct Game {
        uint256 gameId;
        uint64 seed;
        GameState status;
        Player player; // current player
    }
        
    struct SpinHistory {
        address player;
        uint256 spinTimestamp;
        uint256 gameId;
        uint256 betAmount;
        uint256 winAmount;
        uint64 spinResult;
    }
    
    address public creditManager; // address of credit manager
    
    uint64[7] public payoutNormalBetType;
    uint64[13] public payoutSpecialBetType;
    
    uint64[18] public redNumbers = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36];
    uint64[18] public blackNumbers = [2, 4, 6, 8, 10, 11, 13, 15, 17, 20, 22, 24, 26, 28, 29, 31, 33, 35];
    
    mapping (uint256 => Game) games;
    
    SpinHistory[] public spinHistory;
    SpinHistory private temp;
    
    uint64 public maxIdleMinutes = 3;
    uint64 public maxNumOfGames = 5000;
    uint256 public betLimit; // 0: no limit
    
    event Start(uint256 gameId);
    event SpinResult(uint64 randomNumber, uint256 winAmount);

    function LetBetRouletteGame(address _creditManager) public {
        creditManager = _creditManager;
        
        payoutNormalBetType[uint8(NormalBetType.ONE_NUM)]   = 36;
        payoutNormalBetType[uint8(NormalBetType.TWO_NUM)]   = 18;
        payoutNormalBetType[uint8(NormalBetType.THREE_NUM)] = 12;
        payoutNormalBetType[uint8(NormalBetType.FOUR_NUM)]  = 9;
        payoutNormalBetType[uint8(NormalBetType.FIVE_NUM)]  = 7;
        payoutNormalBetType[uint8(NormalBetType.SIX_NUM)]   = 6;
        
        payoutSpecialBetType[uint8(SpecialBetType.RED)]      = 2;
        payoutSpecialBetType[uint8(SpecialBetType.BLACK)]    = 2;
        payoutSpecialBetType[uint8(SpecialBetType.EVEN)]     = 2;
        payoutSpecialBetType[uint8(SpecialBetType.ODD)]      = 2;
        payoutSpecialBetType[uint8(SpecialBetType.LOW)]      = 2;
        payoutSpecialBetType[uint8(SpecialBetType.HIGH)]     = 2;
        payoutSpecialBetType[uint8(SpecialBetType.DOZEN_1)]  = 3;
        payoutSpecialBetType[uint8(SpecialBetType.DOZEN_2)]  = 3;
        payoutSpecialBetType[uint8(SpecialBetType.DOZEN_3)]  = 3;
        payoutSpecialBetType[uint8(SpecialBetType.COLUMN_1)] = 3;
        payoutSpecialBetType[uint8(SpecialBetType.COLUMN_2)] = 3;
        payoutSpecialBetType[uint8(SpecialBetType.COLUMN_3)] = 3;
    }
    
    function random(uint256 _gameId, uint64 _upper) internal returns (uint64 randomNumber) {
        games[_gameId].seed = uint64(keccak256(keccak256(block.blockhash(block.number), games[_gameId].seed), now));
        
        return games[_gameId].seed % _upper;
    }
    
    function hasOverMaxIdleTime(uint256 _timestamp) internal view returns (bool hasOver) {
        return (now > _timestamp * 1 seconds + maxIdleMinutes * 1 minutes);
    }
    
    function getInfo(uint256 _gameId) public constant returns (uint8 status, address player, uint256 latestSpinTimestamp, uint64 infoMaxIdleMinutes, uint64 infoMaxNumOfGames, uint256 infoBetLimit) {
        require(_gameId > 0 && _gameId <= maxNumOfGames);
        
        return (uint8(games[_gameId].status), games[_gameId].player.addr, games[_gameId].player.latestSpinTimestamp, maxIdleMinutes, maxNumOfGames, betLimit);
    }
        
    function getNumOfSpinHistory() public constant returns (uint numOfSpinHistory) {
        return spinHistory.length;
    }
        
    function getSpinHistory(uint _index) public constant returns (address player, uint256 spinTimestamp, uint256 gameId, uint256 betAmount, uint256 winAmount, uint64 spinResult) {
        require(_index < spinHistory.length);
        
        SpinHistory memory history = spinHistory[_index];
        return (history.player, history.spinTimestamp, history.gameId, history.betAmount, history.winAmount, history.spinResult);
    }
    
    function existValidGame() public constant returns (bool exist) {
        for (uint i = 1; i <= maxNumOfGames; ++i) {
            if (games[i].status == GameState.UNKNOWN || games[i].status == GameState.AVAILABLE || hasOverMaxIdleTime(games[i].player.latestSpinTimestamp)) {
                return true;
            }
        }
        
        return false;
    }
    
    function start() public returns (bool success) {
        uint256 gameId = 0;
        
        for (uint i = 1; i <= maxNumOfGames; ++i) {
            if (games[i].status == GameState.UNKNOWN || games[i].status == GameState.AVAILABLE || hasOverMaxIdleTime(games[i].player.latestSpinTimestamp)) {
                games[i].gameId = i;
                games[i].seed   = uint64(keccak256(keccak256(block.blockhash(block.number), uint64(msg.sender)), now));
                games[i].status = GameState.BUSY;
                games[i].player = Player(msg.sender, now);
                
                gameId = i;
                break;
            }
        }
        
        Start(gameId);
        
        return true;
    }
    
    function end(uint256 _gameId) onlyOwner public returns (bool success) {
        require(_gameId > 0 && _gameId <= maxNumOfGames);
        require(games[_gameId].status == GameState.BUSY);
        
        games[_gameId].status = GameState.AVAILABLE;
        
        return true;
    }
    
    function endFromPlayer(uint256 _gameId) public returns (bool success) {
        require(_gameId > 0 && _gameId <= maxNumOfGames);
        require(games[_gameId].status == GameState.BUSY);
        require(games[_gameId].player.addr == msg.sender);
        
        games[_gameId].status = GameState.AVAILABLE;
        
        return true;
    }
    
    function setMaxIdleMinutes(uint64 _maxIdleMinutes) onlyOwner public returns (bool success) {
        require(_maxIdleMinutes > 0);
        
        maxIdleMinutes = _maxIdleMinutes;
        
        return true;
    }
    
    function setMaxNumOfGames(uint64 _maxNumOfGames) onlyOwner public returns (bool success) {
        require(_maxNumOfGames > 0);
    
        maxNumOfGames = _maxNumOfGames;
        
        return true;
    }
    
    function setBetLimit(uint256 _betLimit) onlyOwner public returns (bool success) {
        betLimit = _betLimit;
        
        return true;
    }
    
    function calcWinAmountForNormalBetType(uint64 _randomNumber, NormalBetType _betType, uint64[] _betValue, uint _index, uint256 _betAmount) internal view returns (uint256 winAmount) {
        require(_betValue.length.sub(_index) >= uint8(_betType));
    
        uint256 amount = 0;
        
        if (_randomNumber < 37 && _betType >= NormalBetType.ONE_NUM && _betAmount > 0) {
            for (uint i = _index; i < uint8(_betType); ++i) {
                if (_randomNumber == _betValue[i]) {
                    amount = _betAmount.mul(payoutNormalBetType[uint8(_betType)]);
                    break;
                }
            }
        }
        
        return amount;
    }
    
    function calcWinAmountForSpecialBetType(uint64 _randomNumber, SpecialBetType _betType, uint256 _betAmount) internal view returns (uint256 winAmount) {
        uint256 amount = 0;
        uint i = 0;
        bool isWin = false;
        
        if (_randomNumber > 0 && _randomNumber < 37 && _betType >= SpecialBetType.RED && _betAmount > 0) {
            if (_betType == SpecialBetType.RED) {
                for (i = 0; i < redNumbers.length; ++i) {
                    if (_randomNumber == redNumbers[i]) {
                        isWin = true;
                        break;
                    }
                }
            } else if (_betType == SpecialBetType.BLACK) {
                for (i = 0; i < blackNumbers.length; ++i) {
                    if (_randomNumber == blackNumbers[i]) {
                        isWin = true;
                        break;
                    }
                }
            } else if ((_betType == SpecialBetType.EVEN && _randomNumber % 2 == 0)
                        || (_betType == SpecialBetType.ODD && _randomNumber % 2 == 1)
                        || (_betType == SpecialBetType.LOW && _randomNumber < 19)
                        || (_betType == SpecialBetType.HIGH && _randomNumber > 18)
                        || (_betType == SpecialBetType.DOZEN_1 && _randomNumber < 13)
                        || (_betType == SpecialBetType.DOZEN_2 && _randomNumber > 12 && _randomNumber < 25)
                        || (_betType == SpecialBetType.DOZEN_3 && _randomNumber > 24)
                        || (_betType == SpecialBetType.COLUMN_1 && _randomNumber % 3 == 1)
                        || (_betType == SpecialBetType.COLUMN_2 && _randomNumber % 3 == 2)
                        || (_betType == SpecialBetType.COLUMN_3 && _randomNumber % 3 == 0)) {
                isWin = true;
            }
            
            if (isWin) {
                amount = _betAmount.mul(payoutSpecialBetType[uint8(_betType)]);
            }
        }
        
        return amount;
    }
    
    function spin(uint256 _gameId, uint8[] _normalBetType, uint64[] _normalBetValue, uint256[] _normalBetAmount, uint8[] _specialBetType, uint256[] _specialBetAmount) public returns (bool success) {
        require(_gameId > 0 && _gameId <= maxNumOfGames);
        require(games[_gameId].status == GameState.BUSY);
        require(games[_gameId].player.addr == msg.sender);
        require(_normalBetType.length == _normalBetAmount.length && _specialBetType.length == _specialBetAmount.length);
        
        uint i = 0;
        uint256 betAmountTotal = 0;
        
        for (i = 0; i < _normalBetType.length; ++i) {
            if (_normalBetType[i] > uint8(NormalBetType.SIX_NUM)) revert();
        }
        
        for (i = 0; i < _specialBetType.length; ++i) {
            if (_specialBetType[i] > uint8(SpecialBetType.COLUMN_3)) revert();
        }
        
        for (i = 0; i < _normalBetType.length; ++i) {
            betAmountTotal = betAmountTotal.add(_normalBetAmount[i]);
        }
        
        for (i = 0; i < _specialBetType.length; ++i) {
            betAmountTotal = betAmountTotal.add(_specialBetAmount[i]);
        }
        
        if (betLimit > 0 && betAmountTotal > betLimit) revert();
        
        LetBetCreditManager lbcm = LetBetCreditManager(creditManager);
        
        if (lbcm.getCredit(msg.sender) < betAmountTotal) revert();
        
        if (!lbcm.decreaseCredit(msg.sender, betAmountTotal)) revert();
        
        uint64 x = random(_gameId, 37);
        
        uint256 winAmount = 0;
        uint j = 0;
        
        for (i = 0; i < _normalBetType.length; ++i) {
            winAmount = winAmount.add(calcWinAmountForNormalBetType(x, NormalBetType(_normalBetType[i]), _normalBetValue, j, _normalBetAmount[i]));
            j = j + _normalBetType[i];
        }
        
        for (i = 0; i < _specialBetType.length; ++i) {
            winAmount = winAmount.add(calcWinAmountForSpecialBetType(x, SpecialBetType(_specialBetType[i]), _specialBetAmount[i]));
        }
        
        if (winAmount > 0) {
            if (!lbcm.increaseCredit(msg.sender, winAmount)) revert();
        }
        
        temp = SpinHistory(msg.sender, now, _gameId, betAmountTotal, winAmount, x);        
        spinHistory.push(temp);
        
        SpinResult(x, winAmount);
        
        return true;
    }
    
}
