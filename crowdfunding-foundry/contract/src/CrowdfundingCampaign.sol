// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title CrowdfundingCampaign
 * @dev 众筹活动合约
 * @notice 该合约用于创建和管理众筹活动，包括活动的创建、状态更新、捐赠和提取资金等功能
 */
contract CrowdfundingCampaign {
    /**
     * 活动状态枚举
     */
       enum CampaignStatus {
        // 活动状态：准备中
        Preparing,
        // 活动状态：进行中
        Active,
        // 活动状态：已成功
        Successful,
        // 活动状态：已失败
        Failed,
        // 活动状态：已关闭(活动成功且资金已提取)
        Closed
    }
    // 活动状态
    CampaignStatus public status;
    // 活动所有者
    address public immutable owner;
    // 活动名称
    string public campaignName;
    // 活动目标金额
    uint256 public campaignGoal;
    // 活动结束时间
    uint256 public campaignDeadline;
    // 活动当前金额 raise
    uint256 public campaignRaised;
    // 活动捐赠记录
    mapping(address => uint256) public campaignDonations;
    // 活动捐赠者列表
    address[] public campaignDonors;
    /**
     * 活动状态改变事件
     * @param oldStatus 旧状态
     * @param newStatus 新状态
     */
    event CampaignStatusChanged(CampaignStatus oldStatus, CampaignStatus newStatus);

    /**
     * 活动捐赠事件
     * @param campaign 活动地址
     * @param donor 捐赠者地址
     * @param amount 捐赠金额
     */
    event CampaignDonated(address indexed campaign, address indexed donor, uint256 amount);

    /**
     * 提取资金事件
     * @param campaign 活动地址
     * @param amount 提取金额
     */
    event CampaignWithdrawn(address indexed campaign, uint256 amount);

    /**
     * 退款事件
     * @param campaign 活动地址
     * @param amount 退款金额
     */
    event CampaignRefunded(address indexed campaign, uint256 amount);

    /**
     * 仅允许活动所有者调用的修饰符
     */
    modifier onlyOwner {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    /**
     * 检查活动状态是否为指定状态的修饰符
     * @param _status 活动状态
     */
    modifier isStatus(CampaignStatus _status) {
        require(status == _status, "Invalid campaign status");
        _;
    }
    /**
     * 检查活动是否已过期的修饰符
     */
    modifier notExpired {
        require(block.timestamp < campaignDeadline, "Campaign deadline has passed");
        _;
    }
    /**
     * 活动贡献金额为0错误
     */
    error ZeroContributionAmount();
    /**
     * 活动未过期错误
     */
    error HasNotExpired();

    /**
     * 活动构造函数
     * @param _owner 活动所有者地址
     * @param _campaignName 活动名称
     * @param _campaignGoal 活动目标金额, 单位：wei
     * @param _durationInDays 活动持续时间（天） 范围：1-90天
     */
    constructor(
        address _owner,
        string memory _campaignName,
        uint256 _campaignGoal,
        uint256 _durationInDays
    ) {
        require(address(_owner) != address(0), "Owner address cannot be zero");
        require(bytes(_campaignName).length > 0, "Campaign name cannot be empty");
        require(_campaignGoal > 0, "Campaign goal must be greater than 0");
        require(_durationInDays > 0 && _durationInDays <= 90, "Campaign duration must be greater than 0 and less than or equal to 90 days");
        owner = _owner;
        campaignName = _campaignName;
        campaignGoal = _campaignGoal;
        campaignDeadline = block.timestamp + (_durationInDays * 1 days);
        status = CampaignStatus.Preparing;
    }
    
    /**
     * 启动活动
     * @dev 仅允许活动所有者调用，将活动状态设置为进行中
     */
    function startCampaign() external onlyOwner isStatus(CampaignStatus.Preparing) {
        status = CampaignStatus.Active;
        emit CampaignStatusChanged(CampaignStatus.Preparing, status);
    }

    /**
     * 活动贡献
     * @dev 活动进行中时，用户可以贡献资金
     */
    function contribute() external payable isStatus(CampaignStatus.Active) notExpired() {
        if(msg.value == 0) {
            revert ZeroContributionAmount();
        }
        address donor = msg.sender;
        uint256 addAmount = msg.value;
        if (campaignDonations[donor] == 0) {
            campaignDonors.push(donor);
        }
        campaignDonations[donor] += addAmount;
        campaignRaised += addAmount;
        emit CampaignDonated(address(this), donor, addAmount);
        if (campaignRaised >= campaignGoal) {
            status = CampaignStatus.Successful;
            emit CampaignStatusChanged(CampaignStatus.Active, status);
        }
    }

    /**
     * 结束活动
     * @dev 活动结束时间后，活动状态设置为已完成
     */
    function endCampaign() external onlyOwner {
        if (block.timestamp < campaignDeadline) {
            revert HasNotExpired();
        }
        CampaignStatus oldStatus = status;
        if (campaignRaised >= campaignGoal) {
            status = CampaignStatus.Successful;
        } else {
            status = CampaignStatus.Failed;
        }
        emit CampaignStatusChanged(oldStatus, status);
    }

    /**
     * 提取资金
     * @dev 活动完成时，活动所有者可以提取资金
     */
    function withdrawFunds() external onlyOwner isStatus(CampaignStatus.Successful) {
        status = CampaignStatus.Closed;
        // 获取合约当前余额
        uint256 amount = address(this).balance;
        (bool success, ) = owner.call{value: amount}("");
        require(success, "Failed to withdraw funds");
        emit CampaignWithdrawn(address(this), amount);
        emit CampaignStatusChanged(CampaignStatus.Successful, CampaignStatus.Closed);
    }


    /**
     * 退款资金
     * @dev 活动失败时，用户可以退款资金
     */
    function refundDonations() external isStatus(CampaignStatus.Failed) {
        uint256 refundAmount = campaignDonations[msg.sender];
        require(refundAmount > 0, "No refund amount to refund");
        campaignDonations[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: refundAmount}("");
        require(success, "Failed to refund funds");
        emit CampaignRefunded(msg.sender, refundAmount);
    }

    /**
     * 获取所有贡献者
     * @return 返回所有贡献者的地址数组
     */
    function getContributors() external view returns (address[] memory) {    
        return campaignDonors;
    }

    /**
     * 获取贡献者数量
     * @return 返回所有贡献者的数量
     */
    function getContributorCount() external view returns (uint256) {
        return campaignDonors.length;
    }

    /**
     * 检查活动是否进行中
     * @return 返回活动状态是否为进行中
     */
    function isActive() external view returns (bool) {
        return status == CampaignStatus.Active;
    }

    /**
     * 获取活动进度
     * @return 返回当前进度的百分比
     */
    function getProgress() external view returns (uint256) {
        if (campaignGoal == 0) {
            return 0;
        }
        uint256 progress = (campaignRaised * 100) / campaignGoal;
        return progress > 100 ? 100 : progress;
    }

}