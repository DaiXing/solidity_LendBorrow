// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./MultiSignatureClient.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// 地址的权限。
contract AddressPrivileges is MultiSignatureClient {
    using EnumerableSet for EnumerableSet.AddressSet;

    // 铸造者。
    EnumerableSet.AddressSet private _minters;

    constructor(
        address multiSignature
    ) public MultiSignatureClient(multiSignature) {}

    // 添加。
    function addMinter(address minter) public returns (bool) {
        require(minter != address(0), "minter invalid");
        return _minters.add(minter);
    }

    // 删除
    function delMinter(address minter) public returns (bool) {
        require(minter != address(0), "minter invalid");
        return _minters.remove(minter);
    }

    // 数量。
    function getMinterLength() public returns (uint256) {
        return _minters.length();
    }

    // 包含。
    function isMinter(address minter) public returns (bool) {
        require(minter != address(0), "minter invalid");
        return _minters.contains(minter);
    }

    // 读取
    function getMinter(uint256 index) public returns (bool) {
        require(index < getMinterLength(), "index invalid");
        return _minters.at(index);
    }

    modifier onlyMinter() {
        require(isMinter(msg.sender), "not minter");
        _;
    }
}
