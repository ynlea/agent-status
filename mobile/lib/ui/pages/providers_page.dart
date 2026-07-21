import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/api/rest_client.dart';
import '../../data/prefs/settings_store.dart';
import '../../data/repo/status_repository.dart';
import '../../domain/models.dart';
import '../../theme/qingya_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/assets.dart';

class ProvidersPage extends ConsumerStatefulWidget {
  const ProvidersPage({super.key, required this.machineId});

  final String machineId;

  @override
  ConsumerState<ProvidersPage> createState() => _ProvidersPageState();
}

class _ProvidersPageState extends ConsumerState<ProvidersPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  ProvidersListResponse? _data;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  RestClient? _client() {
    final s = ref.read(settingsProvider);
    if (!s.isConfigured || s.demoMode) return null;
    return RestClient(baseUrl: s.baseUrl, apiKey: s.apiKey);
  }

  bool get _ready => _data?.ready == true;

  String get _app => _tabs.index == 0 ? 'codex' : 'claude';

  Future<void> _reload({bool forceRemote = false}) async {
    final client = _client();
    if (client == null) {
      setState(() {
        _loading = false;
        _error = ref.read(settingsProvider).demoMode
            ? '演示模式不支持供应商管理'
            : '请先配置服务器';
        _data = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (forceRemote) {
        // Ask monitor to re-scan local cc-switch and push a fresh snapshot.
        final cmd = await client.runCommandAndWait(
          machineId: widget.machineId,
          app: 'all',
          type: 'refresh_providers',
          payload: const {},
          timeout: const Duration(seconds: 45),
          interval: const Duration(milliseconds: 800),
        );
        if (!cmd.isSuccess && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                cmd.errorMessage.isEmpty
                    ? '远端刷新失败：${cmd.status}'
                    : '远端刷新失败：${cmd.errorMessage}',
              ),
            ),
          );
        }
      }
      final data = await client.fetchProviders(widget.machineId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _runCommand({
    required String type,
    required Map<String, dynamic> payload,
    required String successText,
    String app = '',
  }) async {
    final client = _client();
    if (client == null) return;
    final needsCLI = type == 'switch_provider' || type == 'update_provider';
    if (needsCLI && !_ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_data?.notReadyReason.isNotEmpty == true
              ? _data!.notReadyReason
              : '未安装 cc-switch-cli，无法操作'),
        ),
      );
      return;
    }
    if (!needsCLI && _data?.canManage != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_data?.manageBlockedReason.isNotEmpty == true
              ? _data!.manageBlockedReason
              : '本机无 cc-switch 数据，无法管理配置'),
        ),
      );
      return;
    }
    for (final m in ref.read(statusRepositoryProvider).machines) {
      if (m.machineId == widget.machineId && !m.online) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('设备当前离线，命令已入队；离线超时前不会标记成功'),
          ),
        );
        break;
      }
    }
    setState(() => _busy = true);
    try {
      final cmd = await client.runCommandAndWait(
        machineId: widget.machineId,
        app: app.isEmpty ? _app : app,
        type: type,
        payload: payload,
      );
      if (!mounted) return;
      if (cmd.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successText)),
        );
        await _reload();
      } else {
        final msg = cmd.errorMessage.isEmpty ? cmd.status : cmd.errorMessage;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('失败：$msg')),
        );
        await _reload();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请求失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _switchTo(ProviderInfo p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = ctx.qingya;
        return AlertDialog(
          backgroundColor: c.card,
          surfaceTintColor: Colors.transparent,
          title: Text(
            '切换供应商',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          content: Text(
            '将 ${_app == 'codex' ? 'Codex' : 'Claude'} 切换为「${p.name}」。\n\n'
            '说明：已在运行的会话不一定立刻跟随。',
            style: TextStyle(fontSize: 13, color: c.textPrimary, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(foregroundColor: c.textSecondary),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('切换'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    await _runCommand(
      type: 'switch_provider',
      payload: {'provider_id': p.id},
      successText: '已切换为「${p.name}」',
    );
  }

  Future<void> _edit(ProviderInfo p) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.qingya.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _EditProviderSheet(app: _app, provider: p),
    );
    if (result == null) return;
    final savedName = (result['name'] as String?)?.trim();
    await _runCommand(
      type: 'update_provider',
      payload: result,
      successText:
          '已保存「${(savedName != null && savedName.isNotEmpty) ? savedName : p.name}」',
    );
  }


  Future<void> _create() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.qingya.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _EditProviderSheet(app: _app, provider: null, title: '添加供应商'),
    );
    if (result == null) return;
    await _runCommand(
      type: 'create_provider',
      payload: result,
      successText: '已添加「${result['name'] ?? ''}」',
    );
  }

  Future<void> _duplicate(ProviderInfo p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = ctx.qingya;
        return AlertDialog(
          backgroundColor: c.card,
          surfaceTintColor: Colors.transparent,
          title: Text('复制供应商', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w700)),
          content: Text('将复制「${p.name}」为新配置（不会自动切换）。', style: TextStyle(color: c.textPrimary)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('复制')),
          ],
        );
      },
    );
    if (ok != true) return;
    await _runCommand(
      type: 'duplicate_provider',
      payload: {'provider_id': p.id},
      successText: '已复制「${p.name}」',
    );
  }

  Future<void> _delete(ProviderInfo p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = ctx.qingya;
        return AlertDialog(
          backgroundColor: c.card,
          surfaceTintColor: Colors.transparent,
          title: Text('删除供应商', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w700)),
          content: Text('确定删除「${p.name}」？此操作不可撤销。', style: TextStyle(color: c.textPrimary)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    await _runCommand(
      type: 'delete_provider',
      payload: {'provider_id': p.id},
      successText: '已删除「${p.name}」',
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(statusRepositoryProvider);
    Machine? machine;
    for (final m in snapshot.machines) {
      if (m.machineId == widget.machineId) {
        machine = m;
        break;
      }
    }
    final c = context.qingya;
    final title = machine?.machineName ?? widget.machineId;
    final updated = _data?.updatedAt;

    return Scaffold(
      backgroundColor: c.scaffold,
      floatingActionButton: (_data?.canManage == true && !_busy)
          ? FloatingActionButton.extended(
              onPressed: _create,
              backgroundColor: c.device,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加'),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        size: 18, color: c.textPrimary),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '供应商 · $title',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                        ),
                        if (updated != null)
                          Text(
                            '快照 ${DateFormat('MM-dd HH:mm:ss').format(updated.toLocal())}',
                            style: TextStyle(
                              fontSize: 11,
                              color: c.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_busy)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c.device,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: '从本机重新拉取',
                    onPressed: (_busy || _loading)
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            await _reload(forceRemote: true);
                            if (mounted) setState(() => _busy = false);
                          },
                    visualDensity: VisualDensity.compact,
                    icon: QingyaTintIcon(QingyaAssets.refreshV2, size: 18),
                  ),
                ],
              ),
            ),
            if (_data != null && !_ready)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: c.deviceSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: c.device),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _data!.notReadyReason.isEmpty
                              ? '未安装 cc-switch-cli，切换/编辑已禁用'
                              : '${_data!.notReadyReason}。切换/编辑已禁用。',
                          style: TextStyle(
                            fontSize: 12,
                            color: c.textPrimary,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _AppTab(
                        label: 'Codex',
                        selected: _tabs.index == 0,
                        onTap: () => _tabs.animateTo(0),
                      ),
                    ),
                    Expanded(
                      child: _AppTab(
                        label: 'Claude',
                        selected: _tabs.index == 1,
                        onTap: () => _tabs.animateTo(1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: c.device))
                  : _error != null
                      ? EmptyState(
                          asset: QingyaAssets.catDetailPeekV3,
                          title: '加载失败',
                          subtitle: _error!,
                        )
                      : RefreshIndicator(
                          color: c.device,
                          onRefresh: () => _reload(forceRemote: true),
                          child: _buildBody(c),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(QingyaPalette c) {
    if (_data != null && !_ready) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
        children: [
          EmptyState(
            asset: QingyaAssets.catDetailPeekV3,
            title: '未安装 cc-switch-cli',
            subtitle:
                '${_data!.notReadyReason}\n下拉可让监控端重新探测；安装后请重启监控端。',
          ),
        ],
      );
    }

    final snap = _data?.forApp(_app);
    if (snap == null || snap.providers.isEmpty) {
      bool? online;
      for (final m in ref.watch(statusRepositoryProvider).machines) {
        if (m.machineId == widget.machineId) {
          online = m.online;
          break;
        }
      }
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
        children: [
          EmptyState(
            asset: QingyaAssets.catDetailPeekV3,
            title: '暂无供应商数据',
            subtitle: online == false
                ? '设备离线，或监控端尚未上报快照\n下拉可请求重新拉取'
                : '监控端可能尚未上报，下拉可强制重新拉取本机配置',
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 24),
      itemCount: snap.providers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final p = snap.providers[i];
        final current = p.id == snap.currentId;
        return _ProviderTile(
          provider: p,
          app: _app,
          current: current,
          busy: _busy,
          onSwitch: (!_ready || current || _busy) ? null : () => _switchTo(p),
          onEdit: (!(_data?.canManage == true) || _busy) ? null : () => _edit(p),
          onDuplicate: (!(_data?.canManage == true) || _busy) ? null : () => _duplicate(p),
          onDelete: (!(_data?.canManage == true) || current || _busy)
              ? null
              : () => _delete(p),
        );
      },
    );
  }
}

