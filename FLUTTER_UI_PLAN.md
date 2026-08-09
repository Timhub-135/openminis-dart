# Flutter UI 完整实现 — 规划、步骤与 TODO

## 目标

将 OpenMinis 的完整 UI 层用 Flutter 实现，覆盖原版 iOS 的核心视图模块，
适配 Windows + Android（无 iOS）。UI 层与 `dart_lib` 核心通过 `app_state.dart`
桥接，所有业务逻辑已在核心完成。

## 已检查的对照（原版 iOS Views）

| 原版模块 | 文件数 | 对应 Flutter 模块 | 状态 |
|---|---|---|---|
| **Chat** | 24 文件 | chat/ (核心视图) | ❌ 仅骨架 |
| **MessageList** | 3 文件 | chat/message_list.dart | ❌ 无 |
| **Markdown** | 3 文件 | 用 flutter_markdown 或自建 | ❌ 无 |
| **Settings** | 18 文件 | settings/ | ❌ 无 |
| **Skills** | 1 文件 | skills/ | ❌ 无 |
| **MCP** | 4 文件 | mcp/ | ❌ 无 |
| **Providers** | 16 文件 | providers/ | ❌ 无 |
| **Sync** | 2 文件 | sync/ (含在 core) | ⚠️ core 含引擎，UI 缺失 |
| **ContentView** | 1 文件 | main.dart 骨架 | ⚠️ 需要重做 |
| **Backup/Alarms/Rootfs** | 各 1-3 文件 | ⛔ 平台专用，暂不实现 |

## 实现步骤

### Phase 0: 安装 Flutter SDK ARM64（前置条件）

**状态：✅ 完成**

- 从 `zhzhzhy/Flutter-SDK-ARM64` release tag `Flutter-SDK-2026-08-06` 下载 SDK zip（280MB）
- 解压到 `/tmp/flutter_arm64/flutter/`，自带 Dart 3.14.0-beta + engine artifacts + flutter_tools（完整）
- 环境变量配置：
  - `PATH` 指向 `/tmp/flutter_arm64/flutter/bin`
  - `PUB_HOSTED_URL=https://pub.flutter-io.cn`（China 镜像）
  - `FLUTTER_GIT_URL=file:///tmp/flutter_arm64/flutter`（跳过 git 版本检查）
- 验证：`dart analyze lib` 通过（2 warning，0 error），`flutter --version` 输出 3.47.0-0.4.pre

### Phase 1: 基础架构 — App Shell + 路由 + 主题

**文件：**
- `lib/main.dart` — 重写，MaterialApp + 路由表 + 主题
- `lib/src/theme.dart` — 与原版一致的暗色主题 + 配色方案
- `lib/src/routes.dart` — 路由定义

**内容：**
1. 用 `GoRouter` 或 `Navigator 2.0` 做路由：`/` → 主页, `/chat/:id` → 聊天, `/settings` → 设置, 各类子页面
2. 深色主题：原配色的蓝紫色调（#2E5BFF 为主色）
3. 底部导航：会话 / (当前聊天) / 设置
4. Provider 注入：全局 `AppState` 通过 `ChangeNotifierProvider`

### Phase 2: 会话列表

**文件：**
- `lib/src/ui/screens/sessions_screen.dart` — 重写现有骨架
- `lib/src/ui/widgets/session_tile.dart` — 单个会话卡片

**内容：**
1. 列表展示：标题、最近更新时间、消息数、模型标签
2. 新建会话（FAB + 弹窗选模型）
3. 长按删除（确认对话框，走同步墓碑）
4. 搜索/筛选
5. 点击进入聊天
6. 空状态：无会话时的引导

### Phase 3: 聊天界面（核心，最重）

