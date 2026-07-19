import 'package:flutter_test/flutter_test.dart';
import 'package:qingya/domain/models.dart';

void main() {
  test('active session sort order', () {
    final sessions = [
      Session(
        machineId: 'm',
        agent: 'claude',
        sessionId: '1',
        displayName: 'a',
        state: SessionState.done,
        message: 'd',
      ),
      Session(
        machineId: 'm',
        agent: 'claude',
        sessionId: '2',
        displayName: 'b',
        state: SessionState.confirm,
        message: 'c',
      ),
      Session(
        machineId: 'm',
        agent: 'codex',
        sessionId: '3',
        displayName: 'c',
        state: SessionState.working,
        message: 'w',
      ),
      Session(
        machineId: 'm',
        agent: 'claude',
        sessionId: '4',
        displayName: 'idle',
        state: SessionState.idle,
        message: '',
      ),
    ];
    final active = sortActiveSessions(sessions);
    expect(active.map((e) => e.sessionId).toList(), ['2', '3', '1']);
  });
}
