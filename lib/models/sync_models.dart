import 'note.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Note Sync - Track sync state of individual notes
// ─────────────────────────────────────────────────────────────────────────────

class NoteSync {
  final String noteId;
  final String? driveFileId;
  final DateTime? lastSyncedAt;
  final DateTime? remoteVersion;
  final bool pendingUpload;
  final SyncConflict? conflict;

  const NoteSync({
    required this.noteId,
    this.driveFileId,
    this.lastSyncedAt,
    this.remoteVersion,
    this.pendingUpload = false,
    this.conflict,
  });

  NoteSync copyWith({
    String? driveFileId,
    DateTime? lastSyncedAt,
    DateTime? remoteVersion,
    bool? pendingUpload,
    SyncConflict? conflict,
    bool clearConflict = false,
  }) =>
      NoteSync(
        noteId: noteId,
        driveFileId: driveFileId ?? this.driveFileId,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        remoteVersion: remoteVersion ?? this.remoteVersion,
        pendingUpload: pendingUpload ?? this.pendingUpload,
        conflict: clearConflict ? null : (conflict ?? this.conflict),
      );

  Map<String, dynamic> toJson() => {
        'noteId': noteId,
        'driveFileId': driveFileId,
        'lastSyncedAt': lastSyncedAt?.toIso8601String(),
        'remoteVersion': remoteVersion?.toIso8601String(),
        'pendingUpload': pendingUpload,
        'conflict': conflict?.toJson(),
      };

