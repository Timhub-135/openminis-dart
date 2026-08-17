# 跨设备分享架构·OpenMinis 接收 + Firefox 扩展发送（简化版）

> **目标**：一台装有 OpenMinis Android app 的手机作为"接收端"运行后端服务，另一台 Android 手机通过 Firefox 扩展作为"发送端"，将 URL/文本发送进 OpenMinis 会话。

---

## 一、决策确认

| # | 决策项 | 选择 |
|---|--------|------|
| 1 | 两台手机通信方式 | **A：局域网直连**（同 WiFi） |
| 2 | 是否需要更新 OpenMinis app | **不需要**——后端服务直接跑在 OpenMinis 的沙箱内，app 不重新安装 |
| 3 | Firefox 扩展触发方式 | **仅分享菜单**（长按/选中文字 → "发送到 OpenMinis"） |
| 4 | IP 配置方式 | **手动输入一次**并持久化在扩展本地存储 |
| 5 | 是否需要认证 | **不需要**——本地网络已有认证，设备可信 |
| 6 | **会话选择** | **不选择**——所有分享固定进入接收端 agent 的当前对话。Firefox 扩展无会话列表、无选择 UI、无新建会话 |

### 决策 6 的约束来源

OpenMinis 原版 app 的沙箱中，`minis-sessions-cli` 只提供只读查询（`list`/`search`/`messages`），没有 `send`/`create` 写入会话的能力。任何沙箱内的后端都**无法通过 CLI 创建会话或写入消息**。

因此架构完全绕开会话操作，改为"分享内容写入文件 → agent 主动读取"模式。所有分享进入同一个 agent 对话。

---

## 二、整体架构

```
┌──────────────────────────────────────────────────────────┐
│          同一局域网 (WiFi, 192.168.x.x/24)               │
│                                                          │
│  ┌──── 手机 A（装有 OpenMinis）─────┐                   │
│  │ OpenMinis Android App (原版)     │                   │
│  │   └─ 沙箱: Alpine Linux (PRoot)  │                   │
│  │       └─ share_receiver.py       │ (Python HTTP 服务) │
│  │          bind 0.0.0.0:8741       │                   │
│  │          POST /share             │ 接受分享          │
│  │            → 写 incoming-share.txt                   │
│  │                                  │                   │
│  │       agent (当前运行的 AI)       │                   │
│  │         定时/手动读取缓冲区       │                   │
│  │           → 作为用户消息处理      │                   │
│  │                                  │                   │
│  │  IP: 192.168.1.20 (例)          │                   │
│  └──────────────────────────────────┘                   │
│                      ↑                                   │
│                 HTTP POST (JSON)                          │
│                      ↓                                   │
│  ┌──── 手机 B（无 OpenMinis）──────┐                     │
│  │ Firefox Android 浏览器           │                     │
│  │   └─ OpenMinis Firefox 扩展     │                     │
│  │       ├─ manifest.json          │                     │
│  │       ├─ background.js           │                     │
│  │       ├─ popup/                  │                     │
│  │       └─ options/                │                     │
│  │                                 │                     │
│  │  触发：分享菜单 "发送到 OpenMinis"                       │
│  │  流程：输入确认 → POST → 完成                           │
│  └──────────────────────────────────┘                     │
└──────────────────────────────────────────────────────────┘
```

---

## 三、接收端 —— OpenMinis 沙箱内的后端服务

### 3.1 设计原则

- **零依赖**：只用沙箱已有的 Python3（`/usr/bin/python3`），不加任何 pip 包
- **极简**：一个 Python 脚本 `share_receiver.py`，约 80 行
- **面向文件缓冲区**：分享内容写入 `/var/minis/workspace/incoming-share.txt`，agent 后续读取
- **固定会话**：无会话概念——agent 当前活跃对话自动处理

### 3.2 后端服务 —— `share_receiver.py`

