// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title 链上留言板 OnChain Guestbook
/// @notice 功能完整的链上留言板：发布、编辑、删除、点赞、分页查询、按作者查询
/// @dev 面向学习的完整项目，覆盖 Solidity 核心语法与常见工程实践
contract Guestbook {

    // ========== 1. 数据结构 ==========

    struct Message {
        uint256 id;          // 自增 ID，删除后不复用
        address author;      // 作者钱包地址
        string content;      // 留言内容
        uint256 timestamp;   // 发布时间（区块时间戳）
        uint256 likes;       // 点赞数
    }

    // 自增 ID 生成器：删除不影响其他留言的 ID
    uint256 private nextId;

    // id => Message，用 mapping 按 ID 直接定位
    mapping(uint256 => Message) private messages;

    // 存所有有效留言的 ID，用于分页遍历（删除时用 swap-and-pop 维护）
    uint256[] private activeIds;

    // author => 该作者的留言 ID 列表
    mapping(address => uint256[]) private authorIds;

    // author => 留言数量
    mapping(address => uint256) public messageCount;

    // messageId => (liker => 是否已点赞)，嵌套 mapping 实现"一人一赞"
    mapping(uint256 => mapping(address => bool)) public hasLiked;

    // ========== 2. 事件 ==========

    event MessagePosted(address indexed author, uint256 indexed id, string content, uint256 timestamp);
    event MessageUpdated(address indexed author, uint256 indexed id, string newContent);
    event MessageDeleted(address indexed author, uint256 indexed id);
    event MessageLiked(address indexed liker, uint256 indexed id, uint256 totalLikes);
    event MessageUnliked(address indexed liker, uint256 indexed id, uint256 totalLikes);

    // ========== 3. 自定义错误（比 require 字符串更省 gas）==========

    error EmptyContent();
    error ContentTooLong(uint256 max);
    error MessageNotFound(uint256 id);
    error NotAuthor();
    error AlreadyLiked();
    error NotLiked();
    error InvalidPage(uint256 offset, uint256 limit);

    uint256 public constant MAX_CONTENT_LENGTH = 280;

    // ========== 4. 写函数（改状态，发交易，付 gas）==========

    /// @notice 发布一条留言
    function postMessage(string calldata content) external returns (uint256 id) {
        if (bytes(content).length == 0) revert EmptyContent();
        if (bytes(content).length > MAX_CONTENT_LENGTH) revert ContentTooLong(MAX_CONTENT_LENGTH);

        id = nextId++;
        messages[id] = Message({
            id: id,
            author: msg.sender,
            content: content,
            timestamp: block.timestamp,
            likes: 0
        });
        activeIds.push(id);
        authorIds[msg.sender].push(id);
        messageCount[msg.sender] += 1;

        emit MessagePosted(msg.sender, id, content, block.timestamp);
    }

    /// @notice 编辑自己的留言（权限控制：只有作者能改）
    function updateMessage(uint256 id, string calldata newContent) external {
        if (bytes(newContent).length == 0) revert EmptyContent();
        if (bytes(newContent).length > MAX_CONTENT_LENGTH) revert ContentTooLong(MAX_CONTENT_LENGTH);

        Message storage m = _requireMessage(id);
        if (m.author != msg.sender) revert NotAuthor();

        m.content = newContent;
        emit MessageUpdated(msg.sender, id, newContent);
    }

    /// @notice 删除自己的留言
    /// @dev swap-and-pop：把数组最后一个 ID 挪到被删位置再 pop，O(1) 删除
    function deleteMessage(uint256 id) external {
        Message storage m = _requireMessage(id);
        if (m.author != msg.sender) revert NotAuthor();

        // 从 activeIds 中移除（swap-and-pop）
        _removeId(activeIds, id);
        // 从作者的 ID 列表中移除
        _removeId(authorIds[msg.sender], id);

        delete messages[id];
        messageCount[msg.sender] -= 1;

        emit MessageDeleted(msg.sender, id);
    }

    /// @notice 点赞（一人一赞，不能重复）
    function likeMessage(uint256 id) external {
        _requireMessage(id);
        if (hasLiked[id][msg.sender]) revert AlreadyLiked();

        hasLiked[id][msg.sender] = true;
        messages[id].likes += 1;
        emit MessageLiked(msg.sender, id, messages[id].likes);
    }

    /// @notice 取消点赞
    function unlikeMessage(uint256 id) external {
        _requireMessage(id);
        if (!hasLiked[id][msg.sender]) revert NotLiked();

        hasLiked[id][msg.sender] = false;
        messages[id].likes -= 1;
        emit MessageUnliked(msg.sender, id, messages[id].likes);
    }

    // ========== 5. 读函数（view，免费调用）==========

    /// @notice 按 ID 读一条留言
    function getMessage(uint256 id) external view returns (Message memory) {
        return _requireMessage(id);
    }

    /// @notice 分页查询所有留言，offset 起始位置，limit 条数
    function getMessages(uint256 offset, uint256 limit) external view returns (Message[] memory result) {
        if (limit == 0) revert InvalidPage(offset, limit);
        if (offset >= activeIds.length) return new Message[](0);

        uint256 end = offset + limit;
        if (end > activeIds.length) end = activeIds.length;

        result = new Message[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = messages[activeIds[i]];
        }
    }

    /// @notice 查询某个作者的所有留言
    function getMessagesByAuthor(address author) external view returns (Message[] memory result) {
        uint256[] storage ids = authorIds[author];
        result = new Message[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            result[i] = messages[ids[i]];
        }
    }

    /// @notice 当前有效留言总数
    function totalMessages() external view returns (uint256) {
        return activeIds.length;
    }

    /// @notice 某条留言的点赞数
    function getLikes(uint256 id) external view returns (uint256) {
        return _requireMessage(id).likes;
    }

    // ========== 6. 内部辅助函数 ==========

    /// @dev 校验留言存在，否则回滚
    function _requireMessage(uint256 id) internal view returns (Message storage) {
        Message storage m = messages[id];
        if (m.author == address(0)) revert MessageNotFound(id);
        return m;
    }

    /// @dev 从 uint256 数组中删除某个 ID（swap-and-pop）
    function _removeId(uint256[] storage arr, uint256 id) internal {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == id) {
                arr[i] = arr[arr.length - 1];
                arr.pop();
                return;
            }
        }
    }
}
