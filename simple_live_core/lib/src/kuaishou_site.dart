import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:simple_live_core/src/common/core_log.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:simple_live_core/src/danmaku/kuaishou_danmaku.dart';
import 'package:simple_live_core/src/interface/live_danmaku.dart';
import 'package:simple_live_core/src/interface/live_site.dart';
import 'package:simple_live_core/src/model/live_anchor_item.dart';
import 'package:simple_live_core/src/model/live_category.dart';
import 'package:simple_live_core/src/model/live_category_result.dart';
import 'package:simple_live_core/src/model/live_message.dart';
import 'package:simple_live_core/src/model/live_play_quality.dart';
import 'package:simple_live_core/src/model/live_play_url.dart';
import 'package:simple_live_core/src/model/live_room_detail.dart';
import 'package:simple_live_core/src/model/live_room_item.dart';
import 'package:simple_live_core/src/model/live_search_result.dart';

class KuaishouSite implements LiveSite {
  @override
  String id = "kuaishou";

  @override
  String name = "快手直播";

  String cookie = "";

  /// 当前使用的随机 User-Agent
  String _ua = "";

  /// 生成随机 User-Agent，参考 pure_live FakeUserAgent
  static String getRandomUserAgent() {
    final agents = [
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0",
    ];
    return agents[Random().nextInt(agents.length)];
  }

  Map<String, dynamic> get _defaultHeaders {
    if (_ua.isEmpty) {
      _ua = getRandomUserAgent();
    }
    return {
      'User-Agent': _ua,
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Connection': 'keep-alive',
    };
  }

