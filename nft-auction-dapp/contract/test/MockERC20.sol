// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title MockERC20
 * @dev ERC20 Mock 合约，用于测试
 */
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /*
     * @notice 构造函数
     * @param _name 代币名称
     * @param _symbol 代币符号
     * @param _decimals 代币小数位数
     */
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }
    /*
     * @notice 向指定地址铸造代币
     * @param _to 目标地址
     * @param _amount 铸造数量
     */
    function mint(address _to, uint256 _amount) external {
        balanceOf[_to] += _amount;
        totalSupply += _amount;
        emit Transfer(address(0), _to, _amount);
    }
    /*
     * @notice 授权指定地址代币
     * @param _spender 授权地址
     * @param _amount 授权数量
     * @return 是否授权成功
     */
    function approve(address _spender, uint256 _amount) external returns (bool) {
        allowance[msg.sender][_spender] = _amount;
        emit Approval(msg.sender, _spender, _amount);
        return true;
    }
    /*
     * @notice 转账指定地址代币
     * @param _to 目标地址
     * @param _amount 转账数量
     * @return 是否转账成功
     */
    function transfer(address _to, uint256 _amount) external returns (bool) {
        require(balanceOf[msg.sender] >= _amount, "Insufficient balance");
        balanceOf[msg.sender] -= _amount;
        balanceOf[_to] += _amount;
        emit Transfer(msg.sender, _to, _amount);
        return true;
    }
    /*
     * @notice 从指定地址转账指定地址代币
     * @param _from 转账源地址
     * @param _to 目标地址
     * @param _amount 转账数量
     * @return 是否转账成功
     */
    function transferFrom(address _from, address _to, uint256 _amount) external returns (bool) {
        require(balanceOf[_from] >= _amount, "Insufficient balance");
        require(allowance[_from][msg.sender] >= _amount, "Insufficient allowance");
        balanceOf[_from] -= _amount;
        balanceOf[_to] += _amount;
        allowance[_from][msg.sender] -= _amount;
        emit Transfer(_from, _to, _amount);
        return true;
    }
}
