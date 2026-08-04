// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CrowdfundingFactory} from "../src/CrowdfundingFactory.sol";
import {CrowdfundingCampaign} from "../src/CrowdfundingCampaign.sol";

contract CrowdfundingFactoryTest is Test {
    CrowdfundingFactory public factory;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    string constant CAMPAIGN_NAME = unicode"测试众筹活动";
    uint256 constant GOAL = 10 ether;
    uint256 constant DURATION_DAYS = 7;

    function setUp() public {
        factory = new CrowdfundingFactory();
    }

    function testCreateCampaign() public {
        vm.prank(owner);
        address campaignAddress = factory.createCampaign(CAMPAIGN_NAME, GOAL, DURATION_DAYS);
        assertEq(factory.getCampaignCount(), 1);
        assertNotEq(campaignAddress, address(0));

        CrowdfundingCampaign campaign = CrowdfundingCampaign(payable(campaignAddress));
        assertEq(campaign.owner(), owner);
        assertEq(campaign.campaignGoal(), GOAL);
    }
    /**
     * @notice 测试创建众筹活动事件
     * @dev 测试在创建众筹活动时是否触发了CampaignCreated 事件  
     */
    function testCreateCampaignEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit CrowdfundingFactory.CampaignCreated(owner, address(0), CAMPAIGN_NAME, GOAL, block.timestamp + (DURATION_DAYS * 1 days));
        factory.createCampaign(CAMPAIGN_NAME, GOAL, DURATION_DAYS);
    }

    /**
     * @notice 测试多个用户创建众筹活动
     * @dev 测试多个用户是否能够成功创建众筹活动
     */
    function testMultipleUsersCreateCampaigns() public {
        vm.prank(user1);
        factory.createCampaign(CAMPAIGN_NAME, GOAL, DURATION_DAYS);
        vm.prank(user2);
        factory.createCampaign(CAMPAIGN_NAME, GOAL, DURATION_DAYS);
        assertEq(factory.getCampaignCount(), 2);
    }

    /**
     * @notice 测试获取所有众筹活动合约地址
     * @dev 测试在创建多个众筹活动后，是否能够正确获取所有活动合约地址
     */
    function testGetCampaigns() public {
        vm.prank(user1);
        factory.createCampaign(CAMPAIGN_NAME, GOAL, DURATION_DAYS);
        vm.prank(user1);
        factory.createCampaign(CAMPAIGN_NAME, GOAL * 2, DURATION_DAYS);
        vm.prank(user2);
        factory.createCampaign(CAMPAIGN_NAME, GOAL * 3, DURATION_DAYS);
        address[] memory campaigns = factory.getCampaigns();
        assertEq(campaigns.length, 3);
        assertNotEq(campaigns[0], address(0));
        assertNotEq(campaigns[1], address(0));
        assertNotEq(campaigns[2], address(0));
    }

    /**
     * @notice 测试获取用户创建的众筹活动合约地址
     * @dev 测试在创建多个众筹活动后，是否能够正确获取用户创建的活动合约地址
     */
    function testGetUserCampaigns() public {
        vm.prank(user1);
        factory.createCampaign(CAMPAIGN_NAME, GOAL, DURATION_DAYS);

        vm.prank(user1);
        factory.createCampaign(CAMPAIGN_NAME, GOAL * 2, DURATION_DAYS);

        vm.prank(user2);
        factory.createCampaign(CAMPAIGN_NAME, GOAL * 3, DURATION_DAYS);

        address[] memory user1Campaigns = factory.getUserCampaigns(user1);
        assertEq(user1Campaigns.length, 2);

        address[] memory user2Campaigns = factory.getUserCampaigns(user2);
        assertEq(user2Campaigns.length, 1);
    }

    /**
     * @notice 测试获取所有众筹活动合约地址
     * @dev 测试在创建多个众筹活动后，是否能够正确获取所有活动合约地址
     */
    function testGetCampaignCount() public {
        vm.prank(user1);
        factory.createCampaign(CAMPAIGN_NAME, GOAL, DURATION_DAYS);

        vm.prank(user1);
        factory.createCampaign(CAMPAIGN_NAME, GOAL * 2, DURATION_DAYS);

        vm.prank(user2);
        factory.createCampaign(CAMPAIGN_NAME, GOAL * 3, DURATION_DAYS);

        assertEq(factory.getCampaignCount(), 3);
    }

    /**
     * @notice 测试创建众筹活动时，目标金额为0的情况
     * @dev 测试在创建众筹活动时，目标金额为0的情况，是否能够正确抛出异常
     */
    function testRevertCreateCampaignWithZeroGoal() public {
        vm.prank(owner);
        vm.expectRevert("Campaign goal must be greater than 0");
        factory.createCampaign(CAMPAIGN_NAME, 0, DURATION_DAYS);
    }

    /**
     * @notice 测试创建众筹活动时，持续时间为为0的情况
     * @dev 测试在创建众筹活动时，持续时间为为0的情况，是否能够正确抛出异常
     */
    function testRevertCreateCampaignWithZeroDuration() public {
        vm.prank(owner);
        vm.expectRevert("Campaign duration must be greater than 0");
        factory.createCampaign(CAMPAIGN_NAME, GOAL, 0);
    }
}