// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library Address {
    // 地址，是否合约。
    function isContract(address addr) public view returns (bool) {
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
    ) private pure returns (bytes memory) {
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

    // 代理调用。
    function functionDelegateCall(
        address target,
        bytes memory data
    ) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "functionDelegateCall fail");
    }

    // 静态调用。
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errMsg
    ) internal view returns (bytes memory) {
        require(isContract(target), "target is not contract ");

        (bool success, bytes memory returnData) = target.staticcall(data);
        return _verifyCallResult(success, returnData, errMsg);
    }

    // 静态调用。
    function functionStaticCall(
        address target,
        bytes memory data
    ) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "functionStaticCall fail");
    }

    // 普通调用。带上eth
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errMsg
    ) internal returns (bytes memory) {
        require(isContract(target), "target is not contract ");
        require(value > 0, "value invalid");

        (bool success, bytes memory returnData) = target.call{value: value}(
            data
        );
        return _verifyCallResult(success, returnData, errMsg);
    }

    // 普通调用。带上eth
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return
            functionCallWithValue(
                target,
                data,
                value,
                "functionCallWithValue fail"
            );
    }

    // 普通调用。不带eth
    function functionCall(
        address target,
        bytes memory data,
        string memory errMsg
    ) internal returns (bytes memory) {
        // value 填 0
        return functionCallWithValue(target, data, 0, errMsg);
    }

    // 普通调用。不带eth
    function functionCall(
        address target,
        bytes memory data
    ) internal returns (bytes memory) {
        // value 填 0
        return functionCallWithValue(target, data, 0, "functionCall fail");
    }
}