```python
#!/usr/bin/env python3
"""OpenMinis Share Receiver — a tiny HTTP service that accepts URL/text
shares from another device on the LAN and writes them as a file for the
agent to pick up.

Endpoint:
  POST /share   {"url": "https://...", "text": "some text", "title": "..."}

No dependencies beyond Python 3 stdlib. Bind 0.0.0.0:8741.
"""
import json, os, sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

OUTPUT_FILE = "/var/minis/workspace/incoming-share.txt"

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/share":
            self.send_error(404); return

        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)
        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            self.send_error(400, "Invalid JSON"); return

        url    = data.get("url", "")
        text   = data.get("text", "")
        title  = data.get("title", "")
        source = data.get("source", "Firefox")

        # Build a markdown-ish entry.
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        lines = [f"## 来自 {source} 的分享 · {ts}"]
        if title:
            lines.append(f"**标题**: {title}")
        if url:
            lines.append(f"**URL**: {url}")
        if text:
            lines.append(f"\n{text}")
        lines.append("---\n")

        os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)
        with open(OUTPUT_FILE, "a") as f:
            f.write("\n".join(lines) + "\n")

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"ok": True, "saved": OUTPUT_FILE}).encode())

    def do_OPTIONS(self):
        # CORS preflight for browser-based clients.
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST,OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "content-type")
        self.end_headers()

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8741
server = HTTPServer(("0.0.0.0", PORT), Handler)
print(f"[share-receiver] listening on 0.0.0.0:{PORT}", flush=True)
try:
    server.serve_forever()
except KeyboardInterrupt:
    server.server_close()
```

### 3.3 启动方式

```sh
# OpenMinis 终端中：
python3 /var/minis/workspace/share_receiver.py 8741 &
```

后台运行即可。服务绑定 `0.0.0.0:8741`，局域网内其他设备可访问。

### 3.4 Agent 读取分享

我（当前运行的 AI agent）定期检查 `/var/minis/workspace/incoming-share.txt`：
- 存在且有新增内容 → 作为用户消息处理
- 处理完后清空文件（或将已处理部分移到结尾）

Agent 将此内容直接作为当前对话的输入，无需选择会话。

### 3.5 文件格式

```
## 来自 Firefox 的分享 · 2026-08-10 14:30:05
**标题**: 如何训练 LLaMA 模型
**URL**: https://example.com/llama-training

这篇文章介绍了 LLaMA 模型的开源训练方案...
---
```

每次分享用 `---` 分隔，agent 可按分隔符逐个处理。

---

## 四、发送端 —— Firefox 扩展

### 4.1 扩展触发

**仅通过分享菜单**。用户在 Firefox 中长按链接/选中文字 → "发送到 OpenMinis"。

### 4.2 扩展文件结构

```
openminis-firefox-extension/
├── manifest.json          # 权限声明
├── background.js          # 创建分享菜单、触发分享
├── popup/
│   ├── popup.html         # 弹出窗口（最小 UI：确认发送）
│   └── popup.css
├── options/
│   ├── options.html       # 设置页面（输入 OpenMinis IP）
│   └── options.js
├── icons/                 # 图标 (16/32/48/96 px)
└── lib/
    └── api.js             # POST /share API 封装
```

### 4.3 manifest.json

```json
{
  "manifest_version": 3,
  "name": "OpenMinis Share",
  "version": "1.0",
  "description": "将 URL/文本分享到局域网中的 OpenMinis",
  "permissions": [
    "contextMenus",
    "storage",
    "activeTab"
  ],
  "host_permissions": ["http://*/*"],
  "background": {
    "scripts": ["lib/api.js", "background.js"]
  },
  "options_ui": {
    "page": "options/options.html",
    "open_in_tab": false
  },
  "action": {
    "default_title": "OpenMinis",
    "default_popup": "popup/popup.html"
  },
  "icons": {
    "16": "icons/icon-16.png",
    "32": "icons/icon-32.png",
    "48": "icons/icon-48.png",
    "96": "icons/icon-96.png"
  }
}
```

### 4.4 分享流程

