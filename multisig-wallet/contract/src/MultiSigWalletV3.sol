// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MultiSigWalletV2.sol";

/**
 * @title 多签钱包 V3
 * @dev V3 新增：紧急暂停功能
 *      - 暂停时无法创建提案、确认提案、执行提案
 *      - Owner 管理（add/remove/changeThreshold）不受暂停影响
 *      - 版本号升级到 3
 */
contract MultiSigWalletV3 is MultiSigWalletV2 {
    // ================ V3 新增状态变量 ================
    bool public paused;

    // ================ V3 新增事件 ================
    event Paused(address indexed account);
    event Unpaused(address indexed account);

    // ================ V3 modifier ================
    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    modifier whenPaused() {
        require(paused, "Contract is not paused");
        _;
    }

    // ================ V3 初始化 ================
    /**
     * @dev 升级到 V3 后调用，设置版本号
     * reinitializer(3) 表示这是第 3 次初始化（initialize=1, initializeV2=2, initializeV3=3）
     */
    function initializeV3() public reinitializer(3) {
        version = 3;
        paused = false;
    }

    // ================ V3 新功能：暂停 ================
    /**
     * @dev 暂停合约（只有 owner 能调用）
     * 暂停后：createProposal / confirmTx / revokeConfirmTx / executeTx 全部无法调用
     */
    function pause() public onlyOwner whenNotPaused {
        paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev 恢复合约（只有 owner 能调用）
     */
    function unpause() public onlyOwner whenPaused {
        paused = false;
        emit Unpaused(_msgSender());
    }

    // ================ V3 重写：在有风险的操作上加 whenNotPaused ================

    /// @dev 覆盖 V1 的 createProposal，加暂停检查
    function createProposal(
        address _to,
        uint256 _value,
        bytes memory _data
    ) public virtual override whenNotPaused {
        super.createProposal(_to, _value, _data);
    }

    /// @dev 覆盖 V2 的 confirmTx，加暂停检查
    function confirmTx(uint256 _txIndex) public virtual override whenNotPaused {
        super.confirmTx(_txIndex);
    }

    /// @dev 覆盖 V1 的 revokeConfirmTx，加暂停检查
    function revokeConfirmTx(uint256 _txIndex) public virtual override whenNotPaused {
        super.revokeConfirmTx(_txIndex);
    }

    /// @dev 覆盖 V1 的 executeTx，加暂停检查
    function executeTx(uint256 _txIndex) public virtual override whenNotPaused {
        super.executeTx(_txIndex);
    }
}
