import 'dart:typed_data';

import 'crop/crop_models.dart';

class CapturedImage {
  final String id;
  final Uint8List bytes;
  final String? path;
  final int width;
  final int height;
  final DateTime capturedAt;
  final String? captureId;

  /// SHA-256 of the exact stored original bytes, when ingestion completed.
  final String? sha256;

  /// EXIF orientation (1-8). Bytes are never modified to apply it.
  final int orientation;

  const CapturedImage({
    required this.id,
    required this.bytes,
    required this.width,
    required this.height,
    required this.capturedAt,
    this.path,
    this.captureId,
    this.sha256,
    this.orientation = 1,
  });

  CapturedImage withPath(String value) => CapturedImage(
    id: id,
    bytes: bytes,
    width: width,
    height: height,
    capturedAt: capturedAt,
    path: value,
    captureId: captureId,
    sha256: sha256,
    orientation: orientation,
  );

  CapturedImage withCaptureId(String value) => CapturedImage(
    id: id,
    bytes: bytes,
    width: width,
    height: height,
    capturedAt: capturedAt,
    path: path,
    captureId: value,
    sha256: sha256,
    orientation: orientation,
  );
}

class PrintJob {
  final String id;
  final String state;
  final String completion;
  final int attempts;
  final String? deliveryUrl;
  final String? error;
  final String? reprintOf;
  final String gifState;
  final String printerMode;
  final List<String> imageHashes;

  const PrintJob({
    required this.id,
    required this.state,
    required this.completion,
    required this.attempts,
    this.deliveryUrl,
    this.error,
    this.reprintOf,
    this.gifState = 'unknown',
    this.printerMode = 'unknown',
    this.imageHashes = const [],
  });

  bool get isTerminal =>
      state == 'completed' || state == 'failed' || state == 'unknown';

  factory PrintJob.fromJson(Map<String, dynamic> json) => PrintJob(
    id: json['job_id'] as String,
    state: json['state'] as String,
    completion: (json['completion'] as String?) ?? 'unknown',
    attempts: (json['attempts'] as num?)?.toInt() ?? 0,
    deliveryUrl: json['delivery_url'] as String?,
    error: json['error'] as String?,
    reprintOf: json['reprint_of'] as String?,
    gifState: (json['gif_state'] as String?) ?? 'unknown',
    printerMode: (json['printer_mode'] as String?) ?? 'unknown',
    imageHashes: [
      for (final image in (json['images'] as List? ?? const []))
        if (image is Map && image['sha256'] is String)
          image['sha256'] as String,
    ],
  );
}

class HealthStatus {
  final String service;
  final String version;
  final Map<String, dynamic> printer;

  const HealthStatus({
    required this.service,
    required this.version,
    required this.printer,
  });

  factory HealthStatus.fromJson(Map<String, dynamic> json) => HealthStatus(
    service: json['service'] as String? ?? 'unknown',
    version: json['version'] as String? ?? 'unknown',
    printer: (json['printer'] as Map?)?.cast<String, dynamic>() ?? const {},
  );
}

class SubmittedJob {
  final String eventId;
  final String sessionId;
  final String jobId;
  final DateTime submittedAt;
  final String printState;
  final String completion;
  final String gifState;
  final String templateId;
  final int templateVersion;
  final String? deliveryUrl;
  final bool dismissed;

  const SubmittedJob({
    required this.eventId,
    required this.sessionId,
    required this.jobId,
    required this.submittedAt,
    this.printState = 'received',
    this.completion = 'unknown',
    this.gifState = 'pending',
    this.templateId = 'strip_2x6_3up_v1',
    this.templateVersion = 1,
    this.deliveryUrl,
    this.dismissed = false,
  });

  SubmittedJob copyWith({
    String? printState,
    String? completion,
    String? gifState,
    String? deliveryUrl,
    bool clearDeliveryUrl = false,
    bool? dismissed,
  }) => SubmittedJob(
    eventId: eventId,
    sessionId: sessionId,
    jobId: jobId,
    submittedAt: submittedAt,
    printState: printState ?? this.printState,
    completion: completion ?? this.completion,
    gifState: gifState ?? this.gifState,
    templateId: templateId,
    templateVersion: templateVersion,
    deliveryUrl: clearDeliveryUrl ? null : (deliveryUrl ?? this.deliveryUrl),
    dismissed: dismissed ?? this.dismissed,
  );

