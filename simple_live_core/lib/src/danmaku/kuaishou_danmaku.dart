import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/kuaishou_proto_helper.dart';
import 'package:simple_live_core/src/common/web_socket_util.dart';

/// 快手弹幕连接参数
class KuaishouDanmakuArgs {
  /// 直播流ID (liveStream.id)
  final String liveStreamId;

  /// 主播用户ID
  final String authorId;

  /// 弹幕鉴权Token，从页面 __INITIAL_STATE__ 中提取
  final String token;

  /// 登录Cookie
  final String cookie;

  /// WebSocket连接地址
  final String wsUrl;

  KuaishouDanmakuArgs({
    required this.liveStreamId,
    required this.authorId,
    required this.token,
    required this.cookie,
    this.wsUrl = "",
  });

  @override
  String toString() {
    return json.encode({
      "liveStreamId": liveStreamId,
      "authorId": authorId,
      "token": token,
      "cookie": cookie,
      "wsUrl": wsUrl,
    });
  }
}

/// 快手直播弹幕实现
///
/// 快手Web端弹幕采用 WebSocket + Protobuf 方式推送。
/// 本实现通过 WebSocket 连接快手弹幕服务器，
/// 接收实时弹幕、礼物、点赞等消息。
class KuaishouDanmaku implements LiveDanmaku {
  @override
  int heartbeatTime = 30 * 1000; // 30秒心跳

  @override
  Function(LiveMessage msg)? onMessage;
  @override
  Function(String msg)? onClose;
  @override
  Function()? onReady;

  KuaishouDanmakuArgs? _args;
  WebScoketUtils? _webSocketUtils;
  bool _isRunning = false;

  /// 默认的快手弹幕 WebSocket 地址
  static const String _defaultWsUrl =
      "wss://live-ws-pkg.kuaishou.com/websocket";

  @override
  Future start(dynamic args) async {
    _args = args as KuaishouDanmakuArgs;
    _isRunning = true;

    CoreLog.i("快手弹幕启动: liveStreamId=${_args!.liveStreamId}, "
        "authorId=${_args!.authorId}, "
        "token=${_args!.token.isNotEmpty ? '有' : '无'}, "
        "wsUrl=${_args!.wsUrl.isNotEmpty ? '有' : '无'}, "
        "cookie=${_args!.cookie.isNotEmpty ? '有' : '无'}");

    if (_args!.liveStreamId.isEmpty) {
      CoreLog.i("快手弹幕: liveStreamId为空，无法连接弹幕");
      onClose?.call("liveStreamId为空，无法连接弹幕");
      return;
    }

    _connectWebSocket();
  }

