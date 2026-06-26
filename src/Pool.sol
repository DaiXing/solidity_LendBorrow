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
        feeAddress = payable(addr);
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

    // 用户，借款人。存入保证金。 ETH 或 ERC20
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
        // 借款人，取回钱。
        _redeem(msg.sender, poolBase.lendToken, userAmount);

        emit WithdrawLend(msg.sender, poolBase.lendToken, userAmount, amount);
    }

    // 取款。借款人，拿回保证金。
    // 结束后才能。
    function withdrawBorrow(
        uint256 poolId,
        uint256 jpAmount
    ) external whenNotPaused nonReentrant stateFinishLiquidation(poolId) {
        PoolBaseInfo storage poolBase = poolBaseInfo[poolId];
        PoolDataInfo storage poolData = poolDataInfo[poolId];
        BorrowInfo storage borrowInfo = userBorrowInfo[msg.sender][poolId];

        require(jpAmount > 0, "jpAmount invalid");

        // 销毁。
        poolBase.jpCoin.burn(msg.sender, jpAmount);

        // jp token 数量。
        uint256 totalJpAmount = (poolData.settleAmountLend *
            poolBase.martgageRate) / baseDecimal;

        // 用户的比例。
        uint256 jpShare = (jpAmount * calDecimal) / totalJpAmount;

        // 用户的金额。
        uint256 userAmount = 0;
        // 完成
        if (poolBase.state == PoolState.FINISH) {
            // 时间到了。
            require(poolBase.endTime < block.timestamp, "endTime not match ");
            // 用户的金额。
            userAmount = (jpShare * poolData.finishAmountBorrow) / calDecimal;
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
                (jpShare * poolData.liquidationAmountBorrow) /
                calDecimal;
        }

        // 转账。
        _redeem(msg.sender, poolBase.borrowToken, userAmount);

        emit WithdrawBorrow(
            msg.sender,
            poolBase.borrowToken,
            jpAmount,
            userAmount
        );
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

    // 领取 spToken
    // 只能领取1次。
    function claimBorrow(
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

        require(borrowInfo.stakeAmount > 0, "stakeAmount invalid");
        //只能领取1次。
        require(!borrowInfo.hasNoClaim, "hasNoClaim");

        // jp token 数量。
        uint256 totalJpAmount = (poolData.settleAmountLend *
            poolBase.martgageRate) / baseDecimal;

        // 用户的比例。
        uint256 userShare = (borrowInfo.stakeAmount * calDecimal) /
            poolBase.borrowSupply;

        // 用户的数量。
        uint256 jpAmount = (userShare * totalJpAmount) / calDecimal;

        // 给用户新的token。
        // todo jpToken  是什么
        poolBase.jpCoin.mint(msg.sender, jpAmount);

        // todo 为什么用 settleAmountLend lendToken ？
        uint256 borrowAmount = (userShare * poolData.settleAmountLend) /
            calDecimal;

        // todo 核心逻辑： 贷款人，把钱存入 lendToken 。借款人，从 lendToken 获得钱。
        // todo 结算后，借款人才能拿到借款？
        _redeem(msg.sender, poolBase.lendToken, borrowAmount);

        // 只能领取1次。
        borrowInfo.hasNoClaim = true;

        // todo 这里是 borrowToken ？ 前面为啥是 lend ？
        emit ClaimBorrow(msg.sender, poolBase.borrowToken, jpAmount);
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

    // 取款。紧急。 状态是未完成。
    function emergencyBorrowWithdrawal(
        uint256 poolId
    ) external whenNotPaused nonReentrant stateUndone(poolId) {
        PoolBaseInfo storage poolBase = poolBaseInfo[poolId];
        PoolDataInfo storage poolData = poolDataInfo[poolId];
        BorrowInfo storage borrowInfo = userBorrowInfo[msg.sender][poolId];

        require(poolBase.borrowSupply > 0, "borrowSupply invalid");
        require(borrowInfo.stakeAmount > 0, "stakeAmount invalid");
        // 没有退款。
        require(!borrowInfo.hasNoRefund, "hasNoRefund");

        // 转账。
        _redeem(msg.sender, poolBase.borrowToken, borrowInfo.stakeAmount);

        // 没有退款了。
        borrowInfo.hasNoRefund = true;

        emit EmergencyBorrowWithdrawal(
            msg.sender,
            poolBase.borrowToken,
            borrowInfo.stakeAmount
        );
    }

    // 获得最新的预言机价格。 2种 token 价格。
    function getUnderlyingPriceView(
        uint256 poolId
    ) public returns (uint256[2] memory) {
        PoolBaseInfo storage poolBase = poolBaseInfo[poolId];

        // 批量查token 价格。
        uint256[] memory assets = new uint256[](2);
        assets[0] = uint256(uint160(poolBase.lendToken));
        assets[1] = uint256(uint160(poolBase.borrowToken));

        uint256[] memory prices = oracle.getPrices(assets);
        return [prices[0], prices[1]];
    }

    // 能否结算。 结算时间到了。
    function checkoutSettle(uint256 poolId) public view returns (bool) {
        return poolBaseInfo[poolId].settleTime < block.timestamp;
    }

    // 结算。
    function settle(uint256 poolId) public validCall stateMatch(poolId) {
        PoolBaseInfo storage poolBase = poolBaseInfo[poolId];
        PoolDataInfo storage poolData = poolDataInfo[poolId];

        require(checkoutSettle(poolId), "not settle time ");

        // 贷款金额，保证金，都大于 0  。
        if (poolBase.lendSupply > 0 && poolBase.borrowSupply > 0) {
            // 查价格。
            uint256[2] memory prices = getUnderlyingPriceView(poolId);
            uint256 lendPrice = prices[0];
            uint256 borrowPrice = prices[1];

            // 保证金价值 = 保证金数量 * 保证金价格。
            // todo 为啥 borrowPrice/lendPrice ?
            uint256 borrowValue = (poolBase.borrowSupply *
                ((borrowPrice * calDecimal) / lendPrice)) / calDecimal;

            // 稳定币价值
            // todo 为啥 这样算？
            uint256 actualValue = (borrowValue * baseDecimal) /
                poolBase.martgageRate;

            // 贷款 > 借款
            if (poolBase.lendSupply > actualValue) {
                // todo 为啥这样设置 ？
                poolData.settleAmountLend = actualValue;
                poolData.settleAmountBorrow = poolBase.borrowSupply;
            }
            // 贷款 < 借款
            else {
                poolData.settleAmountLend = poolBase.lendSupply;
                poolData.settleAmountBorrow =
                    (poolBase.lendSupply * poolBase.martgageRate) /
                    ((borrowPrice * baseDecimal) / lendPrice);
            }

            // 改状态。
            poolBase.state = PoolState.EXECUTION;
        }
        // 异常情况。
        else {
            // 改状态。
            poolBase.state = PoolState.UNDONE;

            poolData.settleAmountLend = poolBase.lendSupply;
            poolData.settleAmountBorrow = poolBase.borrowSupply;
        }

        emit StateChange(
            poolId,
            uint256(PoolState.MATCH),
            uint256(poolBase.state)
        );
    }

    // 达到结束时间了。
    function checkoutFinish(uint256 poolId) public returns (bool) {
        return poolBaseInfo[poolId].endTime < block.timestamp;
    }

    // 结束。
    function finish(uint256 poolId) public validCall {
        PoolBaseInfo storage poolBase = poolBaseInfo[poolId];
        PoolDataInfo storage poolData = poolDataInfo[poolId];

        require(checkoutFinish(poolId), "not finish time ");
        require(poolBase.state == PoolState.EXECUTION, "state invalid");

        address token0 = poolBase.borrowToken;
        address token1 = poolBase.lendToken;

        // 因为利率是年利率，所以要1年。
        // 时间比例 = (结束时间 - 结算时间) / 1年
        uint256 timeRatio = ((poolBase.endTime - poolBase.settleTime) *
            baseDecimal) / baseYear;

        // 利息 = 时间比例 * 年利率 * 结算贷款金额
        // timeRatio interestRate 都是扩了 baseDecimal
        uint256 interest = (timeRatio *
            poolBase.interestRate *
            poolData.settleAmountLend) /
            baseDecimal /
            baseDecimal;

        // 贷款金额 = 结算贷款 + 利息
        uint256 lendAmount = poolData.settleAmountLend + interest;

        // lendFee 已经是乘以了 baseDecimal
        // 销售金额 = 贷款金额 * (1+贷款费率)
        uint256 sellAmount = (lendAmount * (lendFee + baseDecimal)) /
            baseDecimal;

        // 交换。
        (uint256 amountSell, uint256 amountIn) = _sellExactAmount(
            swapRouter,
            token0,
            token1,
            sellAmount
        );

        require(amountIn >= lendAmount, "amountIn invalid");

        // 贷款金额。
        if (amountIn > lendAmount) {
            uint256 feeAmount = amountIn - lendAmount;

            // 贷款费。 手续费。
            _redeem(feeAddress, poolBase.lendToken, feeAmount);

            poolData.finishAmountLend = amountIn - feeAmount;
        } else {
            poolData.finishAmountLend = amountIn;
        }

        // 借款金额。
        uint256 remainNowAmount = poolData.settleAmountBorrow - amountSell;
        // 收取手续费。
        uint256 remainBorrowAmount = redeemFees(
            borrowFee, // 费率。
            poolBase.borrowToken, // 保证金地址。
            remainNowAmount
        );
        poolData.finishAmountBorrow = remainBorrowAmount;

        // 状态。
        poolBase.state = PoolState.FINISH;
        emit StateChange(
            poolId,
            uint256(PoolState.EXECUTION),
            uint256(poolBase.state)
        );
    }

    // 赎回。 利息
    function redeemFees(
        uint256 feeRatio,
        address token,
        uint256 amount
    ) internal returns (uint256) {
        // 费用 = 金额 * 费率
        uint256 fee = (amount * feeRatio) / baseDecimal;

        // 赎回。 收取利息。
        if (fee > 0) {
            _redeem(feeAddress, token, fee);
        }

        // 剩余金额。
        return amount - fee;
    }

    // 返回 address。
    function _getSwapPath(
        address _swapRouter,
        address token0,
        address token1
    ) internal returns (address[] memory path) {
        IUniswapV2Router2 swap = IUniswapV2Router2(_swapRouter);
        path = new address[](2);
        path[0] = token0 == address(0) ? swap.WETH() : token0;
        path[1] = token1 == address(0) ? swap.WETH() : token1;
    }

    function _getAmountIn(
        address _swapRouter,
        address token0,
        address token1,
        uint256 amountOut
    ) internal returns (uint256) {
        address[] memory path = _getSwapPath(_swapRouter, token0, token1);
        IUniswapV2Router2 swap = IUniswapV2Router2(_swapRouter);
        uint256[] memory amounts = swap.getAmountsIn(amountOut, path);
        return amounts[0];
    }
    function _safeApprove(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x095ea7b3, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "!safeApprove"
        );
    }
    function _swap(
        address _swapRouter,
        address token0,
        address token1,
        uint256 amount0
    ) internal returns (uint256) {
        if (token0 != address(0)) {
            _safeApprove(token0, _swapRouter, type(uint256).max);
        }
        if (token1 != address(0)) {
            _safeApprove(token1, _swapRouter, type(uint256).max);
        }
        IUniswapV2Router2 swap = IUniswapV2Router2(_swapRouter);
        address[] memory path = _getSwapPath(_swapRouter, token0, token1);
        uint256[] memory amounts;

        if (token0 == address(0)) {
            // 用eth换token
            amounts = swap.swapExactETHForTokens{value: amount0}(
                0,
                path,
                address(this),
                block.timestamp + 30
            );
        } else if (token1 == address(0)) {
            // 用token换eth
            amounts = swap.swapExactTokensForETH(
                amount0,
                0,
                path,
                address(this),
                block.timestamp + 30
            );
        } else {
            // 用token换token
            amounts = swap.swapExactTokensForTokens(
                amount0,
                0,
                path,
                address(this),
                block.timestamp + 30
            );
        }

        // todo 最后的数量。
        uint256 amountLast = amounts[amounts.length - 1];
        emit Swap(token0, token1, amounts[0], amountLast);
        return amountLast;
    }
    function _sellExactAmount(
        address _swapRouter,
        address token0,
        address token1,
        uint256 amountOut
    ) internal returns (uint256, uint256) {
        uint256 amountIn = _getAmountIn(_swapRouter, token0, token1, amountOut);
        uint256 amountSell = amountOut > 0 ? amountIn : 0;
        uint256 amount = _swap(_swapRouter, token0, token1, amountSell);
        return (amountSell, amount);
    }

    // 检查需要清算。 保证金的当前价值，与清算阙值比较。
    function checkoutLiquidate(uint256 poolId) public returns (bool) {
        PoolBaseInfo storage poolBase = poolBaseInfo[poolId];
        PoolDataInfo storage poolData = poolDataInfo[poolId];

        // 查价格。
        uint256[2] memory prices = getUnderlyingPriceView(poolId);
        uint256 priceLend = prices[0];
        uint256 priceBorrow = prices[1];

        // 保证金的价值。
        // todo  为啥 priceBorrow / priceLend
        uint256 borrowValueNow = (poolData.settleAmountBorrow *
            ((priceBorrow * calDecimal) / priceLend)) / calDecimal;

        // 清算阙值。
        uint256 liquidateValue = (poolData.settleAmountLend *
            (baseDecimal + poolBase.autoLiquidateThreshold)) / baseDecimal;

        // 达到阙值
        return liquidateValue > borrowValueNow;
    }

    // 清算
    function liquidate(uint256 poolId) public validCall {
        PoolBaseInfo storage poolBase = poolBaseInfo[poolId];
        PoolDataInfo storage poolData = poolDataInfo[poolId];

        require(block.timestamp > poolBase.settleTime, "time not match");
        require(poolBase.state == PoolState.EXECUTION, "state invalid");

        address token0 = poolBase.borrowToken;
        address token1 = poolBase.lendToken;

        // 事件比例
        uint256 timeRatio = ((poolBase.endTime - poolBase.settleTime) *
            baseDecimal) / baseYear;

        // 利息。
        // timeRatio interestRate 都是扩了 baseDecimal
        uint256 interest = (timeRatio *
            poolBase.interestRate *
            poolData.settleAmountLend) /
            baseDecimal /
            baseDecimal;

        uint256 lendAmount = poolData.settleAmountLend + interest;

        uint256 sellAmount = (lendAmount * (lendFee + baseDecimal)) /
            baseDecimal;

        (uint256 amountSell, uint256 amountIn) = _sellExactAmount(
            swapRouter,
            token0,
            token1,
            sellAmount
        );

        // 贷款金额。
        if (amountIn > lendAmount) {
            // 收取 手续费。
            uint256 feeAmount = amountIn - lendAmount;
            _redeem(feeAddress, poolBase.lendToken, feeAmount);

            poolData.liquidationAmountLend = amountIn - feeAmount;
        } else {
            poolData.liquidationAmountLend = amountIn;
        }

        // 借款金额。
        uint256 remainNowAmount = poolData.settleAmountBorrow - amountSell;
        // 收取 手续费。
        uint256 remainBorrowAmount = redeemFees(
            borrowFee,
            poolBase.borrowToken,
            remainNowAmount
        );
        poolData.liquidationAmountBorrow = remainBorrowAmount;

        // 状态。
        poolBase.state = PoolState.LIQUIDATION;
        emit StateChange(
            poolId,
            uint256(PoolState.EXECUTION),
            uint256(poolBase.state)
        );
    }
}
