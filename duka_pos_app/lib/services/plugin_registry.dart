/// A safe, declarative contract for business integrations.
///
/// Plugins are descriptions and capabilities, not downloaded Dart code. A
/// future connector can implement a capability behind the backend/API boundary
/// and be enabled only after the owner explicitly connects it. This keeps a
/// marketplace from gaining arbitrary access to the local till.
enum PluginCategory {
  ai,
  analytics,
  reporting,
  hrPayroll,
  legal,
  insuranceLoans,
  social,
}

class BusinessPlugin {
  const BusinessPlugin({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    this.available = false,
  });

  final String id;
  final String name;
  final String description;
  final PluginCategory category;
  final bool available;

  /// Reads a server-provided marketplace entry without granting it executable
  /// access to the till. Unknown or malformed entries are rejected at the
  /// boundary instead of becoming half-rendered cards.
  static BusinessPlugin? fromJson(Map<String, Object?> json) {
    final Object? rawId = json['id'];
    final Object? rawName = json['name'];
    final Object? rawDescription = json['description'];
    final Object? rawCategory = json['category'];
    if (rawId is! String ||
        rawName is! String ||
        rawDescription is! String ||
        rawCategory is! String) {
      return null;
    }
    final String id = rawId.trim();
    final String name = rawName.trim();
    final String description = rawDescription.trim();
    final String categoryName = rawCategory.trim();
    PluginCategory? category;
    for (final PluginCategory value in PluginCategory.values) {
      if (value.name == categoryName) {
        category = value;
        break;
      }
    }
    if (category == null || id.trim().isEmpty || name.trim().isEmpty) {
      return null;
    }
    return BusinessPlugin(
      id: id,
      name: name,
      description: description,
      category: category,
      available: json['available'] == true,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
        'id': id,
        'name': name,
        'description': description,
        'category': category.name,
        'available': available,
      };
}

/// The app-owned registry. Server-backed connectors can be added here without
/// changing sales, stock, or offline data paths.
class PluginRegistry {
  PluginRegistry._();

  static const List<BusinessPlugin> catalog = <BusinessPlugin>[
    BusinessPlugin(
      id: 'ai-assistant',
      name: 'AI assistant',
      description: 'Business questions and practical next steps.',
      category: PluginCategory.ai,
    ),
    BusinessPlugin(
      id: 'advanced-analytics',
      name: 'Advanced analytics',
      description: 'Deeper trends and forecasting for your shop.',
      category: PluginCategory.analytics,
    ),
    BusinessPlugin(
      id: 'payroll',
      name: 'HR & payroll',
      description: 'Staff records, attendance and payroll workflows.',
      category: PluginCategory.hrPayroll,
    ),
    BusinessPlugin(
      id: 'social-commerce',
      name: 'Social commerce',
      description: 'Connect social channels and customer conversations.',
      category: PluginCategory.social,
    ),
    BusinessPlugin(
      id: 'business-reporting',
      name: 'Business reporting',
      description: 'Export-ready reports for owners and advisors.',
      category: PluginCategory.reporting,
    ),
    BusinessPlugin(
      id: 'legal-compliance',
      name: 'Legal & compliance',
      description: 'Practical compliance workflows for your business.',
      category: PluginCategory.legal,
    ),
    BusinessPlugin(
      id: 'insurance-finance',
      name: 'Insurance & loans',
      description: 'Compare protection and financing options for your shop.',
      category: PluginCategory.insuranceLoans,
    ),
  ];

  /// Merges a remote catalogue with the built-in entries by stable id.
  ///
  /// This is the acceptance point for future marketplace APIs. It only accepts
  /// declarative metadata; plugins cannot ship or execute Dart code inside the
  /// POS process, and built-in entries cannot be replaced by a remote payload.
  static List<BusinessPlugin> mergeRemote(
    Iterable<Map<String, Object?>> remote,
  ) {
    final List<BusinessPlugin> merged = <BusinessPlugin>[...catalog];
    final Set<String> ids = merged.map((BusinessPlugin p) => p.id).toSet();
    for (final Map<String, Object?> json in remote) {
      final BusinessPlugin? plugin = BusinessPlugin.fromJson(json);
      if (plugin != null && ids.add(plugin.id)) merged.add(plugin);
    }
    return List<BusinessPlugin>.unmodifiable(merged);
  }
}
