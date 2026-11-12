import 'dart:async';

import 'package:flutter/material.dart';

import '../booth_controller.dart';
import '../theme/tb_theme.dart';

class SessionClock extends StatefulWidget {
  final BoothController controller;
  const SessionClock({super.key, required this.controller});

  @override
  State<SessionClock> createState() => _SessionClockState();
}

class _SessionClockState extends State<SessionClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _format(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final started = widget.controller.sessionStartedAt;
    final elapsed = started == null
        ? Duration.zero
        : DateTime.now().difference(started);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.timer_outlined, size: 16, color: TbColors.gold),
        const SizedBox(width: 6),
        Text(
          started == null ? '--:--' : _format(elapsed),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: TbColors.gold,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
