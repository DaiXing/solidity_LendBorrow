// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./AddressPrivileges.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract DebtToken is ERC20, AddressPrivileges {
    constructor(
        string memory name,
        string memory symbol,
        address multiSignature
    ) AddressPrivileges(multiSignature) ERC20(name, symbol) {}

    // 铸造
    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    // 销毁。
    function burn(address from, uint256 amount) external onlyMinter {
        _burn(from, amount);
    }
}
