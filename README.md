# CairnDom

CairnDom 是纯 MoonBit 控制流图分析基础库，提供支配树、支配边界、后支配关系、控制依赖、自然循环、强连通分量、变量活跃性、按使用点的值来源解释和 SSA 候选位置规划。它可以作为编译器、静态分析器及图工具的公共算法组件。命令行工具直接读取语言无关的图文件，生成可供人工核对或程序消费的 JSON 与 DOT。

例如，图中的两个分支分别定义一个变量，SDK 可根据迭代支配边界找出 SSA 的 phi 候选位置。CLI 则直接指出分支汇合点、循环头、回边来源、不可达节点，以及哪些可达节点没有到达声明出口的路径。

## 运行

使用官方 MoonBit 工具链，最低支持 moonc **0.10.20**。本版验证的精确版本为 **0.10.20+65efd5b93**。纯库支持 Wasm GC 和 JavaScript。文件 CLI 要求 Node.js **22.16+**。

```sh
moon build --target js --release --deny-warn
node _build/js/release/build/cmd/main/main.js analyze examples/branch-loop.json
node _build/js/release/build/cmd/main/main.js analyze examples/branch-loop.json --format json-summary
node _build/js/release/build/cmd/main/main.js analyze examples/branch-loop.json --format dot --out graph.dot
node _build/js/release/build/cmd/main/main.js control-witness examples/branch-loop.json --controller choose --successor left
node _build/js/release/build/cmd/main/main.js plan-ssa examples/ssa-branch.json
node _build/js/release/build/cmd/main/main.js plan-ssa examples/ssa-branch.json --out phi-plan.json
node _build/js/release/build/cmd/main/main.js query examples/queries.json
node _build/js/release/build/cmd/main/main.js trace-values examples/value-origins.json
node _build/js/release/build/cmd/main/main.js trace-values examples/value-origins.json --out value-origins.json
node _build/js/release/build/cmd/main/main.js trace-use examples/value-origins.json --node join --variable value
node _build/js/release/build/cmd/main/main.js inspect-stages .
```

样例报告中，`left` 和 `right` 的支配边界都是 `join`，`head` 与 `body` 形成一个以 `head` 为头的自然循环，`dead` 不可达。蓝色虚线 DOT 边是直接支配关系，普通边保留原始控制流。DOT 是图描述文件，可由支持该格式的工具进一步渲染。

只需要渲染图时，`analyze --format dot` 和 SDK 的 `graph_dot(graph)` 都只计算入口可达性和直接支配关系。已有完整分析结果时，可继续用 `analysis_dot(result)` 或快照的 `dot_text()` 导出同样的 DOT。

`plan-ssa` 的样例中，两个分支定义 `value` 与 `unused`，汇合块仅使用 `value` 和 `parameter`。输出会为 `value` 在 `join` 安排候选，为未使用的 `unused` 删除候选，并将 `parameter` 列入 `entry_values_required`。报告的 `status` 为 `locations_only`，其中同时给出各块活跃集合和按变量分组的候选；不会生成重命名后的指令或可执行程序。该命令只输出 JSON，并复用相同的输入校验与新文件独占发布约定。

`trace-values` 读取同一 `cairndom.program.v1` 格式，解释每个可达使用点的可能来源。新样例中只有 `left` 分支定义 `value`，因此 `join` 的使用既可能来自 `left`，也可能需要原始入口值；`parameter` 需要调用方提供入口值。`join` 随后定义 `value`，所以 `tail` 的使用只来自 `join`。`dead` 被列入不可达块，不参与来源。这可以帮助分析器定位需要参数或初值的具体使用块。

不传 `--out` 时结果写 stdout。错误为 stderr 上的 JSON，退出码 2。退出码 0 表示成功生成分析，图中仍可能存在不可达节点、多入口循环或无法到达出口的节点。

