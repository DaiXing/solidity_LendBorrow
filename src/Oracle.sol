// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./MultiSignatureClient.sol";
import "./interface/IOracle.sol";
// import "@chainlink/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// 预言机。 预测价格。 查询价格。 针对某个物体。
// PriceFinder 更合理。
// key用 uint256 ，既可以表示 合约地址，也可以表示 具体tokenID 。更通用。
contract Oracle is MultiSignatureClient, IOracle {
    // 价格查询器。  key= 某物体（地址或ID）    value = 查询器
    mapping(uint256 => AggregatorV3Interface) internal assetsMap;
    // 价格的精度。  key= 某物体（地址或ID）    value = 精度
    mapping(uint256 => uint256) internal decimalsMap;
    // 价格。       key= 某物体（地址或ID）    value = 价格
    mapping(uint256 => uint256) internal priceMap;

    uint256 internal decimals = 1;

    constructor(
        address multiSignature
    ) public MultiSignatureClient(multiSignature) {}

    function setDecimals(uint256 _decimal) public validCall {
        decimals = _decimal;
    }

    // 批量，给资产设置价格。
    function setPrices(
        uint256[] memory assets, // 资产地址
        uint256[] memory prices // 价格
    ) public validCall {
        require(assets.length == prices.length, "length not match");

        uint256 len = prices.length;
        for (uint256 k = 0; k < len; k++) {
            priceMap[k] = prices[k];
        }
    }

    // 基础价格。
    function getUnderlyingPrice(
        uint256 underlying
    ) external view returns (uint256) {
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

    // 设置价格。
    function setPrice(address asset, uint256 price) external validCall {
        priceMap[uint256(uint160(asset))] = price;
    }

    // 设置价格。
    function setUnderlyingPrice(
        uint256 underlying, // 基础资产ID
        uint256 price
    ) external validCall {
        require(underlying > 0, "underlying invalid");
        priceMap[underlying] = price;
    }

    // 设置价格查询器。
    function setAssetsAggregator(
        address asset, //资产地址。
        address aggregator, // 聚合器，收集器。
        uint256 _decimals // 精度
    ) external validCall {
        uint256 assetInt = uint256(uint160(asset));
        assetsMap[assetInt] = AggregatorV3Interface(aggregator);
        decimalsMap[assetInt] = _decimals;
    }

    // 设置价格查询器。
    function setUnderlyingAggregator(
        uint256 underlying, // 基础资产ID
        address aggregator, // 聚合器，收集器。
        uint256 _decimals // 精度
    ) external validCall {
        require(underlying > 0, "underlying invalid");
        assetsMap[underlying] = AggregatorV3Interface(aggregator);
        decimalsMap[underlying] = _decimals;
    }

    // 查询价格查询器。
    function getAssetsAggregator(
        address asset //资产地址。
    ) external validCall returns (address agg, uint256 decimal) {
        uint256 assetInt = uint256(uint160(asset));
        return (address(assetsMap[assetInt]), decimalsMap[assetInt]);
    }

    // 查询价格查询器。
    function getUnderlyingAggregator(
        uint256 underlying // 基础资产ID
    ) external validCall returns (address agg, uint256 decimal) {
        require(underlying > 0, "underlying invalid");
        return (address(assetsMap[underlying]), decimalsMap[underlying]);
    }
}
