import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duka_pos/services/live_channel_service.dart';
import 'package:duka_pos/services/live_refresh_mixin.dart';

import 'support/harness.dart';

class _Probe extends StatefulWidget {
  const _Probe({required this.onVisibility});

  final ValueChanged<bool> onVisibility;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with LiveRefresh<_Probe> {
  @override
  Set<LiveReason> get liveReasons => const <LiveReason>{};

  @override
  Future<void> reloadFromLive() async {}

  @override
  Widget build(BuildContext context) {
    widget.onVisibility(liveIsVisible);
    return const SizedBox.shrink();
  }
}

void main() {
  testWidgets('live refresh follows shell ticker visibility',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    final values = <bool>[];

    await tester.pumpApp(
      home: TickerMode(
        enabled: false,
        child: _Probe(onVisibility: values.add),
      ),
    );
    expect(values.last, isFalse);

    await tester.pumpApp(
      home: TickerMode(
        enabled: true,
        child: _Probe(onVisibility: values.add),
      ),
    );
    await tester.pump();
    expect(values.last, isTrue);
  });
}