  Map<String, dynamic> toJson() => {
    'event_id': eventId,
    'session_id': sessionId,
    'job_id': jobId,
    'submitted_at': submittedAt.toUtc().toIso8601String(),
    'print_state': printState,
    'completion': completion,
    'gif_state': gifState,
    'template_id': templateId,
    'template_version': templateVersion,
    'delivery_url': deliveryUrl,
    'dismissed': dismissed,
  };

  factory SubmittedJob.fromJson(Map<String, dynamic> json) => SubmittedJob(
    eventId: json['event_id'] as String? ?? '',
    sessionId: json['session_id'] as String? ?? '',
    jobId: json['job_id'] as String? ?? '',
    submittedAt:
        DateTime.tryParse(json['submitted_at'] as String? ?? '') ??
        DateTime.now(),
    printState: json['print_state'] as String? ?? 'unknown',
    completion: json['completion'] as String? ?? 'unknown',
    gifState: json['gif_state'] as String? ?? 'unknown',
    templateId: json['template_id'] as String? ?? 'strip_2x6_3up_v1',
    templateVersion: (json['template_version'] as num?)?.toInt() ?? 1,
    deliveryUrl: json['delivery_url'] as String?,
    dismissed: json['dismissed'] == true,
  );
}

class RestorableSession {
  final String eventId;
  final String sessionId;
  final String templateId;
  final int templateVersion;
  final List<CapturedImage> photos;
  final Map<String, CropDecision> crops;
  final int photoCount;
  final int countdownSeconds;
  final EventConfiguration? configuration;
  final EventBranding branding;

  const RestorableSession({
    required this.eventId,
    required this.sessionId,
    required this.templateId,
    required this.templateVersion,
    required this.photos,
    required this.crops,
    this.photoCount = 3,
    this.countdownSeconds = 3,
    this.configuration,
    this.branding = const EventBranding(),
  });
}

enum EventStatus { draft, scheduled, active, completed, archived }

extension EventStatusX on EventStatus {
  String get label => switch (this) {
    EventStatus.draft => 'Draft',
    EventStatus.scheduled => 'Scheduled',
    EventStatus.active => 'Active',
    EventStatus.completed => 'Completed',
    EventStatus.archived => 'Archived',
  };

  String get storageValue => name;

  bool get isTerminal => this == EventStatus.archived;

  Set<EventStatus> get allowedTransitions => switch (this) {
    EventStatus.draft => {EventStatus.scheduled, EventStatus.archived},
    EventStatus.scheduled => {
      EventStatus.draft,
      EventStatus.active,
      EventStatus.archived,
    },
    EventStatus.active => {
      EventStatus.scheduled,
      EventStatus.completed,
      EventStatus.archived,
    },
    EventStatus.completed => {EventStatus.archived},
    EventStatus.archived => const {},
  };

  bool canTransitionTo(EventStatus next) =>
      next == this || allowedTransitions.contains(next);

  static EventStatus parse(String? value) {
    return EventStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => EventStatus.scheduled,
    );
  }
}

enum RetakePolicy { allOnly }

enum ReviewMode { required }

enum EventOutputFormat { jpeg }

enum BrandingPlacement { top, bottom }

class EventBranding {
  final bool enabled;
  final String title;
  final String tagline;
  final String colorHex;
  final BrandingPlacement placement;
  final String? logoPath;

  const EventBranding({
    this.enabled = false,
    this.title = '',
    this.tagline = '',
    this.colorHex = '#C8A464',
    this.placement = BrandingPlacement.bottom,
    this.logoPath,
  });

  EventBranding copyWith({
    bool? enabled,
    String? title,
    String? tagline,
    String? colorHex,
    BrandingPlacement? placement,
    String? logoPath,
    bool clearLogo = false,
  }) => EventBranding(
    enabled: enabled ?? this.enabled,
    title: title ?? this.title,
    tagline: tagline ?? this.tagline,
    colorHex: colorHex ?? this.colorHex,
    placement: placement ?? this.placement,
    logoPath: clearLogo ? null : (logoPath ?? this.logoPath),
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'title': title,
    'tagline': tagline,
    'color_hex': colorHex,
    'placement': placement.name,
    'logo_path': logoPath,
  };

