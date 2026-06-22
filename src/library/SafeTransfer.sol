// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Address.sol";
import "./SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

library SafeTransfer {
    using SafeERC20 for IERC20;

    // 兑换。赎回。
    event Redeem(
        address indexed recipientor,
        address indexed token,
        uint256 amount
    );

    // 把钱转到池子。
    function getPayableAmount(
        address token,
        uint256 amount
    ) internal returns (uint256) {
        // eth 。直接收到了。不需要转账。
        if (token == address(0)) {
            return msg.value;
        }
        if (amount > 0) {
            // token 需要转。
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
        return amount;
    }

    // 赎回。 把钱转给某人。
    function _redeem(
        address payable recipientor,
        address token,
        uint256 amount
    ) internal {
        // 转出 eth
        if (token == address(0)) {
            recipientor.transfer(amount);
        } else {
            // token 需要转。
            IERC20(token).safeTransfer(recipientor, amount);
        }

        emit Redeem(recipientor, token, amount);
    }
}
