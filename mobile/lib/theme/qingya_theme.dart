import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 浅色静态别名，仅供 ThemeData 构建与迁移前兼容；UI 请用 [BuildContext.qingya]。
class QingyaColors {
  static const scaffold = Color(0xFFFFF9F5);
  static const card = Color(0xFFFFFEFD);
  static const primary = Color(0xFFFF7F73);
  static const primaryDark = Color(0xFFE9685F);
  static const primarySoft = Color(0xFFFFEEE9);
  static const device = Color(0xFF6078FF);
  static const deviceSoft = Color(0xFFEEF1FF);
  static const textPrimary = Color(0xFF342E2A);
  static const textSecondary = Color(0xFF9D948E);
  static const confirm = Color(0xFFFF6B63);
  static const confirmSoft = Color(0xFFFFE9E6);
  static const working = Color(0xFFFFB23E);
  static const workingSoft = Color(0xFFFFF2D8);
  static const done = Color(0xFF67C77D);
  static const doneSoft = Color(0xFFE9F7EC);
  static const idle = Color(0xFFC6BFB9);
  static const idleSoft = Color(0xFFF4F1EE);
  static const online = Color(0xFF5BC56D);
  static const offline = Color(0xFFFFA21A);
  static const divider = Color(0xFFF2EAE5);
  static const navInactive = Color(0xFFAFA9A4);
  static const shadow = Color(0x120F0703);
  static const border = Color(0xFFF0E4DE);
}

/// 随主题切换的语义色板。
@immutable
class QingyaPalette extends ThemeExtension<QingyaPalette> {
  const QingyaPalette({
    required this.scaffold,
    required this.card,
    required this.primary,
    required this.primaryDark,
    required this.primarySoft,
    required this.device,
    required this.deviceSoft,
    required this.textPrimary,
    required this.textSecondary,
    required this.confirm,
    required this.confirmSoft,
    required this.working,
    required this.workingSoft,
    required this.done,
    required this.doneSoft,
    required this.idle,
    required this.idleSoft,
    required this.online,
    required this.offline,
    required this.divider,
    required this.navInactive,
    required this.shadow,
    required this.border,
    required this.switchTrackOff,
    required this.bubbleFill,
    required this.agentClaude,
    required this.agentClaudeSoft,
    required this.agentCodex,
    required this.agentCodexSoft,
    required this.agentOpencode,
    required this.agentOpencodeSoft,
  });

  final Color scaffold;
  final Color card;
  final Color primary;
  final Color primaryDark;
  final Color primarySoft;
  final Color device;
  final Color deviceSoft;
  final Color textPrimary;
  final Color textSecondary;
  final Color confirm;
  final Color confirmSoft;
  final Color working;
  final Color workingSoft;
  final Color done;
  final Color doneSoft;
  final Color idle;
  final Color idleSoft;
  final Color online;
  final Color offline;
  final Color divider;
  final Color navInactive;
  final Color shadow;
  final Color border;
  final Color switchTrackOff;
  final Color bubbleFill;
  final Color agentClaude;
  final Color agentClaudeSoft;
  final Color agentCodex;
  final Color agentCodexSoft;
  final Color agentOpencode;
  final Color agentOpencodeSoft;

  static const light = QingyaPalette(
    scaffold: QingyaColors.scaffold,
    card: QingyaColors.card,
    primary: QingyaColors.primary,
    primaryDark: QingyaColors.primaryDark,
    primarySoft: QingyaColors.primarySoft,
    device: QingyaColors.device,
    deviceSoft: QingyaColors.deviceSoft,
    textPrimary: QingyaColors.textPrimary,
    textSecondary: QingyaColors.textSecondary,
    confirm: QingyaColors.confirm,
    confirmSoft: QingyaColors.confirmSoft,
    working: QingyaColors.working,
    workingSoft: QingyaColors.workingSoft,
    done: QingyaColors.done,
    doneSoft: QingyaColors.doneSoft,
    idle: QingyaColors.idle,
    idleSoft: QingyaColors.idleSoft,
    online: QingyaColors.online,
    offline: QingyaColors.offline,
    divider: QingyaColors.divider,
    navInactive: QingyaColors.navInactive,
    shadow: QingyaColors.shadow,
    border: QingyaColors.border,
    switchTrackOff: Color(0xFFE7E3E0),
    bubbleFill: Color(0xFFFFFFFF),
    agentClaude: Color(0xFFD97757),
    agentClaudeSoft: Color(0xFFFFF1EB),
    agentCodex: Color(0xFF10A37F),
    agentCodexSoft: Color(0xFFE6F7F2),
    agentOpencode: Color(0xFF6078FF),
    agentOpencodeSoft: Color(0xFFEEF1FF),
  );