  factory EventBranding.fromJson(Map<String, dynamic>? json) {
    final value = json ?? const <String, dynamic>{};
    return EventBranding(
      enabled: value['enabled'] == true,
      title: value['title'] as String? ?? '',
      tagline: value['tagline'] as String? ?? '',
      colorHex: value['color_hex'] as String? ?? '#C8A464',
      placement: BrandingPlacement.values.firstWhere(
        (item) => item.name == value['placement'],
        orElse: () => BrandingPlacement.bottom,
      ),
      logoPath: value['logo_path'] as String?,
    );
  }

  void validate() {
    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(colorHex)) {
      throw const EventValidationException(
        'BRANDING_COLOR_INVALID',
        'Brand colour must be a six-digit hex colour.',
      );
    }
    if (title.length > 80 || tagline.length > 120) {
      throw const EventValidationException(
        'BRANDING_TEXT_TOO_LONG',
        'Branding text is too long.',
      );
    }
    if (logoPath != null && logoPath!.trim().isEmpty) {
      throw const EventValidationException(
        'BRANDING_LOGO_INVALID',
        'Branding logo reference is invalid.',
      );
    }
  }

  int get colorValue =>
      int.parse(colorHex.substring(1), radix: 16) | 0xFF000000;
}

class EventConfiguration {
  final String templateId;
  final int templateVersion;
  final int photoCount;
  final int countdownSeconds;
  final RetakePolicy retakePolicy;
  final ReviewMode reviewMode;
  final EventOutputFormat outputFormat;
  final String brandingLabel;
  final EventBranding branding;

  const EventConfiguration({
    this.templateId = 'strip_2x6_3up_v1',
    this.templateVersion = 1,
    this.photoCount = 3,
    this.countdownSeconds = 3,
    this.retakePolicy = RetakePolicy.allOnly,
    this.reviewMode = ReviewMode.required,
    this.outputFormat = EventOutputFormat.jpeg,
    this.brandingLabel = 'Template branding',
    this.branding = const EventBranding(),
  });

  EventConfiguration copyWith({
    String? templateId,
    int? templateVersion,
    int? photoCount,
    int? countdownSeconds,
    RetakePolicy? retakePolicy,
    ReviewMode? reviewMode,
    EventOutputFormat? outputFormat,
    String? brandingLabel,
    EventBranding? branding,
  }) => EventConfiguration(
    templateId: templateId ?? this.templateId,
    templateVersion: templateVersion ?? this.templateVersion,
    photoCount: photoCount ?? this.photoCount,
    countdownSeconds: countdownSeconds ?? this.countdownSeconds,
    retakePolicy: retakePolicy ?? this.retakePolicy,
    reviewMode: reviewMode ?? this.reviewMode,
    outputFormat: outputFormat ?? this.outputFormat,
    brandingLabel: brandingLabel ?? this.brandingLabel,
    branding: branding ?? this.branding,
  );

  Map<String, dynamic> toJson() => {
    'template_id': templateId,
    'template_version': templateVersion,
    'photo_count': photoCount,
    'countdown_seconds': countdownSeconds,
    'retake_policy': retakePolicy.name,
    'review_mode': reviewMode.name,
    'output_format': outputFormat.name,
    'branding_label': brandingLabel,
    'branding': branding.toJson(),
  };

