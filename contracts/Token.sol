pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/token/StandardToken.sol';

contract Token is StandardToken {

    string public name;
    bytes32 public symbol;
    uint8 public decimals;

}