标准输出处理写入回调、背压和流错误；写出时接收端已关闭等可观测 I/O 故障返回 2。失败之前可能已写出报告前缀，管道输出不具有 `--out` 新文件发布的原子性。标准错误也无法写入时仍保留退出码 2。

`--out` 的目标必须是新文件，父目录须已存在且支持硬链接。完整报告先写入同目录暂存区并同步，再独占发布，拒绝覆盖输入及已有文件。中断或清理失败可能留下 `.cairndom-*` 暂存目录。文件操作面向可信本地目录。POSIX 读取输入文件时，打开前后的路径和文件描述符必须有一致的设备号、inode、大小及修改时间等身份信息。Windows 的路径与句柄可能报告不同口径的设备号，描述符比较沿用兼容处理，路径仍检查实际设备号。

在支持目录同步的本地文件系统上，可给分析命令的 `--out` 加上 `--durable`。例如在 Linux 上运行以下命令。

```sh
node _build/js/release/build/cmd/main/main.js analyze examples/branch-loop.json --out graph-durable.json --durable
```

分析报告仍按原格式写入新文件。进入文件写出阶段后，stdout 返回一份 `cairndom.durable-output.v1` JSON 状态，`output` 是目标绝对路径。参数、输入和分析错误沿用 stderr 的原有诊断。只用 `--out` 时仍沿用原有文件输出行为。

- `published` 表示独占发布已成功。即使后续操作失败，已发布的文件也会保留。
- `directory_synced` 表示发布后，系统已确认同步同一个目标父目录。同步在尝试清理暂存后执行，清理失败时也会尝试同步。
- `stage_created` 和 `stage_cleaned` 分别说明本次是否创建及成功移除自己的暂存目录。创建过时 `stage_path` 记录其绝对路径，否则为 `null`。
- `publication_error`、`sync_error`、`cleanup_error` 分别记录对应阶段的错误，无错误时为 `null`。发布、同步和清理都成功且三个错误字段均为空时退出码为 0，其余写出状态返回 2。

Windows 的 Node.js CLI 会在创建暂存前拒绝该模式。其他平台须能打开并同步目标父目录，实际同步能力取决于本地文件系统和设备。收到退出码 2 时可先检查 `published`，它可能已经为 `true`。持久化状态记录的是文件系统调用结果，适用于可信本地目录。

报告写入中断后，可运行 `inspect-stages DIRECTORY` 检查原输出文件的父目录。命令仅检查该目录的直接子项，最多扫描 4,096 项，识别名称为 `.cairndom-` 加六位 ASCII 字母或数字的候选，按名称排序，将 `cairndom.stage-inspection.v1` JSON 写到 stdout。以短横线开头的目录名可以写作 `inspect-stages -- DIRECTORY`。

- `empty` 表示空目录，`data_only` 表示只有一个链接数为一的普通 `data` 文件，`data_with_other_links` 表示该文件还有其他硬链接。这三种状态的 `possible_residue` 为 `true`。
- 候选若不是目录、含有额外或异常内容、是符号链接、在扫描中变化或无法读取，分别报告 `not_directory`、`unexpected_contents`、`symbolic_link`、`changed` 或 `unreadable`。符号链接形式的扫描目录或祖先路径会报错。

扫描只读取目录项和文件元数据。报告中的 `ownership` 为 `unverified`，`activity` 为 `unknown`。额外硬链接仅说明文件还有其他目录项，文件是否已经发布需要另行核对。这是面向可信本地目录的顺序观测，供人工排查中断残留。

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

图解析会直接返回本次构造的数组，程序和批量查询也复用内嵌图的解析结果。公开接口仍会检查调用方传入的可变图。同步只读查询直接读取已校验的输入；分析、SSA 和全量值来源结果会独立保存需要持有的图与事实数组。

支配关系仅覆盖入口可达子图。入口自身的直接支配节点为空，不可达节点也为空，应同时检查 `reachable`。

