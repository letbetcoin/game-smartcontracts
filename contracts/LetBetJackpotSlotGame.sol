pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import './LetBetCreditManager.sol';

contract LetBetJackpotSlotGame is Ownable {

    using SafeMath for uint256;
    
    enum GameState { UNKNOWN, AVAILABLE, BUSY }
    
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
        uint64[3] spinResult;
    }
    
    address public creditManager; // address of credit manager
    
    uint64[20][3] public reel = [[5, 4, 4, 4, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1],
                                 [5, 5, 4, 4, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1],
                                 [5, 4, 4, 3, 3, 3, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]];
    
    mapping (uint64 => uint64) public payout;
    
    mapping (uint256 => Game) games;
    
    SpinHistory[] public spinHistory;
    
    uint64 public maxIdleMinutes = 3;
    uint64 public maxNumOfGames = 5000;
    uint256 public betLimit; // 0: no limit
    
    event Start(uint256 gameId);
    event SpinResult(uint64 randomNumber1, uint64 randomNumber2, uint64 randomNumber3, uint256 winAmount);

    function LetBetJackpotSlotGame(address _creditManager) public {
        creditManager = _creditManager;
        
        payout[555] = 100;
        payout[444] = 30;
        payout[333] = 10;
        payout[222] = 6;
        payout[111] = 4;
        payout[1]   = 3;
        payout[0]   = 2;
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
    
    function getSpinHistory(uint _index) public constant returns (address player, uint256 spinTimestamp, uint256 gameId, uint256 betAmount, uint256 winAmount, uint64[3] spinResult) {
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
    
    function spin(uint256 _gameId, uint256 _betAmount) public returns (bool success) {
        require(_gameId > 0 && _gameId <= maxNumOfGames);
        require(games[_gameId].status == GameState.BUSY);
        require(games[_gameId].player.addr == msg.sender);
        require(_betAmount > 0);
        require(betLimit == 0 || _betAmount <= betLimit);
        
        LetBetCreditManager lbcm = LetBetCreditManager(creditManager);
        
        if (lbcm.getCredit(msg.sender) < _betAmount) revert();
        
        if (!lbcm.decreaseCredit(msg.sender, _betAmount)) revert();
        
        uint64 x = reel[0][random(_gameId, 20)];
        uint64 y = reel[1][random(_gameId, 20)];
        uint64 z = reel[2][random(_gameId, 20)];
        
        uint256 winAmount = 0;
        uint64 winRate = 0;
        
        if (x == 1 && (y != 1 || z != 1)) {
            if (y == 1) {
                winRate = payout[1];
            } else {
                winRate = payout[0];
            }
        } else {
            uint64 n = x * 100 + y * 10 + z;
            winRate = payout[n];
        }
        
        if (winRate > 0) {
            winAmount = _betAmount.mul(winRate);
            if (!lbcm.increaseCredit(msg.sender, winAmount)) revert();
        }
        
        games[_gameId].player.latestSpinTimestamp = now;
        
        spinHistory.push(SpinHistory(msg.sender, now, _gameId, _betAmount, winAmount, [x, y, z]));
        
        SpinResult(x, y, z, winAmount);
        
        return true;
    }
    
}