  Map<String, dynamic> get _headers {
    var headers = Map<String, dynamic>.from(_defaultHeaders);
    if (cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  /// 从快手页面获取 Cookie（参考 pure_live 的 Cookie 自动获取机制）
  /// 返回获取到的 HTML 响应体，失败时返回 null
  Future<String?> _fetchCookie(String roomId) async {
    try {
      // 每次获取房间详情时重新随机 UA
      _ua = getRandomUserAgent();

      final dio = HttpClient.instance.dio;
      final response = await dio.get(
        'https://live.kuaishou.com/u/$roomId',
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent': _ua,
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9',
          },
          followRedirects: true,
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      // 从响应头中提取 Set-Cookie
      final setCookies = response.headers.map['set-cookie'] ?? [];
      final cookieParts = <String>[];
      String? did;

      for (var raw in setCookies) {
        // Set-Cookie 格式: name=value; Path=...; Domain=...
        final parts = raw.split(';');
        if (parts.isEmpty) continue;
        final nameValue = parts[0].trim();
        cookieParts.add(nameValue);

        // 提取 did（设备ID）
        if (nameValue.startsWith('did=')) {
          did = nameValue.substring(4);
        }
      }

      if (cookieParts.isNotEmpty) {
        cookie = cookieParts.join('; ');
        CoreLog.i("快手 Cookie 获取成功，长度=${cookie.length}");
      }

      // 如果拿到了 did，调用 registerDid
      if (did != null && did.isNotEmpty) {
        await _registerDid(did);
      }

      // 返回 HTML 响应体，供 getRoomDetail 复用，避免重复请求
      return response.data?.toString();
    } catch (e) {
      CoreLog.w("快手 Cookie 获取失败: $e");
      // Cookie 获取失败不阻塞后续流程
      return null;
    }
  }

  /// 注册设备 ID（参考 pure_live 的 registerDid）
  Future<void> _registerDid(String did) async {
    try {
      final dio = HttpClient.instance.dio;
      await dio.post(
        'https://log-sdk.ksapisrv.com/rest/log/sdk/da',
        data: {
          'did': did,
          'app': 0,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'User-Agent': _ua,
          },
          validateStatus: (status) => true,
        ),
      );
      CoreLog.i("快手 registerDid 成功: $did");
    } catch (e) {
      CoreLog.w("快手 registerDid 失败: $e");
      // registerDid 失败不影响主流程
    }
  }

  @override
  LiveDanmaku getDanmaku() => KuaishouDanmaku();

  @override
  Future<List<LiveCategory>> getCategores() async {
    const Map<int, String> categoryMap = {
      1: "热门",
      2: "网游",
      3: "单机",
      4: "手游",
      5: "棋牌",
      6: "娱乐",
      7: "综合",
      8: "文化",
    };

    List<LiveCategory> categories = [];
    for (var entry in categoryMap.entries) {
      try {
        var result = await HttpClient.instance.getJson(
          "https://live.kuaishou.com/live_api/category/data",
          queryParameters: {
            "type": entry.key,
            "page": 1,
            "size": 100,
          },
          header: _headers,
        );

        List<LiveSubCategory> subs = [];
        var list = result["data"]?["list"] as List? ?? [];
        for (var item in list) {
          subs.add(LiveSubCategory(
            id: item["id"].toString(),
            name: item["name"]?.toString() ?? "",
            parentId: entry.key.toString(),
            pic: item["poster"]?.toString(),
          ));
        }

        categories.add(LiveCategory(
          id: entry.key.toString(),
          name: entry.value,
          children: subs,
        ));
      } catch (e) {
        categories.add(LiveCategory(
          id: entry.key.toString(),
          name: entry.value,
          children: [],
        ));
      }
    }
    return categories;
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(LiveSubCategory category,
      {int page = 1}) async {
    final areaId = category.id;
    String url;
    if (areaId.length < 7) {
      url =
          "https://live.kuaishou.com/live_api/gameboard/list?filterType=0&pageSize=20&gameId=$areaId&page=$page";
    } else {
      url =
          "https://live.kuaishou.com/live_api/non-gameboard/list?filterType=0&pageSize=20&gameId=$areaId&page=$page";
    }

    var result = await HttpClient.instance.getJson(
      url,
      queryParameters: {},
      header: _headers,
    );

    var items = <LiveRoomItem>[];
    var list = result["data"]?["list"] as List? ?? [];
    for (var item in list) {
      var author = item["author"] as Map? ?? {};
      var liveStream = item["liveStream"] as Map? ?? {};
      items.add(LiveRoomItem(
        roomId: author["id"]?.toString() ?? "",
        title: liveStream["caption"]?.toString() ?? author["name"]?.toString() ?? "",
        cover: liveStream["poster"]?.toString() ?? "",
        userName: author["name"]?.toString() ?? "",
        online: _parseOnline(item["watchingCount"]),
      ));
    }

    return LiveCategoryResult(hasMore: items.length >= 20, items: items);
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    var result = await HttpClient.instance.getJson(
      "https://live.kuaishou.com/live_api/home/list",
      queryParameters: {},
      header: _headers,
    );

    var items = <LiveRoomItem>[];
    var gameList = result["data"]?["list"] as List? ?? [];
    for (var game in gameList) {
      var gameLiveInfoList = game["gameLiveInfo"] as List? ?? [];
      for (var gameLiveInfo in gameLiveInfoList) {
        var liveInfoList = gameLiveInfo["liveInfo"] as List? ?? [];
        for (var liveInfo in liveInfoList) {
          var author = liveInfo["author"] as Map? ?? {};
          var liveStream = liveInfo["liveStream"] as Map? ?? {};
          items.add(LiveRoomItem(
            roomId: author["id"]?.toString() ?? "",
            title: liveStream["caption"]?.toString() ?? author["name"]?.toString() ?? "",
            cover: liveStream["poster"]?.toString() ?? "",
            userName: author["name"]?.toString() ?? "",
            online: _parseOnline(liveInfo["watchingCount"]),
          ));
        }
      }
    }

    return LiveCategoryResult(hasMore: false, items: items);
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    // 先获取 Cookie（参考 pure_live 做法，确保后续 API 请求带有效 Cookie）
    // 同时复用返回的 HTML 响应体，避免对同一 URL 发起第二次请求
    var html = await _fetchCookie(roomId);

    // 如果 _fetchCookie 返回 null（失败），降级到原来的 getText 请求
    html ??= await HttpClient.instance.getText(
      "https://live.kuaishou.com/u/$roomId",
      queryParameters: {},
      header: _headers,
    );

    var match =
        RegExp(r'window\.__INITIAL_STATE__=(.*?);').firstMatch(html);
    if (match == null) {
      throw Exception("无法解析快手直播间数据");
    }

    var jsonStr = match.group(1)!.replaceAll('undefined', 'null');
    Map<String, dynamic> jsonObj = jsonDecode(jsonStr);

    var liveroom = jsonObj["liveroom"] as Map? ?? {};
    var playItem = liveroom["playList"]?[0] as Map? ?? {};
    var liveStream = playItem["liveStream"] as Map? ?? {};
    var author = playItem["author"] as Map? ?? {};
    var gameInfo = playItem["gameInfo"] as Map? ?? {};

    bool isLiving = playItem["isLiving"] == true;

    // 从 __INITIAL_STATE__ 中提取弹幕所需参数
    String liveStreamId = liveStream["id"]?.toString() ?? "";
    String danmakuToken = liveroom["token"]?.toString() ?? "";

    CoreLog.i("快手房间详情: roomId=$roomId, isLiving=$isLiving, "
        "liveStreamId=$liveStreamId, "
        "token=${danmakuToken.isNotEmpty ? '有' : '无'}, "
        "playUrls keys=${(liveStream['playUrls'] as Map?)?.keys.toList()}");

    return LiveRoomDetail(
      roomId: roomId,
      title: liveStream["caption"]?.toString() ??
          gameInfo["name"]?.toString() ??
          "",
      cover: liveStream["poster"]?.toString() ?? "",
      userName: author["name"]?.toString() ?? "",
      userAvatar: author["avatar"]?.toString() ?? "",
      online: _parseOnline(playItem["watchingCount"]),
      introduction: author["description"]?.toString() ?? "",
      notice: "",
      status: isLiving,
      url: "https://live.kuaishou.com/u/$roomId",
      data: liveStream["playUrls"],
      danmakuData: KuaishouDanmakuArgs(
        liveStreamId: liveStreamId,
        authorId: roomId,
        token: danmakuToken,
        cookie: cookie,
      ),
    );
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites(
      {required LiveRoomDetail detail}) async {
    List<LivePlayQuality> qualities = [];
    try {
      var playUrls = detail.data as Map?;
      if (playUrls == null) return qualities;

      // 收集所有可用的 codec 流（h264 优先，h265 作为备用）
      List<Map<String, dynamic>> allRepresentations = [];

      var h264Reps = playUrls["h264"]?["adaptationSet"]
          ?["representation"] as List?;
      if (h264Reps != null) {
        allRepresentations.addAll(h264Reps.whereType<Map<String, dynamic>>());
      }

      var h265Reps = playUrls["h265"]?["adaptationSet"]
          ?["representation"] as List?;
      if (h265Reps != null) {
        // 如果已有 h264，h265 作为备用追加
        if (allRepresentations.isNotEmpty) {
          allRepresentations.addAll(h265Reps.whereType<Map<String, dynamic>>());
        } else {
          allRepresentations = h265Reps.whereType<Map<String, dynamic>>().toList();
        }
      }

      if (allRepresentations.isEmpty) {
        CoreLog.i("快手播放数据中未找到 h264/h265 流，可用 key: ${playUrls.keys.toList()}");
        return qualities;
      }

      // 按清晰度名称分组，收集所有 CDN URL
      final qualityUrlMap = <String, List<String>>{};
      final qualitySortMap = <String, int>{};

      for (var rep in allRepresentations) {
        final urls = <String>[];

        // 主 URL
        var url = rep["url"]?.toString() ?? "";
        if (url.isNotEmpty) urls.add(url);

        // backupUrls 数组（部分快手 API 会返回多个备用 CDN）
        var backupUrls = rep["backupUrls"] as List?;
        if (backupUrls != null) {
          for (var bu in backupUrls) {
            var backupUrl = bu?.toString() ?? "";
            if (backupUrl.isNotEmpty && !urls.contains(backupUrl)) {
              urls.add(backupUrl);
            }
          }
        }

        // 单个 backupUrl 字段
        var singleBackup = rep["backupUrl"]?.toString() ?? "";
        if (singleBackup.isNotEmpty && !urls.contains(singleBackup)) {
          urls.add(singleBackup);
        }

        if (urls.isEmpty) continue;

        var name = rep["name"]?.toString() ?? "未知";
        var sort = int.tryParse(rep["level"].toString()) ?? 0;

        qualityUrlMap.putIfAbsent(name, () => []).addAll(urls);
        qualitySortMap[name] = max(qualitySortMap[name] ?? 0, sort);
      }

      for (var entry in qualityUrlMap.entries) {
        // 去重
        var uniqueUrls = entry.value.toSet().toList();
        qualities.add(LivePlayQuality(
          quality: entry.key,
          sort: qualitySortMap[entry.key] ?? 0,
          data: uniqueUrls,
        ));
      }

      qualities.sort((a, b) => b.sort.compareTo(a.sort));
    } catch (e) {
      CoreLog.error(e);
    }
    return qualities;
  }

  @override
  Future<LivePlayUrl> getPlayUrls(
      {required LiveRoomDetail detail,
      required LivePlayQuality quality}) async {
    // 快手 CDN 需要 Referer 和 Cookie 头才能正常播放
    final playHeaders = <String, String>{
      'Referer': 'https://live.kuaishou.com/',
      'Origin': 'https://live.kuaishou.com',
      'User-Agent': _ua.isNotEmpty ? _ua : getRandomUserAgent(),
    };
    if (cookie.isNotEmpty) {
      playHeaders['Cookie'] = cookie;
    }
    return LivePlayUrl(
      urls: List<String>.from(quality.data as List),
      headers: playHeaders,
    );
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword,
      {int page = 1}) async {
    try {
      var result = await HttpClient.instance.postJson(
        "https://live.kuaishou.com/live_api/search/room",
        data: {
          "keyword": keyword,
          "page": page,
          "size": 20,
          "isLive": 1,
        },
        header: _headers,
        formUrlEncoded: true,
      );

      var items = <LiveRoomItem>[];
      var list = result["data"]?["list"] as List? ?? [];
      for (var item in list) {
        var author = item["author"] as Map? ?? {};
        var liveStream = item["liveStream"] as Map? ?? {};
        items.add(LiveRoomItem(
          roomId: author["id"]?.toString() ?? "",
          title: liveStream["caption"]?.toString() ??
              item["title"]?.toString() ??
              "",
          cover: liveStream["poster"]?.toString() ??
              item["poster"]?.toString() ??
              "",
          userName: author["name"]?.toString() ?? "",
          online: _parseOnline(item["watchingCount"]),
        ));
      }
      return LiveSearchRoomResult(
        hasMore: items.length >= 20,
        items: items,
      );
    } catch (e) {
      CoreLog.error(e);
      return LiveSearchRoomResult(hasMore: false, items: []);
    }
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword,
      {int page = 1}) async {
    try {
      var result = await HttpClient.instance.postJson(
        "https://live.kuaishou.com/live_api/search/user",
        data: {
          "keyword": keyword,
          "page": page,
          "size": 20,
        },
        header: _headers,
        formUrlEncoded: true,
      );

      var items = <LiveAnchorItem>[];
      var list = result["data"]?["list"] as List? ?? [];
      for (var item in list) {
        items.add(LiveAnchorItem(
          roomId: item["id"]?.toString() ??
              item["author"]?["id"]?.toString() ??
              "",
          avatar: item["avatar"]?.toString() ??
              item["author"]?["avatar"]?.toString() ??
              "",
          userName: item["name"]?.toString() ??
              item["author"]?["name"]?.toString() ??
              "",
          liveStatus: item["isLiving"] == true ||
              item["liveStatus"] == true,
        ));
      }
      return LiveSearchAnchorResult(
        hasMore: items.length >= 20,
        items: items,
      );
    } catch (e) {
      CoreLog.error(e);
      return LiveSearchAnchorResult(hasMore: false, items: []);
    }
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    try {
      var detail = await getRoomDetail(roomId: roomId);
      return detail.status;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage(
      {required String roomId}) async {
    return [];
  }

  int _parseOnline(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? 0;
  }
}
