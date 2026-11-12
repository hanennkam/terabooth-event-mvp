import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';
import 'services/bridge_client.dart';
import 'services/bridge_token_store.dart';
import 'services/camera_pipeline.dart';
import 'services/camera_service.dart';
import 'services/custom_template_composer.dart';
import 'templates/builtin_templates.dart';
import 'templates/template_models.dart';
import 'services/storage_service.dart';
import 'services/face_detection_service.dart';
import 'crop/crop_models.dart';
import 'crop/crop_planner.dart';

enum BoothPhase { idle, capturing, review, uploading, printing, done, error }

class BoothController extends ChangeNotifier {
  final CameraService camera;
  final StorageService storage;
  final CameraPipeline cameraPipeline;
  final Duration countdownDelay;
  final Duration pollInterval;
  final FaceDetector faceDetector;
  late final SmartCropPlanner cropPlanner;

  BridgeClient bridge;
  final BridgeTokenStore? bridgeTokenStore;
  String eventId;
  String eventTitle;
  String eventDate;

  BoothPhase phase = BoothPhase.idle;
  List<CapturedImage> photos = [];
  int countdown = 0;
  int activePhoto = 0;
  String? sessionId;
  String? error;
  PrintJob? job;
  bool saving = false;

  Uint8List? liveViewFrame;
  String? liveViewError;
  StreamSubscription<Uint8List>? _liveViewSubscription;
  bool _liveViewStarted = false;

  /// Slot currently being retaken (0-based), or null.
  int? retakingSlot;

  /// Last retake failure; the previously approved image remains selected.
  String? retakeError;

  /// Locally cached bridge-generated final composition.
  Uint8List? compositionBytes;
  bool compositionLoading = false;
  String? compositionError;

  Uint8List? gifBytes;
  bool gifLoading = false;
  String? gifError;

  /// Ordered event catalog; first entry is the active event.
  List<EventProfile> events = [];
  EventProfile? _selectedEvent;
  bool hasSelectedEvent = true;
  List<BoothSessionRecord> sessionHistory = [];
  BoothSessionRecord? interruptedSession;
  SessionRecovery? interruptedRecovery;
  bool eventsLoading = false;
  String? eventsError;
  DateTime? sessionStartedAt;
  String sessionStatus = 'idle';
  int sessionPhotoCount = 3;
  int sessionCountdownSeconds = 3;
  PhotoTemplate? sessionTemplate;
  EventConfiguration? sessionConfiguration;
  EventBranding sessionBranding = const EventBranding();
  bool countdownActive = false;
  bool _countdownCancelled = false;
  bool _endRequested = false;
  bool _disposed = false;

  HealthStatus? bridgeHealth;
  bool bridgeChecking = false;
  String? bridgeCheckError;

  PhotoTemplate template = BuiltinTemplates.defaultStrip;
  final Map<String, CropDecision> crops = {};
  RestorableSession? restorableSession;
  SubmittedJob? submittedJob;
  bool submittedJobReconciling = false;
  String? submittedJobError;

  BoothController({
    required this.camera,
    required this.storage,
    required this.bridge,
    PhotoTemplate? initialTemplate,
    FaceDetector? faceDetector,
    this.eventId = 'evt_demo',
    this.eventTitle = 'Kate & Jack',
    this.eventDate = '14 Nov 2026',
    this.countdownDelay = const Duration(seconds: 1),
    this.pollInterval = const Duration(seconds: 1),
    Duration captureTimeout = const Duration(seconds: 15),
    Duration connectTimeout = const Duration(seconds: 20),
    CameraPipeline? pipeline,
    this.bridgeTokenStore,
  }) : faceDetector = faceDetector ?? defaultFaceDetector(),
       cameraPipeline =
           pipeline ??
           CameraPipeline(
             camera: camera,
             storage: storage,
             captureTimeout: captureTimeout,
             connectTimeout: connectTimeout,
           ) {
    template = initialTemplate ?? BuiltinTemplates.defaultStrip;
    _selectedEvent = EventProfile(
      id: eventId,
      title: eventTitle,
      date: eventDate,
      status: EventStatus.active,
      configuration: EventConfiguration(
        templateId: template.id,
        templateVersion: template.version,
      ),
    );
    cropPlanner = SmartCropPlanner(faceDetector: this.faceDetector);
    cameraPipeline.addListener(_cameraChanged);
  }

  bool get isMock => camera.isSimulated;
  int get expectedPhotoCount => sessionPhotoCount.clamp(1, 4);
  CameraConnectionState get connectionState => cameraPipeline.connectionState;
  CameraCaptureState get captureState => cameraPipeline.captureState;

  EventProfile get currentEvent =>
      _selectedEvent ??
      EventProfile(
        id: eventId,
        title: eventTitle,
        date: eventDate,
        configuration: EventConfiguration(
          templateId: template.id,
          templateVersion: template.version,
        ),
      );

