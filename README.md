# Boost v2.5.2 (Custom Fork)

基于 [Filecoin 官方 Boost v2.5.2](https://github.com/filecoin-project/boost) 的定制分支，针对大规模存储提供者场景进行了优化。

> 历史：本分支接续 [Brian44913/boost-2.4.7](https://github.com/Brian44913/boost-2.4.7)。boost-2.4.7 仓库已归档不再更新，所有沿用改动已 squash 到本仓库的对应 commit。`openReader` mmap CAR v2 验证（boost-2.4.7 commit 81a7203）+ `--start-epoch-head-offset` 已被上游 v2.5.2 subsume，不再单独维护。

---

## 与原版的改动

### 1. 关闭 GitHub Actions 自动触发

**涉及文件：**
- `.github/workflows/ci.yml`
- `.github/workflows/issue-project.yml`
- `.github/workflows/label-syncer.yml`

**改动说明：**

将 3 个 workflow 的 `on:` 段改为只保留 `workflow_dispatch`（手动触发），原有的 `push` / `pull_request` / `issues` 触发器注释保留（不删除）方便回滚。

**为什么：** 个人 fork 仓库的 CI 噪音大，`issue-project.yml` 依赖上游专有 `secrets.BOOST_BOARD`（fork 没有），label-syncer 同样不适用。手动触发保留 fallback 能力。

**触发方式：** GitHub UI → Actions → CI → "Run workflow"，或 `gh workflow run ci.yml -R Brian44913/boost-2.5.2`。

---

### 2. 跳过 CommP 验证 (`SkipCommPVerify`)

**涉及文件：**
- `node/config/types.go` — 新增 `SkipCommPVerify` 配置项
- `node/config/def.go` — 默认值 `true`
- `storagemarket/provider.go` — Provider Config 新增字段
- `storagemarket/direct_deals_provider.go` — DDPConfig 新增字段 + execDeal 重构
- `node/modules/storageminer.go` — 配置传递
- `node/modules/directdeals.go` — 配置传递
- `storagemarket/deal_execution.go` — 离线订单和在线订单验证逻辑

**改动说明：**

新增 `SkipCommPVerify` 配置开关（默认 `true`），统一控制三处 CommP 验证：

| 场景 | 文件 | 原行为 | 改后 |
|------|------|--------|------|
| 离线订单导入 | `deal_execution.go` `execDealUptoAddPiece()` | 强制 `verifyCommP()` | `SkipCommPVerify=true` 时跳过 |
| 在线订单传输 | `deal_execution.go` `transferAndVerify()` | 强制 `verifyCommP()` | `SkipCommPVerify=true` 时跳过 |
| DDO 直接导入 | `direct_deals_provider.go` `execDeal()` | 计算 CommP + 比对 | `SkipCommPVerify=true` 时跳过计算，按最小 2 的整数次幂 PaddedPieceSize 推算 |

**配置方式（config.toml）：**
```toml
[Dealmaking]
  SkipCommPVerify = true   # 默认已开启
```

**PieceSize 计算（直接导入路径）：**
```go
paddedSize := abi.PaddedPieceSize(128)
for paddedSize.Unpadded() < abi.UnpaddedPieceSize(fstat.Size()) {
    paddedSize <<= 1
}
entry.PieceSize = paddedSize
```

**收益：** 跳过 CommP 计算可显著加速离线订单和 DDO 订单的导入，尤其在批量导入场景下。

---

### 3. 修复 DirectDealsDB.List 翻页 bug（上游遗漏）

**涉及文件：**
- `db/directdeals.go` — `List()` 函数

**问题现象：** Web UI 的 `/direct-deals` 页面，第 1 页有数据，从第 2 页开始翻页无数据且无报错；`/storage-deals` 页面翻页正常。

**根因：** `DirectDealsDB.List()` 中的 cursor 子查询写错了表名：

```go
// 原代码（上游 v2.5.2 仍带此 bug）
where += "CreatedAt <= (SELECT CreatedAt FROM Deals WHERE ID = ?)"

// 修复后
where += "CreatedAt <= (SELECT CreatedAt FROM DirectDeals WHERE ID = ?)"
```

cursor 是 direct deal 的 UUID，但子查询去了 `Deals` 表（普通订单表），找不到记录返回 NULL，导致 `CreatedAt <= NULL` 永远为 false，翻页结果为空。**这是上游 boost 官方代码的 bug，v2.5.2 仍未修。**

---

### 4. 修复 Web UI 大数据量白屏

**涉及文件：**
- `react/src/transform.jsx` — 递归改迭代
- `react/src/gql.jsx` — transformResponseLink 加 try-catch
- `react/src/Deals.jsx` — 空值保护
- `react/src/DirectDeals.jsx` — 空值保护

**问题现象：** 当 deals 数量超过 5 万条后，Storage Deals 页面加载后变成空白，浏览器控制台报错：
```
TypeError: can't access property "deals", b is undefined
```

**根因分析：**

虽然前端查询是分页的（默认 10 条/页），但 `pollInterval: 10000` 每 10 秒重新查询。当 `SELECT count(*) FROM Deals`（50k+ 行）变慢时，Apollo Client 的 poll 触发竞态，导致 `data` 返回 `undefined`，前端直接访问 `data.deals` 崩溃白屏。

此外 `transform.jsx` 中的递归 response 转换在极端场景下有栈溢出风险。

**修复方案（3 层防护）：**

| 层级 | 改动 | 作用 |
|------|------|------|
| 根因修复 | `transform.jsx` 递归改为迭代（显式栈） | 消除栈溢出风险，不受数据量限制 |
| 安全网 | `gql.jsx` transformResponse 加 try-catch | 转换失败时返回原始数据，不中断 Apollo 链路 |
| 崩溃保护 | `Deals.jsx` / `DirectDeals.jsx` 加 `!data \|\| !data.deals` 检查 | `data` 为 undefined 时显示错误提示，不再白屏 |

> 注：v2.5.2 将 React 文件从 `.js` 重命名为 `.jsx` 但保留了原递归 `transformResponse` 实现，本分支重新迭代化。

---

### 5. 发单支持自定义 libp2p 地址（`--libp2p`）

**涉及文件：**
- `cmd/boost/deal_cmd.go`

**改动说明：**

在 `dealFlags` 中新增 `--libp2p` 可选参数，允许覆盖链上查询到的存储提供者完整 libp2p 地址（含 peer ID），直接连接指定节点进行发单。

**适用命令：**
```bash
boost deal --libp2p=/ip4/10.78.36.98/tcp/49413/ws/p2p/12D3KooWNZ1bNn... ...
boost offline-deal --libp2p=/ip4/10.78.36.97/tcp/4949/p2p/12D3KooWRJi4nB... ...
```

**实现方式：**
- 在 `GetAddrInfo` 获取链上地址后、`Connect` 之前，用 `peer.AddrInfoFromString` 解析 multiaddr
- 完整替换 `addrInfo`（包含 peer ID 和地址列表），不再受链上 PeerId 限制

**未指定时：** 完全兼容原版行为，不影响任何现有逻辑。

---

## 编译

filecoin-ffi 沿用上游 submodule 方式，clone 后需要 init：

```bash
git clone git@github.com:Brian44913/boost-2.5.2.git
cd boost-2.5.2
git submodule update --init --recursive
make build
```

## 原版仓库

- 官方仓库：https://github.com/filecoin-project/boost
- 官方文档：https://boost.filecoin.io
- 上一版 fork：https://github.com/Brian44913/boost-2.4.7（已归档）
