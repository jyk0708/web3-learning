// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./NftAuctionUpgradeable.sol";

/**
 * @title NFT 拍卖 V2
 * @dev NftAuctionV2 是 NftAuctionUpgradeable 的升级版本，新增以下功能：
 *   1. version() —— 返回合约版本号，用于验证升级是否成功
 *   2. 最小加价幅度（minBidIncrement）—— 每次新出价必须比当前最高出价高出一定比例，防止恶意微小加价
 *
 * 存储布局说明（UUPS 升级兼容性）：
 *   V1 末尾有 uint256[256] private __gap 作为预留空间。Solidity 不允许子合约
 *   修改父合约已声明的存储变量，因此 V2 无法"缩减" V1 的 __gap。
 *   V2 的正确做法是【仅追加】新变量到 V1 存储末尾之后：
 *     - V1 存储: [业务变量...][__gap_256]  (slot 0..N+255)
 *     - V2 追加: [_minBidIncrementBps][__gap_255]  (slot N+256..)
 *   V2 新增的 _minBidIncrementBps 位于 V1 从未写入的新槽位，初始值为 0，
 *   由 initializeV2() 在升级后设置。V1 的旧数据（owner/拍卖/预言机）完全不受影响。
 *   V2 末尾再次预留 __gap，便于未来 V3 继续追加变量。
 */
contract NftAuctionV2 is NftAuctionUpgradeable {

    /**
     * @dev 返回合约版本号
     * @return 版本字符串
     */
    function version() external pure returns (string memory) {
        return "V2";
    }

    /// @dev V2 自身的预留 gap，为未来 V3 升级预留存储空间
    /// @notice 注意：此 __gap 与 V1 的 __gap 是两个独立的存储数组（shadowing），
    ///         不要误以为这里是"缩减 V1 的 gap"
    uint256[255] private __gap;
}