```
User 长按链接/选中文字 → Firefox 分享菜单 "发送到 OpenMinis"
  ↓
background.js 提取: info.selectionText || info.linkUrl || tab.url
  ↓
读取 storage.local.serverUrl（已配置的 IP）
  ↓
POST {serverUrl}/share  {url, text, title, source: "Firefox"}
  ↓
成功 → 简短提示（toast/通知）
失败 → 静默失败（Firefox Android 限制：不应弹窗）
```

核心代码（background.js）：

```javascript
browser.contextMenus.create({
  id: "openminis-share",
  title: "发送到 OpenMinis",
  contexts: ["selection", "link", "page"]
});

browser.contextMenus.onClicked.addListener(async (info, tab) => {
  const content = info.selectionText || info.linkUrl || tab.url;
  if (!content) return;

  const settings = await browser.storage.local.get(["serverUrl"]);
  const baseUrl = settings.serverUrl;
  if (!baseUrl) {
    // 未配置 IP：打开设置页面
    browser.runtime.openOptionsPage();
    return;
  }

  const payload = {
    url: info.linkUrl || tab.url,
    text: info.selectionText || "",
    title: tab.title || "",
    source: "Firefox"
  };

  fetch(`${baseUrl}/share`, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify(payload)
  }).catch(() => {});
});
```

### 4.5 无弹出窗口 UI

因为不再需要选择会话，分享流程一步完成：菜单点击 → 发送 → 完成。不需要 popup UI，也不需要 `action.default_popup`。扩展的工具栏图标仅作为设置入口（点击打开 options 页）。

### 4.6 设置页面

与之前相同——扩展安装后第一次使用时自动打开，输入 OpenMinis 手机的 IP。

### 4.7 Firefox Android 特殊说明

- `contextMenus` 在 Firefox Android 中通过长按触发，功能正常
- `contexts: ["selection", "link", "page"]` 覆盖选中文字、链接、页面 URL
- `host_permissions: ["http://*/*"]` 允许 HTTP 请求到局域网 IP
- 发送失败时静默失败（Firefox Android 限制：不应弹窗遮挡用户）
- 无 session 列表、无会话选择 UI

---

## 五、完整数据流

```
另一台手机 Firefox
  ↓ 用户长按链接/选中文字
分享菜单 "发送到 OpenMinis"
  ↓ background.js 提取 content + 读取 storage.local.serverUrl
POST http://192.168.1.20:8741/share {url, text, title}
  ↓ share_receiver.py 处理
写入 /var/minis/workspace/incoming-share.txt
  ↓ agent 定时检查/主动读取
作为当前对话的用户消息
  ↓ agent 正常处理
```

---

## 六、需要你确认的未决问题

| # | 问题 | 需要你决定 |
|---|------|-----------|
| 1 | **扩展图标** | 有偏好吗（颜色/形状）？不指定用 OpenMinis 蓝绿色 + M 字母图标。 |
| 2 | **发送反馈** | Firefox Android 不支持弹窗。发送失败/成功如何反馈？① 静默（无条件）② 工具栏图标变色/徽章 ③ 打开一个确认页。**建议①**因为它最简单。|
| 3 | **扩展发布方式** | Firefox Add-ons 商店 或 **侧载**（手动导入 .xpi）？侧载最简单。|
| 4 | **agent 读取节奏** | 我（agent）是**定时检查** incoming-share.txt（如每 30 秒），还是你自己在聊天中**主动触发**（如发一条"处理分享"消息）？定时更自动化但需 agent 持续运行。 |
| 5 | **多个分享合并** | 如果短时间内多条分享到达（incoming-share.txt 累积），agent 是逐条处理还是合并为一条消息？**建议合并**，用 `---` 分隔。 |
| 6 | **分享带图片** | 以上方案只处理 URL+文本。图片分享需额外处理（Firefox 不能直接读图片字节）。暂时只支持 URL+文本。 |

---

回答这些后，我按你确认的方向实现（编码）。这次无需再讨论会话选择——它已完全移除。