  Map<String, dynamic> _buildHeaders() {
    final headers = <String, dynamic>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Origin': 'https://live.kuaishou.com',
      'Referer': 'https://live.kuaishou.com/',
    };
    if (_args != null && _args!.cookie.isNotEmpty) {
      headers['Cookie'] = _args!.cookie;
    }
    return headers;
  }

  @override
  Future stop() async {
    _isRunning = false;
    _webSocketUtils?.close();
    _webSocketUtils = null;
    onMessage = null;
    onClose = null;
    onReady = null;
  }

  @override
  void heartbeat() {
    if (_webSocketUtils != null && _isRunning) {
      try {
        final heartbeatMsg = KuaishouProtoHelper.buildHeartbeatMessage();
        _webSocketUtils?.sendMessage(heartbeatMsg);
        CoreLog.i("快手弹幕心跳已发送");
      } catch (e) {
        CoreLog.w("快手弹幕心跳发送失败: $e");
      }
    }
  }

  // ──────────────────── WebSocket 连接 ────────────────────

  /// 通过WebSocket连接快手弹幕服务器
  void _connectWebSocket() {
    if (!_isRunning || _args == null) return;

    // 确定 WebSocket URL
    String wsUrl = _args!.wsUrl;
    if (wsUrl.isEmpty) {
      wsUrl = _defaultWsUrl;
    }

    // 添加连接参数
    final uri = Uri.parse(wsUrl);
    final queryParams = Map<String, String>.from(uri.queryParameters);
    if (_args!.token.isNotEmpty) {
      queryParams['token'] = _args!.token;
    }
    queryParams['liveStreamId'] = _args!.liveStreamId;
    final finalUri = uri.replace(queryParameters: queryParams);

    CoreLog.i("快手弹幕WebSocket连接: ${finalUri.toString()}");

    _webSocketUtils = WebScoketUtils(
      url: finalUri.toString(),
      heartBeatTime: heartbeatTime,
      headers: _buildHeaders(),
      onReady: () {
        CoreLog.i("快手弹幕WebSocket连接成功");
        onReady?.call();
        _joinRoom();
      },
      onMessage: (data) {
        _handleMessage(data);
      },
      onHeartBeat: () {
        heartbeat();
      },
      onReconnect: () {
        CoreLog.i("快手弹幕WebSocket断开，正在重连...");
        onClose?.call("弹幕连接断开，正在重连...");
      },
      onClose: (msg) {
        CoreLog.i("快手弹幕WebSocket关闭: $msg");
        if (_isRunning) {
          onClose?.call("弹幕连接已断开: $msg");
        }
      },
    );

    _webSocketUtils?.connect();
  }

  /// 加入房间，发送认证消息
  void _joinRoom() {
    if (_webSocketUtils == null || _args == null) return;

    try {
      final joinMsg = KuaishouProtoHelper.buildJoinRoomMessage(
        token: _args!.token,
        liveStreamId: _args!.liveStreamId,
      );
      _webSocketUtils?.sendMessage(joinMsg);
      CoreLog.i("快手弹幕已发送加入房间消息");
    } catch (e) {
      CoreLog.w("快手弹幕发送加入房间消息失败: $e");
    }
  }

  // ──────────────────── WebSocket 消息处理 ────────────────────

  /// 处理接收到的WebSocket消息
  void _handleMessage(dynamic data) {
    if (!_isRunning) return;

    try {
      // 使用 Protobuf 解析器解析消息
      final messages = KuaishouProtoHelper.parseMessages(data);

      for (var message in messages) {
        _handleParsedMessage(message);
      }
    } catch (e) {
      CoreLog.w("快手弹幕消息处理失败: $e");
    }
  }

  /// 处理解析后的消息
  void _handleParsedMessage(KuaishouMessage message) {
    switch (message.type) {
      case KuaishouMessageType.chat:
        _handleChatMessageParsed(message);
        break;
      case KuaishouMessageType.gift:
        _handleGiftMessageParsed(message);
        break;
      case KuaishouMessageType.like:
        _handleLikeMessageParsed(message);
        break;
      case KuaishouMessageType.userEnter:
        _handleUserEnterParsed(message);
        break;
      case KuaishouMessageType.onlineCount:
        _handleOnlineCountParsed(message);
        break;
      case KuaishouMessageType.liveStatus:
        // 直播状态变更，暂不处理
        break;
      case KuaishouMessageType.unknown:
        // 未知消息类型，忽略
        break;
    }
  }

  // ──────────────────── 消息处理 ────────────────────

  /// 处理聊天弹幕消息
  void _handleChatMessageParsed(KuaishouMessage message) {
    final userName = message.userName ?? "未知用户";
    final content = message.content ?? "";

    if (content.isEmpty) return;

    onMessage?.call(LiveMessage(
      type: LiveMessageType.chat,
      color: LiveMessageColor.white,
      message: content,
      userName: userName,
    ));
  }

  /// 处理在线人数更新
  void _handleOnlineCountParsed(KuaishouMessage message) {
    final online = message.onlineCount ?? 0;

    onMessage?.call(LiveMessage(
      type: LiveMessageType.online,
      data: online,
      color: LiveMessageColor.white,
      message: "",
      userName: "",
    ));
  }

  /// 处理礼物消息
  void _handleGiftMessageParsed(KuaishouMessage message) {
    final userName = message.userName ?? "未知用户";
    final giftName = message.giftName ?? "礼物";
    final count = message.giftCount ?? 1;

    onMessage?.call(LiveMessage(
      type: LiveMessageType.gift,
      color: LiveMessageColor.white,
      message: "送出 $giftName x$count",
      userName: userName,
    ));
  }

  /// 处理点赞消息
  void _handleLikeMessageParsed(KuaishouMessage message) {
    final userName = message.userName ?? "";
    if (userName.isEmpty) return;

    // 点赞消息可以显示为系统消息或忽略
    // 这里选择忽略，不显示在弹幕中
  }

  /// 处理用户进入直播间
  void _handleUserEnterParsed(KuaishouMessage message) {
    final userName = message.userName ?? "";
    if (userName.isEmpty) return;

    onMessage?.call(LiveMessage(
      type: LiveMessageType.chat,
      color: LiveMessageColor(150, 150, 150),
      message: "进入直播间",
      userName: userName,
    ));
  }

  // ──────────────────── 工具方法 ────────────────────

  /// 获取当前连接状态
  bool get isConnected => _webSocketUtils?.status == SocketStatus.connected;

  /// 获取当前运行状态
  bool get isRunning => _isRunning;
}
