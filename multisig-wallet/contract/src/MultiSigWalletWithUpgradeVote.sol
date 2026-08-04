// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @dev 多签钱包合约，支持升级提案和投票
 * @notice 升级提案需要通过投票确认后才能执行
 */
contract MultiSigWalletUpgradeableVote is Initializable, ContextUpgradeable, UUPSUpgradeable {
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

    // 升级提案的结构体
    struct UpgradeProposal {
        // 新的实现合约地址
        address newImplementation;
        // 已确认的数量
        uint256 confirmations;
        // 是否已执行
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
    // 升级提案的数组
    UpgradeProposal[] public upgradeProposals;
    // 升级提案的确认映射
    // key: 升级提案的索引
    // value: 确认者地址
    // value: 是否确认
    mapping(uint256 => mapping(address => bool)) public upgradeConfirmers;
    // 当前已授权升级的实现地址（一次性，防止重放）
    address private _pendingUpgradeImplementation;

    /**
     * @dev 仅允许所有者调用的修饰符
     */
    modifier onlyOwner {
        require(ownerMapping[_msgSender()], "Only owner can call this function");
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
        require(confirmers[_txIndex][_msgSender()] == false, "Transaction already confirmed");
        _;
    }
    /**
     * @dev 仅允许已确认的交易调用的修饰符
     * @param _txIndex 交易提案的索引
     */
    modifier hasConfirmed(uint256 _txIndex) {
        require(confirmers[_txIndex][_msgSender()] == true, "Transaction not confirmed");
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
     * @dev 提交升级提案事件
     */
    event SubmitUpgradeProposal(uint256 indexed proposalId, address indexed newImplementation);
    /**
     * @dev 确认升级提案事件
     */
    event ConfirmUpgradeProposal(uint256 indexed proposalId, address indexed confirmor);
    /**
     * @dev 撤销升级确认事件
     */
    event RevokeUpgradeConfirmation(uint256 indexed proposalId, address indexed confirmor);
    /**
     * @dev 执行升级提案事件
     */
    event ExecuteUpgradeProposal(uint256 indexed proposalId, address indexed newImplementation);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }


    /**
     * @dev 构造函数，初始化多签钱包的账户和需要确认的交易阈值
     * @param _owners 多签钱包的账户
     * @param _numConfirmationsRequired 多签钱包的账户需要确认的交易阈值
     */
    function initialize(address[] memory _owners, uint256 _numConfirmationsRequired) public initializer {
        __Context_init(); 
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
    /**
     * @dev 授权升级多签钱包合约
     * 必须通过多签提案批准后，由 executeUpgradeProposal 触发
     * @param newImplementation 新的多签钱包合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal onlyOwner override {
        // 检查升级是否经过多签提案批准
        require(
            _pendingUpgradeImplementation == newImplementation,
            "Upgrade must be approved by multi-sig proposal"
        );
        // 清除授权标记，防止重放攻击
        _pendingUpgradeImplementation = address(0);
    }

    // ------------------ 多签钱包的账户管理 start ------------------

    /**
     * @dev 添加多签钱包的账户
     * @param _owner 多签钱包的账户
     */
    function addOwner(address _owner) public virtual onlyOwner {
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
    function removeOwner(address _owner) public virtual onlyOwner {
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
    function changeThreshold(uint256 _newThreshold) public virtual onlyOwner {
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
    function getOwners() public virtual view returns (address[] memory) {
        return owners;
    }

    /**
     * @dev 获取多签钱包的账户数量
     * @return 多签钱包的账户数量
     */
    function getOwnerCount() public virtual view returns (uint256) {
        return owners.length;
    }

    /**
     * @dev 检查账户是否是多签钱包的所有者
     * @param _owner 账户
     * @return 是否是多签钱包的所有者
     */
    function isOwner(address _owner) public virtual view returns (bool) {
        return ownerMapping[_owner];
    }

    /**
     * @dev 获取多签钱包的账户需要确认的交易阈值
     * @return 多签钱包的账户需要确认的交易阈值
     */
    function getThreshold() public virtual view returns (uint256) {
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
    function createProposal(address _to, uint256 _value, bytes memory _data) public virtual onlyOwner {
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
    function getProposal(uint256 _txIndex) public virtual view returns (
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
    function getProposalCount() public virtual view returns (uint256) {
        return proposals.length;
    }

    /**
     * @dev 获取交易提案的索引
     * @return 交易提案的索引
     */
    function getProposalIndexs() public virtual view returns (uint256[] memory) {
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
    function confirmTx(uint256 _txIndex) public virtual onlyOwner txExists(_txIndex) notExecuted(_txIndex) notConfirmed(_txIndex) {
        confirmers[_txIndex][_msgSender()] = true;
        Proposal storage proposal = proposals[_txIndex];
        proposal.confirmations += 1;
        emit ConfirmTransaction(_txIndex, _msgSender());
    }
    /**
     * @dev 撤销确认交易提案
     * @param _txIndex 交易提案的索引
     */
    function revokeConfirmTx(uint256 _txIndex) public virtual onlyOwner txExists(_txIndex) notExecuted(_txIndex) hasConfirmed(_txIndex) {
        Proposal storage proposal = proposals[_txIndex];
        confirmers[_txIndex][_msgSender()] = false;
        proposal.confirmations -= 1;
        emit RevokeConfirmation(_txIndex, _msgSender());
    }

    /**
     * @dev 检查交易提案是否已确认
     * @param _txIndex 交易提案的索引
     * @param _confirmor 确认者
     * @return 是否已确认
     */
    function isTransactionConfirmed(uint256 _txIndex, address _confirmor) public virtual view returns (bool) {
        return confirmers[_txIndex][_confirmor];
    }


    /**
     * @dev 获取交易提案的已确认阈值量
     * @param _txIndex 交易提案的索引
     * @return 已确认的交易数量
     */
    function getConfirmationCount(uint256 _txIndex) public virtual view returns (uint256) {
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
    function executeTx(uint256 _txIndex) public virtual onlyOwner txExists(_txIndex) notExecuted(_txIndex) {
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

    // ------------------ 升级提案模块 start ------------------
    /**
     * @dev 创建升级提案
     * @param _newImplementation 新的实现合约地址
     * @return proposalId 升级提案的索引
     */
    function createUpgradeProposal(address _newImplementation) public virtual onlyOwner returns (uint256) {
        require(_newImplementation != address(0), "Invalid implementation address");
        require(_newImplementation != address(this), "Cannot upgrade to self");
        uint256 proposalId = upgradeProposals.length;
        upgradeProposals.push(UpgradeProposal({
            newImplementation: _newImplementation,
            confirmations: 0,
            executed: false
        }));
        emit SubmitUpgradeProposal(proposalId, _newImplementation);
        return proposalId;
    }

    /**
     * @dev 确认升级提案
     * @param _proposalId 升级提案的索引
     */
    function confirmUpgradeProposal(uint256 _proposalId) public virtual onlyOwner {
        require(_proposalId < upgradeProposals.length, "Upgrade proposal not found");
        UpgradeProposal storage proposal = upgradeProposals[_proposalId];
        require(!proposal.executed, "Proposal already executed");
        require(!upgradeConfirmers[_proposalId][_msgSender()], "Already confirmed");
        upgradeConfirmers[_proposalId][_msgSender()] = true;
        proposal.confirmations += 1;
        emit ConfirmUpgradeProposal(_proposalId, _msgSender());
    }

    /**
     * @dev 撤销升级确认
     * @param _proposalId 升级提案的索引
     */
    function revokeUpgradeConfirmation(uint256 _proposalId) public virtual onlyOwner {
        require(_proposalId < upgradeProposals.length, "Upgrade proposal not found");
        UpgradeProposal storage proposal = upgradeProposals[_proposalId];
        require(!proposal.executed, "Proposal already executed");
        require(upgradeConfirmers[_proposalId][_msgSender()], "Not confirmed");
        upgradeConfirmers[_proposalId][_msgSender()] = false;
        proposal.confirmations -= 1;
        emit RevokeUpgradeConfirmation(_proposalId, _msgSender());
    }

    /**
     * @dev 检查升级提案是否可以执行
     * @param _proposalId 升级提案的索引
     * @return 是否可以执行
     */
    function canExecuteUpgrade(uint256 _proposalId) public view returns (bool) {
        require(_proposalId < upgradeProposals.length, "Upgrade proposal not found");
        return upgradeProposals[_proposalId].confirmations >= numConfirmationsRequired;
    }

    /**
     * @dev 执行升级提案，触发合约升级
     * 必须达到多签阈值才能执行
     * @param _proposalId 升级提案的索引
     */
    function executeUpgradeProposal(uint256 _proposalId) public virtual onlyOwner {
        require(_proposalId < upgradeProposals.length, "Upgrade proposal not found");
        UpgradeProposal storage proposal = upgradeProposals[_proposalId];
        require(!proposal.executed, "Proposal already executed");
        require(canExecuteUpgrade(_proposalId), "Not enough confirmations");

        proposal.executed = true;
        // 设置授权标记，_authorizeUpgrade 会验证这个标记
        _pendingUpgradeImplementation = proposal.newImplementation;

        // 通过代理调用 upgradeTo，触发 _authorizeUpgrade 检查
        // upgradeTo 是 public virtual 函数，通过低级 call 触发外部调用，经过代理 delegatecall
        (bool success,) = address(this).call(
            abi.encodeWithSignature("upgradeTo(address)", proposal.newImplementation)
        );
        require(success, "Upgrade failed");

        emit ExecuteUpgradeProposal(_proposalId, proposal.newImplementation);
    }

    /**
     * @dev 获取升级提案
     * @param _proposalId 升级提案的索引
     * @return newImplementation 新的实现合约地址
     * @return confirmations 已确认的数量
     * @return executed 是否已执行
     */
    function getUpgradeProposal(uint256 _proposalId) public virtual view returns (
        address newImplementation,
        uint256 confirmations,
        bool executed
    ) {
        require(_proposalId < upgradeProposals.length, "Upgrade proposal not found");
        UpgradeProposal storage proposal = upgradeProposals[_proposalId];
        return (proposal.newImplementation, proposal.confirmations, proposal.executed);
    }

    /**
     * @dev 获取升级提案数量
     * @return 升级提案数量
     */
    function getUpgradeProposalCount() public virtual view returns (uint256) {
        return upgradeProposals.length;
    }

    /**
     * @dev 检查账户是否已确认升级提案
     * @param _proposalId 升级提案的索引
     * @param _confirmor 确认者
     * @return 是否已确认
     */
    function isUpgradeConfirmed(uint256 _proposalId, address _confirmor) public virtual view returns (bool) {
        return upgradeConfirmers[_proposalId][_confirmor];
    }
    // ------------------ 升级提案模块 end ------------------

    /**
     * @dev 接收以太币
     */
    receive() external payable {
        if (msg.value > 0) {
            emit Deposit(_msgSender(), msg.value);
        }
    }
    /**
     * @dev 回退函数
     */
    fallback() external payable {
        if (msg.value > 0) {
            emit Deposit(_msgSender(), msg.value);
        }
    }
    /**
     * @dev 获取合约余额
     * @return 合约余额
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // 存储间隙【强制】
    uint256[256] private __gap;
}
