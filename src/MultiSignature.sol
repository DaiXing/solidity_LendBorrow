// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./MultiSignatureClient.sol";

// 白名单地址。
library WhiteListAddress {
    // 地址是合格的。 去重。
    function isEligibleAddress(
        address[] memory whiteList,
        address tmp
    ) public pure returns (bool) {
        uint256 len = whiteList.length;
        // 遍历。
        for (uint256 k = 0; k < len; k++) {
            // 地址相等。
            if (whiteList[k] == tmp) {
                return true;
            }
        }
        return false;
    }

    // 添加白名单地址。
    function addWhiteListAddress(
        address[] storage whiteList,
        address tmp
    ) internal {
        // 地址去重。
        if (!isEligibleAddress(whiteList, tmp)) {
            whiteList.push(tmp);
        }
    }

    // 删除白名单地址。
    function removeWhiteListAddress(
        address[] storage whiteList,
        address tmp
    ) internal returns (bool found) {
        uint256 len = whiteList.length;

        uint256 k = 0;
        for (; k < len; k++) {
            // 找到。
            if (whiteList[k] == tmp) {
                found = true;
                break;
            }
        }

        if (found) {
            // 删除。
            whiteList[k] = whiteList[len - 1];
            whiteList.pop();
        }
    }
}

// 多签。
contract MultiSignature is MultiSignatureClient {
    uint256 private constant defaultIndex = 0;

    // 数组，也可以用lib
    using WhiteListAddress for address[];

    // 多个owner 。有权签名。
    address[] public signatureOwners;

    // 阈值。 满足几个签名。
    uint256 public threshold;

    // 签名请求。 某人创建了请求，需要多个人签名。
    struct signatureInfo {
        // 申请人。
        address applicant;
        // 签名人。
        address[] signatures;
    }

    // 全部签名。 key = 申请人。
    mapping(bytes32 => signatureInfo[]) signatureMap;

    // 切换owner
    event TransferOwner(
        address indexed sender,
        address indexed oldOwner,
        address indexed newOwner
    );

    // 创建申请。
    event CreateApplication(
        address indexed from,
        address indexed to,
        bytes32 indexed msghash
    );

    // 签名一个申请
    event SignApplication(
        address indexed from,
        bytes32 indexed msghash,
        uint256 index
    );

    // 撤销一个申请。
    event RevokeApplication(
        address indexed from,
        bytes32 indexed msghash,
        uint256 index
    );

    constructor(
        address[] memory owners,
        uint256 limitSignNum
    ) public MultiSignatureClient(address(this)) {
        // 数量必须够。
        require(owners.length >= limitSignNum, "limitSignNum is too small");
        signatureOwners = owners;
        threshold = limitSignNum;
    }
    // 只能owner
    modifier onlyOwner() {
        require(signatureOwners.isEligibleAddress(msg.sender), "not owner");
        _;
    }
    // 下标，不能越界
    modifier validIndex(bytes32 msghash, uint256 index) {
        require(signatureMap[msghash].length > index, "index exceed");
        _;
    }

    // 切换owner。 新owner代替老owner。
    function transferOwner(uint256 index, address newOwner) public {
        require(index < signatureOwners.length, "index invalid");
        address oldOwner = signatureOwners[index];
        signatureOwners[index] = newOwner;
        emit TransferOwner(msg.sender, oldOwner, newOwner);
    }

    function getApplicationHash(
        address from,
        address to
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(from, to));
    }

    // 创建申请。
    function createApplication(address to) public returns (uint256 index) {
        // 主要表示请求人。
        bytes32 msghash = getApplicationHash(msg.sender, to);

        // 下标。
        index = signatureMap[msghash].length;

        // 放个集合。
        signatureMap[msghash].push(
            signatureInfo({applicant: msg.sender, signatures: new address[](0)})
        );

        emit CreateApplication(msg.sender, to, msghash);
    }

    // 自己，签名。
    function signApplication(bytes32 msghash) public onlyOwner {
        // 把自己，加入已签名列表。
        signatureMap[msghash][defaultIndex].signatures.addWhiteListAddress(
            msg.sender
        );

        emit SignApplication(msg.sender, msghash, defaultIndex);
    }

    // 自己，取消签名。
    function revokeApplication(bytes32 msghash) public onlyOwner {
        // 把自己，从已签名列表中删除
        signatureMap[msghash][defaultIndex].signatures.removeWhiteListAddress(
            msg.sender
        );

        emit RevokeApplication(msg.sender, msghash, defaultIndex);
    }

    // 返回1个有效的签名。
    function getValidSignature(
        bytes32 msghash,
        uint256 lastIndex // 起点。
    ) public returns (uint256) {
        signatureInfo[] storage infos = signatureMap[msghash];
        uint256 len = infos.length;
        for (uint256 k = lastIndex; k < len; k++) {
            // 签名的个数，满足了。
            if (infos[k].signatures.length >= threshold) {
                return k + 1;
            }
        }
        return 0;
    }

    // 查询1个申请。
    function getApplicationInfo(
        bytes32 msghash,
        uint256 index
    )
        public
        view
        validIndex(msghash, index)
        returns (address, address[] memory)
    {
        signatureInfo[] storage infos = signatureMap[msghash];
        return (infos[index].applicant, infos[index].signatures);
    }

    // 查询申请的数量。
    function getApplicationCount(
        bytes32 msghash
    ) public view returns (uint256) {
        signatureInfo[] storage infos = signatureMap[msghash];
        return infos.length;
    }
}
