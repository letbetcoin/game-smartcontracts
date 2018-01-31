pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import './LetBetCreditManager.sol';

contract LetBetRNGGame is Ownable {

    using SafeMath for uint256;
    
    enum BetOption { EVEN, ODD }
    
    struct BetEvenOddHistory {
        address player;
        uint256 betTimestamp;
        BetOption betOption;
        uint256 betAmount;
        uint256 winAmount;
        uint64 randomNumber;
    }
    
    struct BetNumberHistory {
        address player;
        uint256 betTimestamp;
        uint64 betNumber;
        uint256 betAmount;
        uint256 winAmount;
        uint64 randomNumber;
    }
    
    address public creditManager; // address of credit manager
    
    BetEvenOddHistory[] public betEvenOddHistory;
    BetNumberHistory[] public betNumberHistory;
    
    uint64 private seed;
    
    uint256 public betLimit; // 0: no limit
    
    event ResultEvenOdd(uint64 result, uint256 winAmount);
    event ResultRandomNumber(uint64 randomNumber, uint256 winAmount);

    function LetBetRNGGame(address _creditManager) public {
        creditManager = _creditManager;
    }
    
    function random() internal returns (uint64 randomNumber) {
        seed = uint64(keccak256(keccak256(block.blockhash(block.number), seed), now));
        
        return seed;
    }
    
    function random(uint64 _upper) internal returns (uint64 randomNumber) {
       seed = uint64(keccak256(keccak256(block.blockhash(block.number), seed), now));
       
       return seed % _upper + 1;
    }
    
    function getNumOfBetEvenOddHistory() public constant returns (uint numOfBetEvenOddHistory) {
        return betEvenOddHistory.length;
    }
    
    function getBetEvenOddHistory(uint _index) public constant returns (address player, uint256 betTimestamp, uint8 betOption, uint256 betAmount, uint256 winAmount, uint64 randomNumber) {
        require(_index < betEvenOddHistory.length);
    
        BetEvenOddHistory memory history = betEvenOddHistory[_index];
        return (history.player, history.betTimestamp, uint8(history.betOption), history.betAmount, history.winAmount, history.randomNumber);
    }
    
    function getNumOfBetNumberHistory() public constant returns (uint numOfBetNumberHistory) {
        return betNumberHistory.length;
    }
    
    function getBetNumberHistory(uint _index) public constant returns (address player, uint256 betTimestamp, uint64 betNumber, uint256 betAmount, uint256 winAmount, uint64 randomNumber) {
        require(_index < betNumberHistory.length);
    
        BetNumberHistory memory history = betNumberHistory[_index];
        return (history.player, history.betTimestamp, history.betNumber, history.betAmount, history.winAmount, history.randomNumber);
    }
    
    function setBetLimit(uint256 _betLimit) onlyOwner public returns (bool success) {
        betLimit = _betLimit;
        
        return true;
    }
    
    function betEvenOdd(uint8 _betOption, uint256 _betAmount) public returns (bool success) {
        require(BetOption(_betOption) == BetOption.EVEN || BetOption(_betOption) == BetOption.ODD);
        require(_betAmount > 0);
        require(betLimit == 0 || _betAmount <= betLimit);
        
        LetBetCreditManager lbcm = LetBetCreditManager(creditManager);
        
        if (lbcm.getCredit(msg.sender) < _betAmount) revert();
        
        if (!lbcm.decreaseCredit(msg.sender, _betAmount)) revert();
        
        uint64 n = random();
        
        uint256 winAmount = 0;
        
        if (n % 2 == _betOption) {
            winAmount = _betAmount.mul(19).div(10);
        }
        
        if (winAmount > 0) {
            if (!lbcm.increaseCredit(msg.sender, winAmount)) revert();
        }
        
        betEvenOddHistory.push(BetEvenOddHistory(msg.sender, now, BetOption(_betOption), _betAmount, winAmount, n));
        
        ResultEvenOdd(n % 2, winAmount);
        
        return true;
    }
    
    function betNumber(uint64 _betNumber, uint256 _betAmount) public returns (bool success) {
        require(_betAmount > 0);
        require(betLimit == 0 || _betAmount <= betLimit);
        
        LetBetCreditManager lbcm = LetBetCreditManager(creditManager);
        
        if (lbcm.getCredit(msg.sender) < _betAmount) revert();
        
        if (!lbcm.decreaseCredit(msg.sender, _betAmount)) revert();
        
        uint64 n = random(5);
        
        uint256 winAmount = 0;
        
        if (n == _betNumber) {
            winAmount = _betAmount.mul(49).div(10);
        }
        
        if (winAmount > 0) {
            if (!lbcm.increaseCredit(msg.sender, winAmount)) revert();
        }
        
        betNumberHistory.push(BetNumberHistory(msg.sender, now, _betNumber, _betAmount, winAmount, n));
        
        ResultRandomNumber(n, winAmount);
        
        return true;
    }
    
}
