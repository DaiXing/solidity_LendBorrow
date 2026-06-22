// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IOracle {
    function getPrice(address asset) external view returns (uint256);
    function getUnderlyingPrice(uint256 token) external view returns (uint256);
    function getPrices(
        uint256[] calldata assets
    ) external view returns (uint256[] memory);
}
