import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/controllers/execution_controller.dart';
import '../../state/controllers/hid_status_controller.dart';
import '../../widgets/confirm_dialog.dart';

const appUpdatesChannel = MethodChannel('org.kaijinlab.tap_ducky/updates');

class AppUpdatesScreen extends ConsumerStatefulWidget {
  const AppUpdatesScreen({super.key});

  @override
  ConsumerState<AppUpdatesScreen> createState() => _AppUpdatesScreenState();
}

class _AppUpdatesScreenState extends ConsumerState<AppUpdatesScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _settings;
  Map<String, dynamic>? _release;
  bool _checking = false;
  bool _installing = false;
  bool _changingPreference = false;
  String? _message;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_checking) _refreshSettings();
  }

  Future<void> _refreshSettings() async {
    try {
      final settings = await appUpdatesChannel.invokeMapMethod<String, dynamic>(
        'settings',
      );
      if (mounted) setState(() => _settings = settings);
    } catch (_) {
      // A failed refresh must not replace the last known settings.
    }
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _release = null;
      _message = null;
      _failed = false;
    });
    try {
      await _refreshSettings();
      final release = await appUpdatesChannel.invokeMapMethod<String, dynamic>(
        'check',
      );
      if (!mounted) return;
      setState(() {
        _release = release;
        if (release == null) _message = 'No newer release found.';
      });
    } catch (error) {
      _showError(error, 'Could not check GitHub for updates.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _changingPreference = true);
    try {
      final settings = await appUpdatesChannel.invokeMapMethod<String, dynamic>(
        'setEnabled',
        value,
      );
      if (mounted) setState(() => _settings = settings);
    } catch (error) {
      _showError(error, 'Could not change update notifications.');
    } finally {
      if (mounted) setState(() => _changingPreference = false);
    }
  }

  Future<void> _install(String version) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Download update from GitHub?',
      message:
          'This downloads an APK from GitHub outside F-Droid\'s build and verification process. If you installed TapDucky through F-Droid, update it there instead.',
      confirmLabel: 'Download APK',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _installing = true;
      _message = null;
      _failed = false;
    });
    try {
      final opened = await appUpdatesChannel.invokeMethod<bool>(
        'install',
        version,
      );
      if (!mounted) return;
      setState(
        () => _message = opened == true
            ? 'Confirm the update in the Android installer.'
            : 'Allow installs from TapDucky in Android Settings, then try again.',
      );
    } catch (error) {
      _showError(error, 'Could not download or open the update.');
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  void _showError(Object error, String fallback) {
    if (!mounted) return;
    setState(() {
      _failed = true;
      _message = error is PlatformException
          ? error.message ?? fallback
          : fallback;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hid = ref.watch(hidStatusControllerProvider);
    final running = ref.watch(
      executionControllerProvider.select((s) => s.isRunning),
    );
    final busy = _checking || _installing;
    final installBlocked = running || hid.sessionArmed || hid.usbRestoring;
    final release = _release;
    final installed = _settings?['installed'];
    final notificationsEnabled = _settings?['enabled'] == true;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: const Text('App updates'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (installed is String)
              ListTile(
                title: const Text('Installed version'),
                subtitle: Text(installed),
              ),
            if (release != null)
              ListTile(
                title: Text('Version ${release['version']} available'),
                subtitle: release['installable'] != true
                    ? const Text('No verified APK for this device.')
                    : installBlocked
                    ? const Text('Disarm the USB session before updating.')
                    : null,
              ),
            if (busy) ...[
              Text(
                _installing
                    ? 'Downloading and verifying the APK...'
                    : 'Checking GitHub...',
              ),
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (_message case final String message)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    style: _failed
                        ? TextStyle(color: theme.colorScheme.error)
                        : null,
                  ),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (release?['installable'] == true)
                  FilledButton.icon(
                    onPressed: busy || installBlocked
                        ? null
                        : () => _install(release!['version'] as String),
                    icon: const Icon(Icons.system_update),
                    label: const Text('Download and install'),
                  ),
                OutlinedButton.icon(
                  onPressed: busy ? null : _check,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Check for updates'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    try {
                      if (!await launchUrl(
                        Uri.https('github.com', '/iodn/tap-ducky/releases'),
                        mode: LaunchMode.externalApplication,
                      )) {
                        _showError(
                          StateError('No browser'),
                          'Could not open GitHub Releases.',
                        );
                      }
                    } catch (error) {
                      _showError(error, 'Could not open GitHub Releases.');
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('GitHub releases'),
                ),
              ],
            ),
            const Divider(height: 32),
            SwitchListTile(
              title: const Text('Update notifications'),
              value: notificationsEnabled,
              onChanged: _settings == null || _changingPreference
                  ? null
                  : _setEnabled,
            ),
            if (notificationsEnabled &&
                _settings?['notificationsAllowed'] != true)
              ListTile(
                leading: const Icon(Icons.notifications_off_outlined),
                title: const Text('Android notifications are off'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () async {
                  try {
                    await appUpdatesChannel.invokeMethod<void>(
                      'notificationSettings',
                    );
                  } catch (error) {
                    _showError(
                      error,
                      'Could not open Android notification settings.',
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
