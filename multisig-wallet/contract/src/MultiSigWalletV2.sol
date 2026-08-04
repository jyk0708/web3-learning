// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MultiSigWalletUpgradeable.sol";
/**
 * @title 多签钱包 V2
 * @dev 多签钱包 V2 是多签钱包的升级版本，支持升级到新的实现合约。
 */
contract MultiSigWalletV2 is MultiSigWalletUpgradeable {
    // ================ 新加的状态变量 ================
    uint256 public version;
    mapping(address => uint256) public ownerVoteCount;
    // ================ 新加的事件 ================
    event VersionUpgrade(uint256 indexed oldVersion, uint256 indexed newVersion);
    event OwnerVoteCountUpdated(address indexed owner, uint256 indexed newVoteCount);
    /**
     * @dev 初始化多签钱包 V2
     * @param _version 多签钱包 V2 的版本号
     */
    function initializeV2(uint256 _version) public reinitializer(2) {
        version = _version;
        emit VersionUpgrade(1, _version);
    }

    /**
     * @dev 确认交易提案
     * @param _txIndex 交易提案的索引
    * 功能增强：
     * - 继承父类的所有验证逻辑（onlyOwner, txExists, notExecuted, notConfirmed）
     * - 在确认交易后，自动增加确认者的投票计数
     */
    function confirmTx(uint256 _txIndex) public override virtual onlyOwner txExists(_txIndex) notExecuted(_txIndex) notConfirmed(_txIndex) {
        // 调用父类的确认逻辑（包含所有验证和状态更新）
        super.confirmTx(_txIndex);
         // V2 新功能：确认交易时自动增加投票计数
        ownerVoteCount[_msgSender()] += 1;
        emit OwnerVoteCountUpdated(_msgSender(), ownerVoteCount[_msgSender()]);
    }

    // ============ 新功能 ============
    /**
     * @dev 增加所有者的投票计数（演示新功能）
     * @notice 可以手动增加投票计数，但确认交易时会自动增加
     * @param owner 所有者地址
     */
    function incrementOwnerVoteCount(address owner) public onlyOwner {
        require(ownerMapping[owner], "Not an owner");
        ownerVoteCount[owner] += 1;
        emit OwnerVoteCountUpdated(owner, ownerVoteCount[owner]);
    }

    /**
     * @dev 撤销确认交易提案
     * @param _txIndex 交易提案的索引
     * 功能增强：
     * - 继承父类的所有验证逻辑（onlyOwner, txExists, notExecuted）
     * - 在撤销确认后，自动减少撤销者的投票计数（但不能低于0）
     */
    function revokeConfirmTx(uint256 _txIndex) public virtual override onlyOwner txExists(_txIndex) notExecuted(_txIndex) hasConfirmed(_txIndex) {
        super.revokeConfirmTx(_txIndex);

        // V2 新功能：撤销确认时减少投票计数（但不能低于0）
        if (ownerVoteCount[_msgSender()] > 0) {
            ownerVoteCount[_msgSender()] -= 1;
            emit OwnerVoteCountUpdated(_msgSender(), ownerVoteCount[_msgSender()]);
        }
    }


    /**
     * @dev 获取所有者的投票计数
     * @param owner 所有者地址
     * @return 投票计数
     */
    function getOwnerVoteCount(address owner) public view returns (uint256) {
        return ownerVoteCount[owner];
    }

    // ============ 存储间隙 ============
    uint256[48] private __gap;
}