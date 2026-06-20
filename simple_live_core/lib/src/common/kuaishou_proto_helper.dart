import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:simple_live_core/src/common/core_log.dart';

/// 快手弹幕消息类型枚举
enum KuaishouMessageType {
  chat, // 聊天弹幕
  gift, // 礼物
  like, // 点赞
  userEnter, // 用户进入
  onlineCount, // 在线人数
  liveStatus, // 直播状态
  unknown, // 未知类型
}

/// 快手弹幕消息
class KuaishouMessage {
  final KuaishouMessageType type;
  final String? id;
  final String? content;
  final String? userId;
  final String? userName;
  final String? userAvatar;
  final String? giftId;
  final String? giftName;
  final int? giftCount;
  final int? onlineCount;
  final bool? isLiving;
  final int? timestamp;

  KuaishouMessage({
    required this.type,
    this.id,
    this.content,
    this.userId,
    this.userName,
    this.userAvatar,
    this.giftId,
    this.giftName,
    this.giftCount,
    this.onlineCount,
    this.isLiving,
    this.timestamp,
  });
}

/// 快手 Protobuf 消息解析工具类
///
/// 注意：由于快手使用自定义的二进制协议（非标准 Protobuf），
/// 这里使用手动解析方式处理二进制数据。
class KuaishouProtoHelper {
  /// 消息类型常量
  static const int msgTypeChat = 1;
  static const int msgTypeGift = 2;
  static const int msgTypeLike = 3;
  static const int msgTypeUserEnter = 4;
  static const int msgTypeOnlineCount = 5;
  static const int msgTypeLiveStatus = 6;

  /// 解析接收到的二进制消息
  static List<KuaishouMessage> parseMessages(dynamic data) {
    final messages = <KuaishouMessage>[];

    try {
      Uint8List bytes;
      if (data is Uint8List) {
        bytes = data;
      } else if (data is List<int>) {
        bytes = Uint8List.fromList(data);
      } else if (data is String) {
        // 尝试作为 JSON 解析
        return _parseJsonMessages(data);
      } else {
        CoreLog.w("快手弹幕: 未知数据类型: ${data.runtimeType}");
        return messages;
      }

      // 尝试解压 gzip
      bytes = _tryDecompress(bytes);

      // 尝试解析二进制数据
      messages.addAll(_parseBinaryMessages(bytes));
    } catch (e) {
      CoreLog.w("快手弹幕解析失败: $e");
    }

    return messages;
  }

  /// 尝试解压 gzip 数据
  static Uint8List _tryDecompress(Uint8List data) {
    try {
      // 检查 gzip 魔数 (0x1f, 0x8b)
      if (data.length > 2 && data[0] == 0x1f && data[1] == 0x8b) {
        return Uint8List.fromList(gzip.decode(data));
      }
    } catch (e) {
      // 解压失败，返回原始数据
    }
    return data;
  }

  /// 解析 JSON 格式的消息（某些情况下快手可能返回 JSON）
  static List<KuaishouMessage> _parseJsonMessages(String jsonStr) {
    final messages = <KuaishouMessage>[];

    try {
      final json = jsonDecode(jsonStr);
      if (json is Map) {
        final type = json['type']?.toString() ?? '';
        final data = json['data'] ?? json;

        switch (type) {
          case 'chat':
          case 'comment':
            messages.add(_parseChatMessage(data));
            break;
          case 'gift':
          case 'sendGift':
            messages.add(_parseGiftMessage(data));
            break;
          case 'like':
            messages.add(_parseLikeMessage(data));
            break;
          case 'enter':
          case 'enterRoom':
            messages.add(_parseUserEnterMessage(data));
            break;
          case 'online':
          case 'onlineCount':
            messages.add(_parseOnlineCountMessage(data));
            break;
        }
      } else if (json is List) {
        for (var item in json) {
          if (item is Map) {
            messages.addAll(_parseJsonMessages(jsonEncode(item)));
          }
        }
      }
    } catch (e) {
      CoreLog.w("快手 JSON 消息解析失败: $e");
    }

    return messages;
  }