后支配使用虚拟出口，**仅针对入口可达且最终到达声明出口的有限路径**。报告以 `can_reach_exit` 和 `postdominator_is_virtual_exit` 区分无出口路径与虚拟父节点。这种分析不会证明所有执行都终止，分支进入永久循环时尤其需要保留该范围解释。控制依赖采用同一有限出口路径范围。

`control_dependence_witnesses(graph)` 返回造成控制依赖的原始分支边。JSON 报告中的 `control_witnesses` 保留 `controller`、`successor` 和 `dependent`，可区分同一分支的不同出口，也能解释循环的自控制依赖；该信息同样遵守有限出口路径范围。SDK 的独立查询只计算入口可达性和直接后支配关系，再生成证据。

边级证据上限为 65,536 条。超过上限时 SDK 报错；JSON 报告保留按索引排序的前缀，并将 `control_witnesses_complete` 标为 `false`，节点级控制依赖仍完整。需要完整边级证据的调用方必须检查此标志。这个上限避免密集分支图生成数百万条重复展开记录。

只查一条原始有向边时，可用 `control_dependence_witnesses_at(graph, controller_index, successor_index)` 或上面的 `control-witness` 命令。即使全量证据被截断或超过输出预算，单条边仍可返回完整结果。CLI 的 `cairndom.control-witness.v1` 报告包含两端节点 ID 和按节点索引排序的 `dependents`，示例中 `choose → left` 的结果为 `["left"]`。合法边没有有限出口范围内的证据时返回空数组。未知 ID、越界索引或不存在的有向边会报错。以 `--` 开头的 ID 可用 `--controller=NODE_ID` 或 `--successor=NODE_ID` 传入。命令支持 `--out` 和可选的 `--durable`。

如果只需要节点级分析，使用 `analyze --format json-summary` 或快照的 `summary_json_text()`。摘要使用独立格式 `cairndom.analysis-summary.v1`，保留可达性、支配关系、控制依赖、自然循环和强连通分量，跳过边级证据的计算与输出。密集图的完整报告若因边级证据过大而无法导出，摘要仍可能适用。两种 JSON 输出都受各自入口的 16 MiB 上限约束。

摘要按记录生成，在追加每段文本前核对剩余字节。SDK 可用 `saved.summary_json_text_limit(bytes)` 将正文预算设为 0 到 16 MiB，刚好达到预算时仍可导出。CLI 把末尾换行计入 16 MiB，仅在整份报告符合预算后才写入标准输出或新文件。

自然循环由“循环头支配回边来源”定义，同一头的回边合并。多入口 SCC 会单独标记，它们可能没有自然循环头。SCC 的 `multiple_entries` 只描述该分量的入口数，完整的嵌套不可约性分类仍属后续工作。

SDK 的 `loop_boundaries(graph)` 为每个自然循环列出进入边、离开边和返回循环头的回边，按端点索引排序，排除不可达前驱。嵌套循环分别计算边界；包含图入口的循环不会凭空添加进入边。没有离开边仅表示图结构，不构成终止性证明。展开总量限制为 65,536 个边记录，超限会报错，避免返回不完整边界。独立查询只计算入口可达性、直接支配关系和自然循环成员及回边。

只查一个循环时，SDK 可用 `loop_boundary_at(graph, header_index)`。它只展开指定循环，边的内容和排序与全量对应项一致。即使全量超过 65,536 条边记录，单个循环仍可完整返回。合法但不可达的节点或普通节点返回 `None`，越界索引、无效图会报错。

文件 CLI 使用节点 ID 指定循环头。示例里的 `head` 会返回进边 `join → head`、离开边 `head → exit` 和回边 `body → head`。

```sh
node _build/js/release/build/cmd/main/main.js loop-boundary examples/branch-loop.json --header head
```