  factory EventConfiguration.fromJson(Map<String, dynamic>? json) {
    final value = json ?? const <String, dynamic>{};
    return EventConfiguration(
      templateId: value['template_id'] as String? ?? 'strip_2x6_3up_v1',
      templateVersion: (value['template_version'] as num?)?.toInt() ?? 1,
      photoCount: (value['photo_count'] as num?)?.toInt() ?? 3,
      countdownSeconds: (value['countdown_seconds'] as num?)?.toInt() ?? 3,
      retakePolicy: RetakePolicy.values.firstWhere(
        (item) => item.name == value['retake_policy'],
        orElse: () => RetakePolicy.allOnly,
      ),
      reviewMode: ReviewMode.values.firstWhere(
        (item) => item.name == value['review_mode'],
        orElse: () => ReviewMode.required,
      ),
      outputFormat: EventOutputFormat.values.firstWhere(
        (item) => item.name == value['output_format'],
        orElse: () => EventOutputFormat.jpeg,
      ),
      brandingLabel: value['branding_label'] as String? ?? 'Template branding',
      branding: EventBranding.fromJson(
        (value['branding'] as Map?)?.cast<String, dynamic>(),
      ),
    );
  }
}

class EventValidationException implements Exception {
  final String code;
  final String message;
  const EventValidationException(this.code, this.message);
  @override
  String toString() => 'EventValidationException($code): $message';
}

class EventProfile {
  final String id;
  final String title;
  final String date;
  final String dateIso;
  final String client;
  final String startTime;
  final String endTime;
  final String venue;
  final String description;
  final EventStatus status;
  final EventConfiguration configuration;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? archivedAt;

  const EventProfile({
    required this.id,
    required this.title,
    required this.date,
    this.dateIso = '',
    this.client = '',
    this.startTime = '',
    this.endTime = '',
    this.venue = '',
    this.description = '',
    this.status = EventStatus.scheduled,
    this.configuration = const EventConfiguration(),
    this.createdAt,
    this.updatedAt,
    this.archivedAt,
  });

  EventProfile copyWith({
    String? title,
    String? date,
    String? dateIso,
    String? client,
    String? startTime,
    String? endTime,
    String? venue,
    String? description,
    EventStatus? status,
    EventConfiguration? configuration,
    DateTime? updatedAt,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
  }) => EventProfile(
    id: id,
    title: title ?? this.title,
    date: date ?? this.date,
    dateIso: dateIso ?? this.dateIso,
    client: client ?? this.client,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    venue: venue ?? this.venue,
    description: description ?? this.description,
    status: status ?? this.status,
    configuration: configuration ?? this.configuration,
    createdAt: createdAt,
    updatedAt: updatedAt,
    archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'date': date,
    'date_iso': dateIso,
    'client': client,
    'start_time': startTime,
    'end_time': endTime,
    'venue': venue,
    'description': description,
    'status': status.storageValue,
    'configuration': configuration.toJson(),
    'created_at': createdAt?.toUtc().toIso8601String(),
    'updated_at': updatedAt?.toUtc().toIso8601String(),
    'archived_at': archivedAt?.toUtc().toIso8601String(),
  };

  factory EventProfile.fromJson(Map<String, dynamic> json) => EventProfile(
    id: json['id'] as String? ?? 'evt_unknown',
    title: json['title'] as String? ?? 'Terabooth',
    date: json['date'] as String? ?? '',
    dateIso: json['date_iso'] as String? ?? '',
    client: json['client'] as String? ?? '',
    startTime: json['start_time'] as String? ?? '',
    endTime: json['end_time'] as String? ?? '',
    venue: json['venue'] as String? ?? '',
    description: json['description'] as String? ?? '',
    status: EventStatusX.parse(json['status'] as String?),
    configuration: EventConfiguration.fromJson(
      (json['configuration'] as Map?)?.cast<String, dynamic>(),
    ),
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
    archivedAt: DateTime.tryParse(json['archived_at'] as String? ?? ''),
  );

