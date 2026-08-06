// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title MockERC721
 * @dev ERC721 Mock 合约，用于测试
 */
contract MockERC721 {
    string public name;
    string public symbol;

    mapping(uint256 => address) private _ownerOf;
    mapping(address => uint256) private _balanceOf;
    mapping(uint256 => address) private _getApproved;
    mapping(address => mapping(address => bool)) private _isApprovedForAll;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }
    /*
     * @notice 获取指定地址的代币余额
     * @param _owner 地址
     * @return 代币余额
     */
    function balanceOf(address _owner) external view returns (uint256) {
        return _balanceOf[_owner];
    }
    /*
     * @notice 获取指定代币的拥有者
     * @param _tokenId 代币ID
     * @return 代币拥有者
     */
    function ownerOf(uint256 _tokenId) external view returns (address) {
        return _ownerOf[_tokenId];
    }
    /*
     * @notice 向指定地址铸造代币
     * @param _to 目标地址
     * @param _tokenId 代币ID
     */
    function mint(address _to, uint256 _tokenId) external {
        _ownerOf[_tokenId] = _to;
        _balanceOf[_to] += 1;
        emit Transfer(address(0), _to, _tokenId);
    }
    /*
     * @notice 授权指定地址代币
     * @param _approved 授权地址
     * @param _tokenId 代币ID
     * @return 是否授权成功
     */
    function approve(address _approved, uint256 _tokenId) external {
        address tokenOwner = _ownerOf[_tokenId];
        require(msg.sender == tokenOwner || _isApprovedForAll[tokenOwner][msg.sender], "Not owner nor approved for all");
        _getApproved[_tokenId] = _approved;
        emit Approval(tokenOwner, _approved, _tokenId);
    }
    /*
     * @notice 获取指定代币的授权地址
     * @param _tokenId 代币ID
     * @return 授权地址
     */
    function getApproved(uint256 _tokenId) external view returns (address) {
        return _getApproved[_tokenId];
    }
    /*
     * @notice 授权指定地址所有代币
     * @param _operator 授权地址
     * @param _approved 是否授权
     * @return 是否授权成功
     */
    function setApprovalForAll(address _operator, bool _approved) external {
        _isApprovedForAll[msg.sender][_operator] = _approved;
        emit ApprovalForAll(msg.sender, _operator, _approved);
    }
    /*
     * @notice 检查指定地址是否授权所有代币
     * @param _owner 地址
     * @param _operator 授权地址
     * @return 是否授权所有代币
     */
    function isApprovedForAll(address _owner, address _operator) external view returns (bool) {
        return _isApprovedForAll[_owner][_operator];
    }
    /*
     * @notice 从指定地址转移代币
     * @param _from 转移源地址
     * @param _to 转移目标地址
     * @param _tokenId 代币ID
     * @return 是否转移成功
     */
    function transferFrom(address _from, address _to, uint256 _tokenId) external {
        require(_ownerOf[_tokenId] == _from, "Not owner");
        require(_to != address(0), "Invalid recipient");
        require(
            msg.sender == _from || _getApproved[_tokenId] == msg.sender || _isApprovedForAll[_from][msg.sender],
            "Not authorized"
        );
        _ownerOf[_tokenId] = _to;
        _balanceOf[_from] -= 1;
        _balanceOf[_to] += 1;
        _getApproved[_tokenId] = address(0);
        emit Transfer(_from, _to, _tokenId);
    }
    /*
     * @notice 从指定地址安全转移代币
     * @param _from 转移源地址
     * @param _to 转移目标地址
     * @param _tokenId 代币ID
     * @return 是否安全转移成功
     */
    function safeTransferFrom(address _from, address _to, uint256 _tokenId) external {
        require(_ownerOf[_tokenId] == _from, "Not owner");
        require(_to != address(0), "Invalid recipient");
        require(
            msg.sender == _from || _getApproved[_tokenId] == msg.sender || _isApprovedForAll[_from][msg.sender],
            "Not authorized"
        );
        _ownerOf[_tokenId] = _to;
        _balanceOf[_from] -= 1;
        _balanceOf[_to] += 1;
        _getApproved[_tokenId] = address(0);
        emit Transfer(_from, _to, _tokenId);

        if (_to.code.length > 0) {
            try NftAuctionUpgradeableReceiver(_to).onERC721Received(msg.sender, _from, _tokenId, bytes("")) returns (bytes4) {
                // success
            } catch {
                // revert
                revert("ERC721: transfer to non ERC721Receiver implementer");
            }
        }
    }
    /*
     * @notice 从指定地址安全转移代币
     * @param _from 转移源地址
     * @param _to 转移目标地址
     * @param _tokenId 代币ID
     * @param _data 附加数据
     * @return 是否安全转移成功
     */
    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes calldata) external {
        this.safeTransferFrom(_from, _to, _tokenId);
    }
}

/**
 * @title NftAuctionUpgradeableReceiver
 * @dev 接收 ERC721 代币的接口，用于测试
 */
interface NftAuctionUpgradeableReceiver {
    /*
     * @notice 接收 ERC721 代币
     * @param operator 转移源地址
     * @param from 转移源地址
     * @param tokenId 代币ID
     * @param data 附加数据
     * @return 接收结果
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}