  /// 在现有浅色品牌感上推导的深色 token。
  static const dark = QingyaPalette(
    scaffold: Color(0xFF1C1917),
    card: Color(0xFF2A2624),
    primary: Color(0xFFFF8F84),
    primaryDark: Color(0xFFE9685F),
    primarySoft: Color(0xFF3D2A28),
    device: Color(0xFF7B8FFF),
    deviceSoft: Color(0xFF2A3048),
    textPrimary: Color(0xFFF5EDE6),
    textSecondary: Color(0xFFA89F97),
    confirm: Color(0xFFFF7A73),
    confirmSoft: Color(0xFF3D2826),
    working: Color(0xFFFFC04D),
    workingSoft: Color(0xFF3D3220),
    done: Color(0xFF74D489),
    doneSoft: Color(0xFF243528),
    idle: Color(0xFF8A837C),
    idleSoft: Color(0xFF32302E),
    online: Color(0xFF5BC56D),
    offline: Color(0xFFFFA21A),
    divider: Color(0xFF3A3532),
    navInactive: Color(0xFF7A736C),
    shadow: Color(0x66000000),
    border: Color(0xFF3F3935),
    switchTrackOff: Color(0xFF4A4541),
    bubbleFill: Color(0xFF2A2624),
    agentClaude: Color(0xFFE08A6C),
    agentClaudeSoft: Color(0xFF3D2C26),
    agentCodex: Color(0xFF2DB894),
    agentCodexSoft: Color(0xFF1E332C),
    agentOpencode: Color(0xFF7B8FFF),
    agentOpencodeSoft: Color(0xFF2A3048),
  );

  @override
  QingyaPalette copyWith({
    Color? scaffold,
    Color? card,
    Color? primary,
    Color? primaryDark,
    Color? primarySoft,
    Color? device,
    Color? deviceSoft,
    Color? textPrimary,
    Color? textSecondary,
    Color? confirm,
    Color? confirmSoft,
    Color? working,
    Color? workingSoft,
    Color? done,
    Color? doneSoft,
    Color? idle,
    Color? idleSoft,
    Color? online,
    Color? offline,
    Color? divider,
    Color? navInactive,
    Color? shadow,
    Color? border,
    Color? switchTrackOff,
    Color? bubbleFill,
    Color? agentClaude,
    Color? agentClaudeSoft,
    Color? agentCodex,
    Color? agentCodexSoft,
    Color? agentOpencode,
    Color? agentOpencodeSoft,
  }) {
    return QingyaPalette(
      scaffold: scaffold ?? this.scaffold,
      card: card ?? this.card,
      primary: primary ?? this.primary,
      primaryDark: primaryDark ?? this.primaryDark,
      primarySoft: primarySoft ?? this.primarySoft,
      device: device ?? this.device,
      deviceSoft: deviceSoft ?? this.deviceSoft,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      confirm: confirm ?? this.confirm,
      confirmSoft: confirmSoft ?? this.confirmSoft,
      working: working ?? this.working,
      workingSoft: workingSoft ?? this.workingSoft,
      done: done ?? this.done,
      doneSoft: doneSoft ?? this.doneSoft,
      idle: idle ?? this.idle,
      idleSoft: idleSoft ?? this.idleSoft,
      online: online ?? this.online,
      offline: offline ?? this.offline,
      divider: divider ?? this.divider,
      navInactive: navInactive ?? this.navInactive,
      shadow: shadow ?? this.shadow,
      border: border ?? this.border,
      switchTrackOff: switchTrackOff ?? this.switchTrackOff,
      bubbleFill: bubbleFill ?? this.bubbleFill,
      agentClaude: agentClaude ?? this.agentClaude,
      agentClaudeSoft: agentClaudeSoft ?? this.agentClaudeSoft,
      agentCodex: agentCodex ?? this.agentCodex,
      agentCodexSoft: agentCodexSoft ?? this.agentCodexSoft,
      agentOpencode: agentOpencode ?? this.agentOpencode,
      agentOpencodeSoft: agentOpencodeSoft ?? this.agentOpencodeSoft,
    );
  }

