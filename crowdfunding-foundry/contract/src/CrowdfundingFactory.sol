// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "./CrowdfundingCampaign.sol";

/**
 * @title CrowdfundingFactory
 * @dev 众筹活动工厂合约
 * @notice 该合约用于创建和管理众筹活动合约，包括活动的创建、状态更新、捐赠和提取资金等功能
 */
contract CrowdfundingFactory {
    // 活动合约地址数组
    address[] public campaignContracts;
    // 用户创建的活动合约地址数组
    mapping(address => uint256[]) public userCampaigns;

    /**
     * 活动创建事件
     * @param creator 创建者地址
     * @param campaign 活动合约地址
     * @param campaignName 活动名称
     * @param campaignGoal 活动目标金额
     * @param campaignDeadline 活动结束时间
     */
    event CampaignCreated(
        address indexed creator, 
        address indexed campaign, 
        string campaignName,
        uint256 campaignGoal,
        uint256 campaignDeadline);


    /**
     * 创建众筹活动
     * @param campaignName 活动名称
     * @param campaignGoal 活动目标金额
     * @param durationInDays 活动持续时间（天）
     * @return 活动合约地址
     */
    function createCampaign(
        string memory campaignName,
        uint256 campaignGoal,
        uint256 durationInDays
    ) external returns (address) {
        require(campaignGoal > 0, "Campaign goal must be greater than 0");
        require(durationInDays > 0, "Campaign duration must be greater than 0");
        // 创建活动合约
        address campaignAddress = address(new CrowdfundingCampaign(
            msg.sender,
            campaignName,
            campaignGoal,
            durationInDays
        ));
        // 记录合约地址
        campaignContracts.push(campaignAddress);
        // 记录用户创建的合约地址， campaignContracts.length - 1 即为最新创建的合约在数组中的索引
        userCampaigns[msg.sender].push(campaignContracts.length - 1);
        // 触发活动创建事件
        emit CampaignCreated(
            msg.sender, 
            campaignAddress, 
            campaignName, 
            campaignGoal, 
            block.timestamp + (durationInDays * 1 days));
        return campaignAddress;
    }

    /**
     * 获取所有众筹活动合约地址
     * @return 所有众筹活动合约地址数组
     */
    function getCampaigns() public view returns (address[] memory) {
        uint256 campaignCount = campaignContracts.length;
        address[] memory campaigns = new address[](campaignCount);
        for (uint256 i = 0; i < campaignCount; i++) {
            campaigns[i] = campaignContracts[i];
        }
        return campaigns;
    }

    /**
     * 获取某1个用户创建的众筹活动合约地址
     * @param user 用户地址
     * @return 用户创建的众筹活动合约地址数组
     */
    function getUserCampaigns(address user) public view returns (address[] memory) {
        uint256[] memory indices = userCampaigns[user];
        uint256 campaignCount = indices.length;
        address[] memory campaigns = new address[](campaignCount);
        for (uint256 i = 0; i < campaignCount; i++) {
            campaigns[i] = campaignContracts[indices[i]];
        }
        return campaigns;
    }

    /**
     * 获取所有众筹活动合约数量
     * @return 所有众筹活动合约数量
     */
    function getCampaignCount() public view returns (uint256) {
        return campaignContracts.length;
    }
}
