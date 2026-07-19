class QingyaAssets {
  static const catAvatar = 'assets/images/cat/cat_avatar.png';
  static const catWelcome = 'assets/images/cat/cat_welcome.png';
  static const catEmptyRest = 'assets/images/cat/cat_empty_rest.png';
  static const catEmptyDevices = 'assets/images/cat/cat_empty_devices.png';
  static const catOffline = 'assets/images/cat/cat_offline.png';
  static const catError = 'assets/images/cat/cat_error.png';
  static const catAppIcon = 'assets/images/cat/cat_app_icon.png';
  static const catWorking = 'assets/images/cat/cat_working.png';
  static const catConfirm = 'assets/images/cat/cat_confirm.png';
  static const catDone = 'assets/images/cat/cat_done.png';
  static const catSearchEmpty = 'assets/images/cat/cat_search_empty.png';
  static const catSleepNight = 'assets/images/cat/cat_sleep_night.png';
  static const catHeroWinkV3 = 'assets/images/cat/cat_hero_wink_v3.png';
  static const catBrandAvatarV3 = 'assets/images/cat/cat_brand_avatar_v3.png';
  static const catEmptySleepV3 = 'assets/images/cat/cat_empty_sleep_v3.png';
  static const catDetailPeekV3 = 'assets/images/cat/cat_detail_peek_v3.png';
  static const catWhiteBustV3 = 'assets/images/cat/cat_white_bust_v3.png';
  static const catGrayTabbyBustV3 =
      'assets/images/cat/cat_gray_tabby_bust_v3.png';
  static const catOrangeTabbyBustV3 =
      'assets/images/cat/cat_orange_tabby_bust_v3.png';
  static const catRagdollBustV3 = 'assets/images/cat/cat_ragdoll_bust_v3.png';

  static const navHome = 'assets/images/nav/ic_nav_home.png';
  static const navDevices = 'assets/images/nav/ic_nav_devices.png';
  static const navSettings = 'assets/images/nav/ic_nav_settings.png';
  static const navHomeV2 = 'assets/images/nav/ic_nav_home_paw_v2.png';
  static const navDevicesV2 = 'assets/images/nav/ic_nav_devices_monitor_v2.png';
  static const navSettingsV2 = 'assets/images/nav/ic_nav_settings_gear_v2.png';
  static const refreshV2 = 'assets/images/nav/ic_refresh_v2.png';
  static const bell = 'assets/images/nav/ic_bell.png';
  static const back = 'assets/images/nav/ic_back.png';
  static const chevron = 'assets/images/nav/ic_chevron_right.png';

  static const serverUrl = 'assets/images/settings/ic_server_url.png';
  static const key = 'assets/images/settings/ic_key.png';
  static const themeSystem = 'assets/images/settings/ic_theme_system.png';
  static const visibility = 'assets/images/settings/ic_visibility.png';
  static const visibilityOff = 'assets/images/settings/ic_visibility_off.png';

  static const notifyConfirm = 'assets/images/status/ic_notify_confirm.png';
  static const notifyWorking = 'assets/images/status/ic_notify_working.png';
  static const notifyDone = 'assets/images/status/ic_notify_done.png';
  static const linkOk = 'assets/images/status/ic_link_ok.png';
  static const linkOff = 'assets/images/status/ic_link_off.png';

  static const refresh = 'assets/images/action/ic_refresh.png';
  static const expand = 'assets/images/action/ic_expand.png';
  static const collapse = 'assets/images/action/ic_collapse.png';
  static const warning = 'assets/images/action/ic_warning.png';

  static const deviceLaptop = 'assets/images/device/device_laptop.png';
  static const deviceDesktop = 'assets/images/device/device_desktop.png';
  static const deviceServer = 'assets/images/device/device_server.png';
  static const deviceUnknown = 'assets/images/device/device_unknown.png';
  static const deviceThinkpadV2 = 'assets/images/device/device_thinkpad_v2.png';
  static const deviceMacbookV2 = 'assets/images/device/device_macbook_v2.png';
  static const deviceMacminiV2 = 'assets/images/device/device_macmini_v2.png';
  static const deviceUbuntuServerV2 =
      'assets/images/device/device_ubuntu_server_v2.png';
  static const deviceWindowsPcV2 =
      'assets/images/device/device_windows_pc_v2.png';
  static const deviceLaptopV2 = 'assets/images/device/device_laptop_v2.png';
  static const deviceServerV2 = 'assets/images/device/device_server_v2.png';
  static const deviceUnknownV2 = 'assets/images/device/device_unknown_v2.png';

  /// 根据稳定字符串分配不同布偶猫动作，避免卡片重复（文件名历史遗留，内容均为浅色布偶）。
  static String catForSeed(String seed) {
    const cats = [
      catWhiteBustV3,
      catGrayTabbyBustV3,
      catOrangeTabbyBustV3,
      catRagdollBustV3,
    ];
    final index = seed.codeUnits.fold<int>(0, (sum, value) => sum + value);
    return cats[index % cats.length];
  }

  static String agent(String agent) {
    switch (agent.toLowerCase()) {
      case 'claude':
        return 'assets/images/agent/agent_claude.png';
      case 'codex':
        return 'assets/images/agent/agent_codex.png';
      default:
        return 'assets/images/agent/agent_unknown.png';
    }
  }

  /// 透明底官方字形，适合小尺寸色标内嵌。
  static String agentGlyph(String agent) {
    switch (agent.toLowerCase()) {
      case 'claude':
        return 'assets/images/agent/agent_claude_glyph.png';
      case 'codex':
        return 'assets/images/agent/agent_codex_glyph.png';
      default:
        return 'assets/images/agent/agent_unknown.png';
    }
  }
}
