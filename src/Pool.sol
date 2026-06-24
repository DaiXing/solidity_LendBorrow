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
    ) public payable whenNotPaused nonReentrant {
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

    function refundLend() public {}
}
