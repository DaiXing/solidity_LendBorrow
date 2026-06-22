// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library Address {
    // 地址，是否合约。
    function isContract(address addr) public returns (bool) {
        uint256 size;
        // 取代码size。
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    // 发送eth
    function sendValue(address payable recipient, uint256 amount) internal {
        (bool ok, ) = recipient.call{value: amount}("");
        require(ok, "sendValue fail");
    }

    // 验证调用结果。
    function _verifyCallResult(
        bool success,
        bytes memory returnData,
        string memory errMsg
    ) private returns (bytes memory) {
        if (success) {
            return returnData;
        }

        if (returnData.length > 0) {
            assembly {
                let size := mload(returnData)
                revert(add(32, returnData), size)
            }
        } else {
            revert(errMsg);
        }
    }

    // 代理调用。
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errMsg
    ) internal returns (bytes memory) {
        require(isContract(target), "target is not contract ");

        (bool success, bytes memory returnData) = target.delegatecall(data);
        return _verifyCallResult(success, returnData, errMsg);
    }
}