**文件：**
- `lib/src/ui/screens/chat_screen.dart` — 聊天主屏
- `lib/src/ui/chat/chat_input_bar.dart` — 输入栏（文本+附件+发送）
- `lib/src/ui/chat/message_list.dart` — 消息列表（用户气泡/助手气泡/系统提示）
- `lib/src/ui/chat/assistant_bubble.dart` — 助手消息气泡（文本+思考块+工具chips）
- `lib/src/ui/chat/thinking_block.dart` — 可折叠的思考块
- `lib/src/ui/chat/tool_chip.dart` — 工具调用状态 chip（streaming→running→success/failed）
- `lib/src/ui/chat/markdown_view.dart` — 轻量 Markdown 渲染（代码块、表格、加粗）
- `lib/src/ui/chat/usage_bar.dart` — token 用量条
- `lib/src/ui/chat/title_bar.dart` — 顶部标题栏（会话标题、模型选择器、同步状态）

**内容：**
1. **SSE 流式渲染**：通过 `AppState.liveAssistantText` ValueNotifier 订阅，文本逐字上屏
2. **思考块**：可折叠，显示「🧠 正在思考…」，展开显示内容，带自适应刷新节流（核心已有）
3. **工具调用**：tool_start → 显示运行中 chip（带 ➤ 图标），tool_end → 更新为 ✓ 或 ✕
4. **Markdown 渲染**：代码块高亮、表格、列表、粗体斜体
5. **附件预览**：图片/文件缩略图
6. **compaction divider**：历史压缩分隔线
7. **错误/回退提示**：显示自动重试次数
8. **输入栏**：多行自适应高度、附件按钮（相机/相册/文件）、发送按钮
9. **模型选择器**：右上角下拉选择 provider/model
10. **标题自动生成**：每次 agent 回复后异步生成标题

### Phase 4: 设置页面

**文件：**
- `lib/src/ui/screens/settings_screen.dart` — 设置主屏
- `lib/src/ui/settings/providers_screen.dart` — Provider 管理
- `lib/src/ui/settings/model_groups_screen.dart` — 模型分组
- `lib/src/ui/settings/sync_settings_screen.dart` — 同步设置（对应 CloudSyncSettingsView）
- `lib/src/ui/settings/soul_settings_screen.dart` — Agent 人格/规则设置（对应 SoulSettingsView）
- `lib/src/ui/settings/skills_screen.dart` — 技能管理
- `lib/src/ui/settings/memory_screen.dart` — 记忆管理
- `lib/src/ui/settings/mcp_screen.dart` — MCP 集成管理
- `lib/src/ui/settings/environments_screen.dart` — 环境变量
- `lib/src/ui/settings/about_screen.dart` — 关于
- `lib/src/ui/settings/mounted_folders_screen.dart` — 挂载文件夹（Windows 专有）
- `lib/src/ui/settings/storage_screen.dart` — 存储管理

**内容：**
1. 设置列表分组：通用、Provider & 模型、技能 & 记忆、同步、数据、关于
2. Provider 管理：添加/删除/测试 provider（对应 AddProviderView / ProviderInstanceDetailView）
3. 模型分组：Agent Loop 模型的各 slot 分配（对应 ModelGroupsView / AgentLoopModelsView）
4. 同步：LAN 同步状态、开关、手动同步（对应 CloudSyncSettingsView）
5. Agent 人格：编辑 Soul/GLOBAL.md 规则
6. 技能：已安装技能列表、启用/禁用
7. MCP：MCP server 配置添加/编辑/启用/禁用
8. 环境变量：增删改查（值脱敏显示）
9. 挂载文件夹：Windows 上绑定外部目录到 `/var/minis/mounts/`
10. 存储：数据目录大小、清理缓存

### Phase 5: 会话详情面板（右面板/抽屉）

**文件：**
- `lib/src/ui/panels/tools_panel.dart` — 当前会话可用工具列表
- `lib/src/ui/panels/memory_panel.dart` — 当前会话记忆条目
- `lib/src/ui/panels/skills_panel.dart` — 关联技能
- `lib/src/ui/panels/sync_panel.dart` — 跨平台同步状态

**内容：**
- 在聊天屏右侧（桌面）或底部 sheet（移动端）展示
- 与 Web App 的右面板一致

### Phase 6: MCP 视图

**文件：**
- `lib/src/ui/screens/mcp_integrations_screen.dart` — MCP 集成列表
- `lib/src/ui/widgets/mcp_form.dart` — 添加/编辑 MCP Server 表单
- `lib/src/ui/widgets/mcp_import_sheet.dart` — JSON 导入 MCP 配置

