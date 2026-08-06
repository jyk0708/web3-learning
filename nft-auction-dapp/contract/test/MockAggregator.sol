// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title MockAggregator
 * @dev Chainlink 预言机 Mock 合约，用于测试
 */
contract MockAggregator {
    // @notice 最新价格
    int256 public price;
    // @notice 价格小数位数
    uint8 private _decimals;
    // @notice 最新更新时间
    uint256 public updatedAt;
    // @notice 最新轮次
    uint80 public roundId;
    // @notice 最新回答轮次 ，用于判断是否回答过
    uint80 public answeredInRound;

    /*
     * @notice 构造函数
     * @param _price 初始价格
     * @param __decimals 价格小数位数
     */
    constructor(int256 _price, uint8 __decimals) {
        price = _price;
        _decimals = __decimals;
        updatedAt = block.timestamp;
        roundId = 1;
        answeredInRound = 1;
    }

    /*
     * @notice 设置最新价格
     * @param _price 最新价格
     */
    function setPrice(int256 _price) external {
        price = _price;
        updatedAt = block.timestamp;
    }
    /*
     * @notice 设置最新价格和更新时间
     * @param _price 最新价格
     * @param _updatedAt 最新更新时间
     */
    function setPrice(int256 _price, uint256 _updatedAt) external {
        price = _price;
        updatedAt = _updatedAt;
    }
    /*
     * @notice 设置最新轮次和回答轮次
     * @param _roundId 最新轮次
     * @param _answeredInRound 最新回答轮次
     */
    function setRound(uint80 _roundId, uint80 _answeredInRound) external {
        roundId = _roundId;
        answeredInRound = _answeredInRound;
    }
    /*
     * @notice 获取最新轮次数据
     * @return _roundId 最新轮次
     * @return _answer 最新价格
     * @return _startedAt 最新更新时间
     * @return _updatedAt 最新更新时间
     * @return _answeredInRound 最新回答轮次
     */
    function latestRoundData()
        external
        view
        returns (uint80 _roundId, int256 _answer, uint256 _startedAt, uint256 _updatedAt, uint80 _answeredInRound)
    {
        _roundId = roundId;
        _answer = price;
        _startedAt = updatedAt;
        _updatedAt = updatedAt;
        _answeredInRound = answeredInRound;
    }
    /*
     * @notice 获取价格小数位数
     * @return _decimals 价格小数位数
     */
    function decimals() external view returns (uint8) {
        return _decimals;
    }
}
