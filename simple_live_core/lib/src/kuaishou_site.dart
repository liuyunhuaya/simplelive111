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

  /// Cookie 持久化回调
  /// APP 层可以设置此回调来实现 Cookie 的持久化存储
  Function(String cookie)? onCookieChanged;

  /// Cookie 加载回调
  /// APP 层可以设置此回调来从持久化存储中加载 Cookie
  Function()? onCookieLoad;

  /// 当前使用的随机 User-Agent 信息
  Map<String, dynamic> _uaInfo = {};

  String get _ua => _uaInfo['userAgent']?.toString() ?? '';

  /// 设置 Cookie 并触发保存回调
  void setCookie(String newCookie) {
    cookie = newCookie;
    onCookieChanged?.call(cookie);
  }

  /// 初始化时加载 Cookie
  void initCookie() {
    onCookieLoad?.call();
  }

  // ============================================================
  // FakeUserAgent - 参考 pure_live 的完整实现
  // ============================================================

  static final List<String> _chromeVersions = [
    '120.0.6099.109',
    '120.0.6099.71',
    '120.0.6099.62',
    '120.0.6099.56',
    '119.0.6045.199',
    '119.0.6045.159',
    '119.0.6045.123',
    '119.0.6045.105',
    '118.0.5993.117',
    '118.0.5993.88',
    '118.0.5993.70',
    '117.0.5938.139',
    '117.0.5938.110',
    '117.0.5938.92',
    '116.0.5845.187',
    '116.0.5845.179',
    '116.0.5845.140',
    '115.0.5790.170',
    '115.0.5790.136',
    '115.0.5790.102',
    '121.0.6167.139',
    '121.0.6167.85',
    '122.0.6261.94',
    '122.0.6261.69',
    '122.0.6261.57',
    '123.0.6312.58',
    '123.0.6312.41',
  ];

  static final List<String> _safariVersions = [
    '17.2',
    '17.1.2',
    '17.1.1',
    '17.1',
    '17.0',
    '16.6',
    '16.5.2',
    '16.5.1',
    '16.5',
    '16.4',
    '16.3',
    '16.2',
  ];

  static final List<String> _edgeVersions = [
    '120.0.2210.144',
    '120.0.2210.133',
    '120.0.2210.91',
    '119.0.2151.97',
    '119.0.2151.72',
    '118.0.2088.76',
    '118.0.2088.61',
    '117.0.2045.60',
    '117.0.2045.47',
    '117.0.2045.43',
    '121.0.2277.83',
    '121.0.2277.70',
    '122.0.2365.52',
    '122.0.2365.30',
  ];

  static final List<String> _macOSDevicesVersions = [
    '10_15_7',
    '10_15_6',
    '10_15_5',
    '10_15_4',
    '10_15_3',
    '10_15_2',
    '10_15_1',
    '14_2_1',
    '14_2',
    '14_1_2',
    '14_1_1',
    '14_1',
    '14_0',
    '13_6_2',
    '13_6_1',
    '13_6',
    '13_5_2',
    '13_5_1',
    '13_5',
    '13_4_1',
    '13_4',
    '13_3_1',
    '13_3',
    '13_2_1',
  ];

  /// 生成随机 User-Agent 信息，返回 Map 格式
  /// 返回 {userAgent, device, browser, version, v}
  static Map<String, dynamic> fakeUserAgent() {
    final random = Random();
    final isMac = random.nextBool();
    final browserType = random.nextInt(3); // 0=chrome, 1=safari, 2=edge

    String userAgent;
    String device;
    String browser;
    String version;
    String v;

    if (browserType == 1 && isMac) {
      // Safari (only on Mac)
      version = _safariVersions[random.nextInt(_safariVersions.length)];
      final macVersion =
          _macOSDevicesVersions[random.nextInt(_macOSDevicesVersions.length)];
      device = 'Macintosh; Intel Mac OS X $macVersion';
      browser = 'Safari';
      v = version;
      userAgent =
          'Mozilla/5.0 ($device) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/$version Safari/605.1.15';
    } else if (browserType == 2) {
      // Edge
      version = _edgeVersions[random.nextInt(_edgeVersions.length)];
      v = version.split('.')[0];
      if (isMac) {
        final macVersion = _macOSDevicesVersions[
            random.nextInt(_macOSDevicesVersions.length)];
        device = 'Macintosh; Intel Mac OS X $macVersion';
      } else {
        device = 'Windows NT 10.0; Win64; x64';
      }
      browser = 'Edge';
      final chromeVer =
          _chromeVersions[random.nextInt(_chromeVersions.length)];
      userAgent =
          'Mozilla/5.0 ($device) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$chromeVer Safari/537.36 Edg/$version';
    } else {
      // Chrome (default)
      version = _chromeVersions[random.nextInt(_chromeVersions.length)];
      v = version.split('.')[0];
      if (isMac) {
        final macVersion = _macOSDevicesVersions[
            random.nextInt(_macOSDevicesVersions.length)];
        device = 'Macintosh; Intel Mac OS X $macVersion';
      } else {
        device = 'Windows NT 10.0; Win64; x64';
      }
      browser = 'Chrome';
      userAgent =
          'Mozilla/5.0 ($device) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$version Safari/537.36';
    }

    return {
      'userAgent': userAgent,
      'device': device,
      'browser': browser,
      'version': version,
      'v': v,
    };
  }

  /// 构建 sec-ch-ua 头
  String _buildSecChUa(Map<String, dynamic> uaInfo) {
    final browser = uaInfo['browser']?.toString() ?? 'Chrome';
    final v = uaInfo['v']?.toString() ?? '120';
    if (browser == 'Safari') {
      return '';
    } else if (browser == 'Edge') {
      return '"Chromium";v="$v", "Not A Brand";v="99", "Microsoft Edge";v="$v"';
    } else {
      return '"Chromium";v="$v", "Not A Brand";v="99", "Google Chrome";v="$v"';
    }
  }

  /// 构建 sec-ch-ua-platform 头
  String _buildSecChUaPlatform(Map<String, dynamic> uaInfo) {
    final device = uaInfo['device']?.toString() ?? '';
    if (device.contains('Macintosh')) {
      return '"macOS"';
    }
    return '"Windows"';
  }

  // ============================================================
  // Headers
  // ============================================================

  Map<String, dynamic> get _defaultHeaders {
    if (_uaInfo.isEmpty) {
      _uaInfo = fakeUserAgent();
    }
    return {
      'User-Agent': _ua,
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
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

  // ============================================================
  // getPageId - 参考 pure_live 的 pageId 生成器
  // ============================================================

  String getPageId() {
    var pageId = '';
    const charset =
        'bjectSymhasOwnProp-0123456789ABCDEFGHIJKLMNQRTUVWXYZ_dfgiklquvxz';
    for (var i = 0; i < 16; i++) {
      pageId += charset[Random().nextInt(63)];
    }
    var currentTime = DateTime.now().millisecondsSinceEpoch;
    return '${pageId}_$currentTime';
  }

  // ============================================================
  // Cookie 获取 - 从快手页面获取 Cookie（包含 did）
  // 增强版：添加重试机制和更完整的浏览器请求头
  // ============================================================

  static const int _maxRetryCount = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  Future<String?> _getCookie(String url) async {
    int retryCount = 0;

    while (retryCount < _maxRetryCount) {
      try {
        final dio = HttpClient.instance.dio;

        // 构建更完整的浏览器请求头，模拟真实浏览器
        final headers = _buildBrowserHeaders();

        // 1. 先访问快手首页获取初始 Cookie
        if (cookie.isEmpty && retryCount == 0) {
          try {
            CoreLog.i("快手: 先访问首页获取初始 Cookie");
            final homeResponse = await dio.get(
              'https://www.kuaishou.com/',
              options: Options(
                responseType: ResponseType.plain,
                headers: headers,
                followRedirects: true,
                validateStatus: (status) => status != null && status < 500,
              ),
            );
            _mergeCookiesFromResponse(homeResponse);
          } catch (e) {
            CoreLog.w("快手: 访问首页获取 Cookie 失败: $e");
          }
        }

        // 2. 访问直播间页面获取 Cookie
        final response = await dio.get(
          url,
          options: Options(
            responseType: ResponseType.plain,
            headers: {
              ...headers,
              if (cookie.isNotEmpty) 'Cookie': cookie,
            },
            followRedirects: true,
            validateStatus: (status) => status != null && status < 500,
          ),
        );

        // 检查响应状态
        final statusCode = response.statusCode ?? 0;
        if (statusCode == 501 || statusCode == 403) {
          CoreLog.w("快手: 获取 Cookie 遇到状态码 $statusCode，重试中...");
          retryCount++;
          if (retryCount < _maxRetryCount) {
            await Future.delayed(_retryDelay * retryCount);
            continue;
          }
          return null;
        }

        // 3. 合并 Cookie
        _mergeCookiesFromResponse(response);

        // 4. 从 cookie 中提取 did 并注册
        String? did = _extractDid();
        if (did != null && did.isNotEmpty) {
          await registerDid(did);
          CoreLog.i("快手 Cookie 获取成功，did=$did，cookie长度=${cookie.length}");
        } else {
          CoreLog.w("快手 Cookie 中未找到 did");
        }

        return cookie.isNotEmpty ? cookie : null;
      } catch (e) {
        CoreLog.w("快手 getCookie 失败 (重试 $retryCount): $e");
        retryCount++;
        if (retryCount < _maxRetryCount) {
          await Future.delayed(_retryDelay * retryCount);
        }
      }
    }

    return null;
  }

  /// 构建完整的浏览器请求头
  Map<String, dynamic> _buildBrowserHeaders() {
    return {
      'User-Agent': _ua,
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Accept-Encoding': 'gzip, deflate, br',
      'Connection': 'keep-alive',
      'Upgrade-Insecure-Requests': '1',
      'Sec-Fetch-Dest': 'document',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-Site': 'none',
      'Sec-Fetch-User': '?1',
      'Cache-Control': 'max-age=0',
      'sec-ch-ua':
          '"Google Chrome";v="131", "Chromium";v="131", "Not_A Brand";v="24"',
      'sec-ch-ua-mobile': '?0',
      'sec-ch-ua-platform': '"Windows"',
    };
  }

  /// 从响应中合并 Cookie
  void _mergeCookiesFromResponse(Response response) {
    final setCookies = response.headers.map['set-cookie'] ?? [];
    final cookieParts = <String>[];

    for (var raw in setCookies) {
      final parts = raw.split(';');
      if (parts.isEmpty) continue;
      final nameValue = parts[0].trim();
      if (nameValue.isNotEmpty) {
        cookieParts.add(nameValue);
      }
    }

    if (cookieParts.isNotEmpty) {
      final pageCookie = cookieParts.join('; ');
      String newCookie;
      if (cookie.isNotEmpty) {
        final existing = _parseCookieMap(cookie);
        final page = _parseCookieMap(pageCookie);
        for (var entry in page.entries) {
          existing.putIfAbsent(entry.key, () => entry.value);
        }
        newCookie = existing.entries.map((e) => '${e.key}=${e.value}').join('; ');
      } else {
        newCookie = pageCookie;
      }
      // 使用 setCookie 触发持久化回调
      setCookie(newCookie);
    }
  }

  /// 从 Cookie 中提取 did
  String? _extractDid() {
    if (cookie.isEmpty) return null;
    final match = RegExp(r'did=([^;]+)').firstMatch(cookie);
    return match?.group(1);
  }

  Map<String, String> _parseCookieMap(String cookieStr) {
    final map = <String, String>{};
    for (var part in cookieStr.split(';')) {
      final trimmed = part.trim();
      final idx = trimmed.indexOf('=');
      if (idx > 0) {
        map[trimmed.substring(0, idx)] = trimmed.substring(idx + 1);
      }
    }
    return map;
  }

  // ============================================================
  // registerDid - 参考 pure_live 的完整 JSON 注册
  // ============================================================

  Future registerDid(String did) async {
    try {
      var data = {
        'common': {
          'identity_package': {'device_id': did, 'global_id': ''},
          'app_package': {
            'language': 'zh-CN',
            'platform': 10,
            'container': 'WEB',
            'product_name': 'KS_GAME_LIVE_PC',
          },
          'device_package': {
            'os_version': 'NT 6.1',
            'model': 'Windows',
            'ua': _ua,
          },
          'need_encrypt': 'false',
          'network_package': {'type': 3},
          'h5_extra_attr':
              '{"sdk_name":"webLogger","sdk_version":"3.9.49","sdk_bundle":"log.common.js","app_version_name":"","host_product":"","resolution":"1600x900","screen_with":1600,"screen_height":900,"device_pixel_ratio":1,"domain":"https://live.kuaishou.com"}',
          'global_attr': '{}',
        },
        'logs': [
          {
            'client_timestamp': DateTime.now().millisecondsSinceEpoch,
            'client_increment_id': Random().nextInt(8999) + 1000,
            'session_id': '1eb20f88-51ac-4ecf-8dc3-ace5aefcae4f',
            'time_zone': 'GMT+08:00',
            'event_package': {
              'task_event': {
                'type': 1,
                'status': 0,
                'operation_type': 1,
                'operation_direction': 0,
                'session_id': '1eb20f88-51ac-4ecf-8dc3-ace5aefcae4f',
                'url_package': {
                  'page': 'GAME_DETAL_PAGE',
                  'identity': '5316c78e-f0b6-4be2-a076-c8f9d11ebc0a',
                  'page_type': 2,
                  'params': '{"game_id":1001,"game_name":"王者荣耀"}',
                },
                'element_package': {},
              },
            },
          },
        ],
      };

      await HttpClient.instance.postJson(
        'https://log-sdk.ksapisrv.com/rest/wd/common/log/collect/misc2?v=3.9.49&kpn=KS_GAME_LIVE_PC',
        header: _defaultHeaders,
        data: data,
      );
    } catch (e) {
      CoreLog.w("快手 registerDid 失败: $e");
    }
  }

  @override
  LiveDanmaku getDanmaku() => LiveDanmaku();

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
        title:
            liveStream["caption"]?.toString() ?? author["name"]?.toString() ?? "",
        cover: liveStream["poster"]?.toString() ??
            liveStream["coverUrl"]?.toString() ??
            item["poster"]?.toString() ??
            item["coverUrl"]?.toString() ??
            "",
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
            title: liveStream["caption"]?.toString() ??
                author["name"]?.toString() ??
                "",
            cover: liveStream["poster"]?.toString() ??
                liveStream["coverUrl"]?.toString() ??
                liveInfo["poster"]?.toString() ??
                liveInfo["coverUrl"]?.toString() ??
                "",
            userName: author["name"]?.toString() ?? "",
            online: _parseOnline(liveInfo["watchingCount"]),
          ));
        }
      }
    }

    return LiveCategoryResult(hasMore: false, items: items);
  }

  // ============================================================
  // getRoomDetail - 严格遵循 pure_live 流程
  // ============================================================

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    // 1. 生成 FakeUserAgent
    _uaInfo = fakeUserAgent();

    // 2. 构建完整 headers
    final secChUa = _buildSecChUa(_uaInfo);
    final secChUaPlatform = _buildSecChUaPlatform(_uaInfo);

    final pageUrl = 'https://live.kuaishou.com/u/$roomId';

    // 3. 用户设置的 cookie 优先（已在 cookie 字段中）

    // 4. 获取页面 cookie（包含 did）并注册
    await _getCookie(pageUrl);

    // 5. 用 HttpClient.instance.getText() 获取 HTML
    String html;
    int retryCount = 0;
    const maxRetry = 3;

    while (true) {
      try {
        final dio = HttpClient.instance.dio;
        final response = await dio.get(
          pageUrl,
          options: Options(
            responseType: ResponseType.plain,
            headers: {
              'User-Agent': _ua,
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
              'Accept-Language': 'zh-CN,zh;q=0.9',
              'Accept-Encoding': 'gzip, deflate, br',
              'Connection': 'keep-alive',
              if (secChUa.isNotEmpty) 'sec-ch-ua': secChUa,
              if (secChUa.isNotEmpty) 'sec-ch-ua-mobile': '?0',
              if (secChUa.isNotEmpty) 'sec-ch-ua-platform': secChUaPlatform,
              'sec-fetch-dest': 'document',
              'sec-fetch-mode': 'navigate',
              'sec-fetch-site': 'none',
              'sec-fetch-user': '?1',
              'upgrade-insecure-requests': '1',
              if (cookie.isNotEmpty) 'Cookie': cookie,
            },
            followRedirects: true,
            validateStatus: (status) => status != null && status < 500,
          ),
        );

        final statusCode = response.statusCode ?? 0;

        // 处理 501/403 错误，重试
        if (statusCode == 501 || statusCode == 403) {
          CoreLog.w("快手获取页面遇到状态码 $statusCode，重试 $retryCount/$maxRetry");
          retryCount++;
          if (retryCount >= maxRetry) {
            throw Exception("快手服务器返回错误 ($statusCode)，请稍后再试");
          }
          // 重新获取 Cookie
          await _getCookie(pageUrl);
          await Future.delayed(Duration(seconds: 2 * retryCount));
          continue;
        }

        html = response.data?.toString() ?? '';

        // 如果这次响应有新的 Set-Cookie，也合并进来
        _mergeCookiesFromResponse(response);

        break; // 成功获取，退出循环
      } catch (e) {
        if (retryCount >= maxRetry - 1) {
          CoreLog.w("快手获取页面HTML失败: $e");
          // 降级使用 HttpClient.instance.getText
          html = await HttpClient.instance.getText(
            pageUrl,
            queryParameters: {},
            header: _headers,
          );
          break;
        }
        retryCount++;
        CoreLog.w("快手获取页面失败，重试 $retryCount/$maxRetry: $e");
        await Future.delayed(Duration(seconds: 2 * retryCount));
      }
    }

    // 7. 解析 __INITIAL_STATE__ JSON
    var match =
        RegExp(r'window\.__INITIAL_STATE__\s*=\s*(\{.*?\});', dotAll: true)
            .firstMatch(html);
    if (match == null) {
      // 尝试另一种匹配模式
      match = RegExp(r'window\.__INITIAL_STATE__=(.*?);').firstMatch(html);
    }
    if (match == null) {
      throw Exception("无法解析快手直播间数据");
    }

    var jsonStr = match.group(1)!.replaceAll('undefined', 'null');
    Map<String, dynamic> jsonObj = jsonDecode(jsonStr);

    // 8. 提取 liveroom.playList[0] 的数据
    var liveroom = jsonObj["liveroom"] as Map? ?? {};
    var playItem = liveroom["playList"]?[0] as Map? ?? {};
    var liveStream = playItem["liveStream"] as Map? ?? {};
    var author = playItem["author"] as Map? ?? {};
    var gameInfo = playItem["gameInfo"] as Map? ?? {};

    bool isLiving = playItem["isLiving"] == true;

    // 从 __INITIAL_STATE__ 中提取弹幕所需参数
    String liveStreamId = liveStream["id"]?.toString() ?? "";
    String danmakuToken = liveroom["token"]?.toString() ?? "";

    // 尝试从页面数据中提取 WebSocket URL
    String wsUrl = "";
    // 1. 尝试从 playItem 中获取
    wsUrl = playItem["websocketUrl"]?.toString() ?? "";
    // 2. 尝试从 liveStream 中获取
    if (wsUrl.isEmpty) {
      wsUrl = liveStream["websocketUrl"]?.toString() ?? "";
    }
    // 3. 尝试从 liveroom 中获取
    if (wsUrl.isEmpty) {
      wsUrl = liveroom["websocketUrl"]?.toString() ?? "";
    }
    // 4. 尝试从整个 JSON 中搜索
    if (wsUrl.isEmpty) {
      final wsMatch = RegExp(r'"websocketUrl":"(wss://[^"]+)"').firstMatch(jsonStr);
      if (wsMatch != null) {
        wsUrl = wsMatch.group(1) ?? "";
      }
    }

    CoreLog.i("快手房间详情: roomId=$roomId, isLiving=$isLiving, "
        "liveStreamId=$liveStreamId, "
        "token=${danmakuToken.isNotEmpty ? '有' : '无'}, "
        "wsUrl=${wsUrl.isNotEmpty ? '有' : '无'}, "
        "playUrls keys=${(liveStream['playUrls'] as Map?)?.keys.toList()}");

    return LiveRoomDetail(
      roomId: roomId,
      title: liveStream["caption"]?.toString() ??
          gameInfo["name"]?.toString() ??
          "",
      cover: liveStream["poster"]?.toString() ??
          liveStream["coverUrl"]?.toString() ??
          playItem["poster"]?.toString() ??
          playItem["coverUrl"]?.toString() ??
          "",
      userName: author["name"]?.toString() ?? "",
      userAvatar: author["avatar"]?.toString() ?? "",
      online: _parseOnline(playItem["watchingCount"]),
      introduction: author["description"]?.toString() ?? "",
      notice: "",
      status: isLiving,
      url: pageUrl,
      data: liveStream["playUrls"],
      danmakuData: KuaishouDanmakuArgs(
        liveStreamId: liveStreamId,
        authorId: roomId,
        token: danmakuToken,
        cookie: cookie,
        wsUrl: wsUrl,
      ),
    );
  }

  // ============================================================
  // getPlayQualites - 简化，保留 h265 降级
  // ============================================================

  @override
  Future<List<LivePlayQuality>> getPlayQualites(
      {required LiveRoomDetail detail}) async {
    List<LivePlayQuality> qualities = [];
    try {
      var playUrls = detail.data as Map?;
      if (playUrls == null) return qualities;

      // h264 优先，h265 作为降级
      List<Map<String, dynamic>> representations = [];

      var h264Reps = playUrls["h264"]?["adaptationSet"]
          ?["representation"] as List?;
      if (h264Reps != null && h264Reps.isNotEmpty) {
        representations =
            h264Reps.whereType<Map<String, dynamic>>().toList();
      } else {
        // h264 不可用时降级到 h265
        var h265Reps = playUrls["h265"]?["adaptationSet"]
            ?["representation"] as List?;
        if (h265Reps != null && h265Reps.isNotEmpty) {
          representations =
              h265Reps.whereType<Map<String, dynamic>>().toList();
        }
      }

      if (representations.isEmpty) {
        CoreLog.i(
            "快手播放数据中未找到可用流，可用 key: ${playUrls.keys.toList()}");
        return qualities;
      }

      for (var rep in representations) {
        final urls = <String>[];

        var url = rep["url"]?.toString() ?? "";
        if (url.isNotEmpty) urls.add(url);

        var backupUrls = rep["backupUrls"] as List?;
        if (backupUrls != null) {
          for (var bu in backupUrls) {
            var backupUrl = bu?.toString() ?? "";
            if (backupUrl.isNotEmpty && !urls.contains(backupUrl)) {
              urls.add(backupUrl);
            }
          }
        }

        var singleBackup = rep["backupUrl"]?.toString() ?? "";
        if (singleBackup.isNotEmpty && !urls.contains(singleBackup)) {
          urls.add(singleBackup);
        }

        if (urls.isEmpty) continue;

        var name = rep["name"]?.toString() ?? "未知";
        var sort = int.tryParse(rep["level"].toString()) ?? 0;

        qualities.add(LivePlayQuality(
          quality: name,
          sort: sort,
          data: urls,
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
    // pure_live 对快手不传任何额外 headers，快手 CDN URL 是带签名的，
    // 额外 headers（Referer/Cookie/UA）可能导致 CDN 鉴权失败
    final urls = List<String>.from(quality.data as List);
    CoreLog.i('快手播放地址: $urls');
    return LivePlayUrl(
      urls: urls,
      headers: {},
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
              liveStream["coverUrl"]?.toString() ??
              item["poster"]?.toString() ??
              item["coverUrl"]?.toString() ??
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
          liveStatus: item["isLiving"] == true || item["liveStatus"] == true,
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
