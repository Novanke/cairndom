# CairnDom

CairnDom 是纯 MoonBit 控制流图分析基础库，提供支配树、支配边界、后支配关系、控制依赖、自然循环、强连通分量、变量活跃性和 SSA 候选位置规划。它可以作为编译器、静态分析器及图工具的公共算法组件。命令行工具直接读取语言无关的图文件，生成可供人工核对或程序消费的 JSON 与 DOT。

例如，图中的两个分支分别定义一个变量，SDK 可根据迭代支配边界找出 SSA 的 phi 候选位置。CLI 则直接指出分支汇合点、循环头、回边来源、不可达节点，以及哪些可达节点没有到达声明出口的路径。

## 运行

使用官方 MoonBit 工具链，最低支持 moonc **0.10.20**。本版验证的精确版本为 **0.10.20+65efd5b93**。纯库支持 Wasm GC 和 JavaScript。文件 CLI 要求 Node.js **22.16+**。

```sh
moon build --target js --release --deny-warn
node _build/js/release/build/cmd/main/main.js analyze examples/branch-loop.json
node _build/js/release/build/cmd/main/main.js analyze examples/branch-loop.json --format dot --out graph.dot
node _build/js/release/build/cmd/main/main.js plan-ssa examples/ssa-branch.json
node _build/js/release/build/cmd/main/main.js plan-ssa examples/ssa-branch.json --out phi-plan.json
node _build/js/release/build/cmd/main/main.js query examples/queries.json
```

样例报告中，`left` 和 `right` 的支配边界都是 `join`，`head` 与 `body` 形成一个以 `head` 为头的自然循环，`dead` 不可达。蓝色虚线 DOT 边是直接支配关系，普通边保留原始控制流。DOT 是图描述文件，可由支持该格式的工具进一步渲染。

`plan-ssa` 的样例中，两个分支定义 `value` 与 `unused`，汇合块仅使用 `value` 和 `parameter`。输出会为 `value` 在 `join` 安排候选，为未使用的 `unused` 删除候选，并将 `parameter` 列入 `entry_values_required`。报告的 `status` 为 `locations_only`，其中同时给出各块活跃集合和按变量分组的候选；不会生成重命名后的指令或可执行程序。该命令只输出 JSON，并复用相同的输入校验与新文件独占发布约定。

不传 `--out` 时结果写 stdout。错误为 stderr 上的 JSON，退出码 2。退出码 0 表示成功生成分析，图中仍可能存在不可达节点、多入口循环或无法到达出口的节点。

标准输出处理写入回调、背压和流错误；写出时接收端已关闭等可观测 I/O 故障返回 2。失败之前可能已写出报告前缀，管道输出不具有 `--out` 新文件发布的原子性。标准错误也无法写入时仍保留退出码 2。

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

SDK 构建或编辑图后，可用 `graph_json_text(graph)` 生成同一 `cairndom.graph.v1` 格式，再交给 `parse_graph` 或文件 CLI。导出前会校验图，保留节点、边和出口的输入顺序；分析报告本身是另一种格式，不应当作原图重新导入。

支配关系仅覆盖入口可达子图。入口自身的直接支配节点为空，不可达节点也为空，应同时检查 `reachable`。

后支配使用虚拟出口，**仅针对入口可达且最终到达声明出口的有限路径**。报告以 `can_reach_exit` 和 `postdominator_is_virtual_exit` 区分无出口路径与虚拟父节点。这种分析不会证明所有执行都终止，分支进入永久循环时尤其需要保留该范围解释。控制依赖采用同一有限出口路径范围。

`control_dependence_witnesses(graph)` 返回造成控制依赖的原始分支边。JSON 报告中的 `control_witnesses` 保留 `controller`、`successor` 和 `dependent`，可区分同一分支的不同出口，也能解释循环的自控制依赖；该信息同样遵守有限出口路径范围。

边级证据上限为 65,536 条。超过上限时 SDK 报错；JSON 报告保留按索引排序的前缀，并将 `control_witnesses_complete` 标为 `false`，节点级控制依赖仍完整。需要完整边级证据的调用方必须检查此标志。这个上限避免密集分支图生成数百万条重复展开记录。

自然循环由“循环头支配回边来源”定义，同一头的回边合并。多入口 SCC 会单独标记，它们可能没有自然循环头。SCC 的 `multiple_entries` 只描述该分量的入口数，完整的嵌套不可约性分类仍属后续工作。

SDK 的 `loop_boundaries(graph)` 为每个自然循环列出进入边、离开边和返回循环头的回边，按端点索引排序，排除不可达前驱。嵌套循环分别计算边界；包含图入口的循环不会凭空添加进入边。没有离开边仅表示图结构，不构成终止性证明。展开总量限制为 65,536 个边记录，超限会报错，避免返回不完整边界。

## SDK

```sh
moon add Novanke/cairndom@0.3.0
```

在调用方 `moon.pkg` 中导入 `"Novanke/cairndom" @dom`。可直接构建 `Graph`，或调用 `parse_graph`。核心入口为 `analyze`，也可单独调用 `dominators`。图边使用节点数组索引。

```moonbit
let result = @dom.analyze(graph)
let required = @dom.dominates(result.forward, entry_index, target_index)
let phi_candidates = @dom.iterated_frontier(result.forward, definition_indices)
```

`iterated_frontier` 可接收调用方提供的 `live_in` 节点做剪枝。该接口计算候选位置，调用方负责变量定义、活跃性和具体 IR。后支配树中的虚拟出口索引为 `graph.nodes.length()`。分析结果拥有输入数组的副本。序列化函数要求结果仍保持 `analyze` 生成的有效结构，编辑图后应再次分析。

