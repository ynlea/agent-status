import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/prefs/settings_store.dart';
import '../../theme/qingya_theme.dart';
import '../widgets/assets.dart';

class WelcomePage extends ConsumerWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const _ConnectionSetup(showBack: false);
  }
}

class SetupPage extends ConsumerWidget {
  const SetupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const _ConnectionSetup(showBack: true);
  }
}

class _ConnectionSetup extends ConsumerStatefulWidget {
  const _ConnectionSetup({required this.showBack});

  final bool showBack;

  @override
  ConsumerState<_ConnectionSetup> createState() => _ConnectionSetupState();
}

class _ConnectionSetupState extends ConsumerState<_ConnectionSetup> {
  late final TextEditingController _url;
  late final TextEditingController _key;
  bool _obscure = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _url = TextEditingController(text: settings.baseUrl);
    _key = TextEditingController(text: settings.apiKey);
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_url.text.trim().isEmpty || _key.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写服务地址和访问密钥')),
      );
      return;
    }
    setState(() => _saving = true);
    final current = ref.read(settingsProvider);
    await ref.read(settingsProvider.notifier).save(
          current.copyWith(
            baseUrl: _url.text.trim(),
            apiKey: _key.text.trim(),
            demoMode: false,
          ),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: QingyaColors.scaffold,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 4, 28, 24),
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(minHeight: constraints.maxHeight - 28),
                child: Column(
                  children: [
                    if (widget.showBack)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          onPressed: () => context.pop(),
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 20,
                            color: QingyaColors.textPrimary,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 18),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 236,
                          height: 192,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [Color(0xFFFFF0E7), Color(0x00FFF0E7)],
                            ),
                          ),
                        ),
                        Image.asset(
                          QingyaAssets.catHeroWinkV3,
                          width: 215,
                          height: 202,
                          fit: BoxFit.contain,
                        ),
                        const Positioned(
                          right: 15,
                          top: 32,
                          child: Icon(Icons.favorite,
                              size: 12, color: Color(0xFFFFA5A0)),
                        ),
                        const Positioned(
                          left: 10,
                          bottom: 38,
                          child: Icon(Icons.auto_awesome,
                              size: 14, color: Color(0xFFFFC6B7)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '欢迎使用 轻芽',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: QingyaColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 9),
                    const Text(
                      '配置连接信息，开启跨设备任务管理',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13, color: QingyaColors.textSecondary),
                    ),
                    const SizedBox(height: 28),
                    const _InputLabel('服务地址'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _url,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                          hintText: 'https://api.example.com'),
                    ),
                    const SizedBox(height: 16),
                    const _InputLabel('访问密钥'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _key,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        hintText: '请输入访问密钥',
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Image.asset(
                            _obscure
                                ? QingyaAssets.visibilityOff
                                : QingyaAssets.visibility,
                            width: 20,
                            height: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7184FF), Color(0xFF2854F5)],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x3D4D6DFF),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: TextButton(
                          onPressed: _saving ? null : _save,
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.white),
                          child: Text(
                            _saving ? '保存中…' : '保存并连接',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                    if (!widget.showBack) ...[
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () async {
                          await ref
                              .read(settingsProvider.notifier)
                              .enableDemo();
                          if (context.mounted) context.go('/home');
                        },
                        child: const Text(
                          '跳过，稍后设置',
                          style: TextStyle(
                              fontSize: 12, color: QingyaColors.device),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InputLabel extends StatelessWidget {
  const _InputLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: QingyaColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
