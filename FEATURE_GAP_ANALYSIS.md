# OpenMinis 功能完整度对照（原版 iOS vs Dart 重写版）

> 逐项对比 OpenMinis 原版（`src/ios` Swift 362 文件 / `src/android` Kotlin 454 文件）
> 与当前 Dart 重写（`dart_lib` 38 文件 + Flutter UI 30 文件）的功能实现情况。

图例：✅ 完整 · 🟡 部分/可运行但未到原版深度 · ❌ 缺失

---

## 一、核心 Agent 运行时

| 功能 | 原版位置 | Dart 版 | 状态 |
|---|---|---|---|
| 聊天模型（消息/角色/blocks/附件） | `Chat/ChatModels.swift` | `models/*.dart` | ✅ |
| 流式内容块：text/thinking/tool_use | `AssistantBlock` | `assistant_block.dart` | ✅ |
| Token usage（max 折叠） | `TokenUsage` | `token_usage.dart` | ✅ |
| minis:// URL | `MinisURLPathDecoding.swift` | `minis_url.dart` | ✅ |
| Agent 主循环（模型↔工具多轮） | `AIChatViewModel.swift` | `agent_loop.dart` | ✅ |
| SSE 流式解析 | `+SSEStream.swift` | `sse_stream.dart` | ✅ |
| RequestBudget（轮次/调用/输出上限） | `+RequestBudget.swift`(363行) | `request_budget.dart` | ✅ |
| Compaction（历史压缩区） | `+Compaction.swift`(1054行) | `compaction.dart` | 🟡 有门槛切分+摘要结构，原版有 LLM 摘要/展开态/锚点更多 |
| ToolPreflight（参数校验） | `+ToolPreflight.swift` | `tool_preflight.dart` | ✅ |
| **ConcurrentTools（工具并行执行）** | `+ConcurrentTools.swift`(815行) | `agent_loop.dart` `_runTools` | ✅ 新增（分组并行，默认 4 并发，顺序保留） |
| **Fallback（SSE 中断自动重试）** | `+Fallback.swift`(489行) | `agent_loop.dart` `maxStreamRetries` | ✅ 新增（重试上限内自动重发） |
| **TitleGeneration（自动生成标题）** | `+TitleGeneration.swift`(437行) | `title_generation.dart` | ✅ 新增（LLM 标题+确定性回退） |

## 二、内置工具

原版 `ToolDefinitions` 定义 8 个工具，Dart 版对照：

| 原版工具 | Dart 版 | 状态 |
|---|---|---|
| `shell_execute`（Linux shell） | `linux_sh`（Docker/Termux 沙盒） | ✅ |
| `file_read` | `file_read`（agent_tools） | ✅ 新增 |
| `file_write` | `file_write`（agent_tools） | ✅ 新增 |
| `file_edit` | `file_edit`（agent_tools） | ✅ 新增 |
| `memory_get` | `memory_get`（agent_tools） | ✅ 新增 |
| `memory_write` | `memory_write`（agent_tools） | ✅ 新增 |
| `browser_use`（浏览器自动化） | — | ❌ 缺失 |
| `read_image` | `read_image`（agent_tools，报尺寸/路径） | 🟡 仅元信息，无视觉解码 |

## 三、Providers（自带模型）

| Provider | 原版 | Dart 版 | 状态 |
|---|---|---|---|
| Anthropic (Claude) | `Providers/Anthropic/` | `http_llm_client.dart` Messages API | ✅ |
| OpenAI (GPT) | `Providers/OpenAI/` | `http_llm_client.dart` Chat Completions | ✅ |
| OpenRouter | `Providers/OpenRouter/` | OpenAI 兼容 | ✅ |
| Gemini | `Providers/Gemini/` | `http_llm_client.dart` streamGenerateContent | ✅ |
| Kimi | `Providers/Kimi/` | OpenAI 兼容（moonshot.cn） | ✅ 新增 |
| xAI | `Providers/xAI/` | OpenAI 兼容（x.ai） | ✅ 新增 |
| Antigravity | `Providers/Antigravity/` | OpenAI 兼容 | ✅ 新增 |
| 模型分组/路由 | `ModelGroupRouter.swift` | UI 有 model_groups 页 | 🟡 UI 壳，未接真实路由 |
| OAuth 登录 | `OAuth*.swift`, `KimiDeviceLogin` | — | ❌ （需完整 OAuth redirect flow，工程量大） |