  @override
  QingyaPalette lerp(ThemeExtension<QingyaPalette>? other, double t) {
    if (other is! QingyaPalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return QingyaPalette(
      scaffold: mix(scaffold, other.scaffold),
      card: mix(card, other.card),
      primary: mix(primary, other.primary),
      primaryDark: mix(primaryDark, other.primaryDark),
      primarySoft: mix(primarySoft, other.primarySoft),
      device: mix(device, other.device),
      deviceSoft: mix(deviceSoft, other.deviceSoft),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      confirm: mix(confirm, other.confirm),
      confirmSoft: mix(confirmSoft, other.confirmSoft),
      working: mix(working, other.working),
      workingSoft: mix(workingSoft, other.workingSoft),
      done: mix(done, other.done),
      doneSoft: mix(doneSoft, other.doneSoft),
      idle: mix(idle, other.idle),
      idleSoft: mix(idleSoft, other.idleSoft),
      online: mix(online, other.online),
      offline: mix(offline, other.offline),
      divider: mix(divider, other.divider),
      navInactive: mix(navInactive, other.navInactive),
      shadow: mix(shadow, other.shadow),
      border: mix(border, other.border),
      switchTrackOff: mix(switchTrackOff, other.switchTrackOff),
      bubbleFill: mix(bubbleFill, other.bubbleFill),
      agentClaude: mix(agentClaude, other.agentClaude),
      agentClaudeSoft: mix(agentClaudeSoft, other.agentClaudeSoft),
      agentCodex: mix(agentCodex, other.agentCodex),
      agentCodexSoft: mix(agentCodexSoft, other.agentCodexSoft),
      agentOpencode: mix(agentOpencode, other.agentOpencode),
      agentOpencodeSoft: mix(agentOpencodeSoft, other.agentOpencodeSoft),
    );
  }
}

extension QingyaThemeContext on BuildContext {
  QingyaPalette get qingya =>
      Theme.of(this).extension<QingyaPalette>() ?? QingyaPalette.light;
}

class QingyaTheme {
  static ThemeData light() => _build(Brightness.light, QingyaPalette.light);

  static ThemeData dark() => _build(Brightness.dark, QingyaPalette.dark);

  static ThemeData _build(Brightness brightness, QingyaPalette p) {
    final isLight = brightness == Brightness.light;
    // Windows 桌面优先系统 UI 字体（ClearType 更清晰）；移动端保留 Noto 回退。
    final desktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows);
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: p.primary,
        onPrimary: Colors.white,
        secondary: p.device,
        onSecondary: Colors.white,
        surface: p.card,
        onSurface: p.textPrimary,
        error: p.confirm,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: p.scaffold,
      fontFamily: desktop ? 'Microsoft YaHei UI' : null,
      fontFamilyFallback: desktop
          ? const [
              'Microsoft YaHei',
              'Segoe UI',
              'Segoe UI Variable',
              'PingFang SC',
              'Noto Sans CJK SC',
            ]
          : const ['Noto Sans CJK SC', 'Noto Sans SC', 'PingFang SC'],
      extensions: [p],
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: p.scaffold,
        foregroundColor: p.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: p.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      iconTheme: IconThemeData(color: p.textPrimary),
      primaryIconTheme: IconThemeData(color: p.device),
      dividerColor: p.divider,
      dividerTheme: DividerThemeData(color: p.divider, thickness: 1, space: 1),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary),
      cardTheme: CardThemeData(
        color: p.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.border.withValues(alpha: 0.75)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: p.border.withValues(alpha: 0.85)),
        ),
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: p.textPrimary,
        ),
        contentTextStyle: TextStyle(
          fontSize: 14,
          color: p.textPrimary,
          height: 1.4,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.card,
        contentTextStyle: TextStyle(color: p.textPrimary, fontSize: 13),
        actionTextColor: p.device,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: p.border),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.card,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: p.textPrimary, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.device,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? p.card : p.idleSoft,
        hintStyle: TextStyle(color: p.textSecondary, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: p.device, width: 1.5),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? p.device
              : p.switchTrackOff;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.device,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return p.deviceSoft;
            }
            return isLight ? p.card : p.idleSoft;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return p.device;
            }
            return p.textSecondary;
          }),
          side: WidgetStatePropertyAll(BorderSide(color: p.border)),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          visualDensity: VisualDensity.compact,
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
        ),
      ),
    );
  }
}

/// 单色 PNG 图标按主题着色（chevron / refresh / visibility 等）。
class QingyaTintIcon extends StatelessWidget {
  const QingyaTintIcon(
    this.asset, {
    super.key,
    this.size = 16,
    this.color,
  });

  final String asset;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.qingya.textSecondary;
    return ColorFiltered(
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
      child: Image.asset(asset, width: size, height: size),
    );
  }
}
