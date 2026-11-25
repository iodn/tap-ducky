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
import 'about_screen.dart';
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

  String _speedLabel(double multiplier) {
    if (multiplier >= 3.0) return 'Very Slow';
    if (multiplier >= 1.5) return 'Slow';
    if (multiplier >= 0.9 && multiplier <= 1.1) return 'Normal';
    if (multiplier >= 0.5) return 'Fast';
    return 'Very Fast';
  }

  String _typingSpeedLabel(double factor) {
    if (factor <= 0.4) return 'Very Fast';
    if (factor <= 0.8) return 'Fast';
    if (factor <= 1.2) return 'Normal';
    if (factor <= 2.5) return 'Slow';
    return 'Very Slow';
  }

  Future<void> _resetExecutionDefaults(WidgetRef ref) async {
    final controller = ref.read(appSettingsControllerProvider.notifier);
    await controller.setEnableLogging(true);
    await controller.setDelayMultiplier(1.0);
    await controller.setTypingSpeedFactor(1.0);
    await controller.setHidGraceWindowMs(1500);
    await controller.setUnicodeFallbackMode('warn');
    await controller.setRiskyFastMode(false);
    await controller.setKeepScreenOn(false);
  }

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
        title: const Text('Reset all settings?'),
        content: const Text('This will restore all settings to their defaults.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Reset')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(appSettingsControllerProvider.notifier).resetAllToDefaults();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings reset to defaults')),
    );
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
      subtitle: s == null
          ? 'Speed, timing, logging'
          : '${_speedLabel(s.delayMultiplier)} · ${s.delayMultiplier.toStringAsFixed(2)}×',
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
      title: 'Reset All Settings',
      subtitle: 'Restore every setting to its default',
      keywords: const ['reset', 'default', 'erase', 'restore'],
      danger: true,
      onTap: (context) => _confirmResetAll(context, ref),
    );

    return [
      _SettingsGroup('Personalize', [
        appearance,
        if (model == null || model.state != 'unsupported') aiDraft,
      ]),
      _SettingsGroup('Keyboard & USB', [execution, usb, advanced]),
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
        _buildExecutionSection(
          context,
          ref,
          s,
          s.delayMultiplier.clamp(0.1, 4.0),
        ),
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
    dynamic s,
    double clampedMultiplier,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SectionCard(
        title: 'Execution',
        leading: Icon(Icons.play_arrow, color: cs.primary),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Speed & timing',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _resetExecutionDefaults(ref),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Reset defaults'),
                  ),
                ],
              ),
              Text(
                'Adjust script pauses and the timing of USB key reports.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Script delay multiplier',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '${_speedLabel(s.delayMultiplier)} • ${s.delayMultiplier.toStringAsFixed(2)}×',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Slider(
                value: clampedMultiplier,
                min: 0.1,
                max: 4.0,
                divisions: 39,
                label: '${s.delayMultiplier.toStringAsFixed(2)}×',
                onChanged: (v) => ref
                    .read(appSettingsControllerProvider.notifier)
                    .setDelayMultiplier(v),
              ),
              Row(
                children: [
                  Text('Fast',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                  const Spacer(),
                  Text('Slow',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Key timing multiplier',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '${_typingSpeedLabel(s.typingSpeedFactor)} • ${s.typingSpeedFactor.toStringAsFixed(2)}×',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Slider(
                value: s.typingSpeedFactor.clamp(0.1, 10.0),
                min: 0.1,
                max: 10.0,
                divisions: 99,
                label: '${s.typingSpeedFactor.toStringAsFixed(2)}×',
                onChanged: (v) => ref
                    .read(appSettingsControllerProvider.notifier)
                    .setTypingSpeedFactor(v),
              ),
              Row(
                children: [
                  Text('Fast',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                  const Spacer(),
                  Text('Slow',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
              Text(
                'Lower values send key reports closer together. USB and the host app limit actual speed; this does not change host key repeat.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SpeedPresetChip(
                    label: 'Ultra Fast',
                    multiplier: 0.1,
                    current: s.delayMultiplier,
                    onSelected: () => ref
                        .read(appSettingsControllerProvider.notifier)
                        .setDelayMultiplier(0.1),
                    tooltip: 'Short pauses may not give the host app enough time to respond.',
                  ),
                  _SpeedPresetChip(
                    label: 'Very Fast',
                    multiplier: 0.25,
                    current: s.delayMultiplier,
                    onSelected: () => ref
                        .read(appSettingsControllerProvider.notifier)
                        .setDelayMultiplier(0.25),
                  ),
                  _SpeedPresetChip(
                    label: 'Fast',
                    multiplier: 0.5,
                    current: s.delayMultiplier,
                    onSelected: () => ref
                        .read(appSettingsControllerProvider.notifier)
                        .setDelayMultiplier(0.5),
                  ),
                  _SpeedPresetChip(
                    label: 'Normal',
                    multiplier: 1.0,
                    current: s.delayMultiplier,
                    onSelected: () => ref
                        .read(appSettingsControllerProvider.notifier)
                        .setDelayMultiplier(1.0),
                  ),
                  _SpeedPresetChip(
                    label: 'Slow',
                    multiplier: 2.0,
                    current: s.delayMultiplier,
                    onSelected: () => ref
                        .read(appSettingsControllerProvider.notifier)
                        .setDelayMultiplier(2.0),
                  ),
                  _SpeedPresetChip(
                    label: 'Very Slow',
                    multiplier: 4.0,
                    current: s.delayMultiplier,
                    onSelected: () => ref
                        .read(appSettingsControllerProvider.notifier)
                        .setDelayMultiplier(4.0),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
                ),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  childrenPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  leading: Icon(Icons.tune, color: cs.primary),
                  title: const Text(
                    'Advanced execution',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'Logging, HID reliability, Unicode fallback',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: s.enableLogging,
                      onChanged: (v) => ref
                          .read(appSettingsControllerProvider.notifier)
                          .setEnableLogging(v),
                      title: const Text('Enable logging'),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'HID grace window',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          '${s.hidGraceWindowMs} ms',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Slider(
                      value: s.hidGraceWindowMs.toDouble().clamp(0, 5000),
                      min: 0,
                      max: 5000,
                      divisions: 50,
                      label: '${s.hidGraceWindowMs} ms',
                      onChanged: (v) => ref
                          .read(appSettingsControllerProvider.notifier)
                          .setHidGraceWindowMs(v.round()),
                    ),
                    Text(
                      'Wait briefly for HID to become active before failing a write.',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Unicode fallback',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: cs.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: s.unicodeFallbackMode,
                              style: TextStyle(color: cs.onSurface),
                              items: const [
                                DropdownMenuItem(value: 'warn', child: Text('Warn & skip')),
                                DropdownMenuItem(value: 'skip', child: Text('Skip')),
                                DropdownMenuItem(value: 'ascii', child: Text('ASCII transliterate')),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                ref
                                    .read(appSettingsControllerProvider.notifier)
                                    .setUnicodeFallbackMode(v);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Controls how unsupported characters are handled during typing.',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    Tooltip(
                      message: 'Risky fast mode can cause missed or stuck keys on some hosts.',
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: s.riskyFastMode,
                        onChanged: (v) => ref
                            .read(appSettingsControllerProvider.notifier)
                            .setRiskyFastMode(v),
                        title: const Text('Risky fast mode'),
                        subtitle:
                            const Text('Allows shorter key hold and inter-key delays. May be unreliable.'),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: s.keepScreenOn,
                      onChanged: (v) => ref
                          .read(appSettingsControllerProvider.notifier)
                          .setKeepScreenOn(v),
                      title: const Text('Keep screen on'),
                      subtitle: const Text('Prevents screen from sleeping during execution'),
                    ),
                    if (s.keepScreenOn)
                      Padding(
                        padding: const EdgeInsets.only(left: 16, top: 8),
                        child: Row(
                          children: [
                            Icon(Icons.battery_alert, size: 16, color: cs.tertiary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'May increase battery usage. Screen will stay on even when app is in background.',
                                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                              ),
                            ),
                          ],
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

class _SpeedPresetChip extends StatelessWidget {
  const _SpeedPresetChip({
    required this.label,
    required this.multiplier,
    required this.current,
    required this.onSelected,
    this.tooltip,
  });

  final String label;
  final double multiplier;
  final double current;
  final VoidCallback onSelected;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = (current - multiplier).abs() < 0.01;

    final chip = ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
        fontSize: 12,
      ),
      selectedColor: cs.primaryContainer,
      backgroundColor: cs.surfaceContainerHighest,
      side: BorderSide(
        color: selected ? cs.primary : cs.outlineVariant,
        width: selected ? 1.5 : 1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
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
