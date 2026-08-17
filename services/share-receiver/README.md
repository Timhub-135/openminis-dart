# OpenMinis 跨设备分享

把 URL/文本从另一台安卓手机（Firefox 浏览器）发到装有 OpenMinis 的手机上，作为一次会话开始。
所有分享固定进入 OpenMinis 的当前对话（无会话选择）。

> **安装位置**：服务代码放在 **`/root/services/share-receiver/`**（稳定路径，独立于沙盒的 `/var/minis` 隔离区），
> 避免沙盒隔离导致服务端不可用。

## 组成

```
/root/services/share-receiver/
├── share_receiver.py      # HTTP 服务，POST /share 接收分享
├── share_reader.py        # agent 读取脚本（字节 cursor 防重复）
├── receiver.sh            # start/stop/status 管理脚本
├── data/                  # 运行时生成：incoming-share.txt 缓冲 + cursor
└── README.md

/var/minis/workspace/flutter_minis/firefox-extension/   # 发送端（另一台手机）
└── openminis-share-1.0.0.xpi                          # 已打包（发送端侧载用）
```

## 一、接收端（OpenMinis 手机）

OpenMinis 手机需与另一台手机处于同一 WiFi。

### 1. 启动接收服务

```sh
cd /root/services/share-receiver
./receiver.sh start      # 绑定 0.0.0.0:8741
./receiver.sh status     # 查看运行状态 + health
./receiver.sh stop       # 停止
```

服务把分享写入 `data/incoming-share.txt`（稳定路径）。

> 确认本机局域网 IP（如 `192.168.1.20`），另一台手机用 `http://<该IP>:8741` 访问。

### 2. 查看是否收到分享

```sh
cat /root/services/share-receiver/data/incoming-share.txt
```

### 3. Agent 消费分享

```sh
python3 /root/services/share-receiver/share_reader.py              # 查看未处理
python3 /root/services/share-receiver/share_reader.py --consume    # 读取并标记已消费
```

收到分享后，agent 会将其作为当前对话的用户消息处理。

## 二、发送端（Firefox 扩展 · 另一台手机）

### 安装（侧载 .xpi）——必须用"临时加载"，否则必然报"未经校验"

包文件：`openminis-share-1.1.0.xpi`（MV2，已 zip/zipfile 双重校验无损坏）。

> **关键认知**：Firefox（含 Nightly）对未签名扩展**只能**通过
> **`about:debugging` 的 "Load Temporary Add-on"（临时加载）** 生效。
> 任何"直接打开 .xpi 安装"（永久安装）都会触发签名校验并报 **"此扩展未经校验，无法安装"**。
> 这与包是否损坏**无关**——不要再用"打开 .xpi"方式。

**正确步骤：**

1. 把 `.xpi` 传到另一台手机（微信/网盘/数据线），**后缀保持 `.xpi`**（改成 `.zip` 会报"损坏"）。

2. 打开 **Firefox Nightly / Firefox**，地址栏输入 `about:config`，搜 `xpinstall.signatures.required`，改为 **`false`**。

3. 地址栏输入 `about:debugging#/runtime/this-firefox`：
   - Firefox Android 中若打不开该地址，进入 **Firefox 设置 → 关于 Firefox**（或"实验室/远程调试"），启用远程调试。
   - 找到 **"Load Temporary Add-on"** 按钮，点它，选择 `.xpi` 文件。
   - 加载成功后扩展即生效（工具栏出现 OpenMinis 图标）。

> 局限：临时加载的扩展在**关闭 Firefox / 重启后失效**，需重新走第 3 步。这是无签名侧载的固有限制。
> 若第 3 步 `about:debugging` 在 Nightly Android 上无临时加载入口，则该 Nightly 版本移除了它——
> 那只能走 **AMO 正式签名**（见下一节）或改用桌面 Firefox 的 `about:debugging`。

### （可选）正式签名，彻底告别"未经校验"

要正式版 Firefox Android 直接安装、无需每次临时加载，需给扩展签名：
1. 注册 AMO 账号：https://addons.mozilla.org/
2. 在 https://addons.mozilla.org/developers/ 提交 `openminis-share-1.1.0.xpi`，选择 **"Self-hosted/Unlisted"（未列出）** 提交，
   仅用于获取签名（不上架到公开列表）。
3. 审核通过后下载**已签名 .xpi**，正式版 Firefox 直接可安装，随 app 常驻。

### 配置

1. 点击工具栏 OpenMinis 图标 → 打开连接设置。
2. 填入接收端地址：`http://192.168.1.20:8741`。
3. 点「测试连接」，✓ 成功后保存。

### 使用（v1.2.0 两个入口）

包版本：`openminis-share-1.2.0.xpi`。

**方式 A（最可靠）· 工具栏按钮：**
点击 Firefox 工具栏的 OpenMinis 图标 → 弹出发送窗口：
- URL 自动预填当前页面
- 文字框自动预填剪贴板内容（可编辑）
- 点「发送」→ 发送到 OpenMinis

**方式 B · 长按菜单：**
- **长按页面空白处** 或 **长按一个链接** → 菜单里选「发送到 OpenMinis」

> ⚠️ 关于"选中文字后长按"：Firefox Android 在文字选中后长按，常显示系统的复制/分享条，**扩展菜单项不出现**。这是 Firefox Android 的平台限制。请改用方式 A（工具栏按钮）或长按链接/页面空白处。

## 测试

```
POST /share  {"url","text","title","source"}   → {"ok":true,...}
GET  /health                                   → {"ok":true,"saved":"..."}
GET  /                                        → HTML 状态页
```
