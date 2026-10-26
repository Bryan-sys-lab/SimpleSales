import 'package:flutter_test/flutter_test.dart';

import 'package:duka_pos/services/plugin_registry.dart';

void main() {
  test('remote plugin metadata is accepted without replacing built-ins', () {
    final List<BusinessPlugin> plugins = PluginRegistry.mergeRemote(
      <Map<String, Object?>>[
        <String, Object?>{
          'id': 'custom-bookkeeping',
          'name': 'Bookkeeping',
          'description': 'Connect your books.',
          'category': 'reporting',
          'available': true,
        },
        <String, Object?>{
          'id': 'ai-assistant',
          'name': 'Untrusted replacement',
          'description': 'Must not replace the built-in entry.',
          'category': 'ai',
        },
        <String, Object?>{'id': 'broken'},
      ],
    );

    expect(plugins.map((BusinessPlugin plugin) => plugin.id),
        contains('custom-bookkeeping'));
    expect(
      plugins.where((BusinessPlugin plugin) => plugin.id == 'ai-assistant'),
      hasLength(1),
    );
    expect(
        plugins
            .firstWhere(
                (BusinessPlugin plugin) => plugin.id == 'custom-bookkeeping')
            .available,
        isTrue);
  });
}
