import 'package:flutter/material.dart';

import '../booth_controller.dart';
import '../theme/tb_theme.dart';
import '../widgets/tb_ui.dart';
import 'jpeg_import_test_screen.dart';

class SettingsScreen extends StatefulWidget {
  final BoothController controller;
  const SettingsScreen({super.key, required this.controller});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _bridge;
  late final TextEditingController _token;
  bool _obscureToken = true;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _bridge = TextEditingController(text: widget.controller.bridge.baseUrl);
    _token = TextEditingController();
  }

  @override
  void dispose() {
    _bridge.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _bridge.text.trim();
    if (url.isEmpty) {
      setState(() => _formError = 'Enter the bridge URL.');
      return;
    }
    setState(() => _formError = null);
    await widget.controller.saveBridgeUrl(url);
    final token = _token.text.trim();
    if (token.isNotEmpty) {
      await widget.controller.saveBridgeToken(token);
      _token.clear();
    }
    if (!mounted) return;
    _bridge.text = widget.controller.bridge.baseUrl;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Bridge settings saved')));
  }

  Future<void> _clearToken() async {
    await widget.controller.clearBridgeToken();
    if (!mounted) return;
    _token.clear();
    setState(() => _obscureToken = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Bridge token cleared')));
  }

  Future<void> _testConnection() async {
    final url = _bridge.text.trim();
    if (url.isEmpty) {
      setState(() => _formError = 'Enter the bridge URL.');
      return;
    }
    setState(() => _formError = null);
    await widget.controller.saveBridgeUrl(url);
    final token = _token.text.trim();
    if (token.isNotEmpty) {
      await widget.controller.saveBridgeToken(token);
      _token.clear();
    }
    await widget.controller.checkBridge();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      body: TbBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(TbSpace.xl),
            child: AnimatedBuilder(
              animation: c,
              builder: (context, _) => Column(
                children: [
                  TbPageHeader(
                    showBack: true,
                    eyebrow: 'Operator',
                    title: 'Settings',
                    subtitle: 'Bridge, camera and event diagnostics',
                    actions: [
                      TbPill(
                        label: c.isMock ? 'Simulated camera' : 'Camera',
                        color: c.isMock ? TbColors.rose : TbColors.mint,
                        icon: Icons.videocam_outlined,
                        dense: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: TbSpace.lg),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 880;
                        final left = _settingsColumn(c);
                        final right = _diagnosticsColumn(c);
                        if (!wide) {
                          return SingleChildScrollView(
                            child: Column(
                              children: [
                                left,
                                const SizedBox(height: TbSpace.md),
                                right,
                              ],
                            ),
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: left),
                            const SizedBox(width: TbSpace.md),
                            Expanded(flex: 2, child: right),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingsColumn(BoothController c) {
    return SingleChildScrollView(
      child: Column(
        children: [
          TbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TbEyebrow('Connection'),
                const SizedBox(height: 10),
                Text(
                  'Windows Bridge',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'The iPad and guest phones must be able to reach this address on the local network.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _bridge,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Bridge URL',
                    hintText: 'http://192.168.8.192:8787',
                    errorText: _formError,
                    prefixIcon: const Icon(Icons.link_rounded),
                  ),
                  onSubmitted: (_) => _testConnection(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _token,
                  obscureText: _obscureToken,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: InputDecoration(
                    labelText: 'Bridge API token',
                    helperText: c.bridge.token != null
                        ? 'Token stored securely. Enter a new token to replace it.'
                        : 'Required when Bridge authentication is enabled.',
                    prefixIcon: const Icon(Icons.key_rounded),
                    suffixIcon: IconButton(
                      tooltip: _obscureToken ? 'Show token' : 'Hide token',
                      icon: Icon(
                        _obscureToken
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscureToken = !_obscureToken),
                    ),
                  ),
                  onSubmitted: (_) => _testConnection(),
                ),
                if (c.bridge.token != null) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _clearToken,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Clear stored token'),
                    ),
                  ),
                ],
                const SizedBox(height: TbSpace.md),
                Row(
                  children: [
                    TbPrimaryButton(
                      label: 'Save',
                      icon: Icons.check_rounded,
                      onPressed: _save,
                    ),
                    const SizedBox(width: TbSpace.sm),
                    TbSecondaryButton(
                      label: c.bridgeChecking ? 'Testing…' : 'Test connection',
                      icon: Icons.wifi_tethering_rounded,
                      onPressed: c.bridgeChecking ? null : _testConnection,
                    ),
                  ],
                ),
                const SizedBox(height: TbSpace.md),
                _connectionStatus(c),
              ],
            ),
          ),
          const SizedBox(height: TbSpace.md),
          TbCard(
            color: TbColors.surfaceRaised,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TbEyebrow('Temporary test tools'),
                const SizedBox(height: 8),
                Text(
                  'Operator-only JPEG import for Bridge upload testing. It does not use the camera or replace the booth workflow.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 10),
                TbSecondaryButton(
                  label: 'Import Test JPEG',
                  icon: Icons.upload_file_rounded,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          JpegImportTestScreen(controller: widget.controller),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: TbSpace.md),
          TbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TbEyebrow('Event'),
                const SizedBox(height: 10),
                if (c.hasSelectedEvent)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.eventTitle,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              c.eventDate,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      const TbPill(
                        label: 'Selected',
                        color: TbColors.mint,
                        icon: Icons.check,
                        dense: true,
                      ),
                    ],
                  )
                else
                  const TbEmptyState(
                    icon: Icons.event_busy_outlined,
                    title: 'No event selected',
                    message:
                        'Return to the booth screen to create or select an event.',
                  ),
                const SizedBox(height: TbSpace.md),
                TbMetric(label: 'Event ID', value: c.eventId),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _connectionStatus(BoothController c) {
    if (c.bridgeChecking) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            'Checking bridge…',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      );
    }
    if (c.bridgeCheckError != null) {
      return _statusLine(
        color: TbColors.red,
        icon: Icons.error_outline,
        title: 'Bridge unreachable',
        detail: c.bridgeCheckError!,
      );
    }
    final health = c.bridgeHealth;
    if (health == null) {
      return _statusLine(
        color: TbColors.muted,
        icon: Icons.help_outline,
        title: 'Connection not checked',
        detail: 'Test the bridge before the event starts.',
      );
    }
    return _statusLine(
      color: TbColors.mint,
      icon: Icons.check_circle_outline,
      title: 'Bridge connected',
      detail: '${health.service} ${health.version}',
    );
  }

  Widget _statusLine({
    required Color color,
    required IconData icon,
    required String title,
    required String detail,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(detail, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }

  Widget _diagnosticsColumn(BoothController c) {
    final health = c.bridgeHealth;
    final printer = health?.printer ?? const <String, dynamic>{};
    final printerName = printer['name']?.toString() ?? 'Not reported';
    final printerState = printer['state']?.toString() ?? 'Not reported';
    final printerMode = printer['mode']?.toString() ?? 'Not reported';
    final printerNote = printer['note']?.toString() ?? '';
    return TbCard(
      color: TbColors.surfaceRaised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TbEyebrow('Diagnostics'),
          const SizedBox(height: 10),
          Text(
            'Booth health',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Read-only operational information. Hardware states are reported by the bridge, not inferred.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: TbSpace.lg),
          _diagnosticRow(
            'Camera',
            c.camera.name,
            trailing: TbPill(
              label: c.isMock ? 'Simulated' : 'Native',
              color: c.isMock ? TbColors.rose : TbColors.mint,
              dense: true,
            ),
          ),
          const Divider(height: 26),
          _diagnosticRow(
            'Printer mode',
            printerMode,
            trailing: TbPill(
              label: printerState,
              color: printerState == 'ready' ? TbColors.mint : TbColors.muted,
              dense: true,
            ),
          ),
          const Divider(height: 26),
          _diagnosticRow('Printer', printerName),
          if (printerNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(printerNote, style: Theme.of(context).textTheme.bodyMedium),
          ],
          const Divider(height: 26),
          _diagnosticRow('Event', c.hasSelectedEvent ? c.eventTitle : 'None'),
          const Divider(height: 26),
          _diagnosticRow('Event ID', c.eventId),
          const Divider(height: 26),
          _diagnosticRow('Bridge URL', c.bridge.baseUrl),
          const Divider(height: 26),
          _diagnosticRow(
            'Bridge token',
            c.bridge.token == null ? 'Not configured' : 'Configured securely',
          ),
          const Divider(height: 26),
          _diagnosticRow('Service', health?.service ?? 'Not checked'),
          if (c.bridgeCheckError != null) ...[
            const SizedBox(height: TbSpace.md),
            Text(
              'Diagnostic hint: confirm the Windows bridge is listening on 0.0.0.0:8787 and the Windows firewall allows TCP 8787 on the Private profile.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: TbColors.red),
            ),
          ],
        ],
      ),
    );
  }

  Widget _diagnosticRow(String label, String value, {Widget? trailing}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Align(
            alignment: Alignment.centerRight,
            child:
                trailing ??
                Text(
                  value,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
          ),
        ),
      ],
    );
  }
}
