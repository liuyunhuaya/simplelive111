# 快手直播弹幕 WebSocket 实现计划

## Context

当前项目的快手弹幕功能使用 SSE (Server-Sent Events) 方式实现，但快手实际使用的是 WebSocket + Protobuf 协议。这导致弹幕功能异常，需要重构为 WebSocket 方案。

**目标**：实现完整的快手直播弹幕 WebSocket 连接，支持实时弹幕、礼物、在线人数等消息接收。

---

## 技术方案

### 快手弹幕协议分析

| 项目 | 说明 |
|------|------|
| **协议** | WebSocket (wss://) |
| **数据格式** | Protobuf 二进制 |
| **连接方式** | 从页面 `__INITIAL_STATE__` 提取 token 和 websocket info |
| **心跳** | 需要定期发送心跳维持连接 |

### 实现架构

```
┌─────────────────────────────────────────────────────────┐
│                    KuaishouDanmaku                       │
├─────────────────────────────────────────────────────────┤
│  1. 从 kuaishou_site.dart 获取连接参数                    │
│     - liveStreamId (直播流ID)                             │
│     - token (鉴权token)                                  │
│     - cookie                                             │
├─────────────────────────────────────────────────────────┤
│  2. 解析页面获取 WebSocket URL                            │
│     - 请求直播间页面                                      │
│     - 解析 __INITIAL_STATE__ JSON                         │
│     - 提取 websocketInfo 或构造 WSS URL                   │
├─────────────────────────────────────────────────────────┤
│  3. 建立 WebSocket 连接                                   │
│     - 使用 WebScoketUtils 工具类                          │
│     - 发送认证/加入房间消息                               │
│     - 启动心跳定时器                                      │
├─────────────────────────────────────────────────────────┤
│  4. 解析 Protobuf 消息                                    │
│     - 接收二进制数据                                      │
│     - 解压 (如需要)                                       │
│     - Protobuf 反序列化                                   │
│     - 分发到各消息处理器                                  │
└─────────────────────────────────────────────────────────┘
```

---

## 实现步骤

### Task 1: 分析快手页面数据结构

**目标**：确定如何从页面获取 WebSocket 连接信息

**操作**：
1. 访问快手直播间页面 `https://live.kuaishou.com/u/{roomId}`
2. 解析 HTML 中的 `window.__INITIAL_STATE__` JSON
3. 查找 WebSocket 相关字段（可能在 `liveroom.playList[0].liveStream` 或其他位置）

**关键文件**：
- `simple_live_core/lib/src/kuaishou_site.dart` - `getRoomDetail()` 方法

---

### Task 2: 创建快手 Protobuf 定义文件

**目标**：定义快手弹幕消息的 Protobuf 结构

**操作**：
1. 在 `simple_live_core/lib/src/protobuf/` 目录创建 `kuaishou.proto`
2. 定义核心消息类型：
   - `CSWebFeedRequest` - 客户端请求
   - `SCWebFeedResponse` - 服务端响应
   - `WebChatMessage` - 聊天消息
   - `WebGiftMessage` - 礼物消息
   - `WebLikeMessage` - 点赞消息
   - `WebUserEnterMessage` - 用户进入消息

3. 使用 `protoc` 编译生成 Dart 代码

**参考**：
- BarrageGrab 项目的 Protobuf 定义
- 网络资源中的快手协议分析

**关键文件**：
- `simple_live_core/lib/src/protobuf/kuaishou.proto` (新建)
- `simple_live_core/lib/src/protobuf/kuaishou.pb.dart` (生成)

---

### Task 3: 实现快手 Protobuf 消息解析

**目标**：实现 Protobuf 消息的编解码

**操作**：
1. 创建 `KuaishouProtoHelper` 工具类
2. 实现消息序列化（用于发送认证/心跳）
3. 实现消息反序列化（用于解析接收到的数据）
4. 处理可能的 gzip 压缩

**关键文件**：
- `simple_live_core/lib/src/common/kuaishou_proto_helper.dart` (新建)

---

### Task 4: 重构 KuaishouDanmaku 类

**目标**：将现有 SSE 实现重构为 WebSocket 实现

**操作**：
1. 修改 `KuaishouDanmakuArgs` 类，添加 WebSocket 相关字段
2. 重写 `start()` 方法，建立 WebSocket 连接
3. 实现 `joinRoom()` 方法，发送认证消息
4. 实现 `heartbeat()` 方法，发送心跳
5. 实现 `_handleMessage()` 方法，解析 Protobuf 消息
6. 实现各消息类型的处理方法

**关键文件**：
- `simple_live_core/lib/src/danmaku/kuaishou_danmaku.dart` (重构)

---

### Task 5: 更新 KuaishouSite 获取弹幕参数

**目标**：确保 `getRoomDetail()` 返回正确的弹幕连接参数

**操作**：
1. 修改 `getRoomDetail()` 方法，解析页面获取 WebSocket 信息
2. 更新 `KuaishouDanmakuArgs` 的构造
3. 确保 token、liveStreamId 等参数正确传递

**关键文件**：
- `simple_live_core/lib/src/kuaishou_site.dart` - `getRoomDetail()` 方法

---

### Task 6: 测试和调试

**目标**：验证弹幕功能正常工作

**操作**：
1. 运行控制台程序测试弹幕连接
2. 检查日志输出，确认消息接收正常
3. 测试断线重连机制
4. 测试长时间运行稳定性

**测试命令**：
```bash
cd simple_live_console
dart run bin/simple_live_console.dart
```

---

## 关键文件清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `simple_live_core/lib/src/danmaku/kuaishou_danmaku.dart` | **重构** | 核心弹幕实现，改为 WebSocket |
| `simple_live_core/lib/src/kuaishou_site.dart` | **修改** | 更新 getRoomDetail() 返回弹幕参数 |
| `simple_live_core/lib/src/protobuf/kuaishou.proto` | **新建** | Protobuf 定义文件 |
| `simple_live_core/lib/src/protobuf/kuaishou.pb.dart` | **生成** | Protobuf 生成的 Dart 代码 |
| `simple_live_core/lib/src/common/kuaishou_proto_helper.dart` | **新建** | Protobuf 编解码工具 |

---

## 验证方案

1. **单元测试**：运行 `simple_live_core/test/simple_live_core_test.dart`
2. **控制台测试**：运行 `simple_live_console` 程序，选择快手直播间测试
3. **日志检查**：查看 CoreLog 输出，确认：
   - WebSocket 连接成功
   - 认证消息发送成功
   - 弹幕消息接收正常
   - 心跳维持正常
4. **稳定性测试**：长时间运行（30分钟以上），检查是否断连

---

## 风险和注意事项

1. **Protobuf 定义准确性**：快手协议可能更新，需要持续维护
2. **反爬机制**：快手可能检测异常连接，需要模拟真实浏览器行为
3. **Cookie/Token 有效期**：需要处理过期和刷新
4. **网络环境**：不同网络环境下 WebSocket 连接稳定性可能不同

---

## 参考资源

- BarrageGrab 项目：快手弹幕 Protobuf 定义
- 网络资源：快手直播弹幕协议逆向分析文章
- 项目现有实现：BiliBiliDanmaku、DouyuDanmaku 等
