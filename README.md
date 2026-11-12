# CairnDom

CairnDom 是纯 MoonBit 控制流图分析基础库，提供支配树、支配边界、后支配关系、控制依赖、自然循环和强连通分量。它可以作为编译器、静态分析器及图工具的公共算法组件。命令行工具直接读取语言无关的图文件，生成可供人工核对或程序消费的 JSON 与 DOT。

例如，图中的两个分支分别定义一个变量，SDK 可根据迭代支配边界找出 SSA 的 phi 候选位置。CLI 则直接指出分支汇合点、循环头、回边来源、不可达节点，以及哪些可达节点没有到达声明出口的路径。

## 运行

使用官方 MoonBit 工具链，最低支持 moonc **0.10.20**。本版验证的精确版本为 **0.10.20+65efd5b93**。纯库支持 Wasm GC 和 JavaScript。文件 CLI 要求 Node.js **22.16+**。

```sh
moon build --target js --release --deny-warn
node _build/js/release/build/cmd/main/main.js analyze examples/branch-loop.json
node _build/js/release/build/cmd/main/main.js analyze examples/branch-loop.json --format dot --out graph.dot
```

样例报告中，`left` 和 `right` 的支配边界都是 `join`，`head` 与 `body` 形成一个以 `head` 为头的自然循环，`dead` 不可达。蓝色虚线 DOT 边是直接支配关系，普通边保留原始控制流。DOT 是图描述文件，可由支持该格式的工具进一步渲染。

不传 `--out` 时结果写 stdout。错误为 stderr 上的 JSON，退出码 2。退出码 0 表示成功生成分析，图中仍可能存在不可达节点、多入口循环或无法到达出口的节点。

`--out` 的目标必须是新文件，父目录须已存在且支持硬链接。完整报告先写入同目录暂存区并同步，再独占发布，拒绝覆盖输入及已有文件。中断或清理失败可能留下 `.cairndom-*` 暂存目录。文件操作面向可信本地目录，时间与身份复查提供顺序观测。

## 输入与分析语义

```json
{
  "schema": "cairndom.graph.v1",
  "nodes": ["entry", "left", "right", "join", "exit"],
  "entry": "entry",
  "exits": ["exit"],
  "edges": [["entry","left"], ["entry","right"], ["left","join"], ["right","join"], ["join","exit"]]
}
```

节点 ID 大小写敏感，长 1 到 64，只接受 ASCII 字母、数字、下划线、点和连字符。入口必须存在，出口必须是没有出边的节点。支持空出口列表、自循环、一般有向环和不可约图。重复节点、重复边、未知引用、未知 JSON 字段及重复键会报错。

最多支持 512 个节点、8,192 条边。CLI 输入为普通 UTF-8 文件，最多 2 MiB，输出最多 16 MiB。符号链接路径和特殊文件会被拒绝。节点与集合按输入节点索引排序，固定图的输出确定。

支配关系仅覆盖入口可达子图。入口自身的直接支配节点为空，不可达节点也为空，应同时检查 `reachable`。

后支配使用虚拟出口，**仅针对入口可达且最终到达声明出口的有限路径**。报告以 `can_reach_exit` 和 `postdominator_is_virtual_exit` 区分无出口路径与虚拟父节点。这种分析不会证明所有执行都终止，分支进入永久循环时尤其需要保留该范围解释。控制依赖采用同一有限出口路径范围。

自然循环由“循环头支配回边来源”定义，同一头的回边合并。多入口 SCC 会单独标记，它们可能没有自然循环头。SCC 的 `multiple_entries` 只描述该分量的入口数，完整的嵌套不可约性分类仍属后续工作。

## SDK

```sh
moon add Novanke/cairndom@0.1.0
```

在调用方 `moon.pkg` 中导入 `"Novanke/cairndom" @dom`。可直接构建 `Graph`，或调用 `parse_graph`。核心入口为 `analyze`，也可单独调用 `dominators`。图边使用节点数组索引。

```moonbit
let result = @dom.analyze(graph)
let required = @dom.dominates(result.forward, entry_index, target_index)
let phi_candidates = @dom.iterated_frontier(result.forward, definition_indices)
```

`iterated_frontier` 可接收调用方提供的 `live_in` 节点做剪枝。该接口计算候选位置，调用方负责变量定义、活跃性和具体 IR。后支配树中的虚拟出口索引为 `graph.nodes.length()`。分析结果拥有输入数组的副本。序列化函数要求结果仍保持 `analyze` 生成的有效结构，编辑图后应再次分析。

公开支配查询会先检查树的完整结构，拒绝父链成环、断链、无效根和损坏的边界集合。结构检查无法证明手工填写的支配边界与原图在数学上相符；编辑图后应重新调用 `analyze` 或 `dominators`。

完整示例会执行断言并输出分析与 phi 候选点。

```sh
moon run examples/sdk --target wasm-gc --release --deny-warn
moon run examples/sdk --target js --release --deny-warn
```

## 验证与维护

```sh
moon fmt --check
moon check --target wasm-gc --deny-warn
moon check --target js --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon build --target js --release --deny-warn
python scripts/verify_cli.py
```

独立核对方法、复现结果及后续方向见 [验证记录](docs/verification.md)。CI 在 Windows/Linux 上执行双后端检查、测试、示例和真实文件核对。

## 算法与来源

采用 Cooper–Harvey–Kennedy 支配算法、迭代 DFS、反向图与虚拟出口、Kosaraju SCC 和经典自然循环构造。实现依据算法定义独立编写，算法本身有既有研究基础。运行时只依赖 MoonBit 标准库。

该项目与作者已有的 JSON 迁移、小册子拼版、BitTorrent 元数据和套件备料项目用途及代码独立。MoonBit 生态已有通用图及编译器内部的部分支配分析实现，本项目的交付重点是统一的语言无关 CFG API、出口范围明确的分析和可直接运行的离线工具。公开检索无法覆盖全部未公开参赛资料。

项目使用 AI 辅助实现及技术文档编写，采用 Apache-2.0 许可证。算法参考及生态对照见 [来源说明](THIRD_PARTY.md)。
