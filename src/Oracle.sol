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

    function setDecimals(uint256 _decimal) public validCall {
        decimals = _decimal;
    }

    function setPrices(
        uint256[] memory assets,
        uint256[] memory prices
    ) public validCall {
        require(assets.length == prices.length, "length not match");

        uint256 len = prices.length;
        for (uint256 k = 0; k < len; k++) {
            priceMap[k] = prices[k];
        }
    }

    // 基础价格。
    function getUnderlyingPrice(uint256 underlying) external returns (uint256) {
        // 查询外部价格。
        AggregatorV3Interface agg = assetsMap[underlying];

        // 没有外部价格，直接用本地价格。
        if (address(agg) == address(0)) {
            return priceMap[underlying];
        }

        // 查询外部价格。
        (
            uint80 roundId,
            int256 price,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = agg.latestRoundData();

        // 精度。
        uint256 tokenDecimal = decimalsMap[underlying];

        uint256 price2 = uint256(price);
        uint256 price3 = price2 / decimals;

        // todo 这个乘法没看懂。
        if (tokenDecimal < 18) {
            return price3 * (10 ** (18 - tokenDecimal));
        } else if (tokenDecimal < 18) {
            return price3 * (10 ** (18 - tokenDecimal));
        } else {
            return price3;
        }
    }
}
