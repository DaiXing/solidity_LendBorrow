// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// 多签。
interface IMultiSignature {
    // 生成有效的签名。
    function getValidSignature(
        bytes32 msghash,
        uint256 lastIndex
    ) external view returns (uint256);
}

contract MultiSignatureClient {
    // 字段key。
    uint256 private constant multiSignaturePosition =
        uint256(keccak256("org.multiSignature.storage"));
    uint256 private constant defaultIndex = 0;

    // 传入一个子类地址。
    constructor(address multiSignature) public {
        require(multiSignature != address(0), "multiSignature invalid ");

        // 保存地址。
        saveValue(multiSignaturePosition, uint256(uint160(multiSignature)));
    }

    // 写值
    function saveValue(uint256 position, uint256 value) public {
        assembly {
            // position = value
            sstore(position, value) // 末尾没有分号
        }
    }

    // 读值
    function getValue(uint256 position) public returns (uint256 value) {
        assembly {
            value := sload(position) // 末尾没有分号
        }
    }

    function getMultiSignatureAddress() public returns (address) {
        return address(uint160(getValue(multiSignaturePosition)));
    }

    // 校验多签。
    function checkMultiSignature() internal {
        uint256 value;
        assembly {
            value := callvalue() // 末尾没有分号
        }

        // msg的哈希
        // todo 没有带交易？ sender 没法区分交易
        bytes32 msghash = keccak256(
            abi.encodePacked(msg.sender, address(this))
        );

        address multiSign = getMultiSignatureAddress();

        // 多签。
        uint256 newIndex = IMultiSignature(multiSign).getValidSignature(
            msghash,
            defaultIndex
        );

        // 未授权。
        require(newIndex > defaultIndex, "TX is not approved");
    }

    // 调用是有效的。 验证多个签名。
    modifier validCall() {
        checkMultiSignature();
        _;
    }
}