  /// 解析二进制格式的消息
  static List<KuaishouMessage> _parseBinaryMessages(Uint8List data) {
    final messages = <KuaishouMessage>[];

    try {
      // 快手二进制协议格式（简化版）：
      // [4 bytes: 消息长度] [4 bytes: 消息类型] [N bytes: 消息内容]

      int offset = 0;
      while (offset + 8 <= data.length) {
        // 读取消息长度（大端序）
        final msgLength = data[offset] << 24 |
            data[offset + 1] << 16 |
            data[offset + 2] << 8 |
            data[offset + 3];

        // 读取消息类型
        final msgType = data[offset + 4] << 24 |
            data[offset + 5] << 16 |
            data[offset + 6] << 8 |
            data[offset + 7];

        // 检查数据完整性
        if (offset + 8 + msgLength > data.length) {
          break;
        }

        // 提取消息内容
        final msgData = data.sublist(offset + 8, offset + 8 + msgLength);

        // 根据消息类型解析
        final message = _parseBinaryMessage(msgType, msgData);
        if (message != null) {
          messages.add(message);
        }

        // 移动到下一条消息
        offset += 8 + msgLength;
      }
    } catch (e) {
      CoreLog.w("快手二进制消息解析失败: $e");
    }

    return messages;
  }

  /// 解析单条二进制消息
  static KuaishouMessage? _parseBinaryMessage(int type, Uint8List data) {
    try {
      switch (type) {
        case msgTypeChat:
          return _parseBinaryChatMessage(data);
        case msgTypeGift:
          return _parseBinaryGiftMessage(data);
        case msgTypeLike:
          return _parseBinaryLikeMessage(data);
        case msgTypeUserEnter:
          return _parseBinaryUserEnterMessage(data);
        case msgTypeOnlineCount:
          return _parseBinaryOnlineCountMessage(data);
        case msgTypeLiveStatus:
          return _parseBinaryLiveStatusMessage(data);
        default:
          CoreLog.i("快手弹幕: 未知消息类型: $type");
          return null;
      }
    } catch (e) {
      CoreLog.w("快手消息解析失败 (type=$type): $e");
      return null;
    }
  }

