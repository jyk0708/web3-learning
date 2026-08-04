// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MultiSigWallet} from "../src/MultiSigWallet.sol";

/**
 * @dev Mock 合约，用于接收以太币并触发事件
 */
contract MockTarget {
    event Received(address sender, uint256 amount);

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function doSomething() external pure returns (bool) {
        return true;
    }
}
/**
 * @dev Mock 合约，用于拒绝以太币并触发事件
 */
contract MockRejector {
    receive() external payable {
        revert("Rejected");
    }
}
/**
 * @dev 多签钱包合约合约测试
 */
contract MultiSigWalletTest is Test {
    MultiSigWallet internal wallet;
    MockTarget internal target;
    MockRejector internal rejector;

    address internal owner1 = address(0x1);
    address internal owner2 = address(0x2);
    address internal owner3 = address(0x3);
    address internal owner4 = address(0x4);
    address internal nonOwner = address(0x99);

    address[] internal owners;

    uint256 internal constant INITIAL_THRESHOLD = 2;
    uint256 internal constant AMOUNT = 1 ether;

    /**
     * @dev 设置测试环境，初始化合约实例
     */
    function setUp() public {
        vm.deal(owner1, 100 ether);
        vm.deal(owner2, 100 ether);
        vm.deal(owner3, 100 ether);
        vm.deal(owner4, 100 ether);

        owners = new address[](3);
        owners[0] = owner1;
        owners[1] = owner2;
        owners[2] = owner3;
        /**
         * @dev 初始化多签钱包合约
         */
        wallet = new MultiSigWallet(owners, INITIAL_THRESHOLD);
        /**
         * @dev 初始化接收以太币合约
         */
        target = new MockTarget();
        /**
         * @dev 初始化拒绝以太币合约
         */
        rejector = new MockRejector();
    }

    // ==================== Constructor Tests ====================
    /**
     * @dev 测试多签钱包合约构造函数，成功创建合约实例
     */
    function test_Constructor_Success() public view {
        assertEq(wallet.getOwnerCount(), 3);
        assertEq(wallet.getThreshold(), 2);
        assertTrue(wallet.isOwner(owner1));
        assertTrue(wallet.isOwner(owner2));
        assertTrue(wallet.isOwner(owner3));
        assertFalse(wallet.isOwner(nonOwner));
    }
    /**
     * @dev 测试多签钱包合约构造函数，失败创建合约实例，空所有者数组
     */
    function test_Constructor_Revert_EmptyOwners() public {
        address[] memory emptyOwners = new address[](0);
        vm.expectRevert("At least one owner is required");
        new MultiSigWallet(emptyOwners, 1);
    }
    /**
     * @dev 测试多签钱包合约构造函数，失败创建合约实例，零确认阈值
     */
    function test_Constructor_Revert_ZeroThreshold() public {
        vm.expectRevert("Num confirmations required must be greater than 0 and less than or equal to the number of owners");
        new MultiSigWallet(owners, 0);
    }
    /**
     * @dev 测试多签钱包合约构造函数，失败创建合约实例，确认阈值超过所有者数量
     */
    function test_Constructor_Revert_ThresholdExceedsOwners() public {
        vm.expectRevert("Num confirmations required must be greater than 0 and less than or equal to the number of owners");
        new MultiSigWallet(owners, 4);
    }
    /**
     * @dev 测试多签钱包合约构造函数，失败创建合约实例，所有者地址为零地址
     */
    function test_Constructor_Revert_ZeroAddressOwner() public {
        address[] memory badOwners = new address[](2);
        badOwners[0] = owner1;
        badOwners[1] = address(0);
        vm.expectRevert("Owner cannot be the zero address");
        new MultiSigWallet(badOwners, 1);
    }
    /**
     * @dev 测试多签钱包合约构造函数，失败创建合约实例，所有者地址重复
     */
    function test_Constructor_Revert_DuplicateOwner() public {
        address[] memory dupOwners = new address[](2);
        dupOwners[0] = owner1;
        dupOwners[1] = owner1;
        vm.expectRevert("Owner not unique");
        new MultiSigWallet(dupOwners, 1);
    }

    // ==================== Owner Management Tests ====================
    /**
     * @dev 测试多签钱包合约添加所有者函数，成功添加所有者
     */
    function test_AddOwner_Success() public {
        vm.prank(owner1);
        wallet.addOwner(owner4);

        assertEq(wallet.getOwnerCount(), 4);
        assertTrue(wallet.isOwner(owner4));
    }
    /**
     * @dev 测试多签钱包合约添加所有者函数，失败添加所有者，非所有者调用
     */
    function test_AddOwner_Revert_NotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("Only owner can call this function");
        wallet.addOwner(owner4);
    }
    /**
     * @dev 测试多签钱包合约添加所有者函数，失败添加所有者，所有者地址为零地址
     */
    function test_AddOwner_Revert_ZeroAddress() public {
        vm.prank(owner1);
        vm.expectRevert("Owner cannot be the zero address");
        wallet.addOwner(address(0));
    }
    /**
     * @dev 测试多签钱包合约添加所有者函数，失败添加所有者，所有者地址已存在
     */
    function test_AddOwner_Revert_AlreadyOwner() public {
        vm.prank(owner1);
        vm.expectRevert("Owner already is an owner");
        wallet.addOwner(owner2);
    }
    /**
     * @dev 测试多签钱包合约移除所有者函数，成功移除所有者
     */
    function test_RemoveOwner_Success() public {
        vm.prank(owner1);
        wallet.removeOwner(owner3);

        assertEq(wallet.getOwnerCount(), 2);
        assertFalse(wallet.isOwner(owner3));
    }
    /**
     * @dev 测试多签钱包合约移除所有者函数，失败移除所有者，非所有者调用
     */
    function test_RemoveOwner_Revert_NotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("Only owner can call this function");
        wallet.removeOwner(owner1);
    }
    /**
     * @dev 测试多签钱包合约移除所有者函数，失败移除所有者，所有者地址不存在
     */
    function test_RemoveOwner_Revert_OwnerNotFound() public {
        vm.prank(owner1);
        vm.expectRevert("Owner is not an owner");
        wallet.removeOwner(nonOwner);
    }
    /**
     * @dev 测试多签钱包合约移除所有者函数，失败移除所有者，移除后所有者数量小于确认阈值
     */
    function test_RemoveOwner_Revert_ThresholdWouldExceed() public {
        // 3 owners, threshold 2 → after removing 2, would have 1 owner < threshold 2
        vm.prank(owner1);
        wallet.removeOwner(owner3); // now 2 owners, threshold 2

        vm.prank(owner1);
        vm.expectRevert("the owner number must be greater than or equal to the num confirmations required");
        wallet.removeOwner(owner2);
    }
    /**
     * @dev 测试多签钱包合约移除所有者函数，成功移除所有者，移除后所有者数量等于确认阈值
     */
    function test_RemoveOwner_AllowsEqualThreshold() public {
        // 3 owners, threshold 2 → after removing 1, have 2 owners >= threshold 2 (should work)
        vm.prank(owner1);
        wallet.removeOwner(owner3);

        assertEq(wallet.getOwnerCount(), 2);
        assertEq(wallet.getThreshold(), 2);
    }
    /**
     * @dev 测试多签钱包合约改变确认阈值函数，成功改变确认阈值
     */
    function test_ChangeThreshold_Success() public {
        vm.prank(owner1);
        wallet.changeThreshold(1);
        assertEq(wallet.getThreshold(), 1);
    }
    /**
     * @dev 测试多签钱包合约改变确认阈值函数，失败改变确认阈值，非所有者调用
     */
    function test_ChangeThreshold_Revert_NotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("Only owner can call this function");
        wallet.changeThreshold(1);
    }
    /**
     * @dev 测试多签钱包合约改变确认阈值函数，失败改变确认阈值，确认阈值为0
     */
    function test_ChangeThreshold_Revert_Zero() public {
        vm.prank(owner1);
        vm.expectRevert("Num confirmations required must be greater than 0 and less than or equal to the number of owners");
        wallet.changeThreshold(0);
    }
    /**
     * @dev 测试多签钱包合约改变确认阈值函数，失败改变确认阈值，确认阈值大于所有者数量
     */
    function test_ChangeThreshold_Revert_ExceedsOwnerCount() public {
        vm.prank(owner1);
        vm.expectRevert("Num confirmations required must be greater than 0 and less than or equal to the number of owners");
        wallet.changeThreshold(4);
    }
    /**
     * @dev 测试多签钱包合约获取所有者函数，成功获取所有者
     */
    function test_GetOwners() public view {
        address[] memory result = wallet.getOwners();
        assertEq(result.length, 3);
        assertEq(result[0], owner1);
        assertEq(result[1], owner2);
        assertEq(result[2], owner3);
    }
    /**
     * @dev 测试多签钱包合约获取所有者数量函数，成功获取所有者数量
     */
    function test_GetOwnerCount() public view {
        assertEq(wallet.getOwnerCount(), 3);
    }
    /**
     * @dev 测试多签钱包合约检查所有者函数，成功检查所有者
     */
    function test_IsOwner() public view {
        assertTrue(wallet.isOwner(owner1));
        assertTrue(wallet.isOwner(owner2));
        assertTrue(wallet.isOwner(owner3));
        assertFalse(wallet.isOwner(nonOwner));
    }
    /**
     * @dev 测试多签钱包合约获取确认阈值函数，成功获取确认阈值
     */
    function test_GetThreshold() public view {
        assertEq(wallet.getThreshold(), 2);
    }

    // ==================== Proposal Tests ====================
    /**
     * @dev 测试多签钱包合约创建提案函数，成功创建提案
     */
    function test_CreateProposal_Success() public {
        vm.prank(owner1);
        wallet.createProposal(address(target), AMOUNT, bytes(""));

        assertEq(wallet.getProposalCount(), 1);
        (address to, uint256 value, bytes memory data, uint256 confirmations, bool executed) = wallet.getProposal(0);
        assertEq(to, address(target));
        assertEq(value, AMOUNT);
        assertEq(data.length, 0);
        assertEq(confirmations, 0);
        assertFalse(executed);
    }
    /**
     * @dev 测试多签钱包合约创建提案函数，失败创建提案，非所有者调用
     */
    function test_CreateProposal_Revert_NotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("Only owner can call this function");
        wallet.createProposal(address(target), AMOUNT, bytes(""));
    }
    /**
     * @dev 测试多签钱包合约创建提案函数，失败创建提案，目标地址为0地址
     */
    function test_CreateProposal_Revert_ZeroAddress() public {
        vm.prank(owner1);
        vm.expectRevert("To cannot be the zero address");
        wallet.createProposal(address(0), AMOUNT, bytes(""));
    }
    /**
     * @dev 测试多签钱包合约创建提案函数，成功创建提案，提案数据不为空
     */
    function test_CreateProposal_WithData() public {
        bytes memory data = abi.encodeWithSignature("doSomething()");
        vm.prank(owner1);
        wallet.createProposal(address(target), AMOUNT, data);

        (, , bytes memory storedData, , ) = wallet.getProposal(0);
        assertEq(storedData, data);
    }
    /**
     * @dev 测试多签钱包合约获取提案函数，成功获取提案，提案索引超出范围
     */
    function test_GetProposal_Revert_OutOfRange() public {
        vm.expectRevert("Proposal index out of range");
        wallet.getProposal(0);
    }
    /**
     * @dev 测试多签钱包合约获取提案数量函数，成功获取提案数量
     */
    function test_GetProposalCount() public view {
        assertEq(wallet.getProposalCount(), 0);
    }
    /**
     * @dev 测试多签钱包合约获取提案索引函数，成功获取提案索引
     */
    function test_GetProposalIndexs() public {
        vm.prank(owner1);
        wallet.createProposal(address(target), AMOUNT, bytes(""));
        vm.prank(owner2);
        wallet.createProposal(address(target), 2 ether, bytes(""));

        uint256[] memory indices = wallet.getProposalIndexs();
        assertEq(indices.length, 2);
        assertEq(indices[0], 0);
        assertEq(indices[1], 1);
    }

    // ==================== Confirmation Tests ====================
    /**
     * @dev 测试多签钱包合约创建提案函数，成功创建提案
     */
    function _createProposal() internal returns (uint256) {
        vm.prank(owner1);
        wallet.createProposal(address(target), AMOUNT, bytes(""));
        return 0;
    }
    /**
     * @dev 测试多签钱包合约确认提案函数，成功确认提案，所有者调用
     */
    function test_ConfirmTx_Success() public {
        uint256 txIndex = _createProposal();

        vm.prank(owner1);
        wallet.confirmTx(txIndex);

        assertTrue(wallet.isTransactionConfirmed(txIndex, owner1));
        assertEq(wallet.getConfirmationCount(txIndex), 1);
    }
    /**
     * @dev 测试多签钱包合约确认提案函数，失败确认提案，非所有者调用
     */
    function test_ConfirmTx_Revert_NotOwner() public {
        uint256 txIndex = _createProposal();

        vm.prank(nonOwner);
        vm.expectRevert("Only owner can call this function");
        wallet.confirmTx(txIndex);
    }
    /**
     * @dev 测试多签钱包合约确认提案函数，失败确认提案，提案索引超出范围
     */
    function test_ConfirmTx_Revert_ProposalNotFound() public {
        vm.prank(owner1);
        vm.expectRevert("Proposal index out of range");
        wallet.confirmTx(999);
    }
    /**
     * @dev 测试多签钱包合约确认提案函数，失败确认提案，提案已确认
     */
    function test_ConfirmTx_Revert_AlreadyConfirmed() public {
        uint256 txIndex = _createProposal();

        vm.prank(owner1);
        wallet.confirmTx(txIndex);

        vm.prank(owner1);
        vm.expectRevert("Transaction already confirmed");
        wallet.confirmTx(txIndex);
    }
    /**
     * @dev 测试多签钱包合约确认提案函数，失败确认提案，提案已执行
     */
    function test_ConfirmTx_Revert_AlreadyExecuted() public {
        uint256 txIndex = _createProposal();

        // 给钱包合约发送资金
        vm.deal(address(wallet), AMOUNT);
        vm.prank(owner1);
        wallet.confirmTx(txIndex);
        vm.prank(owner2);
        wallet.confirmTx(txIndex);
        vm.prank(owner1);
        wallet.executeTx(txIndex);

        // Try to confirm after execution
        vm.prank(owner3);
        vm.expectRevert("Transaction already executed");
        wallet.confirmTx(txIndex);
    }
    /**
     * @dev 测试多签钱包合约撤销确认提案函数，成功撤销确认提案，所有者调用
     */
    function test_RevokeConfirmTx_Success() public {
        uint256 txIndex = _createProposal();

        vm.prank(owner1);
        wallet.confirmTx(txIndex);
        assertEq(wallet.getConfirmationCount(txIndex), 1);

        vm.prank(owner1);
        wallet.revokeConfirmTx(txIndex);
        assertEq(wallet.getConfirmationCount(txIndex), 0);
        assertFalse(wallet.isTransactionConfirmed(txIndex, owner1));
    }
    /**
     * @dev 测试多签钱包合约撤销确认提案函数，失败撤销确认提案，非所有者调用
     */
    function test_RevokeConfirmTx_Revert_NotOwner() public {
        uint256 txIndex = _createProposal();

        vm.prank(nonOwner);
        vm.expectRevert("Only owner can call this function");
        wallet.revokeConfirmTx(txIndex);
    }
    /**
     * @dev 测试多签钱包合约撤销确认提案函数，失败撤销确认提案，提案索引超出范围
     */
    function test_RevokeConfirmTx_Revert_ProposalNotFound() public {
        vm.prank(owner1);
        vm.expectRevert("Proposal index out of range");
        wallet.revokeConfirmTx(999);
    }
    /**
     * @dev 测试多签钱包合约撤销确认提案函数，失败撤销确认提案，提案未确认
     */
    function test_RevokeConfirmTx_Revert_NotConfirmed() public {
        uint256 txIndex = _createProposal();

        vm.prank(owner1);
        vm.expectRevert("Transaction not confirmed");
        wallet.revokeConfirmTx(txIndex);
    }
    /**
     * @dev 测试多签钱包合约撤销确认提案函数，失败撤销确认提案，提案已执行
     */
    function test_RevokeConfirmTx_Revert_AlreadyExecuted() public {
        uint256 txIndex = _createProposal();

        vm.deal(address(wallet), AMOUNT);
        vm.prank(owner1);
        wallet.confirmTx(txIndex);
        vm.prank(owner2);
        wallet.confirmTx(txIndex);
        vm.prank(owner1);
        wallet.executeTx(txIndex);

        vm.prank(owner1);
        vm.expectRevert("Transaction already executed");
        wallet.revokeConfirmTx(txIndex);
    }
    /**
     * @dev 测试多签钱包合约撤销确认提案函数，成功撤销确认提案，所有者调用
     */
    function test_IsTransactionConfirmed() public {
        uint256 txIndex = _createProposal();

        assertFalse(wallet.isTransactionConfirmed(txIndex, owner1));

        vm.prank(owner1);
        wallet.confirmTx(txIndex);

        assertTrue(wallet.isTransactionConfirmed(txIndex, owner1));
        assertFalse(wallet.isTransactionConfirmed(txIndex, owner2));
    }
    /**
     * @dev 测试多签钱包合约撤销确认提案函数，成功撤销确认提案，所有者调用
     */
    function test_GetConfirmationCount() public {
        uint256 txIndex = _createProposal();
        assertEq(wallet.getConfirmationCount(txIndex), 0);

        vm.prank(owner1);
        wallet.confirmTx(txIndex);
        assertEq(wallet.getConfirmationCount(txIndex), 1);

        vm.prank(owner2);
        wallet.confirmTx(txIndex);
        assertEq(wallet.getConfirmationCount(txIndex), 2);
    }
    /**
     * @dev 测试多签钱包合约撤销确认提案函数，成功撤销确认提案，所有者调用
     */
    function test_CanExecute() public {
        uint256 txIndex = _createProposal();
        assertFalse(wallet.canExecute(txIndex));

        vm.prank(owner1);
        wallet.confirmTx(txIndex);
        assertFalse(wallet.canExecute(txIndex));

        vm.prank(owner2);
        wallet.confirmTx(txIndex);
        assertTrue(wallet.canExecute(txIndex));
    }

    // ==================== Execute Tests ====================
    /**
     * @dev 测试多签钱包合约执行提案函数，成功执行提案，所有者调用
     */
    function test_ExecuteTx_Success() public {
        uint256 txIndex = _createProposal();

        vm.deal(address(wallet), AMOUNT);

        vm.prank(owner1);
        wallet.confirmTx(txIndex);
        vm.prank(owner2);
        wallet.confirmTx(txIndex);

        uint256 balanceBefore = address(target).balance;
        vm.prank(owner1);
        wallet.executeTx(txIndex);

        assertEq(address(target).balance, balanceBefore + AMOUNT);
        assertTrue(wallet.isTransactionConfirmed(txIndex, owner1));
        assertTrue(wallet.isTransactionConfirmed(txIndex, owner2));

        (, , , , bool executed) = wallet.getProposal(txIndex);
        assertTrue(executed);
    }
    /**
     * @dev 测试多签钱包合约执行提案函数，失败执行提案，非所有者调用
     */
    function test_ExecuteTx_Revert_NotOwner() public {
        uint256 txIndex = _createProposal();

        vm.prank(nonOwner);
        vm.expectRevert("Only owner can call this function");
        wallet.executeTx(txIndex);
    }
    /**
     * @dev 测试多签钱包合约执行提案函数，失败执行提案，提案索引超出范围
     */
    function test_ExecuteTx_Revert_ProposalNotFound() public {
        vm.prank(owner1);
        vm.expectRevert("Proposal index out of range");
        wallet.executeTx(999);
    }
    /**
     * @dev 测试多签钱包合约执行提案函数，失败执行提案，提案未确认
     */
    function test_ExecuteTx_Revert_NotEnoughConfirmations() public {
        uint256 txIndex = _createProposal();

        vm.prank(owner1);
        wallet.confirmTx(txIndex);

        vm.prank(owner1);
        vm.expectRevert("Transaction not executable");
        wallet.executeTx(txIndex);
    }
    /**
     * @dev 测试多签钱包合约执行提案函数，失败执行提案，提案已执行
     */
    function test_ExecuteTx_Revert_AlreadyExecuted() public {
        uint256 txIndex = _createProposal();

        vm.deal(address(wallet), AMOUNT);
        vm.prank(owner1);
        wallet.confirmTx(txIndex);
        vm.prank(owner2);
        wallet.confirmTx(txIndex);
        vm.prank(owner1);
        wallet.executeTx(txIndex);

        vm.prank(owner1);
        vm.expectRevert("Transaction already executed");
        wallet.executeTx(txIndex);
    }
    /**
     * @dev 测试多签钱包合约执行提案函数，失败执行提案，目标合约调用失败
     */
    function test_ExecuteTx_Revert_TargetCallFails() public {
        // Create proposal to rejector
        vm.prank(owner1);
        wallet.createProposal(address(rejector), AMOUNT, bytes(""));
        uint256 txIndex = 0;

        vm.deal(address(wallet), AMOUNT);
        vm.prank(owner1);
        wallet.confirmTx(txIndex);
        vm.prank(owner2);
        wallet.confirmTx(txIndex);

        vm.prank(owner1);
        vm.expectRevert("Transaction execution failed");
        wallet.executeTx(txIndex);
    }
    /**
     * @dev 测试多签钱包合约执行提案函数，成功执行提案，目标合约调用成功
     */
    function test_ExecuteTx_WithFunctionCall() public {
        bytes memory data = abi.encodeWithSignature("doSomething()");
        vm.prank(owner1);
        wallet.createProposal(address(target), 0, data);
        uint256 txIndex = 0;

        vm.prank(owner1);
        wallet.confirmTx(txIndex);
        vm.prank(owner2);
        wallet.confirmTx(txIndex);

        vm.prank(owner1);
        wallet.executeTx(txIndex);

        (, , , , bool executed) = wallet.getProposal(txIndex);
        assertTrue(executed);
    }

    // ==================== Finance Tests ====================
    /**
     * @dev 测试多签钱包合约接收以太币函数，成功接收以太币
     */
    function test_Receive_Ether() public {
        uint256 balanceBefore = address(wallet).balance;
        vm.prank(owner1);
        (bool success, ) = address(wallet).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(wallet).balance, balanceBefore + 1 ether);
    }
    /**
     * @dev 测试多签钱包合约接收以太币函数，成功接收以太币，包含数据
     */
    function test_Fallback_Ether() public {
        uint256 balanceBefore = address(wallet).balance;
        vm.prank(owner1);
        (bool success, ) = address(wallet).call{value: 1 ether}(bytes("someData"));
        assertTrue(success);
        assertEq(address(wallet).balance, balanceBefore + 1 ether);
    }
    /**
     * @dev 测试多签钱包合约获取余额函数，成功获取余额
     */
    function test_GetBalance() public {
        assertEq(wallet.getBalance(), 0);

        vm.deal(address(wallet), 5 ether);
        assertEq(wallet.getBalance(), 5 ether);
    }

    // ==================== Multi-Owner Flow Tests ====================
    /**
     * @dev 测试多签钱包合约多所有者流程，成功执行提案
     */
    function test_FullLifecycle() public {
        // 1. Create proposal
        vm.prank(owner1);
        wallet.createProposal(address(target), AMOUNT, bytes(""));
        uint256 txIndex = 0;

        // 2. Confirmations
        vm.prank(owner2);
        wallet.confirmTx(txIndex);
        assertFalse(wallet.canExecute(txIndex));

        vm.prank(owner3);
        wallet.confirmTx(txIndex);
        assertTrue(wallet.canExecute(txIndex));
        assertEq(wallet.getConfirmationCount(txIndex), 2);

        // 3. Execute
        vm.deal(address(wallet), AMOUNT);
        vm.prank(owner1);
        wallet.executeTx(txIndex);

        (, , , , bool executed) = wallet.getProposal(txIndex);
        assertTrue(executed);
        assertEq(address(target).balance, AMOUNT);
    }
    /**
     * @dev 测试多签钱包合约多所有者流程，成功执行提案，撤销确认
     */
    function test_FullLifecycle_WithRevoke() public {
        // 1. Create
        vm.prank(owner1);
        wallet.createProposal(address(target), AMOUNT, bytes(""));

        // 2. Two confirmations
        vm.prank(owner2);
        wallet.confirmTx(0);
        vm.prank(owner3);
        wallet.confirmTx(0);
        assertTrue(wallet.canExecute(0));

        // 3. Revoke one
        vm.prank(owner2);
        wallet.revokeConfirmTx(0);
        assertFalse(wallet.canExecute(0));
        assertEq(wallet.getConfirmationCount(0), 1);

        // 4. Re-confirm
        vm.prank(owner2);
        wallet.confirmTx(0);
        assertTrue(wallet.canExecute(0));

        // 5. Execute
        vm.deal(address(wallet), AMOUNT);
        vm.prank(owner1);
        wallet.executeTx(0);

        (, , , , bool executed) = wallet.getProposal(0);
        assertTrue(executed);
    }
    /**
     * @dev 测试多签钱包合约多所有者流程，成功执行提案，改变阈值
     */
    function test_ThresholdChange_Lifecycle() public {
        // Change threshold to 1
        vm.prank(owner1);
        wallet.changeThreshold(1);
        assertEq(wallet.getThreshold(), 1);

        // Now only 1 confirmation needed
        vm.prank(owner1);
        wallet.createProposal(address(target), AMOUNT, bytes(""));

        vm.deal(address(wallet), AMOUNT);
        vm.prank(owner2);
        wallet.confirmTx(0);
        assertTrue(wallet.canExecute(0));
        vm.prank(owner1);
        wallet.executeTx(0);

        (, , , , bool executed) = wallet.getProposal(0);
        assertTrue(executed);
    }
}
