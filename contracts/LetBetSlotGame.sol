pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import './LetBetCreditManager.sol';

/*
number | reel_1 | reel_2 | reel_3
5      |    2   |    2   |    1
4      |    3   |    2   |    2
3      |    5   |    4   |    3
2      |    6   |    5   |    5
1      |    4   |    7   |    9
----------------------------------
total       20       20       20

p(555) = (2/20) * (2/20) * (1/20) = 0.0005
p(444) = (3/20) * (2/20) * (2/20) = 0.0015
p(333) = (5/20) * (4/20) * (3/20) = 0.0075
p(222) = (6/20) * (5/20) * (5/20) = 0.01875
p(111) = (4/20) * (7/20) * (9/20) = 0.0315
p(11x) = (4/20) * (7/20) = 0.07
p(1xx) = (4/20) - 0.07 = 0.13

payout(555) = x100
payout(444) = x30
payout(333) = x10
payout(222) = x6
payout(111) = x4
payout(11x) = x3
payout(1xx) = x2

100 * 0.0005 + 30 * 0.0015 + 10 * 0.0075 + 6 * 0.01875 + 4 * 0.0315 + 3 * 0.07 + 2 * 0.13 = 0.8785

*/

contract LetBetSlotGame is Ownable {

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
    
    uint64[20][3] public reel = [[5, 5, 4, 4, 4, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1],
                                 [5, 5, 4, 4, 3, 3, 3, 3, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1],
                                 [5, 4, 4, 3, 3, 3, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1]];
    
    mapping (uint64 => uint64) public payout;
    
    mapping (uint256 => Game) games;
    
    uint64 public maxIdleMinutes = 3;
    uint64 public maxNumOfGames = 1000;
    uint256 public betLimit; // 0: no limit
    
    event Start(uint256 gameId);
    event SpinResult(uint64 randomNumber1, uint64 randomNumber2, uint64 randomNumber3, uint256 winAmount);

    function LetBetSlotGame(address _creditManager) public {
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
        
        SpinResult(x, y, z, winAmount);
        
        return true;
    }
    
}
