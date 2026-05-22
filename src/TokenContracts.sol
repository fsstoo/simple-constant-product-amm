// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract TokenA is ERC20, Ownable, ERC20Permit {
    constructor(address initialOwner) ERC20("Token A", "ATK") Ownable(initialOwner) ERC20Permit("Token A") {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}

contract TokenB is ERC20, Ownable, ERC20Permit {
    constructor(address initialOwner) ERC20("Token B", "BTK") Ownable(initialOwner) ERC20Permit("Token B") {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