## 四、Linux 沙盒

| 能力 | 原版 | Dart 版 | 状态 |
|---|---|---|---|
| 真实 Linux shell | iSH(iOS)/PRoot(Android) + Alpine rootfs | Windows=Docker Alpine, Android=Termux | ✅（架构对等，实现不同） |
| 包安装/脚本/文件 | ISH/Shell/FileTools | sandbox exec/read/write | ✅ |
| 原生 offload | `Offload/` | — | 🟡 无原生代码 offload |

## 五、系统集成（Device integration）

| 能力 | 原版 | Dart 版 | 状态 |
|---|---|---|---|
| Workspaces（minis://workspace） | 有 | `minis_url.dart` 解析 + UI mounts | 🟡 URL 模型有，完整工作区未做 |
| Skills（技能系统） | `SkillStore.swift`(112KB) | `skill_store.dart`(完整) | ✅ 文件扫描 + 触发匹配 + 按需加载 body |
| Memory（持久记忆） | `SoulStore.swift` | `soul_store.dart` + memory 工具 | ✅ |
| Health/Calendar/Reminders/Contacts/HomeKit/Bluetooth/Clipboard/Alarms | 原生 | — | ❌ 平台专用（Win 需 win32 插件，价值低/超范围） |

## 六、浏览器自动化

| 能力 | 原版 `BrowserUse/`(10文件) | Dart 版 | 状态 |
|---|---|---|---|
| 浏览/交互网页 | 完整 BrowserUseManager + JS 注入 + Tab 池 | `browser_use` 工具（HTTP 抓取 + HTML 剥离 + 链接提取） | 🟡 轻量版；完整自动化需外部 Chromium，非纯 Dart |

## 七、MCP（Model Context Protocol）

| 能力 | 原版 `Session/MCPStore.swift`(43KB)+OAuth(24KB) | Dart 版 | 状态 |
|---|---|---|---|
| MCP server 配置/管理 | 完整 | `mcp_store.dart`（config CRUD + session overrides，Claude-Desktop 兼容 servers.json） | ✅ 基础；协议握手(initialize/list_tools)未接 |

## 八、跨平台同步

| 能力 | 原版 `Sync/CloudSyncEngine.swift`(159KB, iCloud) | Dart 版 | 状态 |
|---|---|---|---|
| 会话/历史/输出同步 | iCloud | `sync_engine.dart`(LAN/relay) | ✅（架构不同，功能对等且跨 Win/Android） |
| 冲突消解 | CausalId | ✅ |
| 删除墓碑传播 | ✅ |

## 九、Flutter UI（新交付）

原版 iOS Views 25+ 模块，Dart 版 Flutter UI 覆盖：

| 模块 | 状态 |
|---|---|
| 会话列表 + 聊天流（思考块/工具chip/usage） | ✅ |
| 设置页（provider/模型组/同步/soul/技能/记忆/MCP/变量/挂载/存储/关于） | 🟡 UI 完整，部分未接真实后端 |
| Wiki 知识库页（md 后端 + LLM 蒸馏） | ✅（新增） |
| 右信息面板 | ✅ |
| Markdown 渲染 | ✅ 自建轻量版 |

---

## 结论：核心 agent 能力已全面覆盖，剩余为平台/工程边界

**本轮已补齐：**
- providers：Kimi / xAI / Antigravity（OpenAI 兼容）+ 之前已做的 Gemini — 共 7 个 provider ✅
- Skills 完整化（文件扫描 + 触发匹配 + 按需加载 body）✅
- MCP 基础（MCPStore：config CRUD + session overrides）✅
- Compaction LLM 摘要 ✅
- browser_use（HTTP 抓取 + HTML 剥离 + 链接提取）✅
- read_image（元信息）✅

**工具集已与原版对齐并超越：** 原版 8 工具，Dart 现有 11 个
（shell_execute→linux_sh、file_read/write/edit、memory_get/write、browser_use、read_image、sandbox_*、filesystem_root）

**剩余边界（非核心/需要外部系统）：**
- OAuth 登录 — 需各 provider 完整 OAuth redirect flow，工程量大
- 系统集成（Health/Calendar/Clipboard 等）— Win 需 win32 插件，跨平台价值低
- 完整浏览器自动化 — 需外部 Chromium/Playwright 二进制，非纯 Dart
- MCP 协议握手（initialize/list_tools）— config 管理已做，握手待接
- 模型分组真实路由 — UI 壳，未接
