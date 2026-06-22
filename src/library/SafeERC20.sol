// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
// import {
//     IERC721
// } from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
// import {
//     IERC20
// } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

library SafeERC20 {
    using Address for address;

    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        bytes memory returnData = address(token).functionCall(
            data,
            "IERC20 call fail"
        );

        if (returnData.length > 0) {
            bool ok = abi.decode(returnData, (bool));
            require(ok, "IERC20 _callOptionalReturn fail");
        }
    }

    // 转账。
    function safeTransfer(IERC20 token, address to, uint256 amount) public {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transfer.selector, to, amount)
        );
    }
    // 转账。
    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) public {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.transferFrom.selector,
                from,
                to,
                amount
            )
        );
    }

    // 授权额度。
    function safeApprove(IERC20 token, address spender, uint256 amount) public {
        require(
            amount == 0 || (token.allowance(address(this), spender) == 0),
            "approve init is not zero"
        );
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.approve.selector, spender, amount)
        );
    }
}
