import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';

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

  KuaishouDanmakuArgs({
    required this.liveStreamId,
    required this.authorId,
    required this.token,
    required this.cookie,
  });

  @override
  String toString() {
    return json.encode({
      "liveStreamId": liveStreamId,
      "authorId": authorId,
      "token": token,
      "cookie": cookie,
    });
  }
}

/// 快手直播弹幕实现
///
/// 快手Web端弹幕采用SSE (Server-Sent Events) 方式推送，
/// 通过 POST 请求 `live_api/chat/feed` 接口接收实时弹幕流，
/// 而非WebSocket长连接。本实现遵循快手的SSE协议，
/// 同时提供HTTP长轮询作为降级方案。
class KuaishouDanmaku implements LiveDanmaku {
  @override
  int heartbeatTime = 20 * 1000;

  @override
  Function(LiveMessage msg)? onMessage;
  @override
  Function(String msg)? onClose;
  @override
  Function()? onReady;

  static const String _chatFeedUrl =
      "https://live.kuaishou.com/live_api/chat/feed";

  /// 长轮询拉取弹幕的API地址
  static const String _chatListUrl =
      "https://live.kuaishou.com/live_api/chat/list";

  KuaishouDanmakuArgs? _args;
  CancelToken? _cancelToken;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  bool _isRunning = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  /// SSE重连游标，用于断线续连
  String _sseCursor = "";

  /// 长轮询时间戳游标
  int _pollingCursor = 0;

  /// 当前是否使用长轮询模式（SSE失败时降级）
  bool _usePolling = false;

  late Dio _dio;

