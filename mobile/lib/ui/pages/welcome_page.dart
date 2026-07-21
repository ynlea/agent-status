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
      backgroundColor: context.qingya.scaffold,
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
                          icon: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 20,
                            color: context.qingya.textPrimary,
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
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                context.qingya.primarySoft,
                                context.qingya.primarySoft.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                        Image.asset(
                          QingyaAssets.catHeroWinkV3,
                          width: 215,
                          height: 202,
                          fit: BoxFit.contain,
                        ),
                        Positioned(
                          right: 15,
                          top: 32,
                          child: Icon(Icons.favorite,
                              size: 12, color: context.qingya.primary),
                        ),
                        Positioned(
                          left: 10,
                          bottom: 38,
                          child: Icon(Icons.auto_awesome,
                              size: 14,
                              color: context.qingya.primary.withValues(alpha: 0.75)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '欢迎使用 轻芽',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: context.qingya.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      '配置连接信息，开启跨设备会话监控',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13, color: context.qingya.textSecondary),
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
                          icon: QingyaTintIcon(
                            _obscure
                                ? QingyaAssets.visibilityOff
                                : QingyaAssets.visibility,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            context.qingya.device,
                            Color.lerp(
                                  context.qingya.device,
                                  const Color(0xFF1A2F9E),
                                  0.35,
                                ) ??
                                context.qingya.device,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: context.qingya.device.withValues(alpha: 0.28),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
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
                        child: Text(
                          '跳过，稍后设置',
                          style: TextStyle(
                              fontSize: 12, color: context.qingya.device),
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
        style: TextStyle(
          fontSize: 12,
          color: context.qingya.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
