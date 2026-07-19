import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../theme/qingya_theme.dart';

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.state, this.size = 10});

  final SessionState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      SessionState.confirm => QingyaColors.confirm,
      SessionState.working => QingyaColors.working,
      SessionState.done => QingyaColors.done,
      SessionState.idle => QingyaColors.idle,
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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: online ? QingyaColors.online : QingyaColors.offline,
        shape: BoxShape.circle,
      ),
    );
  }
}