**内容：**
1. MCP Server 列表：名称、传输方式（HTTP/STDIO）、启用状态
2. 添加表单：STDIO（command + args + env）或 HTTP（url + headers）
3. 从 Claude Desktop 的 `mcpServers` JSON 导入
4. 启用/禁用切换

### Phase 7: 其他辅助界面

**文件：**
- `lib/src/ui/screens/welcome_screen.dart` — 首次启动引导/欢迎页
- `lib/src/ui/widgets/loading_view.dart` — 加载动画
- `lib/src/ui/widgets/error_view.dart` — 错误页面
- `lib/src/ui/widgets/status_bar.dart` — 状态栏（同步状态、网络、模型）

## 文件总览（预计 ~30 个文件）

```
lib/
├── main.dart                         # App 入口 + MaterialApp + Provider
├── src/
│   ├── app_state.dart                # (已有) App 级状态管理
│   ├── theme.dart                    # 主题
│   ├── routes.dart                   # 路由
│   ├── sync/lan_transport.dart       # (已有) core 再导出
│   ├── ui/
│   │   ├── screens/
│   │   │   ├── home_screen.dart      # 主页（底部导航容器）
│   │   │   ├── sessions_screen.dart  # 会话列表
│   │   │   ├── chat_screen.dart      # 聊天
│   │   │   ├── settings_screen.dart  # 设置主屏
│   │   │   ├── welcome_screen.dart   # 欢迎
│   │   ├── chat/
│   │   │   ├── chat_input_bar.dart
│   │   │   ├── message_list.dart
│   │   │   ├── assistant_bubble.dart
│   │   │   ├── thinking_block.dart
│   │   │   ├── tool_chip.dart
│   │   │   ├── markdown_view.dart
│   │   │   ├── usage_bar.dart
│   │   │   ├── title_bar.dart
│   │   ├── settings/
│   │   │   ├── providers_screen.dart
│   │   │   ├── model_groups_screen.dart
│   │   │   ├── sync_settings_screen.dart
│   │   │   ├── soul_settings_screen.dart
│   │   │   ├── skills_screen.dart
│   │   │   ├── memory_screen.dart
│   │   │   ├── mcp_screen.dart
│   │   │   ├── environ_screen.dart
│   │   │   ├── about_screen.dart
│   │   │   ├── mounted_folders_screen.dart
│   │   │   ├── storage_screen.dart
│   │   ├── panels/
│   │   │   ├── tools_panel.dart
│   │   │   ├── memory_panel.dart
│   │   │   ├── skills_panel.dart
│   │   ├── widgets/
│   │       ├── session_tile.dart
│   │       ├── loading_view.dart
│   │       ├── error_view.dart
│   │       ├── status_bar.dart
```

## 关于 Flutter 打包依赖的说明

本次同样不依赖 Flutter SDK 的运行环境，仅编写完整源码。
实际编译需要 Flutter SDK 并执行 `flutter pub get`。

## TODO（实施清单）

- [ ] **Phase 1**: 重写 main.dart + 路由 + 主题
- [ ] **Phase 2**: 会话列表
- [ ] **Phase 3**: 聊天界面（流式渲染、思考块、工具chips、markdown、标题生成）
- [ ] **Phase 4**: 设置页面（9个子页面）
- [ ] **Phase 5**: 右面板/抽屉
- [ ] **Phase 6**: MCP 视图
- [ ] **Phase 7**: 辅助界面

## 风险与注意事项

- **Flutter 无法在当前沙箱编译运行**（无 Flutter SDK），只能保证代码正确、dart:core 部分继续被 `dart analyze` 覆盖。
- **包依赖**：如用 `flutter_markdown` 需要声明在 `pubspec.yaml` 中，但无法在此本地解析。代码中会保留 `import 'package:flutter_markdown/flutter_markdown.dart'` 等，实际编译时 `flutter pub get` 即可。
- **Provider vs Riverpod**：当前用 `provider` 包（已在 pubspec 中），保持一致。
- **Desktop 响应式**：Windows 上用宽屏三栏布局（会话列表+聊天+面板），Android 手机用单栏+底部导航+抽屉，需在布局代码中响应式切换。
