import 'package:flutter_test/flutter_test.dart';
import 'package:qingya/data/desktop/island_models.dart';
import 'package:qingya/domain/models.dart';

Session _session({
  required String machineId,
  required String agent,
  required String sessionId,
  required SessionState state,
  String message = 'task',
}) {
  return Session(
    machineId: machineId,
    agent: agent,
    sessionId: sessionId,
    displayName: sessionId,
    state: state,
    message: message,
  );
}

void main() {
  group('island announcement stability', () {
    test('diff isolates sessions by machine, agent, and session id', () {
      final previous = [
        _session(
          machineId: 'machine-a',
          agent: 'claude',
          sessionId: 'shared',
          state: SessionState.working,
        ),
        _session(
          machineId: 'machine-b',
          agent: 'claude',
          sessionId: 'shared',
          state: SessionState.working,
        ),
        _session(
          machineId: 'machine-a',
          agent: 'codex',
          sessionId: 'shared',
          state: SessionState.working,
        ),
      ];
      final next = [
        previous[0].copyWith(state: SessionState.confirm),
        previous[1].copyWith(state: SessionState.done),
        previous[2],
      ];

      final announcements = IslandViewModel.diffAnnouncements(
        previous: previous,
        next: next,
        notifyConfirm: true,
        notifyWorking: true,
        notifyDone: true,
      );

      expect(
        announcements.map((item) => (item.sessionKey, item.state)).toList(),
        [
          ('machine-a|claude|shared', SessionState.confirm),
          ('machine-b|claude|shared', SessionState.done),
        ],
      );
    });

    test('diff filters disabled channels and never announces idle', () {
      final announcements = IslandViewModel.diffAnnouncements(
        previous: const [],
        next: [
          _session(
            machineId: 'm',
            agent: 'claude',
            sessionId: 'done',
            state: SessionState.done,
          ),
          _session(
            machineId: 'm',
            agent: 'claude',
            sessionId: 'working',
            state: SessionState.working,
          ),
          _session(
            machineId: 'm',
            agent: 'claude',
            sessionId: 'confirm',
            state: SessionState.confirm,
          ),
          _session(
            machineId: 'm',
            agent: 'claude',
            sessionId: 'idle',
            state: SessionState.idle,
          ),
        ],
        notifyConfirm: true,
        notifyWorking: false,
        notifyDone: true,
      );

      expect(
        announcements.map((item) => item.state).toList(),
        [SessionState.confirm, SessionState.done],
      );
    });
  });

  group('island presentation reset', () {
    test('explicit reset clears stale announcement and pinned state', () {
      final session = _session(
        machineId: 'm',
        agent: 'codex',
        sessionId: 's',
        state: SessionState.confirm,
      );
      final announcement = IslandAnnouncement.fromSession(session);
      final card = IslandViewModel.fromSessions(
        [session],
        phase: IslandPhase.card,
        pinned: true,
        announcement: announcement,
      );

      final reset = card.copyWith(
        phase: IslandPhase.strip,
        pinned: false,
        clearAnnouncement: true,
      );

      expect(reset.phase, IslandPhase.strip);
      expect(reset.pinned, isFalse);
      expect(reset.announcement, isNull);
      expect(reset.isVisible, isTrue);
    });

    test('disabled rebuild drops all visible presentation state', () {
      final session = _session(
        machineId: 'm',
        agent: 'codex',
        sessionId: 's',
        state: SessionState.confirm,
      );

      final disabled = IslandViewModel.fromSessions(
        [session],
        phase: IslandPhase.card,
        pinned: true,
        enabled: false,
        announcement: IslandAnnouncement.fromSession(session),
      );

      expect(disabled.enabled, isFalse);
      expect(disabled.phase, IslandPhase.hidden);
      expect(disabled.isVisible, isFalse);
      expect(disabled.pinned, isFalse);
      expect(disabled.sessions, isEmpty);
      expect(disabled.primary, isNull);
      expect(disabled.announcement, isNull);
    });
  });
}
