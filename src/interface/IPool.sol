// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IDebtToken.sol";

interface IPool {
    // 状态。
    enum PoolState {
        MATCH, // 匹配
        EXECUTION, // 执行
        FINISH, // 完成
        LIQUIDATION, // 清算
        UNDONE // 回退
    }

    // 池子的基本信息
    struct PoolBaseInfo {
        uint256 settleTime; // 结算时间
        uint256 endTime; // 结束时间
        uint256 interestRate; // 利率。费率。 单位 1e8
        uint256 maxSupply; // 最大供应量
        uint256 lendSupply; // 贷款人的供应量。
        uint256 borrowSupply; // 借款人的供应量。抵押品。存入抵押品，才能拿到借款。
        uint256 martgageRate; // 抵押率。 单位 1e8
        address lendToken; // 贷款方的token地址。存借出、借入的钱。
        address borrowToken; // 借款方的token地址。存保证金。
        PoolState state; // 状态
        IDebtToken spCoin; // supply position token。贷款人，获得存款凭证。
        IDebtToken jpCoin; // j      position token。借款人，获得抵押凭证。
        uint256 autoLiquidateThreshold; // 自动清算的阙值
    }

    // 池子的数据
    struct PoolDataInfo {
        uint256 settleAmountLend; // 结算时，实际贷款金额
        uint256 settleAmountBorrow; // 结算时，实际借款金额
        uint256 finishAmountLend; // 完成时，实际贷款金额
        uint256 finishAmountBorrow; // 完成时，实际借款金额
        uint256 liquidationAmountLend; // 清算时，实际贷款金额
        uint256 liquidationAmountBorrow; // 清算时，实际借款金额
    }

    // 用户的贷款信息。
    struct LendInfo {
        uint256 stakeAmount; // 质押金额
        uint256 refundAmount; // 退款金额 多余
        bool hasNoRefund; // true = 已退款。  false = 未退款
        bool hasNoClaim; // true = 已认领。  false = 未认领
    }
    // 用户的借款信息。
    struct BorrowInfo {
        uint256 stakeAmount; // 质押金额
        uint256 refundAmount; // 退款金额 超额
        bool hasNoRefund; // true = 已退款。  false = 无退款
        bool hasNoClaim; // true = 已索赔。  false = 无索赔
    }

    // 状态变
    event StateChange(uint256 pid, uint256 beforeState, uint256 afterState);
    event SetFee(uint256 newLendFee, uint256 newBorrowFee);
    event SetFeeAddress(address indexed oldFeeAddr, address indexed newFeeAddr);
    event SetMinAmount(uint256 oldMinAmount, uint256 newMinAmount);
    event SetSwapRouterAddress(
        address indexed oldAddr,
        address indexed newAddr
    );

    // 贷款事件。
    event DepositLend(
        address indexed from, // 贷款人
        address indexed token, // 代币地址
        uint256 amount, // 数量
        uint256 mintAmount // 生成数量
    );
    event WithdrawLend(
        address indexed from, // 贷款人
        address indexed token, // 代币地址
        uint256 amount, // 数量
        uint256 burnAmount // 销毁数量
    );
    event RefundLend(
        address indexed from, // 贷款人
        address indexed token, // 代币地址
        uint256 amount // 退款数量
    );
    // 索赔
    event ClaimLend(
        address indexed from, // 贷款人
        address indexed token, // 代币地址
        uint256 amount // 索赔数量
    );

    // 借款事件。
    event DepositBorrow(
        address indexed from, // 贷款人
        address indexed token, // 代币地址
        uint256 amount, // 数量
        uint256 mintAmount // 生成数量
    );
    event WithdrawBorrow(
        address indexed from, // 贷款人
        address indexed token, // 代币地址
        uint256 amount, // 数量
        uint256 burnAmount // 销毁数量
    );
    event RefundBorrow(
        address indexed from, // 贷款人
        address indexed token, // 代币地址
        uint256 amount // 退款数量
    );
    // 索赔
    event ClaimBorrow(
        address indexed from, // 贷款人
        address indexed token, // 代币地址
        uint256 amount // 索赔数量
    );

    // 交换。
    event Swap(
        address indexed fromCoin, // 交换前的币种地址
        address indexed toCoin, // 交换后的币种地址
        uint256 fromValue, // 交换前的数量
        uint256 toValue // 交换后的数量
    );

    // 紧急贷款的提取
    event EmergencyLendWithdrawal(
        address indexed from, // 贷款人
        address indexed token, // 代币地址
        uint256 amount // 数量
    );
    // 紧急借款的提取
    event EmergencyBorrowWithdrawal(
        address indexed from, // 贷款人
        address indexed token, // 代币地址
        uint256 amount // 数量
    );
}
