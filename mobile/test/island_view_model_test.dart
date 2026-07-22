import 'package:flutter_test/flutter_test.dart';
import 'package:qingya/data/desktop/island_models.dart';
import 'package:qingya/domain/models.dart';

Session _s({
  required String id,
  required SessionState state,
  String machine = 'm1',
  String agent = 'claude',
  String message = 'task',
}) {
  return Session(
    machineId: machine,
    agent: agent,
    sessionId: id,
    displayName: id,
    state: state,
    message: message,
  );
}

void main() {
  test('filterSessions respects notify switches', () {
    final active = [
      _s(id: '1', state: SessionState.confirm),
      _s(id: '2', state: SessionState.working),
      _s(id: '3', state: SessionState.done),
      _s(id: '4', state: SessionState.idle),
    ];
    final filtered = IslandViewModel.filterSessions(
      activeSessions: active,
      notifyConfirm: true,
      notifyWorking: false,
      notifyDone: true,
    );
    expect(filtered.map((e) => e.sessionId).toList(), ['1', '3']);
  });

  test('shouldExpand/shouldNudge on new session or upgrade to confirm', () {
    final prev = [_s(id: '1', state: SessionState.working)];
    final nextNew = [
      _s(id: '1', state: SessionState.working),
      _s(id: '2', state: SessionState.done),
    ];
    expect(
      IslandViewModel.shouldExpand(previous: prev, next: nextNew),
      isTrue,
    );

    final nextUpgrade = [_s(id: '1', state: SessionState.confirm)];
    expect(
      IslandViewModel.shouldExpand(previous: prev, next: nextUpgrade),
      isTrue,
    );

    final nextSame = [_s(id: '1', state: SessionState.working)];
    expect(
      IslandViewModel.shouldExpand(previous: prev, next: nextSame),
      isFalse,
    );
  });

  test('fromSessions builds summary; empty still visible when strip', () {
    final vm = IslandViewModel.fromSessions([
      _s(id: '1', state: SessionState.confirm, message: 'need ok'),
      _s(id: '2', state: SessionState.working),
    ]);
    expect(vm.isVisible, isTrue);
    expect(vm.badgeCount, 2);
    expect(vm.primary?.sessionId, '1');
    expect(vm.headline, contains('另有'));

    final empty = IslandViewModel.fromSessions(
      const [],
      phase: IslandPhase.strip,
    );
    expect(empty.enabled, isTrue);
    expect(empty.phase, IslandPhase.strip);
    expect(empty.isVisible, isTrue);
  });

  test('liveSummaryLine matches monitor notification style', () {
    final vm = IslandViewModel.fromSessions(
      const [],
      phase: IslandPhase.hover,
      connected: true,
      onlineMachines: 2,
      workingSessions: 1,
      todayTokens: 172000000,
    );
    expect(vm.liveSummaryLine, '2 台在线 · 1 个进行中任务 · 172M');
    expect(IslandViewModel.formatLiveTokens(null), '—');
    expect(IslandViewModel.formatLiveTokens(0), '0');
    expect(IslandViewModel.formatLiveTokens(1500), '1.5k');
  });

  test('disabled island is hidden', () {
    final vm = IslandViewModel.fromSessions(
      [_s(id: '1', state: SessionState.confirm)],
      enabled: false,
    );
    expect(vm.isVisible, isFalse);
    expect(vm.phase, IslandPhase.hidden);
  });
}