输出为 `cairndom.loop-boundary.v1`。`entering_edges`、`leaving_edges` 和 `back_edges` 中的每条边都是两个节点 ID 的数组。已知节点没有可达自然循环时，`found` 为 `false`，三个边列表为空；未知 ID 会报错。以 `--` 开头的 ID 可用 `--header=NODE_ID` 传入。命令支持 `--out` 和可选的 `--durable`。

## SDK

```sh
moon add Novanke/cairndom@0.8.13
```

在调用方 `moon.pkg` 中导入 `"Novanke/cairndom" @dom`。可直接构建 `Graph`，或调用 `parse_graph`。核心入口为 `analyze`，也可单独调用 `dominators` 或 `postdominators`。图边使用节点数组索引。只需要自然循环边界或控制依赖证据时，可以直接调用相应查询，结果沿用完整分析的图校验和排序规则。

```moonbit
let boundaries = @dom.loop_boundaries(graph)
let one_boundary = @dom.loop_boundary_at(graph, header_index)
let witnesses = @dom.control_dependence_witnesses(graph)
let edge_witnesses = @dom.control_dependence_witnesses_at(graph, controller_index, successor_index)
```

```moonbit
let result = @dom.analyze(graph)
let required = @dom.dominates(result.forward, entry_index, target_index)
let phi_candidates = @dom.iterated_frontier(result.forward, definition_indices)
```

`iterated_frontier` 可接收调用方提供的 `live_in` 节点做剪枝。该接口计算候选位置，调用方负责变量定义、活跃性和具体 IR。后支配树中的虚拟出口索引为 `graph.nodes.length()`。分析结果拥有输入数组的副本。序列化函数要求结果仍保持 `analyze` 生成的有效结构，编辑图后应再次分析。

需要先查看完整分析、再导出同一份 JSON/DOT 的编辑器或 SDK 程序，可以保存不可变快照：

```moonbit
let saved = @dom.prepare_analysis(graph)
let inspected = saved.analysis()
let json = saved.json_text()
let dot = saved.dot_text()
```

`prepare_analysis` 只调用一次完整 `analyze`。`analysis()` 深层复制图、两棵支配树及边界集合、循环、强连通分量和控制依赖；每次读取都可独立修改。修改原始图或检查副本，都不会改变快照之后导出的内容。JSON 与 DOT 继续使用原有格式；导出时仍会生成序列化内容和边级证据，并非缓存字符串。需要分析修改后的图时，应重新调用 `prepare_analysis`，而不是修改检查副本。

快照的 `json_text()` 限制为 16 MiB，超限报错时仍可检查分析并导出 DOT；当前图尺寸上限可保证 DOT 小于该限制。边级证据保留原有的有界前缀与 `control_witnesses_complete` 标志，需要完整证据时仍须检查该标志。`AnalysisSnapshot` 是进程内对象，没有把报告重新解析为快照的接口。现有可修改的 `Analysis`、旧序列化接口和 CLI 行为保持不变。`examples/sdk` 会修改原图与检查副本，再断言已保存的两种导出保持一致。

完整 JSON 的快照和 CLI 入口在追加每段输出前核对剩余字节，超限时停止序列化。SDK 可用 `saved.json_text_limit(bytes)` 指定 0 到 16 MiB 的预算，刚好达到预算也可导出。CLI 的 16 MiB 包含末尾换行，整份报告生成成功后才写入文件或标准输出。原有的 `analysis_json_text(result)` 继续提供无字节预算的字符串接口。

公开支配查询会先检查树的完整结构，拒绝父链成环、断链、无效根和损坏的边界集合。结构检查无法证明手工填写的支配边界与原图在数学上相符；编辑图后应重新调用 `analyze` 或 `dominators`。

反复查询同一棵树时，用 `index_dominance(tree)` 一次校验并建立不可变快照：

```moonbit
let index = @dom.index_dominance(result.forward)
let yes = index.dominates(ancestor_index, target_index)
let common = index.nearest_common([left_index, right_index])
```

