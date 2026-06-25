// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./AddressPrivileges.sol";
import "./DebtToken.sol";
import "./interface/IOracle.sol";
import "./interface/IDebtToken.sol";
import "./MultiSignatureClient.sol";
import "./interface/IUniswapV2Router2.sol";
import "./interface/IPool.sol";
import "./library/SafeTransfer.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

contract Pool is
    ReentrancyGuard,
    MultiSignatureClient,
    SafeTransfer,
    IPool,
    Pausable
{
    using SafeERC20 for IERC20;

    uint256 private constant calDecimal = 1e18;
    uint256 private constant baseDecimal = 1e8;
    uint256 private minAmount = 100e18;
    uint256 private baseYear = 265 days;

    PoolState constant defaultChoice = PoolState.MATCH;

    // 暂停。全部。
    bool public constant globalPaused = false;
    // 交换。
    address public swapRouter;
    // 手续费。接收人。
    address payable public feeAddress;
    // 查询价格
    IOracle public oracle;
    // 贷款人。利息费率
    uint256 public lendFee;
    // 借款人。利息费率
    uint256 public borrowFee;

    // 全部池子。
    PoolBaseInfo[] public poolBaseInfo;
    PoolDataInfo[] public poolDataInfo;

    // 用户的借款、贷款。
    // 用户地址  >>  pool下标  >>  具体。
    mapping(address => mapping(uint256 => LendInfo)) public userLendInfo;
    mapping(address => mapping(uint256 => BorrowInfo)) public userBorrowInfo;

    constructor(
        address _oracle, // 查价格
        address _swapRouter, // 交易。
        address payable _feeAddr, // 手续福
        address _multiSignature // 签名
    ) MultiSignatureClient(_multiSignature) {
        require(_oracle != address(0), "_oracle invalid");
        require(_swapRouter != address(0), "_swapRouter invalid");
        require(_feeAddr != address(0), "_feeAddr invalid");

        oracle = IOracle(_oracle);
        swapRouter = _swapRouter;
        feeAddress = _feeAddr;
        lendFee = 0;
        borrowFee = 0;
    }
    function pause() public validCall {
        _pause();
    }
    function unpause() public validCall {
        _unpause();
    }

    function setFee(uint256 _lendFee, uint256 _borrowFee) public validCall {
        lendFee = _lendFee;
        borrowFee = _borrowFee;
        emit SetFee(_lendFee, _borrowFee);
    }

    function setSwapRouterAddress(address addr) public validCall {
        require(addr != address(0), "addr invalid");
        emit SetSwapRouterAddress(swapRouter, addr);
        swapRouter = addr;
    }

    function setFeeAddress(address addr) public validCall {
        require(addr != address(0), "addr invalid");
        emit SetFeeAddress(feeAddress, addr);
        feeAddress = addr;
    }

    function setMinAmount(uint256 amount) public validCall {
        require(amount > 0, "amount invalid");
        emit SetMinAmount(minAmount, amount);
        minAmount = amount;
    }

    function poolLength() public view returns (uint256) {
        return poolBaseInfo.length;
    }

    // 创建池子。
    function createPoolInfo(
        uint256 _settleTime,
        uint256 _endTime,
        uint64 _interestRate,
        uint256 _maxAmount,
        uint256 _martgegaRate,
        address _lendToken,
        address _borrowToken,
        address _spToken,
        address _jpToken,
        uint256 _autoLiquidationThreshold
    ) public {
        require(_endTime > _settleTime, "time invalid");
        require(_spToken != address(0), "_spToken invalid");
        require(_jpToken != address(0), "_jpToken invalid");

        poolBaseInfo.push(
            PoolBaseInfo({
                settleTime: _settleTime, // 结算时间
                endTime: _endTime, // 结束时间
                interestRate: _interestRate, // 利率。费率。 单位 1e8
                maxSupply: _maxAmount, // 最大供应量
                lendSupply: 0, // 贷款人的供应量
                borrowSupply: 0, // 借款人的供应量
                martgageRate: _martgegaRate, // 抵押率。 单位 1e8
                lendToken: _lendToken, // 贷款方的token地址
                borrowToken: _borrowToken, // 借款方的token地址
                state: defaultChoice, // 状态
                spCoin: IDebtToken(_spToken), // sp token 的erc20地址
                jpCoin: IDebtToken(_jpToken), // jp token 的erc20地址
                autoLiquidateThreshold: _autoLiquidationThreshold // 自动清算的阙值
            })
        );

        poolDataInfo.push(
            PoolDataInfo({
                settleAmountLend: 0, // 结算时，实际贷款金额
                settleAmountBorrow: 0, // 结算时，实际借款金额
                finishAmountLend: 0, // 完成时，实际贷款金额
                finishAmountBorrow: 0, // 完成时，实际借款金额
                liquidationAmountLend: 0, // 清算时，实际贷款金额
                liquidationAmountBorrow: 0 // 清算时，实际借款金额
            })
        );
    }

    function getPoolState(uint256 poolId) public returns (uint256) {
        return uint256(poolBaseInfo[poolId].state);
    }

    modifier timeBefore(uint256 poolId) {
        require(
            block.timestamp < poolBaseInfo[poolId].settleTime,
            "timeBefore error"
        );
        _;
    }
    modifier timeAfter(uint256 poolId) {
        require(
            block.timestamp > poolBaseInfo[poolId].settleTime,
            "timeAfter error"
        );
        _;
    }
    modifier stateMatch(uint256 poolId) {
        PoolState state = poolBaseInfo[poolId].state;
        require(state == PoolState.MATCH, "state MATCH");
        _;
    }
    modifier stateUndone(uint256 poolId) {
        PoolState state = poolBaseInfo[poolId].state;
        require(state == PoolState.UNDONE, "state UNDONE");
        _;
    }
    modifier stateNotMatchUndone(uint256 poolId) {
        PoolState state = poolBaseInfo[poolId].state;
        require(
            state != PoolState.MATCH && state != PoolState.UNDONE,
            "state not MATCH UNDONE"
        );
        _;
    }
    modifier stateFinishLiquidation(uint256 poolId) {
        PoolState state = poolBaseInfo[poolId].state;
        require(
            state == PoolState.FINISH || state == PoolState.LIQUIDATION,
            "state FINISH LIQUIDATION"
        );
        _;
    }

    // 用户，贷款。存入。 ETH 或 ERC20
    function depositLend(
        uint256 poolId,
        uint256 stakeAmount
    )
        public
        payable
        whenNotPaused
        nonReentrant
        timeBefore(poolId)
        stateMatch(poolId)
    {
        PoolBaseInfo storage poolBase = poolBaseInfo[poolId];
        PoolDataInfo storage poolData = poolDataInfo[poolId];
        LendInfo storage lendInfo = userLendInfo[msg.sender][poolId];

        // 看额度。
        require(
            stakeAmount <= (poolBase.maxSupply - poolBase.lendSupply),
            "stakeAmount too much"
        );

        // 接收用户的金额。 ETH 或 ERC20
        uint256 amount = getPayableAmount(poolBase.lendToken, stakeAmount);
        require(amount > 0, "amount is zero");

        lendInfo.hasNoRefund = false;
        lendInfo.hasNoClaim = false;

        // ETH 或 ERC20
        uint256 realAmount = (poolBase.lendToken == address(0))
            ? msg.value
            : stakeAmount;
        lendInfo.stakeAmount += realAmount;
        poolBase.lendSupply += realAmount;

        emit DepositLend(
            msg.sender,
            poolBase.lendToken,
            stakeAmount,
            realAmount
        );
    }

    // 用户，借款。存入。 ETH 或 ERC20
    // 存入抵押品，才能借款。
    function depositBorrow(
        uint256 poolId,
        uint256 stakeAmount
    )
        public
        payable
        whenNotPaused
        nonReentrant
        timeBefore(poolId)
        stateMatch(poolId)
    {
        PoolBaseInfo storage poolBase = poolBaseInfo[poolId];
        PoolDataInfo storage poolData = poolDataInfo[poolId];
        BorrowInfo storage borrowInfo = userBorrowInfo[msg.sender][poolId];

        // todo 借款人，为啥要给合约？
        // 用户存入抵押品，才能借款。 抵押品价值 > 借款金额（通常超额抵押 150%+）
        // 接收用户的金额。 ETH 或 ERC20
        uint256 amount = getPayableAmount(poolBase.borrowToken, stakeAmount);
        require(amount > 0, "amount is zero");

        borrowInfo.hasNoRefund = false;
        borrowInfo.hasNoClaim = false;

        // ETH 或 ERC20
        uint256 realAmount = (poolBase.borrowToken == address(0))
            ? msg.value
            : stakeAmount;
        borrowInfo.stakeAmount += realAmount;
        poolBase.borrowSupply += realAmount;

        emit DepositBorrow(
            msg.sender,
            poolBase.borrowToken,
            stakeAmount,
            realAmount
        );
    }

    // 取款。本金，利息
    // 结束后才能。
    function withdrawLend(
        uint256 poolId,
        uint256 amount
    ) external whenNotPaused nonReentrant stateFinishLiquidation(poolId) {
        PoolBaseInfo storage poolBase = poolBaseInfo[poolId];
        PoolDataInfo storage poolData = poolDataInfo[poolId];
        LendInfo storage lendInfo = userLendInfo[msg.sender][poolId];

        require(amount > 0, "amount invalid");

        // 销毁。
        poolBase.spCoin.burn(msg.sender, amount);

        // 用户的比例。
        uint256 userShare = (amount * calDecimal) / poolData.settleAmountLend;
        // 用户的金额。
        uint256 userAmount = 0;
        // 完成
        if (poolBase.state == PoolState.FINISH) {
            // 时间到了。
            require(poolBase.endTime < block.timestamp, "endTime not match ");
            // 用户的金额。
            userAmount = (userShare * poolData.finishAmountLend) / calDecimal;
        }
        // 清算。
        else if (poolBase.state == PoolState.LIQUIDATION) {
            // 时间到了。
            require(
                poolBase.settleTime < block.timestamp,
                "settleTime not match "
            );
            // 用户的金额。
            userAmount =
                (userShare * poolData.liquidationAmountLend) /
                calDecimal;
        }

        // 转账。
        _redeem(msg.sender, poolBase.lendToken, userAmount);

        emit WithdrawLend(msg.sender, poolBase.lendToken, userAmount, amount);
    }

    // 用户，贷款。退款。
    // todo 只能退1次？
    function refundLend(
        uint256 poolId
    )
        public
        whenNotPaused
        nonReentrant
        timeAfter(poolId)
        stateNotMatchUndone(poolId)
    {
        PoolBaseInfo storage poolBase = poolBaseInfo[poolId];
        PoolDataInfo storage poolData = poolDataInfo[poolId];
        LendInfo storage lendInfo = userLendInfo[msg.sender][poolId];

        require(lendInfo.stakeAmount > 0, "stakeAmount is zero");
        // 池子还有未退款的金额
        require(
            poolBase.lendSupply > poolData.settleAmountLend,
            "no refund amount "
        );
        // 不能重复退款。
        require(!lendInfo.hasNoRefund, "refund repeat");

        // 用户占比 = 用户金额 / 总金额
        uint256 userShare = (lendInfo.stakeAmount * calDecimal) /
            poolBase.lendSupply;

        // 剩余lend金额。
        uint256 leftLendAmount = poolBase.lendSupply -
            poolData.settleAmountLend;

        // 用户金额 = 剩余lend金额 * 用户占比
        uint256 refundAmount = (leftLendAmount * userShare) / calDecimal;

        // 转给用户。 ETH ERC20
        _redeem(msg.sender, poolBase.lendToken, refundAmount);

        // 只能退款1次
        lendInfo.hasNoRefund = true;
        lendInfo.refundAmount += refundAmount;

        emit RefundLend(msg.sender, poolBase.lendToken, refundAmount);
    }

    // 用户，借款。退款。
    // todo 只能退1次？
    function refundBorrow(
        uint256 poolId
    )
        public
        whenNotPaused
        nonReentrant
        timeAfter(poolId)
        stateNotMatchUndone(poolId)
    {
        PoolBaseInfo storage poolBase = poolBaseInfo[poolId];
        PoolDataInfo storage poolData = poolDataInfo[poolId];
        BorrowInfo storage borrowInfo = userBorrowInfo[msg.sender][poolId];

        require(
            poolBase.borrowSupply > poolData.settleAmountBorrow,
            "amount not match"
        );
        require(borrowInfo.stakeAmount > 0, "stakeAmount is zero");
        // 不能重复退款。
        require(!borrowInfo.hasNoRefund, "refund repeat");

        // 用户占比 = 用户金额 / 总金额
        uint256 userShare = (borrowInfo.stakeAmount * calDecimal) /
            poolBase.borrowSupply;

        // 剩余lend金额。
        uint256 leftAmount = poolBase.borrowSupply -
            poolData.settleAmountBorrow;

        // 用户金额 = 剩余lend金额 * 用户占比
        uint256 refundAmount = (leftAmount * userShare) / calDecimal;

        // 转给用户。 ETH ERC20
        _redeem(msg.sender, poolBase.borrowToken, refundAmount);

        // 只能退款1次
        borrowInfo.hasNoRefund = true;
        borrowInfo.refundAmount += refundAmount;

        emit RefundBorrow(msg.sender, poolBase.borrowToken, refundAmount);
    }

    // 领取 spToken
    // 只能领取1次。
    function claimLend(
        uint256 poolId
    )
        public
        whenNotPaused
        nonReentrant
        timeAfter(poolId)
        stateNotMatchUndone(poolId)
    {
        PoolBaseInfo storage poolBase = poolBaseInfo[poolId];
        PoolDataInfo storage poolData = poolDataInfo[poolId];
        LendInfo storage lendInfo = userLendInfo[msg.sender][poolId];

        require(lendInfo.stakeAmount > 0, "stakeAmount invalid");
        //只能领取1次。
        require(!lendInfo.hasNoClaim, "hasNoClaim");

        // 用户的比例。
        uint256 userShare = (lendInfo.stakeAmount * calDecimal) /
            poolBase.lendSupply;

        // 用户的数量。
        uint256 userAmount = (userShare * poolData.settleAmountLend) /
            calDecimal;

        // 给用户新的token。
        poolBase.spCoin.mint(msg.sender, userAmount);

        // 只能领取1次。
        lendInfo.hasNoClaim = true;

        // todo 这里不是 lendToken ？
        emit ClaimLend(msg.sender, poolBase.borrowToken, userAmount);
    }

    // 取款。紧急。 状态是未完成。
    function emergencyLendWithdrawal(
        uint256 poolId
    ) external whenNotPaused nonReentrant stateUndone(poolId) {
        PoolBaseInfo storage poolBase = poolBaseInfo[poolId];
        PoolDataInfo storage poolData = poolDataInfo[poolId];
        LendInfo storage lendInfo = userLendInfo[msg.sender][poolId];

        require(poolBase.lendSupply > 0, "lendSupply invalid");
        require(lendInfo.stakeAmount > 0, "stakeAmount invalid");
        // 没有退款。
        require(!lendInfo.hasNoRefund, "hasNoRefund");

        // 转账。
        _redeem(msg.sender, poolBase.lendToken, lendInfo.stakeAmount);

        // 没有退款了。
        lendInfo.hasNoRefund = true;

        emit EmergencyLendWithdrawal(
            msg.sender,
            poolBase.lendToken,
            lendInfo.stakeAmount
        );
    }
}
