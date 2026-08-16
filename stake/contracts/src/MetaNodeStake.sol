// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract MetaNodeStake is 
    // 初始化合约
    Initializable, 
    // 升级合约
    ContextUpgradeable, 
    // 权限控制
    UUPSUpgradeable,  
    // 角色控制
    AccessControlUpgradeable{


    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    using SafeERC20 for IERC20;

    struct StakePool {
        // 质押币种地址
        address tokenAddress;
        // 质押池权重
        uint256 poolWeight;
        // 最后一次计算奖励的块号
        uint256 lastRewardBlock;
        // 累计每一个质押币奖励的 MetaNode 数量
        uint256 accumulatedMetaNodePerST;
        // 已质押的总币种数量
        uint256 stTotalTokenAmount;
        // 最小质押金额
        uint256 minDepositAmount;
        // 解质押锁定时间（单位：块数）
        uint256 unstakeLockedBlocks;
    }

    struct StakeUser {
        // 质押币种数量
        uint256 stAmount;
        // 领取 MetaNode 数量基线
        uint256 finishedMetaNode;
        // 待领取的 MetaNode 数量
        uint256 pendingMetaNode;
        // 解质押请求列表
        UnstakeRequest[] unstakeRequests;
    }

    struct UnstakeRequest {
        // 解质押数量
        uint256 amount;
        // 解质押等待的区块高度
        uint256 unlockBlocks;
    }

    // 质押开始块号
    uint256 public startBlock;
    // 质押结束块号
    uint256 public endBlock;
    // 每个区块奖励的质押币（MetaNode）数量
    uint256 public metaNodePerBlock;
    // 质押池权重总和
    uint256 public totalPoolWeight;
    // 质押提现是否暂停
    bool public withdrawPaused;
    // 质押领取是否暂停
    bool public claimPaused;
    // MetaNode 代币地址
    IERC20 public meatNodeToken;
    // 质押池信息
    StakePool[] public stakePools;
    // 质押用户信息
    mapping(uint256 => mapping(address => StakeUser)) public stakeUsers;

    /**
     * @dev 触发 MetaNode 代币地址设置事件
     */
    event SetMetaNode(IERC20 indexed meatNodeToken);
    /**
     * @dev 触发质押提现是否暂停事件
     */
    event PauseWithdraw(bool indexed paused);
    /**
     * @dev 触发质押提现是否恢复事件
     */
    event UnpauseWithdraw(bool indexed paused);
    
    /**
     * @dev 触发质押领取是否暂停事件
     */
    event PauseClaim(bool indexed paused);
    /**
     * @dev 触发质押领取是否恢复事件
     */
    event UnpauseClaim(bool indexed paused);
    /**
     * @dev 触发质押开始块号设置事件
     */
    event SetStartBlock(uint256 indexed startBlock);
    
    /**
     * @dev 触发质押结束块号设置事件
     */
    event SetEndBlock(uint256 indexed endBlock);
    
    // 设置 MetaNode 每区块的奖励数量
    event SetMetaNodePerBlock(uint256 indexed MetaNodePerBlock);
    /**
     * @dev 触发质押池权重设置事件
     */
    event SetPoolWeight(uint256 indexed pid, uint256 indexed poolWeight, uint256 indexed totalPoolWeight);
    /**
     * @dev 触发质押池累计每1个质押币种奖励的 MetaNode 数量更新事件
     */
    event UpdatePool(uint256 indexed pid, uint256 indexed accumulatedMetaNodePerST); 
    /**
     * @dev 触发质押用户解质押事件
     */
    event Unstake(address indexed user, uint256 indexed pid, uint256 indexed amount);
    /**
     * @dev 触发质押用户提现事件
     */
    event Withdraw(address indexed user, uint256 indexed pid, uint256 indexed amount);
    /**
     * @dev 触发质押用户领取 MetaNode 事件
     */
    event Claim(address indexed user, uint256 indexed pid, uint256 indexed amount);

    /**
     * @dev 检查质押池ID是否有效
     */
    modifier checkPid(uint256 pid) {
        require(pid < stakePools.length, "Invalid pool index");
        _;
    }
    /**
     * @dev 检查质押领取是否暂停
     */
    modifier whenNotClaimPaused() {
        require(!claimPaused, "Claim paused");
        _;
    }
    /**
     * @dev 检查质押提现是否暂停
     */
    modifier whenNotWithdrawPaused() {
        require(!withdrawPaused, "Withdraw paused");
        _;
    }
    /**
     * @dev 检查质押领取是否暂停
     */
    modifier requirePauseState(bool _pause) {
        require(_pause, "Pause state is not false");
        _;
    }
    /**
     * @dev 检查质押提现是否暂停
     */
    modifier requireWithdrawPauseState(bool _pause) {
        require(_pause, "Withdraw pause state is not false");
        _;
    }
    /**
     * @dev 授权升级合约
     * @param newImplementation 新的实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    /**
     * @dev 初始化合约
     * @param _meatNodeToken MetaNode 代币地址
     * @param _startBlock 质押开始块号
     * @param _endBlock 质押结束块号
     * @param _metaNodePerBlock 每个区块奖励的质押币（MetaNode）数量
     */
    function initialize(IERC20 _meatNodeToken, uint256 _startBlock, uint256 _endBlock, uint256 _metaNodePerBlock) public initializer {
        require(_startBlock < _endBlock, "Invalid block range");
        require(_metaNodePerBlock > 0, "Invalid metaNodePerBlock value");
        // 初始化权限控制
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(UPGRADER_ROLE, _msgSender());
        _grantRole(ADMIN_ROLE, _msgSender());

        setmeatNodeToken(_meatNodeToken);
        startBlock = _startBlock;
        endBlock = _endBlock;
        metaNodePerBlock = _metaNodePerBlock;
    }

    /**
     * @dev 暂停质押提现
     */
    function pauseWithdraw() public onlyRole(ADMIN_ROLE) {
        require(!withdrawPaused, "withdraw has been already paused");
        withdrawPaused = true;
        emit PauseWithdraw(withdrawPaused);
    }
    /**
     * @dev 恢复质押提现
     */
    function unpauseWithdraw() public onlyRole(ADMIN_ROLE) {
        require(withdrawPaused, "withdraw has been already unpaused");
        withdrawPaused = false;
        emit UnpauseWithdraw(withdrawPaused);
    }

    /**
     * @dev 暂停质押领取
     */
    function pauseClaim() public onlyRole(ADMIN_ROLE) {
        require(!claimPaused, "claim has been already paused");
        claimPaused = true;
        emit PauseClaim(claimPaused);
    }
    
    /**
     * @dev 恢复质押领取
     */
    function unpauseClaim() public onlyRole(ADMIN_ROLE) {
        require(claimPaused, "claim has been already unpaused");
        claimPaused = false;
        emit UnpauseClaim(claimPaused);
    }


    /**
     * @dev 设置质押池权重
     * @param _pid 质押池ID
     * @param _poolWeight 质押池权重
     * @param _withUpdate 是否同时更新质押池奖励
     */
    function setPoolWeight(uint256 _pid, uint256 _poolWeight, bool _withUpdate) public onlyRole(ADMIN_ROLE) checkPid(_pid) {
        require(_poolWeight > 0, "Invalid poolWeight value");
        if (_withUpdate) {
            massUpdatePools();
        }
        StakePool storage pool = stakePools[_pid];
        totalPoolWeight = totalPoolWeight - pool.poolWeight + _poolWeight;
        pool.poolWeight = _poolWeight;

        emit SetPoolWeight(_pid, _poolWeight, totalPoolWeight);
    }

    /**
     * @dev 设置质押开始块号
     * @param _startBlock 质押开始块号
     */
    function setStartBlock(uint256 _startBlock) public onlyRole(ADMIN_ROLE) {
        require(_startBlock <= endBlock, "start block must be smaller than end block");
        startBlock = _startBlock;
        emit SetStartBlock(_startBlock);
    }


    /**
     * @dev 设置质押结束块号
     * @param _endBlock 质押结束块号
     */
    function setEndBlock(uint256 _endBlock) public onlyRole(ADMIN_ROLE) {
        require(startBlock <= _endBlock, "start block must be smaller than end block");
        endBlock = _endBlock;
        emit SetEndBlock(_endBlock);
    }
    /**
     * @dev 设置 MetaNode 每区块的奖励数量
     * @param _metaNodePerBlock 每个区块奖励的质押币（MetaNode）数量
     */
    function setMetaNodePerBlock(uint256 _metaNodePerBlock) public onlyRole(ADMIN_ROLE) {
        require(_metaNodePerBlock > 0, "Invalid metaNodePerBlock value");
        metaNodePerBlock = _metaNodePerBlock;
        emit SetMetaNodePerBlock(_metaNodePerBlock);
    }
    /**
     * @dev 设置 MetaNode 代币地址
     */
    function setmeatNodeToken(IERC20 _meatNodeToken) public onlyRole(ADMIN_ROLE) {
        meatNodeToken = _meatNodeToken;
        emit SetMetaNode(_meatNodeToken);
    }

    /**
     * @dev 获取质押池数量
     * @return 质押池数量
     */
    function poolLength() public view returns (uint256) {
        return stakePools.length;
    }

    /**
     * @dev 添加质押池
     */
    function addStakePool(address _tokenAddress, 
        uint256 _poolWeight, 
        uint256 _minDepositAmount, 
        uint256 _unstakeLockedBlocks, 
        bool _withUpdate) public onlyRole(ADMIN_ROLE) { 
        if (stakePools.length > 0) {
            require(_tokenAddress != address(0x0), "Invalid staking token address");
        } else {
            // 第一个质押池，tokenAddress必须是ETH
            require(_tokenAddress == address(0x0), "Invalid staking token address");
        }
        require(_unstakeLockedBlocks > 0, "Invalid unstake locked blocks");
        // 当前块号
        uint256 currentBlock = block.number;
        require(currentBlock < endBlock, "Already ended");

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = currentBlock > startBlock ? currentBlock : startBlock;
        totalPoolWeight = totalPoolWeight + _poolWeight;
        stakePools.push(StakePool({
            tokenAddress: _tokenAddress,
            poolWeight: _poolWeight,
            lastRewardBlock: lastRewardBlock,
            accumulatedMetaNodePerST: 0,
            stTotalTokenAmount: 0,
            minDepositAmount: _minDepositAmount,
            unstakeLockedBlocks: _unstakeLockedBlocks
        }));
    }

    /**
     * @dev 获取用户在指定质押池的质押币种数量
     * @param _pid 质押池ID
     * @param _user 用户地址
     * @return 质押币种数量
     */
    function stakingBalance(uint256 _pid, address _user) public view returns (uint256) {
        StakeUser storage user = stakeUsers[_pid][_user];
        return user.stAmount;
    }


    /**
     * @dev 计算用户在指定质押池的待领取 MetaNode 数量
     * @param _pid 质押池ID
     * @param _user 用户地址
     * @return requestAmount 待领取 MetaNode 数量
     * @return pendingWithdrawAmount 待领取 MetaNode 数量
     */
    function withdrawAmount(uint256 _pid, address _user) public view 
        returns (uint256 requestAmount, uint256 pendingWithdrawAmount) {
        StakeUser storage user = stakeUsers[_pid][_user];
        UnstakeRequest[] memory unstakeRequests = user.unstakeRequests;
        uint256 unstakeRequestsLength = unstakeRequests.length;
        uint256 currentBlock = block.number;
        for (uint256 i = 0; i < unstakeRequestsLength; i++) {
            UnstakeRequest memory request = unstakeRequests[i];
            if (request.unlockBlocks <= currentBlock) {
                pendingWithdrawAmount = pendingWithdrawAmount + request.amount;
            }
            requestAmount = requestAmount + request.amount;
        }
        return (requestAmount, pendingWithdrawAmount);
    }

    /**
     * @dev 计算质押池在指定时间范围内应奖励的 MetaNode 总数量
     * @param _from 开始块号
     * @param _to 结束块号
     * @param _poolWeight 质押池权重
     * @return 质押池在指定时间范围内应奖励的 MetaNode 总数量
     */
    function calcAccumulatedMetaNode(uint256 _from, uint256 _to, uint256 _poolWeight) public view returns (uint256) {
        require(_from <= _to, "Invalid block range");
        _from = _from < startBlock ? startBlock : _from;
        _to = _to > endBlock ? endBlock : _to;
        // 计算离上一次计算奖励的块数差
        uint256 blocksPassed = _to - _from;
        // 累计奖励的质押池 MetaNode 数量
        uint256 totalMetNode = blocksPassed * metaNodePerBlock;
        // 根据质押池权重计算应奖励的 MetaNode 总数量
        return totalMetNode * _poolWeight / totalPoolWeight;
    }

    /**
     * @dev 更新指定质押池的累计每1个质押币种奖励的 MetaNode 数量
     * @param _pid 质押池ID
     */
    function updatePool(uint256 _pid) public checkPid(_pid) { 
        StakePool storage pool = stakePools[_pid];
        uint256 currentBlock = block.number;
        if (pool.lastRewardBlock >= currentBlock) {
            return;
        }
        uint256 _accumulatedMetaNode = calcAccumulatedMetaNode(pool.lastRewardBlock, currentBlock, pool.poolWeight);
        // 质押池已质押的总金额
        uint _stTotalTokenAmount = pool.stTotalTokenAmount;
        if (_stTotalTokenAmount > 0) {
           // 累计每1个质押币奖励的 MetaNode 数量
           uint256 totalMetaNode = (_accumulatedMetaNode * 1 ether) / _stTotalTokenAmount;
           // 更新质押池的累计每1个质押币种奖励的 MetaNode 数量
           pool.accumulatedMetaNodePerST = pool.accumulatedMetaNodePerST + totalMetaNode;
        }
        // 更新质押池的上一次计算奖励的块号
        pool.lastRewardBlock = currentBlock;
        emit UpdatePool(_pid, _accumulatedMetaNode);
    }

    /**
     * @dev 计算指定质押用户的待领取 MetaNode 数量
     * @param userStTokenAmount 质押用户的质押金额
     * @param userFinishedMetaNode 用户质押领取 MetaNode 基线
     * @param userPendingMetaNode 质押用户的待领取 MetaNode 数量
     * @param poolAccumulatedMetaNodePerST 质押池累计每1个质押币种奖励的 MetaNode 数量
     * @return 计算后的质押用户的待领取 MetaNode 数量
     */
    function calcUserPendingMetaNode(
        uint256 userStTokenAmount, 
        uint256 userFinishedMetaNode,
        uint256 userPendingMetaNode,
        uint256 poolAccumulatedMetaNodePerST
        ) public pure returns (uint256) { 
        if (userStTokenAmount > 0) {
            // 计算质押用户的待领取 MetaNode 数量
            uint256 pendingMetaNode = 
                userStTokenAmount * poolAccumulatedMetaNodePerST / 1 ether - userFinishedMetaNode;
            if (pendingMetaNode > 0) {
                // 将新计算的待领取 MetaNode 数量累加到质押用户的待领取 MetaNode 数量中
                userPendingMetaNode = userPendingMetaNode + pendingMetaNode;
            }
        }
        return userPendingMetaNode;
    }


    /**
     * @dev 计算指定质押用户的质押领取 MetaNode 基线
     * @param userStTokenAmount 质押用户的质押金额
     * @param poolAccumulatedMetaNodePerST 质押池累计每1个质押币种奖励的 MetaNode 数量
     * @return 计算后的质押用户的质押领取 MetaNode 基线
     */
    function calcUserFinishedMetaNode(
        uint256 userStTokenAmount, 
        uint256 poolAccumulatedMetaNodePerST
        ) public pure returns (uint256) { 
        return userStTokenAmount * poolAccumulatedMetaNodePerST / 1 ether;
    }


    

    /**
     * @dev 更新所有质押池的累计每1个质押币种奖励的 MetaNode 数量
     */
    function massUpdatePools() public {
        uint256 length = stakePools.length;
        for (uint256 pid = 0; pid < length; pid++) {
            updatePool(pid);
        }
    }


    /**
     * @dev 存储用户在质押池的质押金额
     * @notice 仅支持 ETH 质押
     */
    function depositETH() public payable {
        StakePool storage pool = stakePools[0];
        require(pool.tokenAddress == address(0x0), "Invalid stake token");
        uint256 amount = msg.value;
        require(amount > pool.minDepositAmount, "Invalid deposit amount, deposit amount is too low");
        _deposit(0, amount);
    }

    /**
     * @dev 存储用户在质押池的质押金额
     * @param _pid 质押池ID
     * @param _amount 质押数量
     */
    function deposit(uint256 _pid, uint256 _amount) public checkPid(_pid) {
        StakePool storage pool = stakePools[_pid];
        require(pool.tokenAddress != address(0x0), "Invalid stake token");
        require(_amount > pool.minDepositAmount, "Invalid deposit amount, deposit amount is too low");
        if (_amount > 0) {
            IERC20(pool.tokenAddress).safeTransferFrom(msg.sender, address(this), _amount);
        }
        _deposit(_pid, _amount);
    }

    /**
     * @dev 解质押
     * @param _pid 质押池ID
     * @param _amount 解质押数量
     */
    function unstake(uint256 _pid, uint256 _amount) public checkPid(_pid) whenNotWithdrawPaused {
        StakePool storage pool = stakePools[_pid];
        StakeUser storage user = stakeUsers[_pid][_msgSender()];
        require(_amount > 0, "Invalid unstake amount");
        require(user.stAmount >= _amount, "Insufficient stake amount");
        updatePool(_pid);
        user.pendingMetaNode = calcUserPendingMetaNode(
                user.stAmount, 
                user.finishedMetaNode,
                user.pendingMetaNode, 
                pool.accumulatedMetaNodePerST);

        // 将本次解质押数量减去质押用户的质押数量
        user.stAmount = user.stAmount - _amount;
        user.unstakeRequests.push(UnstakeRequest(_amount, block.number + pool.unstakeLockedBlocks));
        // 计算质押用户的领取 MetaNode 基线
        user.finishedMetaNode = calcUserFinishedMetaNode(user.stAmount, pool.accumulatedMetaNodePerST);
        // 将本次解质押数量减去质押池的总质押数量
        pool.stTotalTokenAmount = pool.stTotalTokenAmount - _amount;
        emit Unstake(_msgSender(), _pid, _amount);
    }

/**
     * @dev 提现
     * @param _pid 质押池ID
     */
    function withdraw(uint256 _pid) public checkPid(_pid) whenNotWithdrawPaused {
        StakePool storage pool = stakePools[_pid];
        StakeUser storage user = stakeUsers[_pid][_msgSender()];
        uint256 currentBlock = block.number;
        uint256 unstakeReqLen = user.unstakeRequests.length;
        uint256 withdrawAmount_ = 0;
        if (unstakeReqLen > 0) {
            // 遍历质押用户的解质押请求列表
            uint256 popNum = 0;
            for (uint256 i = 0; i < unstakeReqLen; i++) {
                UnstakeRequest storage req = user.unstakeRequests[i];
                if (req.unlockBlocks > currentBlock) {
                    break;
                }
                withdrawAmount_ = withdrawAmount_ + req.amount;
                popNum++;
            }
            
            // Advanced2 合约一致的清理逻辑：
            // 将未解锁的请求（popNum 之后）向前搬 popNum 个位置，再 pop 掉末尾 popNum 条
            for (uint256 i = 0; i < unstakeReqLen - popNum; i++) {
                user.unstakeRequests[i] = user.unstakeRequests[i + popNum];
            }

            for (uint256 i = 0; i < popNum; i++) {
                user.unstakeRequests.pop();
            }

            if (withdrawAmount_ > 0) {
                address _tokenAddress = pool.tokenAddress;
                if (_tokenAddress == address(0x0)) {
                    _safeETHTransfer(_msgSender(), withdrawAmount_);
                } else {
                    // 质押币种为其他币种
                    IERC20(_tokenAddress).safeTransfer(_msgSender(), withdrawAmount_);
                }
            }
        }

        emit Withdraw(_msgSender(), _pid, withdrawAmount_);
    }

    

    /**
     * @dev 领取 MetaNode
     * @param _pid 质押池ID
     */
    function claim(uint256 _pid) public checkPid(_pid) whenNotClaimPaused {
        StakePool storage pool = stakePools[_pid];
        StakeUser storage user = stakeUsers[_pid][_msgSender()];
        updatePool(_pid);
         if (user.stAmount > 0) {
            uint256 pendingMetaNode = calcUserPendingMetaNode(
                user.stAmount, 
                user.finishedMetaNode,
                user.pendingMetaNode, 
                pool.accumulatedMetaNodePerST);

            if (pendingMetaNode > 0) {
                user.pendingMetaNode = 0;
                _saveMetaNodeTransfer(_msgSender(), pendingMetaNode);
            }
            user.finishedMetaNode = calcUserFinishedMetaNode(user.stAmount, pool.accumulatedMetaNodePerST);
            emit Claim(_msgSender(), _pid, pendingMetaNode);
        }
        
    }


    /**
     * @dev 质押
     * @param _pid 质押池ID
     * @param _amount 质押数量
     */
    function _deposit(uint256 _pid, uint256 _amount) internal {
        StakePool storage pool = stakePools[_pid];
        StakeUser storage user = stakeUsers[_pid][_msgSender()];
        updatePool(_pid);
        if (user.stAmount > 0) {
            user.pendingMetaNode = calcUserPendingMetaNode(
                user.stAmount, 
                user.finishedMetaNode,
                user.pendingMetaNode, 
                pool.accumulatedMetaNodePerST);
        }
        if (_amount > 0) {
            // 将本次质押数量加到质押用户的质押数量中
            user.stAmount = user.stAmount + _amount;
        }
        // 将本次质押数量加到质押池的总质押数量中
        pool.stTotalTokenAmount = pool.stTotalTokenAmount + _amount;
        // 计算质押用户的领取 MetaNode 基线
        user.finishedMetaNode = calcUserFinishedMetaNode(user.stAmount, pool.accumulatedMetaNodePerST);
    }

    /**
     * @dev 安全转账 MetaNode
     * @param _to 转账地址
     * @param _amount 转账数量
     */
    function _saveMetaNodeTransfer(address _to, uint256 _amount) internal {
       uint256 metaNodeBal = meatNodeToken.balanceOf(address(this));
       if (metaNodeBal >= _amount) {
           // 足够 MetaNode 余额，直接转账
           meatNodeToken.safeTransfer(_to, _amount);
       } else {
           // 不足 MetaNode 余额，转账所有 MetaNode 余额
           meatNodeToken.safeTransfer(_to, metaNodeBal);
       }
    }
    


    /**
     * @dev 安全转账 ETH
     * @param _to 转账地址
     * @param _amount 转账数量
     */
    function _safeETHTransfer(address _to, uint256 _amount) internal {
        (bool sent, bytes memory data) = _to.call{value: _amount}("");
        require(sent, "Failed to send ETH");
        if (data.length > 0) {
            require(abi.decode(data, (bool)), "Failed to send ETH");
        }
    }
}
