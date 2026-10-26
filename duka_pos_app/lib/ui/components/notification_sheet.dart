import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../services/notification_service.dart';
import '../../theme/app_spacing.dart';

Future<String?> showNotificationSheet(
  BuildContext context, {
  required int staffId,
  required String role,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _NotificationSheet(staffId: staffId, role: role),
  );
}

class _NotificationSheet extends StatefulWidget {
  const _NotificationSheet({required this.staffId, required this.role});

  final int staffId;
  final String role;

  @override
  State<_NotificationSheet> createState() => _NotificationSheetState();
}

class _NotificationSheetState extends State<_NotificationSheet> {
  late Future<List<ScheduledNotification>> _future;

  @override
  void initState() {
    super.initState();
    _future = NotificationService().runLocalChecks(
      staffId: widget.staffId,
      role: widget.role,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spacing = AppSpacing.of(context);
    return Padding(
      padding: EdgeInsets.all(spacing.lg),
      child: FutureBuilder<List<ScheduledNotification>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) {
              return Text(l10n.notificationsLoadFailed);
            }
            return const Center(child: CircularProgressIndicator());
          }
          final notifications = snapshot.data!;
          if (notifications.isEmpty) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: spacing.xl),
              child: Center(child: Text(l10n.notificationsEmpty)),
            );
          }
          return ListView.separated(
            shrinkWrap: true,
            itemCount: notifications.length,
            separatorBuilder: (_, __) => SizedBox(height: spacing.xs),
            itemBuilder: (_, index) {
              final notification = notifications[index];
              return ListTile(
                leading: const Icon(Icons.notifications_none),
                title: Text(notification.title),
                subtitle: Text(notification.body),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(
                  context,
                  notification.destination,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
