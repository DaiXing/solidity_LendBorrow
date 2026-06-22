// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// swap V2 的路由。
interface IUniswapV2Router2 {
    // 工厂的地址。
    function factory() external pure returns (address);

    // eth
    function WETH() external pure returns (address);

    // 增加流动性。 2种token
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    // 增加流动性。 1种token ， 1种eth
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountEth, uint liquidity);

    // 删除流动性。 2种token
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity, // 流动性
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);

    // 删除流动性。 1种token ， 1种eth
    function removeLiquidityETH(
        address token,
        uint liquidity, // 流动性
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);

    // 删除流动性。 2种token
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint amountA, uint amountB);

    // 删除流动性。 1种token ， 1种eth
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity, // 流动性
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint amountToken, uint amountETH);

    // 交换。用1种token，交换另一种token 。精确输入。
    function swapExactTokensForTokens(
        uint amountIn, // 输入数量
        uint amountOutMin, // 最小的输出数量
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    // 交换。用1种token，交换另一种token 。精确输出。
    function swapTokensForExactTokens(
        uint amountOut, // 输出数量
        uint amountInMax, // 最大的输入数量
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    // 交换。用ETH，交换token 。精确输入。
    function swapExactETHForTokens(
        // 输入，在 msg.value
        uint amountOutMin, // token 最小的输出数量
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    // 交换。用token，交换ETH 。精确输出。
    function swapTokensForExactETH(
        uint amountOut, // ETH 数量
        uint amountInMax, // token 最大的输入数量
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    // 交换。用token，交换ETH 。精确输入。
    function swapExactTokensForETH(
        uint amountIn, // token 数量
        uint amountOutMin, // ETH 数量
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    // 交换。用ETH，交换token 。精确输出。
    function swapETHForExactTokens(
        uint amountOut,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    // 行情。报价。
    function quote(
        uint amountA,
        uint reserveA,
        uint reserveB
    ) external pure returns (uint amountB);

    // 取数量。
    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) external pure returns (uint amountOut);

    // 取数量。
    function getAmountIn(
        uint amountOut,
        uint reserveIn,
        uint reserveOut
    ) external pure returns (uint amountIn);

    // 取数量。
    function getAmountsOut(
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts);

    // 取数量。
    function getAmountsIn(
        uint amountOut,
        address[] calldata path
    ) external view returns (uint[] memory amounts);

    // 减少ETH的流动性。
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountETH);

    // 减少ETH的流动性。
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint amountETH);

    // 交换。用1种token，交换另一种token 。精确输入。
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn, // 输入数量
        uint amountOutMin, // 最小的输出数量
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    // 交换。用ETH，交换token 。精确输入。
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        // 输入，在 msg.value
        uint amountOutMin, // token 最小的输出数量
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;

    // 交换。用token，交换ETH 。精确输入。
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn, // token 数量
        uint amountOutMin, // ETH 数量
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}
