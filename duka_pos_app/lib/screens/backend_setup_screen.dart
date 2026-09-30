import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/backend_service.dart';

/// One-time backend registration screen shown when owner enables M-Pesa.
/// Starts self-hosted OIDC login and collects the PayHero channel ID.
class BackendSetupScreen extends StatefulWidget {
  final VoidCallback? onComplete;

  const BackendSetupScreen({super.key, this.onComplete});

  @override
  State<BackendSetupScreen> createState() => _BackendSetupScreenState();
}

class _BackendSetupScreenState extends State<BackendSetupScreen> {
  final _channelId = TextEditingController();
  final _tenantId = TextEditingController();
  bool _submitting = false;
  String? _error;
  @override
  void dispose() {
    _channelId.dispose();
    _tenantId.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cid = int.tryParse(_channelId.text.trim());

    if (cid == null) {
      setState(() => _error = 'Enter a valid numeric PayHero channel ID');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await BackendService.requireSystemAdmin();
      if (_tenantId.text.trim().isEmpty) {
        throw StateError('Tenant ID is required');
      }
      await BackendService.configureTenantAsSystemAdmin(
          tenantId: _tenantId.text.trim(), channelId: cid);

      // Mark as linked locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('mpesa_enabled_local', true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('M-Pesa connected successfully')),
        );
        widget.onComplete?.call();
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Only a platform system administrator can configure the backend.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect M-Pesa'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Configure a shop backend',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'This screen is restricted to a platform system administrator. Shop admins create '
              'their own account during local setup; use this screen only to configure an existing tenant.',
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).textTheme.bodySmall?.color),
            ),
            const SizedBox(height: 24),

            TextField(
              controller: _tenantId,
              decoration: const InputDecoration(
                  labelText: 'Tenant ID *', border: OutlineInputBorder()),
              enabled: !_submitting,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _channelId,
              decoration: const InputDecoration(
                labelText: 'PayHero Channel ID *',
                hintText: '12345',
                border: OutlineInputBorder(),
                helperText:
                    'Find this in your PayHero dashboard under wallet settings',
              ),
              keyboardType: TextInputType.number,
              enabled: !_submitting,
            ),
            const SizedBox(height: 24),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),

            // Submit button
            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),

            const SizedBox(height: 16),
            Text(
              '* Required field',
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).textTheme.bodySmall?.color),
            ),
          ],
        ),
      ),
    );
  }
}
