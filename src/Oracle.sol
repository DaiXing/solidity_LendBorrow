// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./MultiSignatureClient.sol";
// import "@chainlink/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// 预言机。 预测价格。
contract Oracle is MultiSignatureClient {
    // 价格查询器。
    mapping(uint256 => AggregatorV3Interface) internal assetsMap;
    // 价格的精度。
    mapping(uint256 => uint256) internal decimalsMap;
    // 价格。
    mapping(uint256 => uint256) internal priceMap;

    uint256 internal decimals = 1;

    constructor(
        address multiSignature
    ) public MultiSignatureClient(multiSignature) {}
}