  void validate() {
    final name = title.trim();
    if (name.isEmpty) {
      throw const EventValidationException(
        'EVENT_NAME_REQUIRED',
        'Event name is required.',
      );
    }
    if (name.length > 120) {
      throw const EventValidationException(
        'EVENT_NAME_TOO_LONG',
        'Event name must be 120 characters or fewer.',
      );
    }
    if (dateIso.isNotEmpty && DateTime.tryParse(dateIso) == null) {
      throw const EventValidationException(
        'EVENT_DATE_INVALID',
        'Event date is not valid.',
      );
    }
    if (startTime.isNotEmpty && !_validTime(startTime)) {
      throw const EventValidationException(
        'EVENT_START_INVALID',
        'Start time must be a valid time.',
      );
    }
    if (endTime.isNotEmpty && !_validTime(endTime)) {
      throw const EventValidationException(
        'EVENT_END_INVALID',
        'End time must be a valid time.',
      );
    }
    if (startTime.isNotEmpty && endTime.isNotEmpty) {
      if (_minutes(endTime) <= _minutes(startTime)) {
        throw const EventValidationException(
          'EVENT_TIME_ORDER',
          'End time must be later than start time.',
        );
      }
    }
    if (configuration.photoCount < 1 || configuration.photoCount > 4) {
      throw const EventValidationException(
        'EVENT_PHOTO_COUNT_INVALID',
        'Photo count must be between 1 and 4.',
      );
    }
    if (!const {0, 3, 5, 10}.contains(configuration.countdownSeconds)) {
      throw const EventValidationException(
        'EVENT_COUNTDOWN_INVALID',
        'Countdown must be Off, 3, 5 or 10 seconds.',
      );
    }
    configuration.branding.validate();
  }

  static bool _validTime(String value) =>
      RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value);

  static int _minutes(String value) {
    final parts = value.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
}

class SessionRecovery {
  final BoothSessionRecord record;
  final List<CapturedImage> photos;
  final List<int> missingSlots;
  final EventConfiguration? configuration;
  final EventBranding branding;
  final Map<String, CropDecision> crops;

  const SessionRecovery({
    required this.record,
    required this.photos,
    required this.missingSlots,
    this.configuration,
    this.branding = const EventBranding(),
    this.crops = const {},
  });

  bool get canResume {
    if (missingSlots.isEmpty) return true;
    if (photos.isEmpty || photos.length >= record.expectedPhotoCount) {
      return false;
    }
    // Resume is safe only when existing photos occupy slots 1..N and every
    // missing slot is after them. A hole in the middle requires recovery.
    for (var slot = 1; slot <= photos.length; slot++) {
      if (missingSlots.contains(slot)) return false;
    }
    return missingSlots.every((slot) => slot > photos.length);
  }

  int get remaining => record.expectedPhotoCount - photos.length;
}

class BoothSessionStatus {
  static const active = 'active';
  static const completed = 'completed';
  static const interrupted = 'interrupted';
  static const recovered = 'recovered';
  static const approved = 'approved';
}

class BoothSessionRecord {
  final String eventId;
  final String sessionId;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String status;
  final int photoCount;
  final int expectedPhotoCount;
  final bool approved;
  final String templateId;
  final int templateVersion;
  final int countdownSeconds;

  const BoothSessionRecord({
    required this.eventId,
    required this.sessionId,
    this.startedAt,
    this.endedAt,
    this.status = 'interrupted',
    this.photoCount = 0,
    this.expectedPhotoCount = 3,
    this.approved = false,
    this.templateId = 'strip_2x6_3up_v1',
    this.templateVersion = 1,
    this.countdownSeconds = 3,
  });

  bool get isActive => status == BoothSessionStatus.active && !approved;
  String get displayStatus => approved ? 'Approved' : status;

  factory BoothSessionRecord.fromJson(
    Map<String, dynamic> json, {
    required String fallbackEventId,
    required String fallbackSessionId,
  }) {
    final captures = json['captures'];
    final count = captures is List ? captures.length : 0;
    return BoothSessionRecord(
      eventId: json['event_id'] as String? ?? fallbackEventId,
      sessionId: json['session_id'] as String? ?? fallbackSessionId,
      startedAt: DateTime.tryParse(json['started_at'] as String? ?? ''),
      endedAt: DateTime.tryParse(json['ended_at'] as String? ?? ''),
      status: json['status'] as String? ?? 'interrupted',
      photoCount: (json['photo_count'] as num?)?.toInt() ?? count,
      expectedPhotoCount: (json['photo_count_expected'] as num?)?.toInt() ?? 3,
      approved: json['approved'] == true,
      templateId: json['template'] as String? ?? 'strip_2x6_3up_v1',
      templateVersion: (json['template_version'] as num?)?.toInt() ?? 1,
      countdownSeconds: (json['countdown_seconds'] as num?)?.toInt() ?? 3,
    );
  }
}
