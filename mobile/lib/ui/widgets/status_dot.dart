import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../theme/qingya_theme.dart';

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.state, this.size = 10});

  final SessionState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    final color = switch (state) {
      SessionState.confirm => c.confirm,
      SessionState.working => c.working,
      SessionState.done => c.done,
      SessionState.idle => c.idle,
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class OnlineDot extends StatelessWidget {
  const OnlineDot({super.key, required this.online, this.size = 10});

  final bool online;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: online ? c.online : c.offline,
        shape: BoxShape.circle,
      ),
    );
  }
}
