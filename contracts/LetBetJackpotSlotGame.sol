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
    
    address public creditManager; // address of credit manager
    
    mapping (uint64 => uint8[2]) public reward; // reward rules
    
    mapping (uint256 => Game) games;
    
    uint64 public maxIdleMinutes = 3;
    uint64 public maxNumOfGames = 1000;
    uint256 public betLimit; // 0: no limit
    
    event Start(uint256 gameId);
    event SpinResult(uint64 randomNumber1, uint64 randomNumber2, uint64 randomNumber3, uint256 winAmount);

    function LetBetJackpotSlotGame(address _creditManager) public {
        creditManager = _creditManager;
        
        reward[555] = [4, 1];
        reward[444] = [7, 2];
        reward[333] = [3, 1];
        reward[222] = [5, 2];
        reward[111] = [2, 1];
        reward[1]   = [3, 2];
        reward[0]   = [5, 4];
    }
    
    function random(uint256 _gameId, uint64 _upper) internal returns (uint64 randomNumber) {
        games[_gameId].seed = uint64(keccak256(keccak256(block.blockhash(block.number), games[_gameId].seed), now));
        
        return (games[_gameId].seed % _upper + 1);
    }
    
    function hasOverMaxIdleTime(uint256 _timestamp) internal view returns (bool hasOver) {
        return (now > _timestamp * 1 seconds + maxIdleMinutes * 1 minutes);
    }
    
    function getInfo(uint256 _gameId) public constant returns (uint8 status, address player, uint256 latestSpinTimestamp, uint64 infoMaxIdleMinutes, uint64 infoMaxNumOfGames, uint256 infoBetLimit) {
        require(_gameId > 0 && _gameId <= maxNumOfGames);
        
        return (uint8(games[_gameId].status), games[_gameId].player.addr, games[_gameId].player.latestSpinTimestamp, maxIdleMinutes, maxNumOfGames, betLimit);
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
        
        uint256 currentCredit = lbcm.getCredit(msg.sender);
        if (currentCredit < _betAmount) revert();
        
        if (!lbcm.decreaseCredit(msg.sender, _betAmount)) revert();
        
        uint64 x = random(_gameId, 5);
        uint64 y = random(_gameId, 5);
        uint64 z = random(_gameId, 5);
        
        uint256 winAmount = 0;
        uint8[2] memory winRate = [0, 0];
        
        if (x == 1 && (y != 1 || z != 1)) {
            if (y == 1) {
                winRate = reward[1];
            } else {
                winRate = reward[0];
            }
        } else {
            uint64 n = x * 100 + y * 10 + z;
            winRate = reward[n];
        }
        
        if (winRate[0] > 0 && winRate[1] > 0) {
            winAmount = _betAmount.mul(winRate[0]).div(winRate[1]);
            if (!lbcm.increaseCredit(msg.sender, winAmount)) revert();
        }
        
        games[_gameId].player.latestSpinTimestamp = now;
        
        SpinResult(x, y, z, winAmount);
        
        return true;
    }
    
}