class _AppTab extends StatelessWidget {
  const _AppTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    return Material(
      color: selected ? c.deviceSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? c.device : c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.provider,
    required this.app,
    required this.current,
    required this.busy,
    this.onSwitch,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
  });

  final ProviderInfo provider;
  final String app;
  final bool current;
  final bool busy;
  final VoidCallback? onSwitch;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    final model = provider.modelSummary(app);
    final url = provider.baseUrl;
    final meta = <String>[
      if (model.isNotEmpty) model,
      if (url.isNotEmpty) url,
    ].join(' · ');

    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit == null || busy ? null : onEdit,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: current
                  ? c.device.withValues(alpha: 0.5)
                  : c.border.withValues(alpha: 0.7),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      provider.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  if (current)
                    Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.deviceSoft,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '当前',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: c.device,
                        ),
                      ),
                    ),
                ],
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  meta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: c.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
              const SizedBox(height: 2),
              Row(
                children: [
                  if (onSwitch != null)
                    TextButton(
                      onPressed: busy ? null : onSwitch,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('设为当前', style: TextStyle(fontSize: 12)),
                    ),
                  if (onEdit != null)
                    TextButton(
                      onPressed: busy ? null : onEdit,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('编辑', style: TextStyle(fontSize: 12)),
                    ),
                  if (onDuplicate != null)
                    TextButton(
                      onPressed: busy ? null : onDuplicate,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('复制', style: TextStyle(fontSize: 12)),
                    ),
                  if (onDelete != null)
                    TextButton(
                      onPressed: busy ? null : onDelete,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: Colors.redAccent,
                      ),
                      child: const Text('删除', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditProviderSheet extends StatefulWidget {
  const _EditProviderSheet({
    required this.app,
    this.provider,
    this.title = '编辑供应商',
  });

  final String app;
  final ProviderInfo? provider;
  final String title;

  @override
  State<_EditProviderSheet> createState() => _EditProviderSheetState();
}

class _EditProviderSheetState extends State<_EditProviderSheet> {
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;
  late final TextEditingController _modelAlias;
  late final TextEditingController _anthropicModel;
  late final TextEditingController _haiku;
  late final TextEditingController _sonnet;
  late final TextEditingController _opus;

  @override
  void initState() {
    super.initState();
    final p = widget.provider;
    _name = TextEditingController(text: p?.name ?? '');
    _baseUrl = TextEditingController(text: p?.baseUrl ?? '');
    _apiKey = TextEditingController();
    _model = TextEditingController(text: p?.model ?? '');
    _modelAlias = TextEditingController(text: p?.modelAlias ?? '');
    _anthropicModel = TextEditingController(text: p?.anthropicModel ?? '');
    _haiku = TextEditingController(text: p?.defaultHaikuModel ?? '');
    _sonnet = TextEditingController(text: p?.defaultSonnetModel ?? '');
    _opus = TextEditingController(text: p?.defaultOpusModel ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    _modelAlias.dispose();
    _anthropicModel.dispose();
    _haiku.dispose();
    _sonnet.dispose();
    _opus.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildPayload() {
    final creating = widget.provider == null;
    final p = widget.provider;
    final payload = <String, dynamic>{};
    if (!creating) {
      payload['provider_id'] = p!.id;
    }
    void putIfChanged(String key, String value, String original) {
      final v = value.trim();
      if (v.isEmpty) return;
      if (!creating && v == original.trim()) return;
      payload[key] = v;
    }

    final name = _name.text.trim();
    if (creating) {
      if (name.isEmpty) return {};
      payload['name'] = name;
    } else {
      putIfChanged('name', _name.text, p!.name);
    }
    putIfChanged('base_url', _baseUrl.text, p?.baseUrl ?? '');
    final key = _apiKey.text.trim();
    if (key.isNotEmpty) {
      payload['api_key'] = key;
    } else if (creating) {
      // allow create without key
    }
    if (widget.app == 'codex') {
      putIfChanged('model', _model.text, p?.model ?? '');
    } else {
      putIfChanged('model_alias', _modelAlias.text, p?.modelAlias ?? '');
      putIfChanged('anthropic_model', _anthropicModel.text, p?.anthropicModel ?? '');
      putIfChanged('default_haiku_model', _haiku.text, p?.defaultHaikuModel ?? '');
      putIfChanged('default_sonnet_model', _sonnet.text, p?.defaultSonnetModel ?? '');
      putIfChanged('default_opus_model', _opus.text, p?.defaultOpusModel ?? '');
    }
    return payload;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.textSecondary.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'API Key 留空表示不修改。当前项保存后会重新应用到 live 配置。',
              style: TextStyle(fontSize: 12, color: c.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 12),
            _field(c, _name, '名称'),
            _field(c, _baseUrl, 'Base URL'),
            _field(
              c,
              _apiKey,
              (widget.provider?.hasApiKey == true)
                  ? 'API Key（已配置，留空不改）'
                  : 'API Key',
              obscure: true,
            ),
            if (widget.app == 'codex') ...[
              _field(c, _model, 'Model'),
            ] else ...[
              _field(c, _modelAlias, 'Model 别名'),
              _field(c, _anthropicModel, 'ANTHROPIC_MODEL'),
              _field(c, _haiku, 'DEFAULT_HAIKU'),
              _field(c, _sonnet, 'DEFAULT_SONNET'),
              _field(c, _opus, 'DEFAULT_OPUS'),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                final payload = _buildPayload();
                final creating = widget.provider == null;
                if (creating) {
                  if ((payload['name'] as String?)?.trim().isNotEmpty != true) {
                    return;
                  }
                  Navigator.pop(context, payload);
                  return;
                }
                if (payload.length <= 1) {
                  Navigator.pop(context);
                  return;
                }
                Navigator.pop(context, payload);
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('保存'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(foregroundColor: c.textSecondary),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    QingyaPalette c,
    TextEditingController ctl,
    String label, {
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctl,
        obscureText: obscure,
        style: TextStyle(fontSize: 14, color: c.textPrimary),
        cursorColor: c.device,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 13, color: c.textSecondary),
          filled: true,
          fillColor: c.scaffold,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }
}
