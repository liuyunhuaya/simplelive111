import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class KuaishouAccountService extends GetxService {
  static KuaishouAccountService get instance =>
      Get.find<KuaishouAccountService>();

  var cookie = "";
  var hasCookie = false.obs;

  @override
  void onInit() {
    cookie = LocalStorageService.instance
        .getValue(LocalStorageService.kKuaishouCookie, "");
    hasCookie.value = cookie.isNotEmpty;
    setSite();
    super.onInit();
  }

  void setSite() {
    var site = (Sites.allSites[Constant.kKuaishou]!.liveSite as KuaishouSite);
    site.cookie = cookie;
  }

  void setCookie(String cookie) {
    this.cookie = cookie;
    LocalStorageService.instance
        .setValue(LocalStorageService.kKuaishouCookie, cookie);
    hasCookie.value = cookie.isNotEmpty;
    setSite();
  }

  void clearCookie() {
    cookie = "";
    LocalStorageService.instance
        .setValue(LocalStorageService.kKuaishouCookie, "");
    hasCookie.value = false;
    setSite();
  }
}