  /// 解析二进制聊天消息
  static KuaishouMessage _parseBinaryChatMessage(Uint8List data) {
    // 简化解析：假设格式为 [userId\0userName\0content]
    final parts = _splitByNull(data);
    return KuaishouMessage(
      type: KuaishouMessageType.chat,
      userId: parts.isNotEmpty ? parts[0] : null,
      userName: parts.length > 1 ? parts[1] : null,
      content: parts.length > 2 ? parts[2] : null,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 解析二进制礼物消息
  static KuaishouMessage _parseBinaryGiftMessage(Uint8List data) {
    final parts = _splitByNull(data);
    return KuaishouMessage(
      type: KuaishouMessageType.gift,
      userId: parts.isNotEmpty ? parts[0] : null,
      userName: parts.length > 1 ? parts[1] : null,
      giftId: parts.length > 2 ? parts[2] : null,
      giftName: parts.length > 3 ? parts[3] : null,
      giftCount: parts.length > 4 ? int.tryParse(parts[4]) : null,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 解析二进制点赞消息
  static KuaishouMessage _parseBinaryLikeMessage(Uint8List data) {
    final parts = _splitByNull(data);
    return KuaishouMessage(
      type: KuaishouMessageType.like,
      userId: parts.isNotEmpty ? parts[0] : null,
      userName: parts.length > 1 ? parts[1] : null,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 解析二进制用户进入消息
  static KuaishouMessage _parseBinaryUserEnterMessage(Uint8List data) {
    final parts = _splitByNull(data);
    return KuaishouMessage(
      type: KuaishouMessageType.userEnter,
      userId: parts.isNotEmpty ? parts[0] : null,
      userName: parts.length > 1 ? parts[1] : null,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 解析二进制在线人数消息
  static KuaishouMessage _parseBinaryOnlineCountMessage(Uint8List data) {
    // 在线人数通常是 4 字节整数
    if (data.length >= 4) {
      final count = data[0] << 24 | data[1] << 16 | data[2] << 8 | data[3];
      return KuaishouMessage(
        type: KuaishouMessageType.onlineCount,
        onlineCount: count,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
    }
    return KuaishouMessage(
      type: KuaishouMessageType.onlineCount,
      onlineCount: 0,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 解析二进制直播状态消息
  static KuaishouMessage _parseBinaryLiveStatusMessage(Uint8List data) {
    return KuaishouMessage(
      type: KuaishouMessageType.liveStatus,
      isLiving: data.isNotEmpty ? data[0] == 1 : false,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 按 null 字节分割数据
  static List<String> _splitByNull(Uint8List data) {
    final parts = <String>[];
    int start = 0;

    for (int i = 0; i < data.length; i++) {
      if (data[i] == 0) {
        if (i > start) {
          parts.add(utf8.decode(data.sublist(start, i), allowMalformed: true));
        }
        start = i + 1;
      }
    }

    // 添加最后一部分
    if (start < data.length) {
      parts.add(utf8.decode(data.sublist(start), allowMalformed: true));
    }

    return parts;
  }

  /// 解析 JSON 格式的聊天消息
  static KuaishouMessage _parseChatMessage(Map data) {
    return KuaishouMessage(
      type: KuaishouMessageType.chat,
      id: data['id']?.toString(),
      content: data['content']?.toString() ?? data['message']?.toString(),
      userId: data['user']?['id']?.toString() ?? data['userId']?.toString(),
      userName: data['user']?['name']?.toString() ?? data['userName']?.toString(),
      userAvatar: data['user']?['avatar']?.toString(),
      timestamp: data['timestamp'] is int ? data['timestamp'] : null,
    );
  }

  /// 解析 JSON 格式的礼物消息
  static KuaishouMessage _parseGiftMessage(Map data) {
    return KuaishouMessage(
      type: KuaishouMessageType.gift,
      id: data['id']?.toString(),
      userId: data['user']?['id']?.toString() ?? data['userId']?.toString(),
      userName: data['user']?['name']?.toString() ?? data['userName']?.toString(),
      giftId: data['giftId']?.toString() ?? data['gift']?['id']?.toString(),
      giftName: data['giftName']?.toString() ?? data['gift']?['name']?.toString(),
      giftCount: data['count'] ?? data['num'] ?? 1,
      timestamp: data['timestamp'] is int ? data['timestamp'] : null,
    );
  }

  /// 解析 JSON 格式的点赞消息
  static KuaishouMessage _parseLikeMessage(Map data) {
    return KuaishouMessage(
      type: KuaishouMessageType.like,
      id: data['id']?.toString(),
      userId: data['user']?['id']?.toString() ?? data['userId']?.toString(),
      userName: data['user']?['name']?.toString() ?? data['userName']?.toString(),
      timestamp: data['timestamp'] is int ? data['timestamp'] : null,
    );
  }

  /// 解析 JSON 格式的用户进入消息
  static KuaishouMessage _parseUserEnterMessage(Map data) {
    return KuaishouMessage(
      type: KuaishouMessageType.userEnter,
      id: data['id']?.toString(),
      userId: data['user']?['id']?.toString() ?? data['userId']?.toString(),
      userName: data['user']?['name']?.toString() ?? data['userName']?.toString(),
      timestamp: data['timestamp'] is int ? data['timestamp'] : null,
    );
  }

  /// 解析 JSON 格式的在线人数消息
  static KuaishouMessage _parseOnlineCountMessage(Map data) {
    final count = data['count'] ?? data['online'] ?? data['onlineCount'] ?? 0;
    return KuaishouMessage(
      type: KuaishouMessageType.onlineCount,
      onlineCount: count is int ? count : int.tryParse(count.toString()) ?? 0,
      timestamp: data['timestamp'] is int ? data['timestamp'] : null,
    );
  }

  /// 构建加入房间消息
  static Uint8List buildJoinRoomMessage({
    required String token,
    required String liveStreamId,
  }) {
    // 构建 JSON 格式的加入房间消息
    final json = jsonEncode({
      'type': 'join',
      'token': token,
      'liveStreamId': liveStreamId,
    });
    return utf8.encode(json);
  }

  /// 构建心跳消息
  static Uint8List buildHeartbeatMessage() {
    // 构建简单的心跳消息
    final json = jsonEncode({
      'type': 'heartbeat',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    return utf8.encode(json);
  }
}
