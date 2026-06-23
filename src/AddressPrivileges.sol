// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./MultiSignatureClient.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract AddressPrivileges is MultiSignatureClient {
    using EnumerableSet for EnumerableSet.AddressSet;

    constructor(
        address multiSignature
    ) public MultiSignatureClient(multiSignature) {}
}
