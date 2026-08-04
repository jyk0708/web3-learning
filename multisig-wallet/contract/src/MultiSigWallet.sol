// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract MultiSigWallet {
    // 交易提案的结构体
    struct Proposal {
        // 交易提案的索引
        uint256 txIndex;
        // 交易目标地址
        address to;
        // 交易金额
        uint256 value;
        // 交易数据
        bytes data;
        // 提提案的确认阈值
        uint256 confirmations;
        // 提案执行状态
        bool executed;
    }

    // 多签钱包的账户
    address[] public owners;
    // 多签钱包的账户需要确认的交易阈值
    uint256 public numConfirmationsRequired;
    // 多签钱包的账户是否是所有者
    mapping(address => bool) public ownerMapping;
    // 交易提案的数组
    Proposal[] public proposals;
    // 交易提案的确认映射
    // key: 交易提案的索引
    // value: 确认者地址
    // value: 是否确认
    mapping(uint256 => mapping(address => bool)) public confirmers;

    /**
     * @dev 仅允许所有者调用的修饰符
     */
    modifier onlyOwner {
        require(ownerMapping[msg.sender], "Only owner can call this function");
        _;
    }
    /**
     * @dev 仅允许存在交易提案的索引调用的修饰符
     * @param _txIndex 交易提案的索引
     */
    modifier txExists(uint256 _txIndex) {
        require(_txIndex < proposals.length, "Proposal index out of range");
        _;
    }
    /**
     * @dev 仅允许未执行的交易调用的修饰符
     * @param _txIndex 交易提案的索引
     */
    modifier notExecuted(uint256 _txIndex) {
        require(!proposals[_txIndex].executed, "Transaction already executed");
        _;
    }

    /**
     * @dev 仅允许未确认的交易调用的修饰符
     * @param _txIndex 交易提案的索引
     */
    modifier notConfirmed(uint256 _txIndex) {
        require(confirmers[_txIndex][msg.sender] == false, "Transaction already confirmed");
        _;
    }
    /**
     * @dev 仅允许已确认的交易调用的修饰符
     * @param _txIndex 交易提案的索引
     */
    modifier hasConfirmed(uint256 _txIndex) {
        require(confirmers[_txIndex][msg.sender] == true, "Transaction not confirmed");
        _;
    }

    /**
     * @dev 存款事件
     */
    event Deposit(address indexed sender, uint256 amount);
    /**
     * @dev 多签钱包的账户添加事件
     */
    event OwnerAdded(address indexed owner);
    /**
     * @dev 多签钱包的账户移除事件
     */
    event OwnerRemoved(address indexed owner);
    /**
     * @dev 多签钱包的账户需要确认的交易阈值改变事件
     */
    event ThresholdChanged(uint256 indexed newThreshold);
    /**
     * @dev 提交交易提案事件
     */
    event SubmitTransaction(uint256 indexed txIndex, address indexed to, uint256 value, bytes data);
    /**
     * @dev 确认交易提案事件
     */
    event ConfirmTransaction(uint256 indexed txIndex, address indexed confirmor);
    /**
     * @dev 撤销确认交易提案事件
     */
    event RevokeConfirmation(uint256 indexed txIndex, address indexed confirmor);
    /**
     * @dev 执行交易提案事件
     */
    event ExecuteTransaction(uint256 indexed txIndex, address indexed executor, bool indexed success, bytes result);



    /**
     * @dev 构造函数，初始化多签钱包的账户和需要确认的交易阈值
     * @param _owners 多签钱包的账户
     * @param _numConfirmationsRequired 多签钱包的账户需要确认的交易阈值
     */
    constructor(address[] memory _owners, uint256 _numConfirmationsRequired) {
        require(_owners.length > 0, "At least one owner is required");
        require(_numConfirmationsRequired > 0 && _numConfirmationsRequired <= _owners.length, 
            "Num confirmations required must be greater than 0 and less than or equal to the number of owners");
        uint256 length = _owners.length;
        for (uint256 i = 0; i < length; i++) {
            require(_owners[i] != address(0), "Owner cannot be the zero address");
            require(!ownerMapping[_owners[i]], "Owner not unique");
            ownerMapping[_owners[i]] = true;
        }
        owners = _owners;
        numConfirmationsRequired = _numConfirmationsRequired;
    }

    // ------------------ 多签钱包的账户管理 start ------------------

    /**
     * @dev 添加多签钱包的账户
     * @param _owner 多签钱包的账户
     */
    function addOwner(address _owner) external onlyOwner {
        require(_owner != address(0), "Owner cannot be the zero address");
        require(!ownerMapping[_owner], "Owner already is an owner");
        owners.push(_owner);
        ownerMapping[_owner] = true;
        emit OwnerAdded(_owner);
    }
    /**
     * @dev 移除多签钱包的账户
     * @param _owner 多签钱包的账户
     */
    function removeOwner(address _owner) external onlyOwner {
        require(ownerMapping[_owner], "Owner is not an owner");
        // 关键约束：移除所有者后，需要确认的交易阈值不能大于所有者数量
        require(owners.length - 1 >= numConfirmationsRequired, 
            "the owner number must be greater than or equal to the num confirmations required");
        delete ownerMapping[_owner];
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == _owner) {
                // Gas 优化，将最后一个元素移动到当前元素的位置，而不是删除当前元素
                owners[i] = owners[owners.length - 1];
                owners.pop();
                break;
            }
        }
        emit OwnerRemoved(_owner);
    }
    /**
     * @dev 改变多签钱包的账户需要确认的交易阈值
     * @param _newThreshold 多签钱包的账户需要确认的交易阈值
     */
    function changeThreshold(uint256 _newThreshold) external onlyOwner {
        // 关键约束：改变阈值后，需要确认的交易阈值不能大于所有者数量
        require(_newThreshold > 0 && _newThreshold <= owners.length, 
            "Num confirmations required must be greater than 0 and less than or equal to the number of owners");
        numConfirmationsRequired = _newThreshold;
        emit ThresholdChanged(_newThreshold);
    }
    /**
     * @dev 获取多签钱包的账户
     * @return 多签钱包的账户
     */
    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    /**
     * @dev 获取多签钱包的账户数量
     * @return 多签钱包的账户数量
     */
    function getOwnerCount() external view returns (uint256) {
        return owners.length;
    }

    /**
     * @dev 检查账户是否是多签钱包的所有者
     * @param _owner 账户
     * @return 是否是多签钱包的所有者
     */
    function isOwner(address _owner) external view returns (bool) {
        return ownerMapping[_owner];
    }

    /**
     * @dev 获取多签钱包的账户需要确认的交易阈值
     * @return 多签钱包的账户需要确认的交易阈值
     */
    function getThreshold() external view returns (uint256) {
        return numConfirmationsRequired;
    }

    // ------------------ 多签钱包的账户管理 end ------------------

    // ------------------ 交易提案模块 start ------------------
    /**
     * @dev 创建交易提案
     * @param _to 接收者
     * @param _value 交易金额
     * @param _data 交易数据
     */
    function createProposal(address _to, uint256 _value, bytes memory _data) external  onlyOwner {
        require(_to != address(0), "To cannot be the zero address");
        // 交易提案的索引
        uint256 txIndex = proposals.length;
        // 创建交易提案
        proposals.push(Proposal(txIndex, _to, _value, _data, 0, false));
        emit SubmitTransaction(txIndex, _to, _value, _data);
    }

    /**
     * @dev 获取交易提案
     * @param _txIndex 交易提案的索引
     * @return to 接收者
     * @return value 交易金额
     * @return data 交易数据
     * @return confirmations 已确认的交易数量
     * @return executed 是否执行过
     */
    function getProposal(uint256 _txIndex) external view returns (
        address to, 
        uint256 value, 
        bytes memory data, 
        uint256 confirmations, 
        bool executed) {
        require(_txIndex < proposals.length, "Proposal index out of range");
        Proposal memory proposal = proposals[_txIndex];
        return (proposal.to, proposal.value, proposal.data, proposal.confirmations, proposal.executed);
    }

    /**
     * @dev 获取交易提案数量
     * @return 交易提案数量
     */
    function getProposalCount() external view returns (uint256) {
        return proposals.length;
    }

    /**
     * @dev 获取交易提案的索引
     * @return 交易提案的索引
     */
    function getProposalIndexs() external view returns (uint256[] memory) {
        uint256[] memory indexs = new uint256[](proposals.length);
        for (uint256 i = 0; i < proposals.length; i++) {
            indexs[i] = proposals[i].txIndex;
        }
        return indexs;
    }

    
    // ------------------ 交易提案模块 end ------------------

    // ------------------ 确认交易模块 start ------------------
    /**
     * @dev 确认交易提案
     * @param _txIndex 交易提案的索引
     */
    function confirmTx(uint256 _txIndex) external onlyOwner txExists(_txIndex) notExecuted(_txIndex) notConfirmed(_txIndex) {
        confirmers[_txIndex][msg.sender] = true;
        Proposal storage proposal = proposals[_txIndex];
        proposal.confirmations += 1;
        emit ConfirmTransaction(_txIndex, msg.sender);
    }
    /**
     * @dev 撤销确认交易提案
     * @param _txIndex 交易提案的索引
     */
    function revokeConfirmTx(uint256 _txIndex) external onlyOwner txExists(_txIndex) notExecuted(_txIndex) hasConfirmed(_txIndex) {
        Proposal storage proposal = proposals[_txIndex];
        confirmers[_txIndex][msg.sender] = false;
        proposal.confirmations -= 1;
        emit RevokeConfirmation(_txIndex, msg.sender);
    }

    /**
     * @dev 检查交易提案是否已确认
     * @param _txIndex 交易提案的索引
     * @param _confirmor 确认者
     * @return 是否已确认
     */
    function isTransactionConfirmed(uint256 _txIndex, address _confirmor) external view returns (bool) {
        return confirmers[_txIndex][_confirmor];
    }


    /**
     * @dev 获取交易提案的已确认阈值量
     * @param _txIndex 交易提案的索引
     * @return 已确认的交易数量
     */
    function getConfirmationCount(uint256 _txIndex) external view returns (uint256) {
        return proposals[_txIndex].confirmations;
    }

    /**
     * @dev 检查交易提案是否可以执行
     * @param _txIndex 交易提案的索引
     * @return 是否可以执行
     */
    function canExecute(uint256 _txIndex) public view returns (bool) {
        return proposals[_txIndex].confirmations >= numConfirmationsRequired;
    }
    // ------------------ 确认交易模块 end ------------------

    // ------------------ 执行交易模块 start ------------------
    /**
     * @dev 执行交易提案
     * @param _txIndex 交易提案的索引
     */
    function executeTx(uint256 _txIndex) external onlyOwner txExists(_txIndex) notExecuted(_txIndex) {
        require(canExecute(_txIndex), "Transaction not executable");
        Proposal storage proposal = proposals[_txIndex];
        proposal.executed = true;
        address addr = proposal.to;
        if (proposal.value > 0) {
            // 执行交易提案
            (bool success, bytes memory result) = addr.call{value: proposal.value}(proposal.data);
            require(success, "Transaction execution failed");
            emit ExecuteTransaction(_txIndex, addr, success, result);
        } else {
            emit ExecuteTransaction(_txIndex, addr, true, "");
        }
    }

    // ------------------ 执行交易模块 end ------------------
    /**
     * @dev 接收以太币
     */
    receive() external payable {
        if (msg.value > 0) {
            emit Deposit(msg.sender, msg.value);
        }
    }
    /**
     * @dev 回退函数
     */
    fallback() external payable {
        if (msg.value > 0) {
            emit Deposit(msg.sender, msg.value);
        }
    }
    /**
     * @dev 获取合约余额
     * @return 合约余额
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
