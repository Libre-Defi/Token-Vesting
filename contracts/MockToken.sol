/**
 * SPDX-License-Identifier: MIT
 *
 */

pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";

contract MockToken is ERC20,ERC20Burnable {
    constructor() public ERC20("Token", "") {
        _mint(address(this), 1000000000000000000000000000000000);
        _mint(address(msg.sender), 1000000000000000000000000000000000);
    }
}