  factory NoteSync.fromJson(Map<String, dynamic> json) => NoteSync(
        noteId: json['noteId'] ?? '',
        driveFileId: json['driveFileId'],
        lastSyncedAt: json['lastSyncedAt'] != null
            ? DateTime.tryParse(json['lastSyncedAt'])
            : null,
        remoteVersion: json['remoteVersion'] != null
            ? DateTime.tryParse(json['remoteVersion'])
            : null,
        pendingUpload: json['pendingUpload'] ?? false,
        conflict: json['conflict'] != null
            ? SyncConflict.fromJson(
                Map<String, dynamic>.from(json['conflict'] as Map))
            : null,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Image Sync - Track sync state of images
// ─────────────────────────────────────────────────────────────────────────────

class ImageSync {
  final String imageId;
  final String? driveFileId;
  final bool pendingUpload;
  final bool existsOnDrive;

  const ImageSync({
    required this.imageId,
    this.driveFileId,
    this.pendingUpload = false,
    this.existsOnDrive = false,
  });

  ImageSync copyWith({
    String? driveFileId,
    bool? pendingUpload,
    bool? existsOnDrive,
  }) =>
      ImageSync(
        imageId: imageId,
        driveFileId: driveFileId ?? this.driveFileId,
        pendingUpload: pendingUpload ?? this.pendingUpload,
        existsOnDrive: existsOnDrive ?? this.existsOnDrive,
      );

  Map<String, dynamic> toJson() => {
        'imageId': imageId,
        'driveFileId': driveFileId,
        'pendingUpload': pendingUpload,
        'existsOnDrive': existsOnDrive,
      };

  factory ImageSync.fromJson(Map<String, dynamic> json) => ImageSync(
        imageId: json['imageId'] ?? '',
        driveFileId: json['driveFileId'],
        pendingUpload: json['pendingUpload'] ?? false,
        existsOnDrive: json['existsOnDrive'] ?? false,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sync Conflict - Handle conflicting versions
// ─────────────────────────────────────────────────────────────────────────────

class SyncConflict {
  final Note remoteVersion;
  final DateTime detectedAt;

  const SyncConflict({
    required this.remoteVersion,
    required this.detectedAt,
  });

  Map<String, dynamic> toJson() => {
        'remoteVersion': remoteVersion.toJson(),
        'detectedAt': detectedAt.toIso8601String(),
      };

  factory SyncConflict.fromJson(Map<String, dynamic> json) => SyncConflict(
        remoteVersion:
            Note.fromJson(Map<String, dynamic>.from(json['remoteVersion'] as Map)),
        detectedAt: DateTime.tryParse(json['detectedAt'] ?? '') ?? DateTime.now(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sync State - Overall sync tracking
// ─────────────────────────────────────────────────────────────────────────────

class SyncState {
  final Map<String, NoteSync> notes;
  final Map<String, ImageSync> images;
  String? rootFolderId;
  String? notesFolderId;
  String? imagesFolderId;
  String? manifestFileId;
  DateTime? lastSyncCompletedAt;
  String? accountEmail;

  SyncState({
    Map<String, NoteSync>? notes,
    Map<String, ImageSync>? images,
    this.rootFolderId,
    this.notesFolderId,
    this.imagesFolderId,
    this.manifestFileId,
    this.lastSyncCompletedAt,
    this.accountEmail,
  })  : notes = notes ?? {},
        images = images ?? {};

  List<String> get pendingNoteUploads =>
      notes.values.where((n) => n.pendingUpload).map((n) => n.noteId).toList();

  List<String> get pendingImageUploads => images.values
      .where((i) => i.pendingUpload)
      .map((i) => i.imageId)
      .toList();

  List<NoteSync> get conflicts =>
      notes.values.where((n) => n.conflict != null).toList();

  void markNoteDirty(String noteId) {
    notes[noteId] = (notes[noteId] ?? NoteSync(noteId: noteId))
        .copyWith(pendingUpload: true);
  }

  void markImageDirty(String imageId) {
    images[imageId] = (images[imageId] ?? ImageSync(imageId: imageId))
        .copyWith(pendingUpload: true);
  }

  Map<String, dynamic> toJson() => {
        'notes': notes.map((k, v) => MapEntry(k, v.toJson())),
        'images': images.map((k, v) => MapEntry(k, v.toJson())),
        'rootFolderId': rootFolderId,
        'notesFolderId': notesFolderId,
        'imagesFolderId': imagesFolderId,
        'manifestFileId': manifestFileId,
        'lastSyncCompletedAt': lastSyncCompletedAt?.toIso8601String(),
        'accountEmail': accountEmail,
      };

  factory SyncState.fromJson(Map<String, dynamic> json) {
    final notesMap = <String, NoteSync>{};
    final imagesMap = <String, ImageSync>{};

    (json['notes'] as Map?)?.forEach((k, v) {
      notesMap[k as String] =
          NoteSync.fromJson(Map<String, dynamic>.from(v as Map));
    });
    (json['images'] as Map?)?.forEach((k, v) {
      imagesMap[k as String] =
          ImageSync.fromJson(Map<String, dynamic>.from(v as Map));
    });

    return SyncState(
      notes: notesMap,
      images: imagesMap,
      rootFolderId: json['rootFolderId'],
      notesFolderId: json['notesFolderId'],
      imagesFolderId: json['imagesFolderId'],
      manifestFileId: json['manifestFileId'],
      lastSyncCompletedAt: json['lastSyncCompletedAt'] != null
          ? DateTime.tryParse(json['lastSyncCompletedAt'])
          : null,
      accountEmail: json['accountEmail'],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drive Manifest - Metadata for Drive sync
// ─────────────────────────────────────────────────────────────────────────────

class DriveManifest {
  final int schemaVersion;
  final DateTime generatedAt;
  final Map<String, Map<String, dynamic>> noteMetadata;
  final Set<String> imageIds;

  const DriveManifest({
    this.schemaVersion = 1,
    required this.generatedAt,
    required this.noteMetadata,
    required this.imageIds,
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'generatedAt': generatedAt.toIso8601String(),
        'noteMetadata': noteMetadata,
        'imageIds': imageIds.toList(),
      };

  factory DriveManifest.fromJson(Map<String, dynamic> json) => DriveManifest(
        schemaVersion: json['schemaVersion'] ?? 1,
        generatedAt:
            DateTime.tryParse(json['generatedAt'] ?? '') ?? DateTime.now(),
        noteMetadata: Map<String, Map<String, dynamic>>.from(
            (json['noteMetadata'] as Map?)?.map((k, v) =>
                    MapEntry(k, Map<String, dynamic>.from(v as Map))) ??
                {}),
        imageIds: Set<String>.from((json['imageIds'] as List?) ?? []),
      );

  factory DriveManifest.empty() => DriveManifest(
        schemaVersion: 1,
        generatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        noteMetadata: {},
        imageIds: {},
      );
}
