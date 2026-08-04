// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CrowdfundingCampaign} from "../src/CrowdfundingCampaign.sol";

contract CrowdfundingCampaignTest is Test {
    CrowdfundingCampaign public campaign;

    address public owner = address(0x1);
    address public contributor1 = address(0x2);
    address public contributor2 = address(0x3);
    address public contributor3 = address(0x4);

    uint256 constant GOAL = 10 ether;
    uint256 constant DURATION_DAYS = 7;
    string constant CAMPAIGN_NAME = unicode"测试众筹活动";

    function setUp() public {
        vm.prank(owner);
        campaign = new CrowdfundingCampaign(owner, CAMPAIGN_NAME, GOAL, DURATION_DAYS);
    }

    /**
     * @dev 测试部署初始状态
     */
    function testDeploymentInitialState() public view {
        assertEq(uint256(campaign.status()), uint256(CrowdfundingCampaign.CampaignStatus.Preparing));
        assertEq(campaign.owner(), owner);
        assertEq(campaign.campaignGoal(), GOAL);
        assertEq(campaign.campaignRaised(), 0);
    }

    /**
     * @dev 测试部署活动结束时间
     */
    function testDeploymentDeadline() public view{
        uint256 deadline = campaign.campaignDeadline();
        uint256 expectedDeadline = block.timestamp + (DURATION_DAYS * 1 days);
        // 活动结束时间与预期时间的差值应小于5秒
        assertApproxEqAbs(deadline, expectedDeadline, 5);
    }

    /**
     * @dev 测试部署无效参数
     */
    function testRevertInvalidConstructorParams() public {
        vm.expectRevert("Owner address cannot be zero");
        new CrowdfundingCampaign(address(0), CAMPAIGN_NAME, GOAL, DURATION_DAYS);

        vm.expectRevert("Campaign name cannot be empty");
        new CrowdfundingCampaign(owner, "", GOAL, DURATION_DAYS);

        vm.expectRevert("Campaign goal must be greater than 0");
        new CrowdfundingCampaign(owner, CAMPAIGN_NAME, 0, DURATION_DAYS);

        vm.expectRevert("Campaign duration must be greater than 0 and less than or equal to 90 days");
        new CrowdfundingCampaign(owner, CAMPAIGN_NAME, GOAL, 0);

        vm.expectRevert("Campaign duration must be greater than 0 and less than or equal to 90 days");
        new CrowdfundingCampaign(owner, CAMPAIGN_NAME, GOAL, 91);
    }

    /**
     * @dev 测试开始活动
     */
    function testStartCampaign() public {
        // 测试开始活动前的状态
        assertEq(uint256(campaign.status()), uint256(CrowdfundingCampaign.CampaignStatus.Preparing));
        vm.prank(owner);
        // 测试开始活动
        campaign.startCampaign();
        assertEq(uint256(campaign.status()), uint256(CrowdfundingCampaign.CampaignStatus.Active));
    }

    function testRevertStartIfNotPreparing() public {
        vm.prank(owner);
        // 测试开始活动
        campaign.startCampaign();

        vm.prank(owner);
        vm.expectRevert("Invalid campaign status");
        campaign.startCampaign();
    }

    /**
     * @dev 测试贡献资金
     */
    function testContribute() public {
        vm.prank(owner);
        campaign.startCampaign();
        uint256 contributionAmount = 5 ether;
        vm.deal(contributor1, contributionAmount);
        vm.prank(contributor1);
        campaign.contribute{value: contributionAmount}();
        assertEq(campaign.campaignRaised(), contributionAmount);
        assertEq(campaign.campaignDonations(contributor1), contributionAmount);
    }

    /**
     * @dev 测试贡献资金
     */
    function testMultipleContributionsSameUser() public {
        vm.prank(owner);
        campaign.startCampaign();

        vm.deal(contributor1, 3 ether);
        vm.prank(contributor1);
        campaign.contribute{value: 3 ether}();

        vm.deal(contributor2, 2 ether);
        vm.prank(contributor2);
        campaign.contribute{value: 2 ether}();
        assertEq(campaign.getContributorCount(), 2);
        address[] memory contributors = campaign.getContributors();
        assertEq(contributors[0], contributor1);
        assertEq(contributors[1], contributor2);
    }

    /**
     * @dev 测试贡献0资金
     */
    function testRevertZeroContribution() public {
        vm.prank(owner);
        campaign.startCampaign();
        vm.prank(contributor1);
        vm.expectRevert(CrowdfundingCampaign.ZeroContributionAmount.selector);
        campaign.contribute{value: 0}();
    }
    // 写法1：使用 .selector
    // vm.expectRevert(CrowdfundingCampaign.ZeroContributionAmount.selector);
    // 写法2：直接传错误对象（不需要 .selector）
    // vm.expectRevert(CrowdfundingCampaign.ZeroContributionAmount());
    // 写法 1：只比对开头 4 字节，只要错误类型匹配就行；适合无参数错误
    // 写法 2：会比对完整编码，如果错误带参数，参数不一样测试直接失败，更严格



    /**
     * @dev 测试贡献资金后活动结束时间
     */
    function testRevertContributionAfterDeadline() public {
        vm.prank(owner);
        campaign.startCampaign();
        // 前进到活动结束时间
        vm.warp(block.timestamp + ((DURATION_DAYS + 1) * 1 days));
        uint256 amount = 5 ether;
        vm.deal(contributor1, amount);
        vm.prank(contributor1);
        vm.expectRevert("Campaign deadline has passed");
        campaign.contribute{value: amount}();
    }

    /**
     * @dev 测试贡献资金时活动未开始
     */
    function testRevertContributionWhenNotActive() public {
        vm.deal(contributor1, 1 ether);
        vm.prank(contributor1);
        vm.expectRevert("Invalid campaign status");
        campaign.contribute{value: 1 ether}();
    }

    /**
     * @dev 测试结束活动成功
     */
    function testEndCampaignSuccess() public {
        vm.prank(owner);
        campaign.startCampaign();

        vm.deal(contributor1, GOAL);
        vm.prank(contributor1);
        campaign.contribute{value: GOAL}();
        // 前进到活动结束时间
        vm.warp(block.timestamp + DURATION_DAYS * 1 days + 1);
        assertEq(uint256(campaign.status()), uint256(CrowdfundingCampaign.CampaignStatus.Successful));
    }

    /**
     * @dev 测试结束活动失败
     */
    function testEndCampaignFailed() public {
        vm.prank(owner);
        campaign.startCampaign();

        vm.deal(contributor1, 5 ether);
        vm.prank(contributor1);
        campaign.contribute{value: 5 ether}();
        // 前进到活动结束时间
        vm.warp(block.timestamp + DURATION_DAYS * 1 days + 1);
        vm.prank(owner);
        campaign.endCampaign();
        assertEq(uint256(campaign.status()), uint256(CrowdfundingCampaign.CampaignStatus.Failed));
    }

    /**
     * @dev 测试结束活动前未到时间
     */
    function testRevertEndCampaignBeforeDeadline() public {
        vm.prank(owner);
        campaign.startCampaign();
        vm.prank(owner);
        vm.expectRevert(CrowdfundingCampaign.HasNotExpired.selector);
        campaign.endCampaign();
    }

    /**
     * @dev 测试结束活动前活动未开始
     */
    function testRevertEndCampaignIfNotOwner() public {
        vm.prank(owner);
        campaign.startCampaign();
        vm.warp(block.timestamp + ((DURATION_DAYS + 1) * 1 days));
        vm.prank(contributor1);
        vm.expectRevert("Only owner can call this function");
        campaign.endCampaign();
    }


    /**
     * @dev 测试提取资金
     */
    function testWithdrawFunds() public {
        vm.prank(owner);
        campaign.startCampaign();

        vm.deal(contributor1, GOAL);
        vm.prank(contributor1);
        campaign.contribute{value: GOAL}();

        vm.warp(block.timestamp + DURATION_DAYS * 1 days + 1);

        vm.prank(owner);
        campaign.endCampaign();

        uint256 ownerBalanceBefore = address(owner).balance;

        vm.prank(owner);
        campaign.withdrawFunds();

        uint256 ownerBalanceAfter = address(owner).balance;
        assertEq(ownerBalanceAfter, ownerBalanceBefore + GOAL);
        assertEq(uint256(campaign.status()), uint256(CrowdfundingCampaign.CampaignStatus.Closed));
    }

    function testRevertWithdrawFundsIfNotOwner() public {
        vm.prank(owner);
        campaign.startCampaign();

        vm.deal(contributor1, GOAL);
        vm.prank(contributor1);
        campaign.contribute{value: GOAL}();

        vm.warp(block.timestamp + DURATION_DAYS * 1 days + 1);

        vm.prank(owner);
        campaign.endCampaign();

        vm.prank(contributor1);
        vm.expectRevert("Only owner can call this function");
        campaign.withdrawFunds();
    }

    /**
     * @dev 测试提取资金前活动未完成
     */
    function testRevertWithdrawIfNotCompleted() public {
        vm.prank(owner);
        campaign.startCampaign();
        vm.prank(owner);
        vm.expectRevert("Invalid campaign status");
        campaign.withdrawFunds();
    }

    /**
     * @dev 测试退款资金
     */
    function testRefundDonations() public {
        vm.prank(owner);
        campaign.startCampaign();

        uint256 contributionAmount1 = 5 ether;
        vm.deal(contributor1, contributionAmount1);
        vm.prank(contributor1);
        campaign.contribute{value: contributionAmount1}();

        uint256 contributionAmount2 = 1 ether;
        vm.deal(contributor2, contributionAmount2);
        vm.prank(contributor2);
        campaign.contribute{value: contributionAmount2}();

        uint256 contributionAmount3 = 3 ether;
        vm.deal(contributor3, contributionAmount3);
        vm.prank(contributor3);
        campaign.contribute{value: contributionAmount3}();

        // 前进到活动结束时间
        vm.warp(block.timestamp + DURATION_DAYS * 1 days + 1);
        vm.prank(owner);
        campaign.endCampaign();

        
        uint256 contributor1BalanceBefore = address(contributor1).balance;
        vm.prank(contributor1);
        campaign.refundDonations();
        uint256 contributor1BalanceAfter = address(contributor1).balance;
        assertEq(contributor1BalanceAfter, contributor1BalanceBefore + contributionAmount1);

        
        uint256 contributor2BalanceBefore = address(contributor2).balance;
        vm.prank(contributor2);
        campaign.refundDonations();
        uint256 contributor2BalanceAfter = address(contributor2).balance;
        assertEq(contributor2BalanceAfter, contributor2BalanceBefore + contributionAmount2);

        
        uint256 contributor3BalanceBefore = address(contributor3).balance;
        vm.prank(contributor3);
        campaign.refundDonations();
        uint256 contributor3BalanceAfter = address(contributor3).balance;
        assertEq(contributor3BalanceAfter, contributor3BalanceBefore + contributionAmount3);
    }

    /**
     * @dev 测试退款资金前未贡献
     */
    function testRevertRefundIfNoContribution() public {
        vm.prank(owner);
        campaign.startCampaign();
        vm.warp(block.timestamp + ((DURATION_DAYS + 1) * 1 days));
        vm.prank(owner);
        campaign.endCampaign();

        vm.expectRevert("No refund amount to refund");
        vm.prank(contributor1);
        campaign.refundDonations();
    }


    /**
     * @dev 测试退款资金前已退款
     */
    function testRevertDoubleRefund() public {
        vm.prank(owner);
        campaign.startCampaign();
        
        uint256 contributionAmount = 5 ether;
        vm.deal(contributor1, contributionAmount);
        vm.prank(contributor1);
        campaign.contribute{value: contributionAmount}();

        vm.warp(block.timestamp + ((DURATION_DAYS + 1) * 1 days));
        vm.prank(owner);
        campaign.endCampaign();

        vm.prank(contributor1);
        campaign.refundDonations();

        vm.prank(contributor1);
        vm.expectRevert("No refund amount to refund");
        campaign.refundDonations();
    }

    /**
     * @dev 测试活动进度50%
     */
    function testGetProgress() public {
        vm.prank(owner);
        campaign.startCampaign();

        vm.deal(contributor1, 3 ether);
        vm.prank(contributor1);
        campaign.contribute{value: 3 ether}();

        vm.deal(contributor2, 2 ether);
        vm.prank(contributor2);
        campaign.contribute{value: 2 ether}();

        assertEq(campaign.getProgress(), 50);
    }

    /**
     * @dev 测试活动进度100%
     */
    function testGetProgress100Percent() public {
        vm.prank(owner);
        campaign.startCampaign();

        vm.deal(contributor1, 3 ether);
        vm.prank(contributor1);
        campaign.contribute{value: 3 ether}();

        vm.deal(contributor2, 2 ether);
        vm.prank(contributor2);
        campaign.contribute{value: 2 ether}();

        vm.deal(contributor3, 5 ether);
        vm.prank(contributor3);
        campaign.contribute{value: 5 ether}();

        assertEq(campaign.getProgress(), 100);
    }

    /**
     * @dev 测试活动状态
     */
    function testIsActive() public {
        vm.prank(owner);
        campaign.startCampaign();

        assertTrue(campaign.isActive());

        vm.deal(contributor1, GOAL);
        vm.prank(contributor1);
        campaign.contribute{value: GOAL}();

        vm.warp(block.timestamp + DURATION_DAYS * 1 days + 1);

        vm.prank(owner);
        campaign.endCampaign();

        assertFalse(campaign.isActive());
    }
}