索引按 DFS 区间判断支配，单次为 O(1)；公共支配节点使用倍增祖先表，k 个操作数为 O(k log n)。索引不暴露内部数组，原树之后的修改不会影响已有答案；图变化后需重新分析和建立索引。这是算法复杂度说明，不是运行时间承诺。空集合或含不可达节点的最近公共查询返回 `None`，越界索引始终报错。后支配索引可返回虚拟出口索引。

只需要后支配关系或分支的公共后继区域时，可以直接建立后支配索引：

```moonbit
let post = @dom.index_dominance(@dom.postdominators(graph))
let shared_region = post.nearest_common([left_index, right_index])
```

`postdominators(graph)` 保留完整图校验，但不计算正向支配树、控制依赖、循环或强连通分量。结果与 `analyze(graph).post` 相同，继续采用前述有限出口路径语义。根索引是 `graph.nodes.length()`，数组长度是原节点数加一；没有入口可达的声明出口时，仅虚拟根可达。不可达的出口或前驱不会参与结果。返回数组独立持有数据，可以交给 `index_dominance` 再做多次查询。这里缩小了实际执行的分析范围，不作未经测量的耗时承诺。

文件批量查询使用 `cairndom.queries.v1`：包含 `graph`、`tree`（`forward` 或 `post`）和 `queries`。每项为 `{"operation":"dominates","ancestor":"entry","node":"join"}` 或 `{"operation":"nearest_common","nodes":["left","right"]}`。`query` 命令用直接支配树或直接后支配树建立一次索引，跳过支配边界计算；样例中两个分支的最近公共支配节点是 `entry`，`join` 和 `exit` 的是 `join`。JSON 入口也可直接通过 SDK 的 `query_json_text` 调用。

`tree: "post"` 的 SDK JSON 与 CLI 查询现在直接使用 `postdominators`，已有输入格式、输出格式、顺序及边界限制保持兼容；`analyze` 仍返回完整分析。

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

需要“查看规划后保存同一份报告”的 SDK 程序，可保存不可变快照：

```moonbit
let saved = @dom.prepare_ssa(program)
let inspected = saved.plan()
// 查看 inspected.placements、inspected.liveness 和 inspected.program。
let report = saved.json_text()
```

`prepare_ssa` 只计算一次活跃性和 phi 规划，内部独立持有完整结果。`plan()` 每次返回可修改的深层副本；修改原始程序或该副本，都不会改变快照及其 JSON。`json_text()` 序列化同一次计算，保留 `cairndom.ssa-plan.v1` 格式和 16 MiB 上限，不会重新规划。大报告仍可通过 `plan()` 检查。导出按块和变量逐条生成，追加文本前检查剩余预算。SDK 的 16 MiB 上限包含报告正文，CLI 另将末尾换行计入同一上限。CLI 只有在完整报告符合上限时才写出。

`ssa_plan_json_text(program)` 仍是按当前程序即时计算并导出的便捷入口。快照用于保存已查看的结果，不用于导出对检查副本所做的修改；图或变量事实改变后，需要新的规划时应重新调用 `prepare_ssa`。快照是进程内对象，JSON 报告没有新增反序列化为规划对象的接口。完整的 `examples/ssa_sdk` 会修改原始输入与检查副本，再断言已保存的报告保持一致。

按使用点查看可能的最后定义块和入口值，可使用独立的值来源分析：

```moonbit
let origins = @dom.trace_values(program)
let uses = origins.uses()
let saved_program = origins.program()
let report = origins.json_text()
```

每个 `UseOrigins` 包含使用块索引 `node`、变量索引 `variable`、排序后的来源块 `definitions` 和 `requires_entry_value`。结果按块和变量索引排序，索引对应 `origins.program()` 的原始节点与变量顺序。`program()` 和 `uses()` 都返回独立可修改的副本；修改输入或副本，不会改变已保存结果及其 JSON。`is_reachable(node)` 可区分不可达块与没有使用的可达块，越界索引报错。