  @override
  Future start(dynamic args) async {
    _args = args as KuaishouDanmakuArgs;
    _isRunning = true;
    _reconnectAttempts = 0;
    _sseCursor = "";
    _pollingCursor = DateTime.now().millisecondsSinceEpoch;
    _usePolling = false;

    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 15),
      headers: _buildHeaders(),
    ));

    _connectSSE();
  }

  Map<String, dynamic> _buildHeaders() {
    final headers = <String, dynamic>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'text/event-stream',
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
    _cancelToken?.cancel();
    _cancelToken = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    onMessage = null;
    onClose = null;
    onReady = null;
    _dio.close(force: true);
  }

  @override
  void heartbeat() {
    // SSE模式下由HTTP连接自身保活，无需额外心跳
    // 长轮询模式下每次请求即为心跳
  }

  // ──────────────────── SSE 连接 ────────────────────

  /// 通过SSE连接快手弹幕推送接口
  void _connectSSE() {
    if (!_isRunning || _args == null) return;

    _cancelToken?.cancel();
    _cancelToken = CancelToken();

    final params = <String, dynamic>{
      "liveStreamId": _args!.liveStreamId,
    };
    if (_args!.token.isNotEmpty) {
      params["token"] = _args!.token;
    }
    if (_sseCursor.isNotEmpty) {
      params["cursor"] = _sseCursor;
    }

    _dio
        .post(
      _chatFeedUrl,
      data: params,
      options: Options(
        responseType: ResponseType.stream,
        contentType: Headers.formUrlEncodedContentType,
      ),
      cancelToken: _cancelToken,
    )
        .then((response) {
      _reconnectAttempts = 0;
      onReady?.call();

      // 启动心跳定时器（SSE模式下主要作为状态检查）
      _startHeartbeatTimer();

      final stream = (response.data as ResponseBody).stream;
      final buffer = StringBuffer();

      stream.listen(
        (chunk) {
          buffer.write(utf8.decode(chunk, allowMalformed: true));

          // SSE事件以双换行分隔
          var content = buffer.toString();
          var events = content.split('\n\n');

          // 最后一段可能不完整，保留在buffer中
          buffer.clear();
          if (!content.endsWith('\n\n')) {
            buffer.write(events.removeLast());
          }

          for (var event in events) {
            if (event.trim().isNotEmpty) {
              _parseSSEEvent(event);
            }
          }
        },
        onError: (e) {
          if (!_isRunning) return;
          CoreLog.error(e);
          _handleDisconnect("弹幕连接异常: $e");
        },
        onDone: () {
          if (!_isRunning) return;
          _handleDisconnect("弹幕连接已断开");
        },
      );
    }).catchError((e) {
      if (!_isRunning) return;
      CoreLog.error(e);

      // SSE连接失败，尝试降级到长轮询
      if (!_usePolling) {
        _usePolling = true;
        CoreLog.i("快手弹幕SSE连接失败，降级为长轮询模式");
        onReady?.call();
        _startHeartbeatTimer();
        _pollMessages();
      } else {
        _handleDisconnect("弹幕连接失败: $e");
      }
    });
  }

  // ──────────────────── SSE 事件解析 ────────────────────

  /// 解析SSE格式事件
  ///
  /// SSE事件格式:
  /// ```
  /// event: <eventType>
  /// data: <jsonData>
  /// ```
  void _parseSSEEvent(String rawEvent) {
    String? eventType;
    String? data;

    for (var line in rawEvent.split('\n')) {
      if (line.startsWith('event:')) {
        eventType = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        data = line.substring(5).trim();
      }
    }

    if (data == null || data.isEmpty) return;

    try {
      final json = jsonDecode(data);
      _handleEvent(eventType ?? json["type"]?.toString(), json);
    } catch (_) {
      // 忽略无法解析的事件（如SSE注释行 : keepalive）
    }
  }

  /// 统一事件分发处理
  void _handleEvent(String? eventType, Map<String, dynamic> json) {
    switch (eventType) {
      case "chat":
      case "chatMessage":
      case "comment":
        _handleChatMessage(json);
        break;
      case "online":
      case "onlineCount":
      case "viewerCount":
      case "watchingCount":
        _handleOnlineCount(json);
        break;
      case "gift":
      case "giftMessage":
      case "sendGift":
        _handleGiftMessage(json);
        break;
      case "enter":
      case "enterRoom":
        _handleEnterRoom(json);
        break;
      case "like":
      case "likeMessage":
        // 点赞消息，暂不处理
        break;
      default:
        // 未知类型，尝试按结构自动识别
        _autoDetectMessage(json);
        break;
    }

    // 更新游标
    if (json.containsKey("cursor")) {
      _sseCursor = json["cursor"].toString();
    }
  }

  // ──────────────────── 消息处理 ────────────────────

  /// 处理聊天弹幕消息
  void _handleChatMessage(Map<String, dynamic> json) {
    final userName = json["userName"]?.toString() ??
        json["user"]?["name"]?.toString() ??
        json["user"]?["nickName"]?.toString() ??
        json["author"]?["name"]?.toString() ??
        json["author"]?["nickName"]?.toString() ??
        "未知用户";

    final content = json["content"]?.toString() ??
        json["message"]?.toString() ??
        json["text"]?.toString() ??
        "";

    if (content.isEmpty) return;

    // 提取弹幕颜色
    final color = _parseColor(json["color"] ?? json["fontColor"]);

    onMessage?.call(LiveMessage(
      type: LiveMessageType.chat,
      color: color,
      message: content,
      userName: userName,
    ));
  }

  /// 处理在线人数更新
  void _handleOnlineCount(Map<String, dynamic> json) {
    final online = json["count"] ??
        json["online"] ??
        json["onlineCount"] ??
        json["watchingCount"] ??
        json["data"] ??
        0;

    onMessage?.call(LiveMessage(
      type: LiveMessageType.online,
      data: online is int ? online : int.tryParse(online.toString()) ?? 0,
      color: LiveMessageColor.white,
      message: "",
      userName: "",
    ));
  }

  /// 处理礼物消息
  void _handleGiftMessage(Map<String, dynamic> json) {
    final userName = json["userName"]?.toString() ??
        json["user"]?["name"]?.toString() ??
        json["author"]?["name"]?.toString() ??
        "未知用户";

    final giftName = json["giftName"]?.toString() ??
        json["gift"]?["name"]?.toString() ??
        "礼物";

    final count = json["count"] ?? json["num"] ?? 1;

    onMessage?.call(LiveMessage(
      type: LiveMessageType.gift,
      color: LiveMessageColor.white,
      message: "送出 $giftName x$count",
      userName: userName,
    ));
  }

  /// 处理进入直播间提示
  void _handleEnterRoom(Map<String, dynamic> json) {
    final userName = json["userName"]?.toString() ??
        json["user"]?["name"]?.toString() ??
        json["author"]?["name"]?.toString() ??
        "";

    if (userName.isEmpty) return;

    onMessage?.call(LiveMessage(
      type: LiveMessageType.chat,
      color: LiveMessageColor(150, 150, 150),
      message: "进入直播间",
      userName: userName,
    ));
  }

  /// 对未知类型的消息进行自动结构识别
  void _autoDetectMessage(Map<String, dynamic> json) {
    // 如果包含 content/message 字段，当作聊天消息
    if (json.containsKey("content") ||
        json.containsKey("message") ||
        json.containsKey("text")) {
      _handleChatMessage(json);
      return;
    }

    // 如果包含 online/count 字段，当作在线人数
    if (json.containsKey("online") ||
        json.containsKey("count") ||
        json.containsKey("onlineCount")) {
      _handleOnlineCount(json);
      return;
    }

    // 如果包含 gift 字段，当作礼物
    if (json.containsKey("gift") || json.containsKey("giftName")) {
      _handleGiftMessage(json);
    }
  }

  // ──────────────────── HTTP 长轮询（降级方案） ────────────────────

  /// HTTP长轮询拉取弹幕消息
  void _pollMessages() async {
    while (_isRunning) {
      try {
        final result = await _dio.post(
          _chatListUrl,
          data: {
            "liveStreamId": _args!.liveStreamId,
            if (_args!.token.isNotEmpty) "token": _args!.token,
            "cursor": _pollingCursor,
            "pageSize": 50,
          },
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );

        _reconnectAttempts = 0;

        if (result.data is Map) {
          final data = result.data as Map;
          final list = data["data"]?["list"] as List? ?? [];

          for (var item in list) {
            if (item is Map<String, dynamic>) {
              final type = item["type"]?.toString();
              _handleEvent(type, item);
            }
          }

          // 更新游标
          final newCursor = data["data"]?["cursor"];
          if (newCursor != null) {
            _pollingCursor = newCursor is int
                ? newCursor
                : int.tryParse(newCursor.toString()) ?? _pollingCursor;
          }
        }

        // 短暂延迟避免请求过于频繁
        await Future.delayed(const Duration(milliseconds: 1500));
      } catch (e) {
        if (!_isRunning) break;
        CoreLog.error(e);
        _reconnectAttempts++;
        if (_reconnectAttempts >= _maxReconnectAttempts) {
          onClose?.call("长轮询超过最大重试次数，弹幕连接已断开");
          _isRunning = false;
          break;
        }
        await Future.delayed(
            Duration(seconds: 2 * _reconnectAttempts));
      }
    }
  }

  // ──────────────────── 重连与保活 ────────────────────

  /// 处理连接断开，进行指数退避重连
  void _handleDisconnect(String reason) {
    if (!_isRunning) return;

    _cancelToken?.cancel();
    _cancelToken = null;

    _reconnectAttempts++;
    if (_reconnectAttempts > _maxReconnectAttempts) {
      onClose?.call("超过最大重连次数，弹幕连接已断开");
      _isRunning = false;
      return;
    }

    onClose?.call("$reason，正在尝试第$_reconnectAttempts次重连...");

    final delaySeconds = _reconnectAttempts * 2;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (_usePolling) {
        _pollMessages();
      } else {
        _connectSSE();
      }
    });
  }

  /// 启动心跳定时器
  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(milliseconds: heartbeatTime),
      (_) => heartbeat(),
    );
  }

  // ──────────────────── 工具方法 ────────────────────

  /// 解析弹幕颜色
  LiveMessageColor _parseColor(dynamic colorValue) {
    if (colorValue == null) return LiveMessageColor.white;
    if (colorValue is int) {
      return colorValue == 0
          ? LiveMessageColor.white
          : LiveMessageColor.numberToColor(colorValue);
    }
    if (colorValue is String) {
      // 处理 #RRGGBB 格式
      var hex = colorValue.replaceAll('#', '');
      if (hex.length == 6) {
        final intColor = int.tryParse(hex, radix: 16);
        if (intColor != null) {
          return LiveMessageColor.numberToColor(intColor);
        }
      }
    }
    return LiveMessageColor.white;
  }
}
