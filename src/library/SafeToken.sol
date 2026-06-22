// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library SafeToken {
    // 余额。自己的。
    function myBalance(address tokenAddr) public view returns (uint256) {
        return IERC20(tokenAddr).balanceOf(address(this));
    }

    // 余额。指定人。
    function balance(
        address tokenAddr,
        address user
    ) public view returns (uint256) {
        return IERC20(tokenAddr).balanceOf(user);
    }

    // 授权。
    function safeApprove(address tokenAddr, address to, uint256 amount) public {
        (bool success, bytes memory data) = tokenAddr.call(
            abi.encodeWithSelector(
                IERC20(tokenAddr).approve.selector,
                to,
                amount
            )
        );
        require(success, "call fail");
        require(
            data.length == 0 || abi.decode(data, (bool)),
            "safeApprove fail"
        );
    }

    // 转账。
    function safeTransfer(
        address tokenAddr,
        address to,
        uint256 amount
    ) public {
        (bool success, bytes memory data) = tokenAddr.call(
            abi.encodeWithSelector(
                IERC20(tokenAddr).transfer.selector,
                to,
                amount
            )
        );
        require(success, "call fail");
        require(
            data.length == 0 || abi.decode(data, (bool)),
            "safeTransfer fail"
        );
    }

    // 转账。
    function safeTransferFrom(
        address tokenAddr,
        address from,
        address to,
        uint256 amount
    ) public {
        (bool success, bytes memory data) = tokenAddr.call(
            abi.encodeWithSelector(
                IERC20(tokenAddr).transferFrom.selector,
                from,
                to,
                amount
            )
        );
        require(success, "call fail");
        require(
            data.length == 0 || abi.decode(data, (bool)),
            "safeTransfer fail"
        );
    }
}
