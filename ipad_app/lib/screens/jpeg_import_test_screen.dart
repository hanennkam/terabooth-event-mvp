import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../booth_controller.dart';
import '../models.dart';
import '../services/bridge_client.dart';
import '../services/camera_pipeline.dart';
import '../services/camera_service.dart';
import '../services/storage_service.dart';
import '../theme/tb_theme.dart';
import '../widgets/tb_ui.dart';

/// TEMPORARY operator test tool. It is deliberately separate from the booth
/// capture workflow and never starts a camera session.
class JpegImportTestScreen extends StatefulWidget {
  final BoothController controller;
  const JpegImportTestScreen({super.key, required this.controller});

  @override
  State<JpegImportTestScreen> createState() => _JpegImportTestScreenState();
}

class _JpegImportTestScreenState extends State<JpegImportTestScreen> {
  Uint8List? _bytes;
  String? _filename;
  int? _width;
  int? _height;
  String? _sha;
  String? _error;
  bool _submitting = false;
  BoothController? _temp;
  Directory? _tempDir;
  PrintJob? _job;
  Uint8List? _artefact;
  String? _artefactError;
  String? _bridgeHash;
  bool? _hashMatch;

  @override
  void dispose() {
    _temp?.dispose();
    if (_tempDir != null) {
      _tempDir!.delete(recursive: true).ignore();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() => _error = null);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg'],
        dialogTitle: 'Select a test JPEG',
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        setState(() => _error = 'The selected file is empty.');
        return;
      }
      final ext = file.name.split('.').last.toLowerCase();
      if (ext != 'jpg' && ext != 'jpeg') {
        setState(() => _error = 'Only .jpg or .jpeg files are accepted.');
        return;
      }
      final validation = await const ImageValidator().validate(
        bytes,
        allowPng: false,
      );
      setState(() {
        _bytes = bytes;
        _filename = file.name;
        _width = validation.width;
        _height = validation.height;
        _sha = sha256.convert(bytes).toString();
        _job = null;
        _artefact = null;
        _artefactError = null;
        _bridgeHash = null;
        _hashMatch = null;
      });
    } catch (e) {
      setState(() => _error = 'JPEG validation failed: $e');
    }
  }

  Future<void> _submit() async {
    final bytes = _bytes;
    final sha = _sha;
    if (bytes == null || sha == null || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
      _artefactError = null;
      _artefact = null;
      _job = null;
    });
    try {
      final main = widget.controller;
      final health = main.bridgeHealth ?? (await _checkHealth(main));
      final mode = health?.printer['mode']?.toString();
      if (health == null) {
        throw StateError(
          'Bridge health is unavailable. Test connection first.',
        );
      }
      if (mode != 'mock') {
        throw StateError(
          'Bridge printer mode is "$mode"; this test is blocked unless MockPrinter is active.',
        );
      }
      final token = main.bridge.token;
      if (token == null || token.isEmpty) {
        throw StateError('Bridge token is not configured.');
      }

      final temp = _temp ?? await _makeController(main);
      _temp = temp;
      final id = 'test_${DateTime.now().millisecondsSinceEpoch}';
      final image = CapturedImage(
        id: id,
        bytes: bytes,
        width: _width!,
        height: _height!,
        capturedAt: DateTime.now(),
        captureId: id,
        sha256: sha,
      );
      final testEventId = 'evt_import_$id';
      final testSessionId = 'ses_import_$id';
      final ingested = await temp.cameraPipeline.ingestor.ingest(
        image: image,
        eventId: testEventId,
        sessionId: testSessionId,
        slot: 1,
        captureId: id,
        allowPng: false,
      );
      temp.prepareImportedTestReview(
        image: ingested,
        testEventId: testEventId,
        testSessionId: testSessionId,
      );
      await temp.approve();
      final job = temp.job;
      if (job == null) {
        throw StateError(temp.error ?? 'Bridge did not accept the test job.');
      }
      final refreshed = await temp.bridge.getJob(job.id);
      Object? artefactError;
      Uint8List? artefact;
      try {
        artefact = await temp.bridge.artefact(job.id);
      } catch (e) {
        artefactError = e;
      }
      if (artefact != null) {
        try {
          final validation = await const ImageValidator().validate(
            artefact,
            allowPng: false,
          );
          if (validation.width != 1200 || validation.height != 1800) {
            artefactError =
                'Derived artefact is ${validation.width}×${validation.height}, expected 1200×1800.';
          }
        } catch (e) {
          artefactError = 'Derived artefact validation failed: $e';
        }
      }
      setState(() {
        _job = refreshed;
        _bridgeHash = refreshed.imageHashes.isEmpty
            ? null
            : refreshed.imageHashes.first;
        _hashMatch = _bridgeHash == null ? null : _bridgeHash == sha;
        _artefact = artefact;
        _artefactError = artefactError?.toString();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<HealthStatus?> _checkHealth(BoothController main) async {
    await main.checkBridge();
    return main.bridgeHealth;
  }

  Future<BoothController> _makeController(BoothController main) async {
    final dir = await Directory.systemTemp.createTemp('terabooth_jpeg_import_');
    _tempDir = dir;
    return BoothController(
      camera: const MockCameraService(),
      storage: StorageService(rootOverride: dir),
      bridge: BridgeClient(
        baseUrl: main.bridge.baseUrl,
        token: main.bridge.token,
      ),
      countdownDelay: Duration.zero,
      pollInterval: const Duration(milliseconds: 200),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Scaffold(
      body: TbBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(TbSpace.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TbPageHeader(
                  showBack: true,
                  eyebrow: 'Operator · Temporary test tool',
                  title: 'JPEG import test',
                  subtitle:
                      'Select a disposable JPEG, submit one solo_4x6_v1 job, and retrieve the derived asset. This is not a booth capture workflow.',
                ),
                const SizedBox(height: TbSpace.lg),
                TbCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const TbPill(
                        label: 'TEMPORARY TEST — NOT FOR EVENT USE',
                        color: TbColors.gold,
                        icon: Icons.science_outlined,
                        dense: true,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'The bridge must be in MockPrinter mode. No camera or physical printer is used.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      TbSecondaryButton(
                        label: 'Select JPEG from Files',
                        icon: Icons.upload_file_rounded,
                        onPressed: _submitting ? null : _pick,
                      ),
                      if (_filename != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          '$_filename · $_width×$_height',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          'SHA-256: $_sha',
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(color: TbColors.red),
                        ),
                      ],
                    ],
                  ),
                ),
                if (bytes != null) ...[
                  const SizedBox(height: TbSpace.md),
                  TbCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const TbEyebrow('Selected original'),
                        const SizedBox(height: 8),
                        Image.memory(
                          bytes,
                          height: 300,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                        const SizedBox(height: 12),
                        TbPrimaryButton(
                          label: _submitting
                              ? 'Submitting…'
                              : 'Submit one test job',
                          icon: Icons.send_rounded,
                          onPressed: _submitting ? null : _submit,
                        ),
                      ],
                    ),
                  ),
                ],
                if (_job != null) ...[
                  const SizedBox(height: TbSpace.md),
                  TbCard(
                    color: TbColors.surfaceRaised,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const TbEyebrow('Bridge result'),
                        const SizedBox(height: 8),
                        _row('Job', _job!.id),
                        _row('State', _job!.state),
                        _row('Completion', _job!.completion),
                        _row('Printer mode', _job!.printerMode),
                        _row(
                          'Original hash',
                          _hashMatch == null
                              ? 'Not returned'
                              : (_hashMatch! ? 'MATCHES' : 'MISMATCH'),
                        ),
                        if (_bridgeHash != null)
                          SelectableText(
                            'Bridge hash: $_bridgeHash',
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        const SizedBox(height: 12),
                        if (_artefact == null)
                          Text(
                            _artefactError ?? 'Derived artefact not ready.',
                            style: const TextStyle(color: TbColors.gold),
                          )
                        else ...[
                          const TbEyebrow('Derived artefact'),
                          const SizedBox(height: 6),
                          Text('1200×1800 JPEG retrieved'),
                          const SizedBox(height: 8),
                          Image.memory(
                            _artefact!,
                            height: 300,
                            fit: BoxFit.contain,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        SizedBox(width: 120, child: Text(label)),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