公开支配查询会先检查树的完整结构，拒绝父链成环、断链、无效根和损坏的边界集合。结构检查无法证明手工填写的支配边界与原图在数学上相符；编辑图后应重新调用 `analyze` 或 `dominators`。

反复查询同一棵树时，用 `index_dominance(tree)` 一次校验并建立不可变快照：

```moonbit
let index = @dom.index_dominance(result.forward)
let yes = index.dominates(ancestor_index, target_index)
let common = index.nearest_common([left_index, right_index])
```

索引按 DFS 区间判断支配，单次为 O(1)；公共支配节点使用倍增祖先表，k 个操作数为 O(k log n)。索引不暴露内部数组，原树之后的修改不会影响已有答案；图变化后需重新分析和建立索引。这是算法复杂度说明，不是运行时间承诺。空集合或含不可达节点的最近公共查询返回 `None`，越界索引始终报错。后支配索引可返回虚拟出口索引。

文件批量查询使用 `cairndom.queries.v1`：包含 `graph`、`tree`（`forward` 或 `post`）和 `queries`。每项为 `{"operation":"dominates","ancestor":"entry","node":"join"}` 或 `{"operation":"nearest_common","nodes":["left","right"]}`。`query` 命令只建立一次索引；样例中两个分支的最近公共支配节点是 `entry`，`join` 和 `exit` 的是 `join`。JSON 入口也可直接通过 SDK 的 `query_json_text` 调用。

查询最多 4,096 项、合计 16,384 个操作数，输入 2 MiB，输出 16 MiB。操作数使用原图 ID，支持重复节点和空列表；不接受虚拟出口作为输入 ID。`found: false` 表示没有结果，`found: true` 且 `virtual_exit: true` 表示结果是后支配虚拟出口，二者不能混同。后支配继续采用前述有限出口路径范围。

`FlowProgram` 为每个块提供变量定义和使用集合，`liveness(program)` 返回按变量索引排序的 `live_in` / `live_out`。这里的 `uses` 表示块内该变量首次定义之前的使用，同一变量可同时出现在使用和定义中。活跃性覆盖全部入口可达路径，包括永久循环；不可达块的结果为空，声明出口不会裁掉这些数据流路径。

最多允许 512 个变量和 16,384 个定义/使用关联。变量 ID 与节点 ID 使用相同语法；定义、使用的行数必须等于图节点数，每行的变量索引需合法且不重复。返回集合独立持有数组，编辑输入不会改变已有结果。

程序事实的文件格式为 `cairndom.program.v1`，通过 `parse_program` / `program_json_text` 导入导出：

```json
{"schema":"cairndom.program.v1",
 "graph":{"schema":"cairndom.graph.v1","nodes":["entry","exit"],"entry":"entry","exits":["exit"],"edges":[["entry","exit"]]},
 "variables":["value"],
 "blocks":[{"node":"entry","defines":["value"],"uses":[]},{"node":"exit","defines":[],"uses":["value"]}]}
```

`blocks` 中未列出的节点表示空定义/使用集合，重复块或未知 ID 会报错。每个列出的块必须包含 `node`、`defines` 和 `uses`。导出按图节点和声明变量顺序排列事实，不修改调用方数组；导入与导出都限制为 2 MiB，以保持文件可重新读取。

`plan_ssa(program)` 将活跃性与迭代支配边界连接起来，对每个变量返回定义块、活跃入口块和剪枝后的 `phi_nodes`。未使用的变量不产生候选，不可达块的事实不参与规划。`SsaPlan` 保留输入程序的完整副本。

每项中的 `requires_entry_value` 表示变量在入口块的本地定义之前就需要值。调用方应提供参数或初始值，或按源语言规则报告缺少初始化。该工具生成候选位置，不推断语句顺序、不重命名变量、不改写 IR，也不保证一个程序已经转换为可执行的 SSA。

完整示例会执行断言并输出分析与 phi 候选点。

```sh
moon run examples/sdk --target wasm-gc --release --deny-warn
moon run examples/sdk --target js --release --deny-warn
moon run examples/ssa_sdk --target wasm-gc --release --deny-warn
moon run examples/ssa_sdk --target js --release --deny-warn
moon run examples/query_sdk --target wasm-gc --release --deny-warn
moon run examples/query_sdk --target js --release --deny-warn
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
python scripts/verify_ssa_cli.py
python scripts/verify_queries.py
python scripts/verify_stdout.py
```

独立核对方法、复现结果及后续方向见 [验证记录](docs/verification.md)。CI 在 Windows/Linux 上执行双后端检查、测试、示例和真实文件核对。

独立的节点删除、集合方程和用例生成位于 MoonBit 的 `verification/reference`，不调用生产分析算法生成预期答案。Python 只负责真实文件、进程、管道及故障注入适配；三个文件验证入口共享同一输出契约。`moon build --target js --release` 同时构建参考命令，验证脚本也接受 `--oracle` 指定它的位置。生产库、测试、独立验证器与主机适配的语言统计分别记录在 [语言构成说明](docs/languages.md)。

## 算法与来源

采用 Cooper–Harvey–Kennedy 支配算法、迭代 DFS、反向图与虚拟出口、Kosaraju SCC 和经典自然循环构造。实现依据算法定义独立编写，算法本身有既有研究基础。运行时只依赖 MoonBit 标准库。

该项目与作者已有的 JSON 迁移、小册子拼版、BitTorrent 元数据和套件备料项目用途及代码独立。MoonBit 生态已有通用图及编译器内部的部分支配分析实现，本项目的交付重点是统一的语言无关 CFG API、出口范围明确的分析和可直接运行的离线工具。公开检索无法覆盖全部未公开参赛资料。

项目使用 AI 辅助实现及技术文档编写，采用 Apache-2.0 许可证。算法参考及生态对照见 [来源说明](THIRD_PARTY.md)。
