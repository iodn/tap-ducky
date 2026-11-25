import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/router.dart';
import '../../data/models/app_settings.dart';
import '../../data/services/local_drafts_service.dart';
import '../../state/controllers/app_settings_controller.dart';
import '../../state/controllers/dynamic_color_controller.dart';
import '../../state/controllers/hid_status_controller.dart';
import '../../widgets/arm_profile_sheet.dart';
import '../../widgets/configuration_page.dart';
import 'about_screen.dart';
import 'usb_id_reference_screen.dart';
import 'widgets/donation_sheet.dart';
import 'widgets/section_card.dart';
import 'widgets/dynamic_colors_tile.dart';
import 'widgets/local_draft_settings.dart';
import 'widgets/support_pill.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static const String _repoUrl = 'https://github.com/iodn/tap-ducky';
  static const String _issuesUrl = 'https://github.com/iodn/tap-ducky/issues';
  static const String _liberapayUrl = 'https://liberapay.com/KaijinLab/donate';

  Future<void> _launchUrl(BuildContext context, String url) async {
    try {
      final uri = Uri.parse(url);
      final canLaunch = await canLaunchUrl(uri);
      if (!canLaunch) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No browser available'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmResetAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset general preferences?'),
        content: const Text('Restore the theme, execution, and session preferences to their defaults.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Reset')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final updated = await _applySetting(
      context,
      ref.read(appSettingsControllerProvider.notifier).resetAllToDefaults,
    );
    if (!context.mounted || !updated) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('General preferences reset')),
    );
  }

  Future<bool> _applySetting(BuildContext context, Future<void> Function() update) async {
    try {
      await update();
      return true;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Could not apply the change. Try again.')));
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsControllerProvider);
    final hid = ref.watch(hidStatusControllerProvider);
    final model = ref.watch(localModelStatusProvider).value;
    final dynamicColors = ref.watch(dynamicColorsControllerProvider);
    final s = settingsAsync.value;
    final groups = _settingsGroups(s, hid, model, dynamicColors);
    final query = _query.trim().toLowerCase();
    final matches = query.isEmpty
        ? const <_SettingsDestination>[]
        : groups
            .expand((group) => group.destinations)
            .where((destination) => destination.matches(query))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            tooltip: 'Device',
            onPressed: () => context.push(const DeviceRoute().location),
            icon: const Icon(Icons.phone_android),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _SettingsSearchField(
            controller: _searchCtrl,
            query: _query,
            onChanged: (value) => setState(() => _query = value),
            onClear: () {
              _searchCtrl.clear();
              setState(() => _query = '');
            },
          ),
          const SizedBox(height: 12),
          if (query.isEmpty)
            for (final group in groups) ...[
              _SettingsGroupCard(group: group),
              const SizedBox(height: 14),
            ]
          else if (matches.isEmpty)
            _SettingsEmptyResult(query: _query)
          else
            _SettingsGroupCard(
              group: _SettingsGroup('Results', matches),
            ),
        ],
      ),
    );
  }

  List<_SettingsGroup> _settingsGroups(
    AppSettings? s,
    HidStatus hid,
    LocalModelStatus? model,
    bool dynamicColors,
  ) {
    final appearance = _SettingsDestination(
      icon: Icons.palette_outlined,
      title: 'Appearance',
      subtitle: s == null
          ? 'Theme and colors'
          : '${_getThemeName(s.themeMode)} · ${dynamicColors ? 'Dynamic color' : 'Static colors'}',
      keywords: const [
        'theme',
        'dark',
        'light',
        'auto',
        'color',
        'dynamic',
        'appearance',
      ],
      builder: _appearancePage,
    );
    final aiDraft = _SettingsDestination(
      icon: Icons.auto_awesome_outlined,
      title: 'AI Drafting',
      subtitle: switch (model?.state) {
        'ready' => model?.name ?? 'Local model ready',
        'missing' => 'No local model selected',
        _ => 'Offline DuckyScript drafting',
      },
      keywords: const [
        'ai',
        'draft',
        'model',
        'litert',
        'offline',
        'duckyscript',
        'generate',
      ],
      builder: _aiDraftPage,
    );
    final execution = _SettingsDestination(
      icon: Icons.keyboard_outlined,
      title: 'Execution & Typing',
      subtitle: 'Script pauses, keyboard timing, and reliability',
      keywords: const [
        'execution',
        'typing',
        'speed',
        'delay',
        'timing',
        'log',
        'unicode',
        'screen',
        'grace',
        'payload',
      ],
      builder: _executionPage,
    );
    final usb = _SettingsDestination(
      icon: Icons.usb,
      title: 'USB & HID',
      subtitle: hid.usbRestoring
          ? 'Restoring USB…'
          : hid.sessionArmed
              ? 'Session armed'
              : 'Session disarmed',
      keywords: const [
        'usb',
        'hid',
        'gadget',
        'root',
        'session',
        'arm',
        'profile',
        'keyboard',
      ],
      builder: _usbPage,
    );
    final advanced = _SettingsDestination(
      icon: Icons.tune,
      title: 'Advanced',
      subtitle: 'Profiles, hotkeys, command presets',
      keywords: const [
        'advanced',
        'vid',
        'pid',
        'profile',
        'hotkey',
        'preset',
        'layout',
        'usb',
      ],
      onTap: (context) =>
          context.push(const AdvancedSettingsRoute().location),
    );
    final usbIds = _SettingsDestination(
      icon: Icons.manage_search,
      title: 'USB ID reference',
      subtitle: 'Find a vendor or product',
      keywords: const ['usb', 'vid', 'pid', 'vendor', 'product', 'database'],
      onTap: (context) => showConfigurationPage<void>(context, (_) => const UsbIdReferenceScreen()),
    );
    final store = _SettingsDestination(
      icon: Icons.storefront_outlined,
      title: 'Payload Store',
      subtitle: 'Browse GitHub payload repositories',
      keywords: const ['store', 'github', 'payload', 'import', 'repository'],
      onTap: (context) => context.push(const PayloadsStoreRoute().location),
    );
    final about = _SettingsDestination(
      icon: Icons.info_outline,
      title: 'About TapDucky',
      subtitle: 'Version, licenses, repository',
      keywords: const ['about', 'version', 'license', 'repo', 'github', 'app'],
      builder: _aboutPage,
    );
    final support = _SettingsDestination(
      icon: Icons.volunteer_activism_outlined,
      title: 'Support the Project',
      subtitle: 'Donate or star the repository',
      keywords: const [
        'support',
        'donate',
        'donation',
        'star',
        'liberapay',
        'bitcoin',
        'ethereum',
      ],
      builder: _supportPage,
    );
    final reset = _SettingsDestination(
      icon: Icons.restart_alt,
      title: 'Reset general preferences',
      subtitle: 'Restore the theme, execution, and session preferences',
      keywords: const ['reset', 'default', 'erase', 'restore'],
      danger: true,
      onTap: (context) => _confirmResetAll(context, ref),
    );

    return [
      _SettingsGroup('Personalize', [
        appearance,
        if (model == null || model.state != 'unsupported') aiDraft,
      ]),
      _SettingsGroup('Keyboard & USB', [execution, usb, usbIds, advanced]),
      _SettingsGroup('Library', [store]),
      _SettingsGroup('About & Support', [about, support, reset]),
    ];
  }

  Widget _appearancePage(BuildContext context, WidgetRef ref) {
    final async = ref.watch(appSettingsControllerProvider);
    final s = async.value;
    if (s == null) return _SettingsLoading(error: async.error);
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [_buildAppearanceSection(context, ref, s.themeMode)],
    );
  }

  Widget _executionPage(BuildContext context, WidgetRef ref) {
    final async = ref.watch(appSettingsControllerProvider);
    final s = async.value;
    if (s == null) return _SettingsLoading(error: async.error);
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        _buildExecutionSection(context, ref, s),
        const SizedBox(height: 8),
        _buildStealthSection(context, ref, s),
      ],
    );
  }

  Widget _aiDraftPage(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: const [LocalDraftSettings()],
    );
  }

  Widget _usbPage(BuildContext context, WidgetRef ref) {
    final hid = ref.watch(hidStatusControllerProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(hid.sessionArmed ? Icons.lock_open : Icons.lock_outline),
                title: Text(hid.sessionArmed ? 'Disarm session' : 'Arm session'),
                subtitle: hid.usbRestoring ? Text(hid.message ?? 'Restoring USB…') : null,
                enabled: hid.rootAvailable && hid.hidSupported && !hid.usbRestoring,
                onTap: () => toggleUsbSession(context, ref),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.phone_android),
                title: const Text('Device diagnostics'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(const DeviceRoute().location),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _aboutPage(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [_buildAboutSection(context)],
    );
  }

  Widget _supportPage(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [_buildDonationsSection(context, ref)],
    );
  }

  Widget _buildDonationsSection(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SectionCard(
        title: 'Support Development',
        leading: Icon(Icons.volunteer_activism_rounded, color: cs.primary),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cs.secondaryContainer.withOpacity(0.7),
                      cs.secondaryContainer.withOpacity(0.4),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: cs.outlineVariant.withOpacity(0.3),
                  ),
                ),
                child: Text(
                  'No ads, no tracking, no locked features. Your support keeps this Rubber Ducky alternative independent and freely available to penetration testers worldwide.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _openDonationSheet(context),
                      icon: const Icon(Icons.favorite_rounded),
                      label: const Text('Donate'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _launchUrl(context, 'https://github.com/iodn/tap-ducky'),
                      onLongPress: () => _copyToClipboard(
                        context,
                        text: 'https://github.com/iodn/tap-ducky',
                        message: 'Repository link copied',
                      ),
                      icon: const Icon(Icons.star_border_rounded),
                      label: const Text('Star Repo'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SupportPill(
                      icon: Icons.lock_outline_rounded, label: 'Local-only'),
                  SupportPill(
                      icon: Icons.shield_outlined, label: 'No tracking'),
                  SupportPill(
                      icon: Icons.speed_rounded, label: 'Lightweight'),
                  SupportPill(
                      icon: Icons.code_rounded, label: 'Open-source'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppearanceSection(
      BuildContext context, WidgetRef ref, ThemeMode mode) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SectionCard(
        title: 'Appearance',
        leading: Icon(Icons.palette_outlined, color: cs.primary),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cs.primaryContainer.withOpacity(0.6),
                      cs.primaryContainer.withOpacity(0.3),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.primary.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getThemeIcon(mode),
                        size: 20,
                        color: cs.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getThemeName(mode),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _getThemeDescription(mode),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onPrimaryContainer.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ThemeCard(
                      icon: Icons.auto_awesome_rounded,
                      label: 'Auto',
                      isSelected: mode == ThemeMode.system,
                      onTap: () => _changeTheme(ref, ThemeMode.system),
                      theme: theme,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ThemeCard(
                      icon: Icons.light_mode_rounded,
                      label: 'Light',
                      isSelected: mode == ThemeMode.light,
                      onTap: () => _changeTheme(ref, ThemeMode.light),
                      theme: theme,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ThemeCard(
                      icon: Icons.dark_mode_rounded,
                      label: 'Dark',
                      isSelected: mode == ThemeMode.dark,
                      onTap: () => _changeTheme(ref, ThemeMode.dark),
                      theme: theme,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
             DynamicColorsTile(),
             const SizedBox(height: 12),
             Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline, size: 16, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _getThemeHint(mode),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExecutionSection(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    final controller = ref.read(appSettingsControllerProvider.notifier);
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: 'Timing',
            leading: Icon(Icons.timer_outlined, color: colors.primary),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ExecutionSlider(
                    title: 'Script pauses',
                    summary: 'Scales delays written in the script. At 2×, a 1-second pause takes 2 seconds.',
                    value: settings.delayMultiplier,
                    min: 0.1,
                    max: 4,
                    divisions: 39,
                    format: (value) => '${value.toStringAsFixed(2)}×',
                    onChanged: controller.setDelayMultiplier,
                  ),
                  const Divider(),
                  _ExecutionSlider(
                    title: 'Keyboard timing',
                    summary: 'Adjusts key hold time and the gap between USB key reports. Higher values give the host more time.',
                    value: settings.typingSpeedFactor,
                    min: 0.1,
                    max: 10,
                    divisions: 99,
                    format: (value) => '${value.toStringAsFixed(2)}×',
                    onChanged: (value) => _applySetting(context, () => controller.setTypingSpeedFactor(value)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Execution',
            leading: Icon(Icons.play_arrow_outlined, color: colors.primary),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  value: settings.enableLogging,
                  onChanged: controller.setEnableLogging,
                  title: const Text('Save execution history'),
                ),
                SwitchListTile(
                  value: settings.keepScreenOn,
                  onChanged: (value) => _applySetting(context, () => controller.setKeepScreenOn(value)),
                  title: const Text('Keep screen on'),
                  subtitle: const Text('While TapDucky is open'),
                ),
                ExpansionTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Keyboard reliability'),
                  subtitle: const Text('USB readiness and unsupported characters'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ExecutionSlider(
                      title: 'USB readiness wait',
                      summary: 'How long Android waits for the USB gadget to become ready.',
                      value: settings.hidGraceWindowMs.toDouble(),
                      min: 0,
                      max: 5000,
                      divisions: 50,
                      format: (value) => '${value.round()} ms',
                      onChanged: (value) => _applySetting(context, () => controller.setHidGraceWindowMs(value.round())),
                    ),
                    const Text('Unsupported characters'),
                    DropdownButton<String>(
                      value: settings.unicodeFallbackMode,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 'warn', child: Text('Skip and log a warning')),
                        DropdownMenuItem(value: 'skip', child: Text('Skip')),
                        DropdownMenuItem(value: 'ascii', child: Text('Use nearest ASCII character')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          _applySetting(context, () => controller.setUnicodeFallbackMode(value));
                        }
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: settings.riskyFastMode,
                      onChanged: (value) => _applySetting(context, () => controller.setRiskyFastMode(value)),
                      title: const Text('Allow shorter key timings'),
                      subtitle: const Text('May cause missed or stuck keys.'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _applySetting(context, controller.resetExecutionDefaults),
              child: const Text('Reset execution settings'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStealthSection(
      BuildContext context, WidgetRef ref, AppSettings s) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SectionCard(
        title: 'Hidden execution',
        leading: Icon(Icons.visibility_off, color: cs.primary),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.hiddenExecution,
                onChanged: (v) => ref
                    .read(appSettingsControllerProvider.notifier)
                    .setHiddenExecution(v),
                title: const Text('Allow hidden execution'),
                subtitle: Text(
                  s.hiddenExecution
                      ? 'Scheduled payloads and dial shortcuts can run while the app is in the background.'
                      : 'Scheduled payloads and dial shortcuts run only while the app is open.',
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Applies to automatic runs from schedules and dial shortcuts. '
                      'Manual execution always works, and "Keep screen on" is a separate setting.',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SectionCard(
        title: 'About',
        leading: Icon(Icons.info_outline, color: cs.primary),
        child: Column(
          children: [
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final info = snapshot.data;
                final version =
                    info == null ? '—' : '${info.version}+${info.buildNumber}';
                return ListTile(
                  leading: const Icon(Icons.apps),
                  title: const Text('TapDucky - KaijinLab Inc.'),
                  subtitle: Text('Version $version'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => AboutScreen(repoUrl: _repoUrl, issuesUrl: _issuesUrl, liberapayUrl: _liberapayUrl),
                      ),
                    );
                  },
                );
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.gavel),
              title: const Text('Licenses'),
              subtitle: const Text('Open source licenses'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                showLicensePage(
                  context: context,
                  applicationName: 'TapDucky',
                  applicationVersion: 'by KaijinLab Inc.',
                  applicationIcon: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Icon(
                      Icons.security,
                      size: 48,
                      color: cs.primary,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeTheme(WidgetRef ref, ThemeMode mode) async {
    await ref.read(appSettingsControllerProvider.notifier).setThemeMode(mode);
    HapticFeedback.selectionClick();
  }

  String _getThemeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'Auto Theme';
      case ThemeMode.light:
        return 'Light Theme';
      case ThemeMode.dark:
        return 'Dark Theme';
    }
  }

  IconData _getThemeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return Icons.auto_awesome_rounded;
      case ThemeMode.light:
        return Icons.light_mode_rounded;
      case ThemeMode.dark:
        return Icons.dark_mode_rounded;
    }
  }

  String _getThemeDescription(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'Follows your device settings';
      case ThemeMode.light:
        return 'Always bright and clear';
      case ThemeMode.dark:
        return 'Easy on the eyes';
    }
  }

  String _getThemeHint(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'Theme automatically switches when you change your device settings between light and dark mode';
      case ThemeMode.light:
        return 'Perfect for daytime use and well-lit environments';
      case ThemeMode.dark:
        return 'Reduces eye strain in low-light conditions and saves battery on OLED screens';
    }
  }

  void _openDonationSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.92,
          child: DonationSheet(
            repoUrl: 'https://github.com/iodn/tap-ducky',
            btcAddress: 'bc1qtf79uecssueu4u4u86zct46vcs0vcd2cnmvw6f',
            ethAddress: '0xCaCc52Cd2D534D869a5C61dD3cAac57455f3c2fD',
            liberapayUrl: 'https://liberapay.com/KaijinLab/donate',
            onCopy: (text, message) =>
                _copyToClipboard(ctx, text: text, message: message),
          ),
        );
      },
    );
  }

  Future<void> _copyToClipboard(
    BuildContext context, {
    required String text,
    required String message,
  }) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    HapticFeedback.selectionClick();
  }
}

class _ExecutionSlider extends StatelessWidget {
  const _ExecutionSlider({
    required this.title,
    required this.summary,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
  });

  final String title;
  final String summary;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max);
    final formatted = format(clamped);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            Text(formatted),
          ],
        ),
        Slider(
          value: clamped,
          min: min,
          max: max,
          divisions: divisions,
          label: formatted,
          semanticFormatterCallback: (value) => '$title, ${format(value)}',
          onChanged: onChanged,
        ),
        Text(summary, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final ThemeData theme;

  const _ThemeCard({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primaryContainer.withOpacity(0.7)
              : cs.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? cs.primary.withOpacity(0.5)
                : cs.outlineVariant.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? cs.primary : cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 24,
                color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color:
                    isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(height: 4),
              Icon(
                Icons.check_circle,
                size: 16,
                color: cs.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsGroup {
  const _SettingsGroup(this.title, this.destinations);

  final String title;
  final List<_SettingsDestination> destinations;
}

class _SettingsDestination {
  const _SettingsDestination({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.keywords,
    this.builder,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> keywords;
  final Widget Function(BuildContext, WidgetRef)? builder;
  final void Function(BuildContext)? onTap;
  final bool danger;

  bool matches(String query) {
    final haystack = '$title $subtitle ${keywords.join(' ')}'.toLowerCase();
    return haystack.contains(query);
  }
}

class _SettingsGroupCard extends StatelessWidget {
  const _SettingsGroupCard({required this.group});

  final _SettingsGroup group;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: group.title,
      child: Column(
        children: [
          for (var i = 0; i < group.destinations.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _SettingsDestinationTile(destination: group.destinations[i]),
          ],
        ],
      ),
    );
  }
}

class _SettingsDestinationTile extends StatelessWidget {
  const _SettingsDestinationTile({required this.destination});

  final _SettingsDestination destination;

  void _open(BuildContext context) {
    final onTap = destination.onTap;
    if (onTap != null) {
      onTap(context);
      return;
    }
    final builder = destination.builder;
    if (builder == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SettingsCategoryPage(
          title: destination.title,
          builder: builder,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = destination.danger ? cs.error : cs.primary;
    final accentContainer =
        destination.danger ? cs.errorContainer : cs.primaryContainer;
    final onAccentContainer =
        destination.danger ? cs.onErrorContainer : cs.onPrimaryContainer;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: accentContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(destination.icon, size: 20, color: onAccentContainer),
      ),
      title: Text(
        destination.title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: destination.danger ? accent : null,
        ),
      ),
      subtitle: Text(
        destination.subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
      onTap: () => _open(context),
    );
  }
}

class _SettingsCategoryPage extends ConsumerWidget {
  const _SettingsCategoryPage({required this.title, required this.builder});

  final String title;
  final Widget Function(BuildContext, WidgetRef) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: builder(context, ref),
    );
  }
}

class _SettingsSearchField extends StatelessWidget {
  const _SettingsSearchField({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search settings',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                onPressed: onClear,
              ),
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}

class _SettingsEmptyResult extends StatelessWidget {
  const _SettingsEmptyResult({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 42, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'No settings match “$query”',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try “theme”, “speed”, “model”, “USB”, or “license”.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsLoading extends StatelessWidget {
  const _SettingsLoading({this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    if (error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Failed to load settings: $error',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