  /// Loads the persisted event catalog and selects its first entry.
  Future<void> loadEvents() async {
    if (_disposed || phase != BoothPhase.idle || photos.isNotEmpty) return;
    eventsLoading = true;
    eventsError = null;
    notifyListeners();
    try {
      final loaded = await storage.readEventCatalog();
      // A user may create/select an event while the catalog read is in flight.
      // Never let a stale read overwrite that choice.
      if (events.isNotEmpty) return;
      if (loaded.isEmpty) {
        events = [];
        _selectedEvent = null;
        hasSelectedEvent = false;
        if (!_disposed) notifyListeners();
        return;
      }
      events = _sortedEvents(loaded);
      hasSelectedEvent = true;
      final settings = await storage.readSettings();
      final preferred = settings['selected_event_id'];
      final selected = events.firstWhere(
        (event) => event.id == preferred,
        orElse: () => events.first,
      );
      _applyEvent(selected);
      await loadSessionFoundation();
      await loadRestorableSession();
      if (!_disposed) notifyListeners();
    } catch (e) {
      eventsError = 'Events could not be loaded: $e';
    } finally {
      eventsLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> selectEvent(EventProfile event) async {
    if (_disposed || phase != BoothPhase.idle || photos.isNotEmpty) return;
    events = _sortedEvents([
      event,
      ...events.where((existing) => existing.id != event.id),
    ]);
    hasSelectedEvent = true;
    _applyEvent(event);
    notifyListeners();
    try {
      await storage.writeEventCatalog(events);
      final settings = await storage.readSettings();
      settings['selected_event_id'] = event.id;
      await storage.writeSettings(settings);
    } catch (_) {
      // Event selection still works in-memory; persistence is best effort.
    }
    restorableSession = null;
    submittedJob = null;
    await loadSessionFoundation();
    await loadRestorableSession();
    await loadSubmittedJob();
  }

  Future<EventProfile> createEvent(String title, String date) async {
    final now = DateTime.now().toUtc();
    final event = EventProfile(
      id: 'evt_${now.microsecondsSinceEpoch}',
      title: title.trim().isEmpty ? 'Terabooth' : title.trim(),
      date: date.trim(),
      status: EventStatus.scheduled,
      createdAt: now,
      updatedAt: now,
    );
    await createEventProfile(event);
    return event;
  }

  /// Creates a fully configured event and makes it the selected event.
  Future<EventProfile> createEventProfile(EventProfile event) async {
    event.validate();
    if (events.any((existing) => existing.id == event.id)) {
      throw const EventValidationException(
        'EVENT_DUPLICATE',
        'An event with this identifier already exists.',
      );
    }
    final now = DateTime.now().toUtc();
    final created = event.copyWith(updatedAt: now);
    await selectEvent(created);
    return created;
  }

  /// Updates event metadata without touching any sessions or originals.
  Future<EventProfile> updateEvent(EventProfile event) async {
    event.validate();
    final now = DateTime.now().toUtc();
    final updated = event.copyWith(updatedAt: now);
    final index = events.indexWhere((existing) => existing.id == event.id);
    if (index == -1) {
      throw const EventValidationException(
        'EVENT_NOT_FOUND',
        'That event no longer exists.',
      );
    }
    events = _sortedEvents([...events]..[index] = updated);
    if (eventId == updated.id) {
      _applyEvent(updated);
    }
    await _persistCatalog();
    notifyListeners();
    return updated;
  }

  Future<EventProfile> transitionEventStatus(
    String id,
    EventStatus next,
  ) async {
    final index = events.indexWhere((event) => event.id == id);
    if (index == -1) {
      throw const EventValidationException(
        'EVENT_NOT_FOUND',
        'That event no longer exists.',
      );
    }
    final current = events[index];
    if (!current.status.canTransitionTo(next)) {
      throw EventValidationException(
        'EVENT_STATUS_TRANSITION',
        '${current.status.label} cannot move to ${next.label}.',
      );
    }
    final updated = current.copyWith(
      status: next,
      updatedAt: DateTime.now().toUtc(),
      archivedAt: next == EventStatus.archived ? DateTime.now().toUtc() : null,
      clearArchivedAt: next != EventStatus.archived,
    );
    return updateEvent(updated);
  }

  Future<EventProfile> archiveEvent(String id) =>
      transitionEventStatus(id, EventStatus.archived);

  /// Drafts with no sessions may be removed. All other events must be archived.
  Future<void> deleteDraftEvent(String id) async {
    final index = events.indexWhere((event) => event.id == id);
    if (index == -1) return;
    final event = events[index];
    if (event.status != EventStatus.draft) {
      throw const EventValidationException(
        'EVENT_DELETE_NOT_DRAFT',
        'Only draft events can be deleted. Archive this event instead.',
      );
    }
    if (await storage.hasSessions(id)) {
      throw const EventValidationException(
        'EVENT_HAS_SESSIONS',
        'This event has sessions and cannot be deleted. Archive it instead.',
      );
    }
    events = [...events]..removeAt(index);
    if (eventId == id) {
      if (events.isEmpty) {
        hasSelectedEvent = false;
        _selectedEvent = null;
        eventId = '';
        eventTitle = '';
        eventDate = '';
      } else {
        _applyEvent(events.first);
      }
    }
    await _persistCatalog();
    notifyListeners();
  }

  Future<void> _persistCatalog() async {
    try {
      await storage.writeEventCatalog(events);
    } on StorageException catch (e) {
      throw EventValidationException('EVENT_SAVE_FAILED', e.message);
    }
  }

  List<EventProfile> _sortedEvents(Iterable<EventProfile> source) {
    final list = [...source];
    int rank(EventStatus status) => switch (status) {
      EventStatus.active => 0,
      EventStatus.scheduled => 1,
      EventStatus.draft => 2,
      EventStatus.completed => 3,
      EventStatus.archived => 4,
    };
    list.sort((a, b) {
      final byStatus = rank(a.status).compareTo(rank(b.status));
      if (byStatus != 0) return byStatus;
      final aDate = DateTime.tryParse(a.dateIso);
      final bDate = DateTime.tryParse(b.dateIso);
      if (aDate != null && bDate != null) {
        final byDate = aDate.compareTo(bDate);
        if (byDate != 0) return byDate;
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return list;
  }

  Future<void> selectTemplate(PhotoTemplate next) async {
    if (_disposed || phase != BoothPhase.idle || photos.isNotEmpty) return;
    next.validate();
    template = next;
    crops.clear();
    final event = _selectedEvent;
    if (event != null) {
      try {
        await updateEvent(
          event.copyWith(
            configuration: event.configuration.copyWith(
              templateId: next.id,
              templateVersion: next.version,
            ),
          ),
        );
      } on EventValidationException {
        // Template is still applied for this session; persistence is best effort.
      }
    }
    notifyListeners();
  }

  CropDecision? cropForSlot(String slotId) => crops[slotId];

  Future<CropDecision> planCropForImage(
    int index, {
    CropMode mode = CropMode.smart,
  }) async {
    if (index < 0 || index >= photos.length) {
      throw const CropValidationException('photo index is out of range');
    }
    final image = photos[index];
    final slots = template.slotsForImage(index);
    if (slots.isEmpty) {
      throw const CropValidationException(
        'template has no slot for this photo',
      );
    }
    return cropPlanner.plan(
      image: image,
      template: template,
      slot: slots.first,
      mode: mode,
    );
  }

  Future<void> updateCrop(CropDecision decision) async {
    decision.validate();
    if (decision.templateId != template.id ||
        decision.templateVersion != template.version) {
      throw const CropValidationException(
        'crop template does not match the session',
      );
    }
    final slot = template.slots
        .where((s) => s.id == decision.slotId)
        .firstOrNull;
    if (slot == null || slot.imageIndex >= photos.length) {
      throw const CropValidationException('crop slot is not in this session');
    }
    if (photos[slot.imageIndex].id != decision.imageId) {
      throw const CropValidationException('crop image does not match the slot');
    }
    crops[decision.slotId] = decision;
    notifyListeners();
    await _writeMetadata();
  }

  Future<void> _computeCropsForImage(int index) async {
    if (index < 0 || index >= photos.length) return;
    final image = photos[index];
    for (final slot in template.slotsForImage(index)) {
      final decision = await cropPlanner.plan(
        image: image,
        template: template,
        slot: slot,
      );
      crops[slot.id] = decision;
    }
  }

  void _applyEvent(EventProfile event) {
    _selectedEvent = event;
    eventId = event.id;
    eventTitle = event.title;
    eventDate = event.date;
    final config = event.configuration;
    final match = BuiltinTemplates.all.where(
      (candidate) =>
          candidate.id == config.templateId &&
          candidate.version == config.templateVersion,
    );
    final preferred = match.isNotEmpty ? match.first : null;
    template = BuiltinTemplates.forPhotoCount(
      config.photoCount,
      preferred: preferred,
    );
    crops.clear();
  }

  Future<void> loadSessionFoundation() async {
    if (_disposed || !hasSelectedEvent) return;
    try {
      sessionHistory = await storage.readSessionsForEvent(eventId);
      final active = await storage.latestActiveSession(eventId);
      if (active != null && active.photoCount < active.expectedPhotoCount) {
        final recovery = await storage.readSessionRecovery(
          eventId,
          active.sessionId,
        );
        await storage.markSessionInterrupted(
          eventId: eventId,
          sessionId: active.sessionId,
        );
        interruptedRecovery = recovery;
        interruptedSession = BoothSessionRecord(
          eventId: active.eventId,
          sessionId: active.sessionId,
          startedAt: active.startedAt,
          endedAt: DateTime.now().toUtc(),
          status: BoothSessionStatus.interrupted,
          photoCount: active.photoCount,
          expectedPhotoCount: active.expectedPhotoCount,
          templateId: active.templateId,
          templateVersion: active.templateVersion,
          countdownSeconds: active.countdownSeconds,
        );
        sessionHistory = await storage.readSessionsForEvent(eventId);
      } else {
        interruptedSession = null;
        interruptedRecovery = null;
      }
      if (!_disposed) notifyListeners();
    } catch (_) {
      // Session history is diagnostic; catalog/capture remains usable.
    }
  }

  void _cameraChanged() {
    notifyListeners();
  }

  void setBridge(String baseUrl) {
    bridge = BridgeClient(baseUrl: baseUrl, token: bridge.token);
    bridgeHealth = null;
    bridgeCheckError = null;
    notifyListeners();
  }

  Future<void> loadSettings() async {
    if (_disposed) return;
    try {
      final settings = await storage.readSettings();
      final storedUrl = settings['bridge_url'];
      final url = storedUrl is String && storedUrl.trim().isNotEmpty
          ? storedUrl.trim()
          : bridge.baseUrl;
      String? token;
      try {
        token = await bridgeTokenStore?.read();
      } catch (_) {
        // A Keychain failure must not expose or log the token.
      }
      bridge = BridgeClient(baseUrl: url, token: token);
      bridgeHealth = null;
      bridgeCheckError = null;
      notifyListeners();
    } catch (_) {
      // Settings are optional; defaults remain usable.
    }
  }

  Future<void> saveBridgeUrl(String baseUrl) async {
    final url = baseUrl.trim();
    if (url.isEmpty) return;
    setBridge(url);
    try {
      final settings = await storage.readSettings();
      settings['bridge_url'] = url;
      await storage.writeSettings(settings);
    } catch (_) {
      // Keep the in-memory setting if persistence fails.
    }
  }

  Future<void> saveBridgeToken(String token) async {
    final value = token.trim();
    if (value.isEmpty || bridgeTokenStore == null) return;
    await bridgeTokenStore!.write(value);
    bridge = BridgeClient(baseUrl: bridge.baseUrl, token: value);
    bridgeHealth = null;
    bridgeCheckError = null;
    notifyListeners();
  }

  Future<void> clearBridgeToken() async {
    await bridgeTokenStore?.clear();
    bridge = BridgeClient(baseUrl: bridge.baseUrl, token: null);
    bridgeHealth = null;
    bridgeCheckError = null;
    notifyListeners();
  }

  Future<void> checkBridge() async {
    if (_disposed || bridgeChecking) return;
    bridgeChecking = true;
    bridgeCheckError = null;
    notifyListeners();
    try {
      bridgeHealth = await bridge.health();
    } catch (e) {
      bridgeHealth = null;
      bridgeCheckError = e.toString();
    } finally {
      if (!_disposed) {
        bridgeChecking = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadRestorableSession() async {
    if (_disposed || !hasSelectedEvent || phase != BoothPhase.idle) return;
    try {
      final restored = await storage.latestUnsubmittedSession(eventId: eventId);
      if (_disposed) return;
      restorableSession = restored;
      notifyListeners();
    } catch (_) {
      // A damaged metadata file must not block normal booth operation.
    }
  }

  Future<void> restorePreviousSession() async {
    final restored = restorableSession;
    if (_disposed || restored == null || phase != BoothPhase.idle) return;
    final templateMatch =
        [...BuiltinTemplates.all, ...BuiltinTemplates.variants].where(
          (item) =>
              item.id == restored.templateId &&
              item.version == restored.templateVersion,
        );
    if (templateMatch.isEmpty) {
      restorableSession = null;
      error = 'That session uses an unsupported template version.';
      notifyListeners();
      return;
    }
    template = templateMatch.first;
    photos = restored.photos;
    sessionPhotoCount = restored.photoCount;
    sessionCountdownSeconds = restored.countdownSeconds;
    sessionTemplate = template;
    sessionConfiguration = restored.configuration;
    sessionBranding = restored.branding;
    sessionStartedAt = null;
    crops
      ..clear()
      ..addAll(restored.crops);
    sessionId = restored.sessionId;
    phase = BoothPhase.review;
    restorableSession = null;
    error = null;
    notifyListeners();
  }

  Future<void> loadSubmittedJob() async {
    if (_disposed || !hasSelectedEvent || phase != BoothPhase.idle) return;
    try {
      final found = await storage.readLatestSubmittedJob(eventId: eventId);
      if (_disposed) return;
      submittedJob = found;
      notifyListeners();
      if (found != null) await reconcileSubmittedJob();
    } catch (_) {
      // Corrupt local job metadata must not block a new session.
    }
  }

  /// Status reconciliation only: this never submits or resubmits a job.
  Future<void> reconcileSubmittedJob() async {
    final record = submittedJob;
    if (_disposed || record == null || submittedJobReconciling) return;
    submittedJobReconciling = true;
    submittedJobError = null;
    notifyListeners();
    try {
      final serverJob = await bridge.getJob(record.jobId);
      if (_disposed) return;
      job = serverJob;
      submittedJob = record.copyWith(
        printState: serverJob.state,
        completion: serverJob.completion,
        gifState: serverJob.gifState,
        deliveryUrl: serverJob.deliveryUrl,
        clearDeliveryUrl: serverJob.deliveryUrl == null,
      );
      try {
        await storage.writeSubmittedJob(submittedJob!);
      } catch (_) {
        // Keep in-memory reference even if local persistence fails.
      }
      phase = serverJob.isTerminal ? BoothPhase.done : BoothPhase.printing;
      notifyListeners();
      if (serverJob.isTerminal) {
        await _maybeLoadComposition();
        unawaited(_maybeLoadGif());
      } else {
        unawaited(_poll());
      }
    } on BridgeException catch (e) {
      submittedJobError = e.message;
      notifyListeners();
    } catch (e) {
      submittedJobError = e.toString();
      notifyListeners();
    } finally {
      if (!_disposed) {
        submittedJobReconciling = false;
        notifyListeners();
      }
    }
  }

  Future<void> dismissSubmittedJob() async {
    final record = submittedJob;
    if (record == null || _disposed) return;
    try {
      await storage.writeSubmittedJob(record.copyWith(dismissed: true));
    } catch (_) {
      // The operator explicitly dismissed it; keep moving.
    }
    submittedJob = null;
    submittedJobError = null;
    notifyListeners();
  }

  Future<void> _persistSubmittedJob(PrintJob serverJob) async {
    final record = submittedJob;
    if (record == null) return;
    final next = record.copyWith(
      printState: serverJob.state,
      completion: serverJob.completion,
      gifState: serverJob.gifState,
      deliveryUrl: serverJob.deliveryUrl,
      clearDeliveryUrl: serverJob.deliveryUrl == null,
    );
    submittedJob = next;
    try {
      await storage.writeSubmittedJob(next);
    } catch (_) {
      // Local persistence is best effort; the operator still sees the state.
    }
  }

  Future<void> _createSubmittedJob(PrintJob serverJob) async {
    submittedJob = SubmittedJob(
      eventId: eventId,
      sessionId: sessionId ?? '',
      jobId: serverJob.id,
      submittedAt: DateTime.now(),
      printState: serverJob.state,
      completion: serverJob.completion,
      gifState: serverJob.gifState,
      templateId: template.id,
      templateVersion: template.version,
      deliveryUrl: serverJob.deliveryUrl,
    );
    try {
      await storage.writeSubmittedJob(submittedJob!);
    } catch (_) {
      // Keep in-memory identity; no print retry is attempted.
    }
  }

  /// Test-only setup for the isolated JPEG import tool. The caller must use a
  /// disposable controller/storage and invoke [approve] explicitly.
  void prepareImportedTestReview({
    required CapturedImage image,
    required String testEventId,
    required String testSessionId,
  }) {
    eventId = testEventId;
    eventTitle = 'JPEG Import Test';
    eventDate = 'Disposable test';
    photos = [image];
    sessionId = testSessionId;
    sessionStartedAt = DateTime.now();
    sessionStatus = BoothSessionStatus.active;
    sessionPhotoCount = 1;
    sessionCountdownSeconds = 0;
    sessionTemplate = BuiltinTemplates.solo;
    sessionConfiguration = const EventConfiguration(
      templateId: 'solo_4x6_v1',
      templateVersion: 1,
      photoCount: 1,
      countdownSeconds: 0,
    );
    sessionBranding = const EventBranding();
    template = BuiltinTemplates.solo;
    crops.clear();
    error = null;
    phase = BoothPhase.review;
    notifyListeners();
  }

  Future<void> startSession() async {
    if (submittedJob != null) {
      error =
          'Resolve or dismiss the submitted print job before starting a new session.';
      notifyListeners();
      return;
    }
    if (!hasSelectedEvent) return;
    final event = _selectedEvent;
    if (event == null) return;
    if (event.status == EventStatus.draft) {
      error = 'Schedule this event before starting a booth session.';
      notifyListeners();
      return;
    }
    if (event.status == EventStatus.completed ||
        event.status == EventStatus.archived) {
      error =
          'This event is ${event.status.label.toLowerCase()} and cannot start a session.';
      notifyListeners();
      return;
    }
    if (phase == BoothPhase.capturing || retakingSlot != null) return;
    if (event.status == EventStatus.scheduled) {
      try {
        await transitionEventStatus(event.id, EventStatus.active);
      } on EventValidationException catch (e) {
        error = e.message;
        notifyListeners();
        return;
      }
    }
    phase = BoothPhase.capturing;
    photos = [];
    job = null;
    error = null;
    countdown = 0;
    activePhoto = 1;
    retakingSlot = null;
    retakeError = null;
    compositionBytes = null;
    compositionLoading = false;
    compositionError = null;
    gifBytes = null;
    gifLoading = false;
    gifError = null;
    crops.clear();
    restorableSession = null;
    sessionId = 'ses_${DateTime.now().millisecondsSinceEpoch}';
    sessionStartedAt = DateTime.now();
    sessionStatus = BoothSessionStatus.active;
    final custom = event.configuration.customTemplate;
    if (custom != null && custom.slots.isNotEmpty) {
      sessionPhotoCount = custom.slots
          .map((slot) => slot.captureOrder + 1)
          .reduce((a, b) => a > b ? a : b)
          .clamp(1, 4);
      sessionConfiguration = event.configuration.copyWith(
        photoCount: sessionPhotoCount,
        templateId: 'custom_design',
      );
      sessionTemplate = custom.toPhotoTemplate();
    } else {
      sessionPhotoCount = event.configuration.photoCount.clamp(1, 4);
      sessionConfiguration = event.configuration;
      sessionTemplate = BuiltinTemplates.forPhotoCount(
        sessionPhotoCount,
        preferred: template,
      );
    }
    sessionCountdownSeconds = event.configuration.countdownSeconds;
    sessionBranding = event.configuration.branding;
    template = sessionTemplate!;
    _countdownCancelled = false;
    _endRequested = false;
    cameraPipeline.resetCaptureState();
    notifyListeners();
    await _runCaptureSession();
  }

  Future<void> _startLiveViewIfAvailable() async {
    if (camera is! CameraLiveViewSource) return;
    final source = camera as CameraLiveViewSource;
    _liveViewSubscription ??= source.liveViewFrames.listen(
      (frame) {
        liveViewFrame = frame;
        if (!_disposed) notifyListeners();
      },
      onError: (Object e) {
        liveViewError = e.toString();
        if (!_disposed) notifyListeners();
      },
    );
    try {
      await source.startLiveView();
      _liveViewStarted = true;
      liveViewError = null;
    } catch (e) {
      // Live View is optional for capture; report it without failing the session.
      liveViewError = e.toString();
      _liveViewStarted = false;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _stopLiveView() async {
    final subscription = _liveViewSubscription;
    _liveViewSubscription = null;
    await subscription?.cancel();
    final source = camera;
    if (_liveViewStarted && source is CameraLiveViewSource) {
      try {
        await (source as CameraLiveViewSource).stopLiveView();
      } catch (_) {
        // Cleanup is best effort; the camera pipeline owns disconnect.
      }
    }
    _liveViewStarted = false;
    liveViewFrame = null;
    liveViewError = null;
  }

  Future<void> _runCaptureSession({bool resume = false}) async {
    try {
      if (!resume) {
        // Cleanup temp files left by a previous termination. Valid originals
        // are never touched.
        await storage.recoverIncompleteWrites(eventId: eventId);
        await storage.recoverOrphans(eventId: eventId);
      }
      await cameraPipeline.connect();
      await _startLiveViewIfAvailable();
      await _writeMetadata();
      for (var i = photos.length; i < sessionPhotoCount; i++) {
        if (_endRequested) throw const _SessionEnded();
        if (_countdownCancelled) throw const _CountdownCancelled();
        activePhoto = i + 1;
        countdownActive = sessionCountdownSeconds > 0;
        for (var n = sessionCountdownSeconds; n >= 1; n--) {
          if (_endRequested) throw const _SessionEnded();
          if (_countdownCancelled) throw const _CountdownCancelled();
          countdown = n;
          notifyListeners();
          await Future<void>.delayed(countdownDelay);
        }
        if (_endRequested) throw const _SessionEnded();
        if (_countdownCancelled) throw const _CountdownCancelled();
        countdown = 0;
        countdownActive = false;
        notifyListeners();
        final image = await cameraPipeline.capture(
          eventId: eventId,
          sessionId: sessionId!,
          slot: i + 1,
        );
        if (_endRequested) {
          photos.add(image);
          await _writeMetadata();
          throw const _SessionEnded();
        }
        photos.add(image);
        await _computeCropsForImage(i);
        await _writeMetadata();
        notifyListeners();
      }
      await _writeMetadata();
      phase = BoothPhase.review;
      notifyListeners();
    } on _SessionEnded {
      await _finishSession(BoothSessionStatus.interrupted);
    } on _CountdownCancelled {
      countdownActive = false;
      await _finishSession(BoothSessionStatus.interrupted);
    } on CameraPipelineException catch (e) {
      // Preserve a more specific disconnect reason reported while connecting.
      error = e.message == 'camera is not connected'
          ? (cameraPipeline.lastError ?? e.message)
          : e.message;
      phase = BoothPhase.error;
      notifyListeners();
    } catch (e) {
      error = e.toString();
      phase = BoothPhase.error;
      notifyListeners();
    }
  }

  /// Cancels a visible countdown before a shutter is requested. Once a capture
  /// has started, this method does not pretend to cancel the in-flight write.
  Future<void> cancelCountdown() async {
    if (phase != BoothPhase.capturing || !countdownActive) return;
    _countdownCancelled = true;
    countdown = 0;
    countdownActive = false;
    notifyListeners();
  }

  /// Ends the active guest session. During capture, it stops after the
  /// in-flight SDK/storage operation; no capture is cancelled mid-write.
  Future<void> endSession() async {
    if (phase == BoothPhase.capturing) {
      _endRequested = true;
      sessionStatus = 'ending';
      notifyListeners();
      return;
    }
    if (phase == BoothPhase.review || phase == BoothPhase.error) {
      await _finishSession(BoothSessionStatus.interrupted);
    }
  }

  Future<void> _finishSession(String status) async {
    await _stopLiveView();
    sessionStatus = status;
    try {
      await _writeMetadata(forceEnded: true);
    } catch (_) {
      // The local metadata write is best effort; originals remain untouched.
    }
    final completed = sessionId;
    sessionStartedAt = null;
    sessionStatus = 'idle';
    phase = BoothPhase.idle;
    photos = [];
    sessionId = null;
    countdownActive = false;
    _countdownCancelled = false;
    sessionTemplate = null;
    sessionConfiguration = null;
    job = null;
    error = null;
    countdown = 0;
    retakingSlot = null;
    retakeError = null;
    compositionBytes = null;
    compositionLoading = false;
    compositionError = null;
    gifBytes = null;
    gifLoading = false;
    gifError = null;
    crops.clear();
    cameraPipeline.resetCaptureState();
    if (completed != null) {
      try {
        sessionHistory = await storage.readSessionsForEvent(eventId);
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<bool> resumeInterruptedSession() async {
    final recovery = interruptedRecovery;
    if (recovery == null || !recovery.canResume) {
      error =
          'This interrupted session has missing or invalid originals and cannot be resumed safely.';
      notifyListeners();
      return false;
    }
    final record = recovery.record;
    final match = [...BuiltinTemplates.all, ...BuiltinTemplates.variants].where(
      (item) =>
          item.id == record.templateId &&
          item.version == record.templateVersion,
    );
    if (match.isEmpty) {
      error = 'This session uses an unsupported layout and cannot be resumed.';
      notifyListeners();
      return false;
    }
    template = match.first;
    sessionTemplate = template;
    sessionPhotoCount = record.expectedPhotoCount.clamp(1, 4);
    sessionCountdownSeconds = record.countdownSeconds;
    sessionConfiguration = recovery.configuration;
    sessionBranding = recovery.branding;
    sessionStartedAt = record.startedAt;
    sessionId = record.sessionId;
    sessionStatus = BoothSessionStatus.active;
    photos = List<CapturedImage>.of(recovery.photos);
    crops.clear();
    for (final crop
        in recovery.photos.isEmpty
            ? const <CropDecision>[]
            : const <CropDecision>[]) {
      crops[crop.slotId] = crop;
    }
    interruptedSession = null;
    interruptedRecovery = null;
    error = null;
    _countdownCancelled = false;
    _endRequested = false;
    phase = BoothPhase.capturing;
    notifyListeners();
    await storage.updateSessionStatus(
      eventId: eventId,
      sessionId: sessionId!,
      status: BoothSessionStatus.active,
      ended: false,
    );
    await _runCaptureSession(resume: true);
    return true;
  }

  Future<void> closeInterruptedSession() async {
    final recovery = interruptedRecovery;
    if (recovery == null) return;
    try {
      await storage.updateSessionStatus(
        eventId: eventId,
        sessionId: recovery.record.sessionId,
        status: BoothSessionStatus.recovered,
      );
    } catch (_) {
      // The session remains recoverable on disk; history is best effort.
    }
    interruptedSession = null;
    interruptedRecovery = null;
    sessionHistory = await storage.readSessionsForEvent(eventId);
    notifyListeners();
  }

  Future<void> retakeAll() async {
    if (phase == BoothPhase.capturing || retakingSlot != null) return;
    await startSession();
  }

  Future<void> retakeOne(int index) async {
    if (retakingSlot != null) return;
    if (index < 0 || index >= photos.length || sessionId == null) return;
    if (phase != BoothPhase.review) return;

    final previous = photos[index];
    retakingSlot = index;
    retakeError = null;
    notifyListeners();
    try {
      final image = await cameraPipeline.capture(
        eventId: eventId,
        sessionId: sessionId!,
        slot: index + 1,
      );
      // The pipeline only returns after validation and atomic storage. Keep the
      // old slot untouched until then.
      photos[index] = image;
      await _computeCropsForImage(index);
      try {
        await _writeMetadata();
      } catch (e) {
        // Metadata failure must not leave a half-updated review: restore the
        // previously approved image. The new original remains on disk as an
        // orphan for recovery.
        photos[index] = previous;
        rethrow;
      }
    } on CameraPipelineException catch (e) {
      // Keep phase=review and the previous image so the operator can retry or
      // approve the original photo.
      retakeError = e.message;
    } catch (e) {
      retakeError = e.toString();
    } finally {
      retakingSlot = null;
      notifyListeners();
    }
  }

  Future<void> _writeMetadata({
    bool approved = false,
    String? jobId,
    bool forceEnded = false,
  }) async {
    final session = sessionId;
    if (session == null) return;
    final ended = approved || forceEnded || sessionStatus == 'ending';
    await storage.writeSessionMetadata(
      eventId: eventId,
      sessionId: session,
      data: {
        'event_id': eventId,
        'session_id': session,
        'event_title': eventTitle,
        'event_date': eventDate,
        'camera': camera.name,
        'simulated': camera.isSimulated,
        'template': template.id,
        'template_version': template.version,
        'approved': approved,
        'status': approved
            ? BoothSessionStatus.approved
            : (forceEnded ? sessionStatus : BoothSessionStatus.active),
        'started_at': sessionStartedAt?.toUtc().toIso8601String(),
        'ended_at': ended ? DateTime.now().toUtc().toIso8601String() : null,
        'photo_count': photos.length,
        'photo_count_expected': sessionPhotoCount,
        'countdown_seconds': sessionCountdownSeconds,
        'configuration': sessionConfiguration?.toJson(),
        'branding': sessionBranding.toJson(),
        'event_status': _selectedEvent?.status.name,
        'job_id': jobId,
        'crops': [for (final crop in crops.values) crop.toJson()],
        'captured_at': DateTime.now().toIso8601String(),
        'captures': [
          for (var i = 0; i < photos.length; i++)
            {
              'slot': i + 1,
              'capture_id': photos[i].captureId,
              'id': photos[i].id,
              'path': photos[i].path,
              'width': photos[i].width,
              'height': photos[i].height,
              'orientation': photos[i].orientation,
              'sha256': photos[i].sha256,
              'captured_at': photos[i].capturedAt.toIso8601String(),
            },
        ],
      },
    );
  }

  Future<void> approve() async {
    if (phase != BoothPhase.review || retakingSlot != null) return;
    if (photos.length != expectedPhotoCount || sessionId == null) return;
    phase = BoothPhase.uploading;
    error = null;
    compositionBytes = null;
    compositionLoading = false;
    compositionError = null;
    gifBytes = null;
    gifLoading = false;
    gifError = null;
    notifyListeners();
    try {
      final custom = sessionConfiguration?.customTemplate;
      var uploadImages = photos;
      var uploadTemplate = sessionTemplate ?? template;
      var uploadBranding = sessionBranding;
      Uint8List? brandingLogo;
      if (custom != null && custom.slots.isNotEmpty) {
        if (custom.artworkPath == null) {
          throw StateError('Custom template artwork is missing.');
        }
        final artwork = await File(custom.artworkPath!).readAsBytes();
        final composed = await CustomTemplateComposer().compose(
          design: custom,
          artworkBytes: artwork,
          photos: photos,
        );
        final composedPath = await storage.saveOriginal(
          eventId: eventId,
          sessionId: sessionId!,
          index: 0,
          bytes: composed,
          captureId: 'composed_${DateTime.now().microsecondsSinceEpoch}',
          extension: 'png',
        );
        final composedImage = CapturedImage(
          id: 'composed',
          bytes: composed,
          width: 1200,
          height: 1800,
          capturedAt: DateTime.now(),
          path: composedPath,
          captureId: 'composed',
          sha256: sha256.convert(composed).toString(),
        );
        uploadImages = [composedImage, ...photos];
        uploadTemplate = BuiltinTemplates.precomposed;
        uploadBranding = const EventBranding();
      } else if (sessionBranding.enabled) {
        brandingLogo = await storage.readBrandingLogo(sessionBranding.logoPath);
      }
      job = await bridge.submit(
        eventId: eventId,
        sessionId: sessionId!,
        title: eventTitle,
        date: eventDate,
        images: uploadImages,
        template: uploadTemplate,
        crops: custom != null ? const [] : crops.values.toList(),
        branding: uploadBranding,
        brandingLogo: brandingLogo,
        printNow: false,
      );
      await _createSubmittedJob(job!);
      try {
        await _writeMetadata(approved: true, jobId: job!.id);
      } catch (_) {
        // The job is already accepted. A metadata write failure must not hide
        // the accepted job or trigger a second submission.
      }
      phase = BoothPhase.printing;
      notifyListeners();
      await _poll();
    } catch (e) {
      error = e.toString();
      phase = BoothPhase.error;
      notifyListeners();
    }
  }

  Future<void> _poll() async {
    final current = job;
    if (current == null) return;
    for (var i = 0; i < 60; i++) {
      try {
        job = await bridge.getJob(current.id);
        if (_disposed) return;
        await _persistSubmittedJob(job!);
        notifyListeners();
        unawaited(_maybeLoadGif());
        if (job!.isTerminal) {
          await _maybeLoadComposition();
          if (_disposed) return;
          phase = BoothPhase.done;
          notifyListeners();
          unawaited(_maybeLoadGif());
          return;
        }
        unawaited(_maybeLoadComposition());
      } catch (e) {
        error = e.toString();
        // Keep polling: a transient LAN failure should not lose the job.
      }
      if (_disposed) return;
      await Future<void>.delayed(pollInterval);
    }
    if (_disposed) return;
    phase = BoothPhase.done;
    notifyListeners();
    await _maybeLoadComposition();
    unawaited(_maybeLoadGif());
  }

  Future<void> revokeGuestAccess() async {
    final current = job;
    if (current == null) return;
    try {
      final updated = await bridge.revokeDelivery(current.id);
      job = updated;
      await _persistSubmittedJob(updated);
      notifyListeners();
    } catch (e) {
      submittedJobError = e.toString();
      notifyListeners();
    }
  }

  Future<void> regenerateGuestAccess() async {
    final current = job;
    if (current == null) return;
    try {
      final updated = await bridge.regenerateDelivery(current.id);
      job = updated;
      await _persistSubmittedJob(updated);
      notifyListeners();
    } catch (e) {
      submittedJobError = e.toString();
      notifyListeners();
    }
  }

  Future<void> reprint({int copies = 1}) async {
    if (phase != BoothPhase.done) return;
    final current = job;
    if (current == null) return;
    if (copies < 1 || copies > 2) return;
    try {
      job = await bridge.reprint(current.id, copies: copies);
      phase = BoothPhase.printing;
      notifyListeners();
      await _poll();
    } catch (e) {
      error = e.toString();
      phase = BoothPhase.error;
      notifyListeners();
    }
  }

  void handleAppBackgrounded() {
    cameraPipeline.handleAppBackgrounded();
    if (phase == BoothPhase.capturing) {
      error = 'Camera session interrupted while the app was in the background.';
      phase = BoothPhase.error;
    }
    notifyListeners();
  }

  Future<void> handleAppForegrounded() async {
    await cameraPipeline.handleAppForegrounded();
    notifyListeners();
  }

  Future<void> _persistGifState(String state) async {
    final record = submittedJob;
    if (record == null) return;
    submittedJob = record.copyWith(gifState: state);
    try {
      await storage.writeSubmittedJob(submittedJob!);
    } catch (_) {
      // Best-effort local state; never surface an unawaited write error.
    }
  }

  Future<void> _maybeLoadGif() async {
    if (_disposed || gifBytes != null || gifLoading) return;
    final current = job;
    if (current == null) return;
    if (current.gifState == 'failed') {
      // The bridge already reported this terminal state; avoid a redundant
      // asynchronous metadata write during shutdown.
      gifError = 'Animated GIF could not be generated.';
      notifyListeners();
      return;
    }
    if (current.gifState == 'unknown') return;
    gifLoading = true;
    gifError = null;
    if (!_disposed) notifyListeners();
    try {
      var attempts = 0;
      while (!_disposed && attempts < 30) {
        try {
          final bytes = await bridge.gif(current.id);
          if (_disposed) return;
          gifBytes = bytes;
          gifError = null;
          unawaited(_persistGifState('ready'));
          break;
        } on BridgeException catch (e) {
          if (e.code == 'GIF_NOT_READY') {
            attempts++;
            if (attempts < 30) {
              await Future<void>.delayed(pollInterval);
              continue;
            }
            gifError = 'Animated GIF is still being prepared.';
            break;
          }
          if (e.code == 'GIF_UNAVAILABLE') {
            gifError = 'Animated GIF is unavailable.';
            break;
          }
          gifError = e.message;
          break;
        } catch (e) {
          gifError = e.toString();
          break;
        }
      }
    } finally {
      if (!_disposed) {
        gifLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _maybeLoadComposition() async {
    if (_disposed) return;
    final current = job;
    if (current == null || compositionLoading || compositionBytes != null) {
      return;
    }
    if (current.state == 'received' || current.state == 'validated') return;
    compositionLoading = true;
    compositionError = null;
    if (!_disposed) notifyListeners();
    try {
      final bytes = await bridge.artefact(current.id);
      if (_disposed) return;
      compositionBytes = bytes;
    } on BridgeException catch (e) {
      if (e.code != 'ARTEFACT_NOT_READY') {
        compositionError = e.message;
      }
    } catch (e) {
      compositionError = e.toString();
    } finally {
      if (!_disposed) {
        compositionLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _persistDismissed(SubmittedJob dismissed) async {
    try {
      await storage.writeSubmittedJob(dismissed);
    } catch (_) {
      // Best effort; explicit dismissal is already reflected in memory.
    }
  }

  void reset() {
    if (submittedJob != null) {
      final dismissed = submittedJob!.copyWith(dismissed: true);
      unawaited(_persistDismissed(dismissed));
    }
    submittedJob = null;
    submittedJobError = null;
    phase = BoothPhase.idle;
    photos = [];
    job = null;
    error = null;
    countdown = 0;
    sessionId = null;
    retakingSlot = null;
    retakeError = null;
    compositionBytes = null;
    compositionLoading = false;
    compositionError = null;
    gifBytes = null;
    gifLoading = false;
    gifError = null;
    crops.clear();
    unawaited(_stopLiveView());
    cameraPipeline.resetCaptureState();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_stopLiveView());
    unawaited(camera.dispose());
    cameraPipeline.removeListener(_cameraChanged);
    cameraPipeline.dispose();
    super.dispose();
  }
}

class _SessionEnded implements Exception {
  const _SessionEnded();
}

class _CountdownCancelled implements Exception {
  const _CountdownCancelled();
}
