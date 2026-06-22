// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// 债务。
interface IDebtToken {
    // 查询余额。
    function balanceOf(address account) external view returns (uint256);

    // 总的供应量。
    function totalSupply() external view returns (uint256);

    // 铸造。
    function mint(address account, uint256 amount) external;

    // 销毁。
    function burn(address account, uint256 amount) external;
}
