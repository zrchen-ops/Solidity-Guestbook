# 链上留言板 · On-Chain Guestbook

一个功能完整的 Solidity 智能合约项目。把留言永久写入链上，任何人可读，作者可编辑、删除，支持点赞与分页查询。

这是从零开发的第一个 Web3 项目，目标是**用一个小项目覆盖 Solidity 的核心语法与常见的工程实践**——不是玩具 demo，而是可以直接讲清楚设计取舍的练手项目。

## 功能特性

| 功能 | 说明 |
| --- | --- |
| 发布留言 | 内容非空、最长 280 字，自增 ID |
| 编辑留言 | 仅作者本人可修改 |
| 删除留言 | 仅作者本人可删除，swap-and-pop O(1) 移除 |
| 点赞 / 取消点赞 | 嵌套 mapping 实现"一人一赞"，防重复 |
| 分页查询 | 按 offset / limit 拉取留言列表 |
| 按作者查询 | 拉取某个地址的全部留言 |
| 事件日志 | 每个写操作都发 event，前端可监听 |

## 技术栈

- **Solidity 0.8.20** + Foundry 1.9.0（Forge / Anvil / Cast）
- 18 个单元测试，覆盖全部功能与边界条件
- 全程本地测试链 + 假币，无真实资产风险

## 设计亮点

1. **自增 ID + mapping 存储，而非数组下标当 ID**：删除留言后其他留言的 ID 保持稳定，也不会复用已删 ID——真实项目该有的做法。
2. **swap-and-pop 删除**：从动态数组删除元素时用末尾元素填补空位再 pop，避免 O(n) 的元素搬移。
3. **嵌套 mapping 实现唯一性约束**：`mapping(uint256 => mapping(address => bool)) hasLiked` 在链上天然实现"一人一赞"，点赞和取消都校验状态。
4. **自定义错误（Custom Errors）**：用 `error` 代替 `require` 字符串，更省 gas，且能携带参数（如 `ContentTooLong(280)`）。
5. **权限控制在合约层**：编辑/删除都校验 `msg.sender == author`，链上无法伪造身份。

## 快速开始

### 1. 安装 Foundry

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### 2. 编译与测试

```bash
forge build
forge test -vv
```

预期：`18 passed; 0 failed`

### 3. 启动本地链并部署

终端 1 启动本地节点：

```bash
anvil
```

终端 2 部署（使用 anvil 自带的测试私钥）：

```bash
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url http://127.0.0.1:8545 --broadcast
```

记下输出里的合约地址 `Guestbook deployed at: 0x...`。

### 4. 交互示例

```bash
RPC=http://127.0.0.1:8545
ADDR=<你的合约地址>
KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# 发布留言（写操作，发交易）
cast send $ADDR "postMessage(string)" "Hello Web3!" \
  --rpc-url $RPC --private-key $KEY

# 点赞（用另一个 anvil 测试账号）
cast send $ADDR "likeMessage(uint256)" 0 \
  --rpc-url $RPC \
  --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d

# 查询（读操作，免费）
cast call $ADDR "totalMessages()(uint256)" --rpc-url $RPC
cast call $ADDR "getMessage(uint256)((uint256,address,string,uint256,uint256))" 0 --rpc-url $RPC
cast call $ADDR "getLikes(uint256)(uint256)" 0 --rpc-url $RPC
```

## 项目结构

```
.
├── src/Guestbook.sol            # 合约：数据结构、事件、错误、读写函数
├── test/Guestbook.t.sol         # 18 个单元测试
├── script/Deploy.s.sol          # 部署脚本
├── foundry.toml                 # Foundry 配置
└── README.md
```

## 可以扩展的方向

- 用 ethers.js / viem 写前端，监听 event 实时刷新留言列表
- 加入打赏功能（`payable` + 提现，练习资金安全与重入攻击防护）
- 演进成链上抢券：库存原子扣减、一人一单、防重——与经典秒杀场景一一对应

## License

MIT