编辑器只需要解释一个使用点时，可直接用块索引和变量索引查询。SSA SDK 示例用块 3（`join`）和变量 0（`value`）演示这条调用。

```moonbit
let selected = @dom.trace_use(program, 3, 0)
```

该调用会校验整个程序，只计算这个使用点的来源。可达的已声明使用返回 `Some(UseOrigins)`，其结果与全量对应项一致，定义块数组由调用方独立持有。不可达块中已声明的使用返回 `None`。越界索引、无效程序、块的 `uses` 中未声明该变量都会报错。全量超过 65,536 条关系时仍可查询单点。

从文件查询时，`trace-use INPUT --node NODE_ID --variable VARIABLE_ID` 直接使用块名和变量名。SDK 的 `trace_use_json_text(program, "join", "value")` 返回相同的 `cairndom.use-origin.v1` 报告。`origin` 是 `trace-values` 中对应的完整一行，声明了使用但块不可达时为 `null`。例如上面的 CLI 调用返回来源块 `left`，同时标记可能需要入口值。未知名字和未声明的使用按输入错误处理。名字以 `--` 开头时可写作 `--node=NODE_ID` 或 `--variable=VARIABLE_ID`。保存报告可用 `--out NEW_FILE`，也可按需加 `--durable`。

来源沿所有入口可达路径计算，包含永久循环；声明出口不会裁掉这些路径。同一块的使用发生在本地定义之前，但本块上一轮循环的定义可以成为来源。后续定义会阻断更早定义。`requires_entry_value` 表示原始入口值可能到达这个使用点，调用方应提供参数或初值，或按自身语言规则处理；它不直接证明源程序存在未初始化错误。这里不分析值、分支条件、别名或语句顺序，也不转换 IR。

总来源关系上限为 **65,536**，每个使用点的入口值标志也计作一条关系；超过上限整体报错，不返回截断结果。每个使用点的反向搜索使用 O(n) 临时空间，工作量为 O(n + e)，另需存储完整结果；不承诺未经测量的耗时。JSON 为 `cairndom.value-origins.v1`，包括 `uses`、`unreachable_blocks`、`source_relation_count` 和 `source_relation_limit`，输出仍限制为 16 MiB。CLI 沿用新文件独占发布约定，分析失败时不会留下半份目标报告。

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
python scripts/verify_value_origins.py
```

独立核对方法、复现结果及后续方向见 [验证记录](docs/verification.md)。CI 在 Windows/Linux 上执行双后端检查、测试、示例和真实文件核对。

独立的节点删除、集合方程、正向定义来源状态遍历和用例生成位于 MoonBit 的 `verification/reference`，不调用生产分析算法生成预期答案。Python 只负责真实文件、进程、管道及故障注入适配；四个文件验证入口共享同一输出契约，另有标准输出验证入口。`moon build --target js --release` 同时构建参考命令，验证脚本也接受 `--oracle` 指定它的位置。生产库、测试、独立验证器与主机适配的语言统计分别记录在 [语言构成说明](docs/languages.md)。

## 算法与来源

采用 Cooper–Harvey–Kennedy 支配算法、迭代 DFS、反向图与虚拟出口、Kosaraju SCC 和经典自然循环构造。实现依据算法定义独立编写，算法本身有既有研究基础。运行时只依赖 MoonBit 标准库。

该项目与作者已有的 JSON 迁移、小册子拼版、BitTorrent 元数据和套件备料项目用途及代码独立。MoonBit 生态已有通用图及编译器内部的部分支配分析实现，本项目的交付重点是统一的语言无关 CFG API、出口范围明确的分析和可直接运行的离线工具。公开检索无法覆盖全部未公开参赛资料。

项目使用 AI 辅助实现及技术文档编写，采用 Apache-2.0 许可证。算法参考及生态对照见 [来源说明](THIRD_PARTY.md)。
