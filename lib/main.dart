import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show pow;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────

const String kNotesBox = 'notes_box_v4';
const String kImagesBox = 'images_box_v1';
const String kSearchIndexBox = 'search_index_box_v2';
const String kSyncStateBox = 'sync_state_box_v3'; // replaces sync_meta_box_v2

const String kDriveRootName = '.liha_notes_app';
const String kDriveNotesDir = 'notes';
const String kDriveImagesDir = 'images';
const String kManifestName = 'manifest.json';

const int kInitialBackoffMs = 500;
const double kBackoffMultiplier = 1.5;
const int kMaxRetries = 5;
const int kMaxBackoffMs = 30000;

// ─────────────────────────────────────────────────────────────────────────────
// ENUMS
// ─────────────────────────────────────────────────────────────────────────────

enum NoteType { normal, checklist, itinerary, mealPlan, recipe }

enum ColorTheme { default_, sunset, orange, forest, lavender, rose }

enum SyncStatus { idle, syncing, error }

enum AppTheme { amber, teal, indigo, rose, slate }

// ─────────────────────────────────────────────────────────────────────────────
// APP SETTINGS PROVIDER
// ─────────────────────────────────────────────────────────────────────────────

class AppSettingsProvider extends ChangeNotifier {
  AppTheme _appTheme = AppTheme.teal;
  bool _isDarkMode = false;

  AppTheme get appTheme => _appTheme;
  bool get isDarkMode => _isDarkMode;

  static Color seedColor(AppTheme theme) => switch (theme) {
        AppTheme.amber => Colors.amber,
        AppTheme.teal => Colors.teal,
        AppTheme.indigo => Colors.indigo,
        AppTheme.rose => Colors.pink,
        AppTheme.slate => Colors.blueGrey,
      };

  static String themeName(AppTheme theme) => switch (theme) {
        AppTheme.amber => 'Amber',
        AppTheme.teal => 'Teal',
        AppTheme.indigo => 'Indigo',
        AppTheme.rose => 'Rose',
        AppTheme.slate => 'Slate',
      };

  void setAppTheme(AppTheme theme) {
    _appTheme = theme;
    notifyListeners();
  }

  void toggleDarkMode() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTE DATA MODELS
// ─────────────────────────────────────────────────────────────────────────────

class ChecklistItem {
  String id, text;
  bool checked;

  ChecklistItem({required this.id, required this.text, this.checked = false});

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'checked': checked};

  factory ChecklistItem.fromJson(Map<String, dynamic> j) => ChecklistItem(
        id: j['id'] ?? const Uuid().v4(),
        text: j['text'] ?? '',
        checked: j['checked'] ?? false,
      );
}

class ItineraryItem {
  String id, location, date, arrivalTime, departureTime, notes;

  ItineraryItem({
    required this.id,
    this.location = '',
    this.date = '',
    this.arrivalTime = '',
    this.departureTime = '',
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'location': location,
        'date': date,
        'arrivalTime': arrivalTime,
        'departureTime': departureTime,
        'notes': notes,
      };

  factory ItineraryItem.fromJson(Map<String, dynamic> j) => ItineraryItem(
        id: j['id'] ?? const Uuid().v4(),
        location: j['location'] ?? '',
        date: j['date'] ?? '',
        arrivalTime: j['arrivalTime'] ?? '',
        departureTime: j['departureTime'] ?? '',
        notes: j['notes'] ?? '',
      );
}

class MealPlanItem {
  String id, day, breakfast, lunch, dinner, snacks;

  MealPlanItem({
    required this.id,
    this.day = '',
    this.breakfast = '',
    this.lunch = '',
    this.dinner = '',
    this.snacks = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'day': day,
        'breakfast': breakfast,
        'lunch': lunch,
        'dinner': dinner,
        'snacks': snacks,
      };

  factory MealPlanItem.fromJson(Map<String, dynamic> j) => MealPlanItem(
        id: j['id'] ?? const Uuid().v4(),
        day: j['day'] ?? '',
        breakfast: j['breakfast'] ?? '',
        lunch: j['lunch'] ?? '',
        dinner: j['dinner'] ?? '',
        snacks: j['snacks'] ?? '',
      );
}

class RecipeData {
  String ingredients, instructions, prepTime, cookTime, servings;

  RecipeData({
    this.ingredients = '',
    this.instructions = '',
    this.prepTime = '',
    this.cookTime = '',
    this.servings = '',
  });

  Map<String, dynamic> toJson() => {
        'ingredients': ingredients,
        'instructions': instructions,
        'prepTime': prepTime,
        'cookTime': cookTime,
        'servings': servings,
      };

  factory RecipeData.fromJson(Map<String, dynamic> j) => RecipeData(
        ingredients: j['ingredients'] ?? '',
        instructions: j['instructions'] ?? '',
        prepTime: j['prepTime'] ?? '',
        cookTime: j['cookTime'] ?? '',
        servings: j['servings'] ?? '',
      );
}

class Note {
  String id, title, content, category;
  DateTime updatedAt;
  bool deleted, pinned;
  NoteType noteType;
  ColorTheme colorTheme;
  List<ChecklistItem> checklistItems;
  List<ItineraryItem> itineraryItems;
  List<MealPlanItem> mealPlanItems;
  RecipeData? recipeData;
  List<String> imageIds;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.updatedAt,
    this.deleted = false,
    this.category = 'General',
    this.pinned = false,
    this.noteType = NoteType.normal,
    this.colorTheme = ColorTheme.default_,
    List<ChecklistItem>? checklistItems,
    List<ItineraryItem>? itineraryItems,
    List<MealPlanItem>? mealPlanItems,
    this.recipeData,
    List<String>? imageIds,
  })  : checklistItems = checklistItems ?? [],
        itineraryItems = itineraryItems ?? [],
        mealPlanItems = mealPlanItems ?? [],
        imageIds = imageIds ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'updatedAt': updatedAt.toIso8601String(),
        'deleted': deleted,
        'category': category,
        'pinned': pinned,
        'noteType': noteType.index,
        'colorTheme': colorTheme.index,
        'checklistItems': checklistItems.map((i) => i.toJson()).toList(),
        'itineraryItems': itineraryItems.map((i) => i.toJson()).toList(),
        'mealPlanItems': mealPlanItems.map((i) => i.toJson()).toList(),
        'recipeData': recipeData?.toJson(),
        'imageIds': imageIds,
      };

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: j['id'] ?? const Uuid().v4(),
        title: j['title'] ?? '',
        content: j['content'] ?? '',
        updatedAt: DateTime.tryParse(j['updatedAt'] ?? '') ?? DateTime.now(),
        deleted: j['deleted'] ?? false,
        category: j['category'] ?? 'General',
        pinned: j['pinned'] ?? false,
        noteType: NoteType.values[j['noteType'] ?? 0],
        colorTheme: ColorTheme.values[j['colorTheme'] ?? 0],
        checklistItems: (j['checklistItems'] as List?)
                ?.map((i) =>
                    ChecklistItem.fromJson(Map<String, dynamic>.from(i as Map)))
                .toList() ??
            [],
        itineraryItems: (j['itineraryItems'] as List?)
                ?.map((i) =>
                    ItineraryItem.fromJson(Map<String, dynamic>.from(i as Map)))
                .toList() ??
            [],
        mealPlanItems: (j['mealPlanItems'] as List?)
                ?.map((i) =>
                    MealPlanItem.fromJson(Map<String, dynamic>.from(i as Map)))
                .toList() ??
            [],
        recipeData: j['recipeData'] != null
            ? RecipeData.fromJson(
                Map<String, dynamic>.from(j['recipeData'] as Map))
            : null,
        imageIds: (j['imageIds'] as List?)?.cast<String>() ?? [],
      );

  Note copyWith({
    String? id,
    String? title,
    String? content,
    String? category,
    DateTime? updatedAt,
    bool? deleted,
    bool? pinned,
    NoteType? noteType,
    ColorTheme? colorTheme,
    List<ChecklistItem>? checklistItems,
    List<ItineraryItem>? itineraryItems,
    List<MealPlanItem>? mealPlanItems,
    RecipeData? recipeData,
    List<String>? imageIds,
  }) =>
      Note(
        id: id ?? this.id,
        title: title ?? this.title,
        content: content ?? this.content,
        updatedAt: updatedAt ?? this.updatedAt,
        deleted: deleted ?? this.deleted,
        category: category ?? this.category,
        pinned: pinned ?? this.pinned,
        noteType: noteType ?? this.noteType,
        colorTheme: colorTheme ?? this.colorTheme,
        checklistItems: checklistItems ?? List.from(this.checklistItems),
        itineraryItems: itineraryItems ?? List.from(this.itineraryItems),
        mealPlanItems: mealPlanItems ?? List.from(this.mealPlanItems),
        recipeData: recipeData ?? this.recipeData,
        imageIds: imageIds ?? List.from(this.imageIds),
      );
}

class NoteAdapter extends TypeAdapter<Note> {
  @override
  final typeId = 100;

  @override
  Note read(BinaryReader r) =>
      Note.fromJson(Map<String, dynamic>.from(r.read() as Map));

  @override
  void write(BinaryWriter w, Note obj) => w.write(obj.toJson());
}

// ─────────────────────────────────────────────────────────────────────────────
// SYNC STATE MODELS  (replaces SyncMetadata + DeltaSyncTracker)
// ─────────────────────────────────────────────────────────────────────────────

/// Tracks sync state for a single note.
class NoteSync {
  final String noteId;
  final String? driveFileId;
  final DateTime? lastSyncedAt;

  /// The updatedAt timestamp of the version currently on Drive.
  final DateTime? remoteVersion;

  /// True when local changes have not yet been pushed to Drive.
  final bool pendingUpload;

  /// Non-null when both sides were modified since last sync.
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

  factory NoteSync.fromJson(Map<String, dynamic> j) => NoteSync(
        noteId: j['noteId'] ?? '',
        driveFileId: j['driveFileId'],
        lastSyncedAt: j['lastSyncedAt'] != null
            ? DateTime.tryParse(j['lastSyncedAt'])
            : null,
        remoteVersion: j['remoteVersion'] != null
            ? DateTime.tryParse(j['remoteVersion'])
            : null,
        pendingUpload: j['pendingUpload'] ?? false,
        conflict: j['conflict'] != null
            ? SyncConflict.fromJson(
                Map<String, dynamic>.from(j['conflict'] as Map))
            : null,
      );
}

/// Tracks sync state for a single image.
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

  factory ImageSync.fromJson(Map<String, dynamic> j) => ImageSync(
        imageId: j['imageId'] ?? '',
        driveFileId: j['driveFileId'],
        pendingUpload: j['pendingUpload'] ?? false,
        existsOnDrive: j['existsOnDrive'] ?? false,
      );
}

/// Stored when both local and remote were modified since last sync.
class SyncConflict {
  final Note remoteVersion;
  final DateTime detectedAt;

  const SyncConflict({required this.remoteVersion, required this.detectedAt});

  Map<String, dynamic> toJson() => {
        'remoteVersion': remoteVersion.toJson(),
        'detectedAt': detectedAt.toIso8601String(),
      };

  factory SyncConflict.fromJson(Map<String, dynamic> j) => SyncConflict(
        remoteVersion:
            Note.fromJson(Map<String, dynamic>.from(j['remoteVersion'] as Map)),
        detectedAt: DateTime.tryParse(j['detectedAt'] ?? '') ?? DateTime.now(),
      );
}

/// The single source of truth for all sync state — persisted to Hive.
class SyncState {
  /// noteId → NoteSync
  final Map<String, NoteSync> notes;

  /// imageId → ImageSync
  final Map<String, ImageSync> images;

  // Cached Drive folder/file IDs
  String? rootFolderId;
  String? notesFolderId;
  String? imagesFolderId;
  String? manifestFileId;

  /// Set after a fully successful sync pass.
  DateTime? lastSyncCompletedAt;

  SyncState({
    Map<String, NoteSync>? notes,
    Map<String, ImageSync>? images,
    this.rootFolderId,
    this.notesFolderId,
    this.imagesFolderId,
    this.manifestFileId,
    this.lastSyncCompletedAt,
  })  : notes = notes ?? {},
        images = images ?? {};

  // ── Convenience helpers ────────────────────────────────────────────────────

  /// Returns all noteIds that need to be uploaded.
  List<String> get pendingNoteUploads =>
      notes.values.where((n) => n.pendingUpload).map((n) => n.noteId).toList();

  /// Returns all imageIds that need to be uploaded.
  List<String> get pendingImageUploads => images.values
      .where((i) => i.pendingUpload)
      .map((i) => i.imageId)
      .toList();

  /// Returns all notes that have an unresolved conflict.
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

  // ── Serialisation ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'notes': notes.map((k, v) => MapEntry(k, v.toJson())),
        'images': images.map((k, v) => MapEntry(k, v.toJson())),
        'rootFolderId': rootFolderId,
        'notesFolderId': notesFolderId,
        'imagesFolderId': imagesFolderId,
        'manifestFileId': manifestFileId,
        'lastSyncCompletedAt': lastSyncCompletedAt?.toIso8601String(),
      };

  factory SyncState.fromJson(Map<String, dynamic> j) {
    final notesMap = <String, NoteSync>{};
    final imagesMap = <String, ImageSync>{};

    (j['notes'] as Map?)?.forEach((k, v) {
      notesMap[k as String] =
          NoteSync.fromJson(Map<String, dynamic>.from(v as Map));
    });
    (j['images'] as Map?)?.forEach((k, v) {
      imagesMap[k as String] =
          ImageSync.fromJson(Map<String, dynamic>.from(v as Map));
    });

    return SyncState(
      notes: notesMap,
      images: imagesMap,
      rootFolderId: j['rootFolderId'],
      notesFolderId: j['notesFolderId'],
      imagesFolderId: j['imagesFolderId'],
      manifestFileId: j['manifestFileId'],
      lastSyncCompletedAt: j['lastSyncCompletedAt'] != null
          ? DateTime.tryParse(j['lastSyncCompletedAt'])
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DRIVE MANIFEST  (written as manifest.json in Drive root folder)
// ─────────────────────────────────────────────────────────────────────────────

/// Lightweight index stored on Drive that enables delta sync without
/// listing individual files on every pull.
class DriveManifest {
  final DateTime generatedAt;

  /// noteId → updatedAt ISO string
  final Map<String, String> noteVersions;

  /// All image IDs known on Drive
  final Set<String> imageIds;

  const DriveManifest({
    required this.generatedAt,
    required this.noteVersions,
    required this.imageIds,
  });

  Map<String, dynamic> toJson() => {
        'generatedAt': generatedAt.toIso8601String(),
        'noteVersions': noteVersions,
        'imageIds': imageIds.toList(),
      };

  factory DriveManifest.fromJson(Map<String, dynamic> j) => DriveManifest(
        generatedAt:
            DateTime.tryParse(j['generatedAt'] ?? '') ?? DateTime.now(),
        noteVersions: Map<String, String>.from(j['noteVersions'] as Map? ?? {}),
        imageIds: Set<String>.from((j['imageIds'] as List?) ?? []),
      );

  /// Empty manifest used when Drive has never been initialised.
  factory DriveManifest.empty() => DriveManifest(
        generatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        noteVersions: {},
        imageIds: {},
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// THEME HELPER
// ─────────────────────────────────────────────────────────────────────────────

class ThemeHelper {
  static Color getThemeColor(ColorTheme theme, {bool isDarkMode = false}) {
    if (isDarkMode) {
      return switch (theme) {
        ColorTheme.default_ => Colors.teal.shade700,
        ColorTheme.sunset => Colors.orange.shade700,
        ColorTheme.orange => Colors.orange.shade600,
        ColorTheme.forest => Colors.green.shade700,
        ColorTheme.lavender => Colors.purple.shade700,
        ColorTheme.rose => Colors.pink.shade700,
      };
    }
    return switch (theme) {
      ColorTheme.default_ => Colors.teal.shade100,
      ColorTheme.sunset => Colors.orange.shade200,
      ColorTheme.orange => Colors.orange.shade300,
      ColorTheme.forest => Colors.green.shade200,
      ColorTheme.lavender => Colors.purple.shade200,
      ColorTheme.rose => Colors.pink.shade200,
    };
  }

  static Color getTextColorForBackground(Color bg) =>
      bg.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;

  static Color getSecondaryTextColorForBackground(Color bg) =>
      bg.computeLuminance() > 0.5 ? Colors.black54 : Colors.white70;

  static String getThemeName(ColorTheme theme) => switch (theme) {
        ColorTheme.default_ => 'Default',
        ColorTheme.sunset => 'Sunset',
        ColorTheme.orange => 'Orange',
        ColorTheme.forest => 'Forest',
        ColorTheme.lavender => 'Lavender',
        ColorTheme.rose => 'Rose',
      };

  static Icon getNoteTypeIcon(NoteType type) => switch (type) {
        NoteType.normal => const Icon(Icons.note_rounded, size: 14),
        NoteType.checklist => const Icon(Icons.check_box_rounded, size: 14),
        NoteType.itinerary => const Icon(Icons.flight_rounded, size: 14),
        NoteType.mealPlan =>
          const Icon(Icons.restaurant_menu_rounded, size: 14),
        NoteType.recipe => const Icon(Icons.menu_book_rounded, size: 14),
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTES PROVIDER
// ─────────────────────────────────────────────────────────────────────────────

class NotesProvider extends ChangeNotifier {
  // ── Hive boxes ──────────────────────────────────────────────────────────────
  Box<dynamic>? _notesBox;
  Box<String>? _imagesBox;
  Box<String>? _searchIndexBox;
  Box<dynamic>? _syncStateBox;

  // ── Google Sign-In ───────────────────────────────────────────────────────────
  late final GoogleSignIn _googleSignIn;
  GoogleSignInAccount? _currentUser;

  // ── Sync state ───────────────────────────────────────────────────────────────
  SyncState _syncState = SyncState();
  SyncStatus _syncStatus = SyncStatus.idle;
  String? _syncStatusMessage;
  Timer? _syncStatusTimer;

  // ── Public getters ───────────────────────────────────────────────────────────

  GoogleSignInAccount? get user => _currentUser;
  SyncStatus get syncStatus => _syncStatus;
  String? get syncStatusMessage => _syncStatusMessage;
  bool get isSyncing => _syncStatus == SyncStatus.syncing;
  List<NoteSync> get syncConflicts => _syncState.conflicts;

  List<Note> get notes {
    if (_notesBox == null) return [];
    final list =
        _notesBox!.values.cast<Note>().where((n) => !n.deleted).toList()
          ..sort((a, b) {
            if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
            return b.updatedAt.compareTo(a.updatedAt);
          });
    return list;
  }

  List<Note> get recycleBin =>
      _notesBox?.values.cast<Note>().where((n) => n.deleted).toList() ?? [];

  // ── Constructor ──────────────────────────────────────────────────────────────

  NotesProvider() {
    _googleSignIn = GoogleSignIn(
      scopes: [drive.DriveApi.driveFileScope],
    );
  }

  // ── Initialisation ───────────────────────────────────────────────────────────

  Future<void> init() async {
    try {
      _notesBox = await Hive.openBox<dynamic>(kNotesBox);
      _imagesBox = await Hive.openBox<String>(kImagesBox);
      _searchIndexBox = await Hive.openBox<String>(kSearchIndexBox);
      _syncStateBox = await Hive.openBox<dynamic>(kSyncStateBox);

      _loadSyncState();
      _rebuildSearchIndex();

      _googleSignIn.onCurrentUserChanged.listen((account) {
        _currentUser = account;
        notifyListeners();
      });

      _currentUser = await _googleSignIn.signInSilently();
      notifyListeners();
    } catch (e) {
      debugPrint('Init error: $e');
    }
  }

  @override
  void dispose() {
    _syncStatusTimer?.cancel();
    super.dispose();
  }

  // ── Search index ─────────────────────────────────────────────────────────────

  void _rebuildSearchIndex() {
    if (_notesBox == null || _searchIndexBox == null) return;
    _searchIndexBox!.clear();
    for (final note in _notesBox!.values.cast<Note>()) {
      _updateSearchIndex(note);
    }
  }

  void _updateSearchIndex(Note note) {
    if (_searchIndexBox == null) return;
    final text = '${note.title} ${note.content} ${note.category}'.toLowerCase();
    _searchIndexBox!.put(note.id, text);
  }

  List<Note> search(String query) {
    if (_searchIndexBox == null || _notesBox == null) return notes;
    if (query.trim().isEmpty) return notes;
    final q = query.toLowerCase();
    return _searchIndexBox!.keys
        .where((k) => (_searchIndexBox!.get(k) ?? '').contains(q))
        .map((k) => _notesBox!.get(k))
        .whereType<Note>()
        .where((n) => !n.deleted)
        .toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
  }

  // ── Note CRUD ─────────────────────────────────────────────────────────────────

  Future<void> addNote(
    String title,
    String content, {
    String category = 'General',
    NoteType noteType = NoteType.normal,
    ColorTheme colorTheme = ColorTheme.default_,
  }) async {
    if (_notesBox == null) return;
    if (title.isEmpty && content.isEmpty) return;

    final note = Note(
      id: const Uuid().v4(),
      title: title.trim(),
      content: content.trim(),
      updatedAt: DateTime.now(),
      category: category,
      noteType: noteType,
      colorTheme: colorTheme,
    );

    await _notesBox!.put(note.id, note);
    _updateSearchIndex(note);
    _syncState.markNoteDirty(note.id);
    _persistSyncState();
    notifyListeners();
  }

  Future<void> updateNote(Note note) async {
    if (_notesBox == null) return;
    note.updatedAt = DateTime.now();
    await _notesBox!.put(note.id, note);
    _updateSearchIndex(note);
    _syncState.markNoteDirty(note.id);
    // Also mark any images that aren't on Drive yet
    for (final imgId in note.imageIds) {
      final imgSync = _syncState.images[imgId];
      if (imgSync == null || !imgSync.existsOnDrive) {
        _syncState.markImageDirty(imgId);
      }
    }
    _persistSyncState();
    notifyListeners();
  }

  Future<void> softDelete(String id) async {
    final note = _notesBox?.get(id) as Note?;
    if (note != null) {
      note.deleted = true;
      note.updatedAt = DateTime.now();
      await _notesBox!.put(id, note);
      _updateSearchIndex(note);
      _syncState.markNoteDirty(id);
      _persistSyncState();
      notifyListeners();
    }
  }

  Future<void> restore(String id) async {
    final note = _notesBox?.get(id) as Note?;
    if (note != null) {
      note.deleted = false;
      note.updatedAt = DateTime.now();
      await _notesBox!.put(id, note);
      _updateSearchIndex(note);
      _syncState.markNoteDirty(id);
      _persistSyncState();
      notifyListeners();
    }
  }

  Future<void> hardDelete(String id) async {
    if (_notesBox == null) return;
    final note = _notesBox!.get(id) as Note?;
    if (note != null) {
      for (final imgId in note.imageIds) {
        await deleteImage(imgId);
      }
    }
    await _notesBox!.delete(id);
    _searchIndexBox?.delete(id);
    _syncState.notes.remove(id);
    _persistSyncState();
    notifyListeners();
  }

  // ── Image store ───────────────────────────────────────────────────────────────

  Future<String> saveImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final imageId = const Uuid().v4();
    await _imagesBox?.put(imageId, base64Encode(bytes));
    _syncState.markImageDirty(imageId);
    _persistSyncState();
    return imageId;
  }

  String? getImage(String imageId) => _imagesBox?.get(imageId);

  Future<void> deleteImage(String imageId) async {
    await _imagesBox?.delete(imageId);
    _syncState.images.remove(imageId);
    _persistSyncState();
  }

  // ── Auth ──────────────────────────────────────────────────────────────────────

  Future<void> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      notifyListeners();
    } catch (e) {
      _setStatus('Sign in failed: $e', isError: true);
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      _currentUser = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Sign out error: $e');
    }
  }

  // ── Conflict resolution ───────────────────────────────────────────────────────

  /// Keep the local version — discard the remote conflict copy.
  Future<void> resolveConflictKeepLocal(String noteId) async {
    final ns = _syncState.notes[noteId];
    if (ns == null) return;
    _syncState.notes[noteId] =
        ns.copyWith(clearConflict: true, pendingUpload: true);
    _persistSyncState();
    notifyListeners();
  }

  /// Overwrite local with the remote version stored in the conflict.
  Future<void> resolveConflictKeepRemote(String noteId) async {
    final ns = _syncState.notes[noteId];
    if (ns?.conflict == null) return;
    final remote = ns!.conflict!.remoteVersion;
    await _notesBox?.put(noteId, remote);
    _updateSearchIndex(remote);
    _syncState.notes[noteId] = ns.copyWith(
      clearConflict: true,
      pendingUpload: false,
      remoteVersion: remote.updatedAt,
      lastSyncedAt: DateTime.now(),
    );
    _persistSyncState();
    notifyListeners();
  }

  /// Keep both — the local version stays, and the remote is saved as a new note.
  Future<void> resolveConflictKeepBoth(String noteId) async {
    final ns = _syncState.notes[noteId];
    if (ns?.conflict == null) return;
    final remote = ns!.conflict!.remoteVersion;
    // Save remote as a brand-new note with a new ID
    final duplicate = remote.copyWith(
      id: const Uuid().v4(),
      title: '${remote.title} (Conflict copy)',
    );
    await _notesBox?.put(duplicate.id, duplicate);
    _updateSearchIndex(duplicate);
    _syncState.markNoteDirty(duplicate.id);
    // Clear conflict on original
    _syncState.notes[noteId] = ns.copyWith(clearConflict: true);
    _persistSyncState();
    notifyListeners();
  }

  // ── Status helpers ────────────────────────────────────────────────────────────

  /// Update the visible sync status.
  ///
  /// - [isError]  : shows error styling and does not auto-dismiss.
  /// - [isSyncing]: set to true only while an operation is actively in progress
  ///                (i.e. the spinner should spin). Success / info messages
  ///                must NOT pass isSyncing:true so the spinner stops.
  void _setStatus(
    String? msg, {
    bool isError = false,
    bool isSyncing = false,
    bool persistent = false,
  }) {
    _syncStatusTimer?.cancel();
    _syncStatusMessage = msg;

    if (msg == null) {
      _syncStatus = SyncStatus.idle;
    } else if (isError) {
      _syncStatus = SyncStatus.error;
    } else if (isSyncing) {
      _syncStatus = SyncStatus.syncing;
    } else {
      // Plain info / success message — spinner should be off.
      _syncStatus = SyncStatus.idle;
    }

    notifyListeners();

    // Auto-dismiss non-persistent, non-in-progress messages after 4 s.
    if (msg != null && !isSyncing && !persistent) {
      _syncStatusTimer = Timer(const Duration(seconds: 4), () {
        _syncStatusMessage = null;
        _syncStatus = SyncStatus.idle;
        notifyListeners();
      });
    }
  }

  // ── Retry helper (stateless — no instance-level counter) ─────────────────────

  Future<T> _retry<T>(
    Future<T> Function() op, {
    String? name,
    int maxRetries = kMaxRetries,
  }) async {
    for (int attempt = 0;; attempt++) {
      try {
        return await op();
      } catch (e) {
        if (attempt >= maxRetries) {
          debugPrint('[$name] failed after $maxRetries retries: $e');
          rethrow;
        }
        final ms = (kInitialBackoffMs * pow(kBackoffMultiplier, attempt))
            .toInt()
            .clamp(kInitialBackoffMs, kMaxBackoffMs);
        debugPrint(
            '[$name] retry ${attempt + 1}/$maxRetries after ${ms}ms: $e');
        await Future.delayed(Duration(milliseconds: ms));
      }
    }
  }

  // ── SyncState persistence ─────────────────────────────────────────────────────

  void _loadSyncState() {
    final raw = _syncStateBox?.get('state');
    if (raw != null) {
      try {
        _syncState = SyncState.fromJson(
          raw is Map ? Map<String, dynamic>.from(raw) : {},
        );
      } catch (e) {
        debugPrint('Failed to load sync state: $e');
        _syncState = SyncState();
      }
    }
  }

  void _persistSyncState() {
    _syncStateBox?.put('state', _syncState.toJson());
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // DRIVE FOLDER MANAGEMENT
  // ─────────────────────────────────────────────────────────────────────────────

  /// Ensures the three Drive folders exist and caches their IDs in SyncState.
  Future<void> _ensureFolders(drive.DriveApi api) async {
    _syncState.rootFolderId ??= await _findOrCreateFolder(
      api,
      kDriveRootName,
      parentId: null,
    );
    _syncState.notesFolderId ??= await _findOrCreateFolder(
      api,
      kDriveNotesDir,
      parentId: _syncState.rootFolderId!,
    );
    _syncState.imagesFolderId ??= await _findOrCreateFolder(
      api,
      kDriveImagesDir,
      parentId: _syncState.rootFolderId!,
    );
    _persistSyncState();
  }

  Future<String> _findOrCreateFolder(
    drive.DriveApi api,
    String name, {
    required String? parentId,
  }) async {
    final parentClause = parentId != null ? " and '$parentId' in parents" : '';
    final list = await _retry(
      () => api.files.list(
        q: "name = '$name' and mimeType = 'application/vnd.google-apps.folder'"
            " and trashed = false$parentClause",
        $fields: 'files(id)',
        pageSize: 1,
      ),
      name: 'findFolder:$name',
    );
    if (list.files?.isNotEmpty ?? false) return list.files!.first.id!;

    final meta = drive.File()
      ..name = name
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = parentId != null ? [parentId] : null;
    final created = await _retry(
      () => api.files.create(meta),
      name: 'createFolder:$name',
    );
    return created.id!;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // MANIFEST
  // ─────────────────────────────────────────────────────────────────────────────

  /// Fetches the manifest from Drive, or returns an empty one if absent.
  Future<DriveManifest> _fetchManifest(drive.DriveApi api) async {
    // Find manifest file if we don't have its ID cached
    if (_syncState.manifestFileId == null) {
      final list = await _retry(
        () => api.files.list(
          q: "name = '$kManifestName' and '${_syncState.rootFolderId}' in parents"
              " and trashed = false",
          $fields: 'files(id)',
          pageSize: 1,
        ),
        name: 'findManifest',
      );
      if (list.files?.isEmpty ?? true) return DriveManifest.empty();
      _syncState.manifestFileId = list.files!.first.id;
      _persistSyncState();
    }

    try {
      final response = await _retry(
        () => api.files.get(
          _syncState.manifestFileId!,
          downloadOptions: drive.DownloadOptions.fullMedia,
        ),
        name: 'fetchManifest',
      );
      if (response is! drive.Media) return DriveManifest.empty();
      final bytes = await response.stream.expand((c) => c).toList();
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      return DriveManifest.fromJson(json);
    } catch (e) {
      debugPrint('Could not fetch manifest: $e');
      return DriveManifest.empty();
    }
  }

  /// Rebuilds and uploads the manifest to Drive.
  Future<void> _pushManifest(drive.DriveApi api) async {
    final allNotes = _notesBox?.values.cast<Note>().toList() ?? [];
    final noteVersions = <String, String>{};
    for (final n in allNotes) {
      noteVersions[n.id] = n.updatedAt.toIso8601String();
    }
    final allImageIds = _syncState.images.entries
        .where((e) => e.value.existsOnDrive)
        .map((e) => e.key)
        .toSet();

    final manifest = DriveManifest(
      generatedAt: DateTime.now(),
      noteVersions: noteVersions,
      imageIds: allImageIds,
    );

    final encoded = utf8.encode(jsonEncode(manifest.toJson()));
    final media = drive.Media(
      Stream.value(encoded),
      encoded.length,
      contentType: 'application/json',
    );

    if (_syncState.manifestFileId != null) {
      await _retry(
        () => api.files.update(
          drive.File(),
          _syncState.manifestFileId!,
          uploadMedia: media,
        ),
        name: 'updateManifest',
      );
    } else {
      final file = drive.File()
        ..name = kManifestName
        ..parents = [_syncState.rootFolderId!];
      final created = await _retry(
        () => api.files.create(file, uploadMedia: media),
        name: 'createManifest',
      );
      _syncState.manifestFileId = created.id;
      _persistSyncState();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // UPLOAD
  // ─────────────────────────────────────────────────────────────────────────────

  /// Pushes all dirty notes and their images to Drive, then updates the manifest.
  Future<void> uploadNotes() async {
    if (_currentUser == null || _notesBox == null) {
      _setStatus('Login required', isError: true);
      return;
    }
    if (isSyncing) return;

    _setStatus('Uploading…', isSyncing: true);

    try {
      final client = await _googleSignIn.authenticatedClient();
      if (client == null) {
        throw Exception('Authentication failed');
      }
      final api = drive.DriveApi(client);

      await _ensureFolders(api);

      final dirtyNoteIds = _syncState.pendingNoteUploads;
      if (dirtyNoteIds.isEmpty) {
        _setStatus('Nothing to upload');
        return;
      }

      for (final noteId in dirtyNoteIds) {
        final note = _notesBox!.get(noteId) as Note?;
        if (note == null) continue;

        // 1. Upload images referenced by this note
        await _uploadImagesForNote(api, note);

        // 2. Upload the note JSON
        await _uploadNote(api, note);
      }

      // 3. Regenerate manifest
      await _pushManifest(api);

      _syncState.lastSyncCompletedAt = DateTime.now();
      _persistSyncState();
      _setStatus('Upload complete ✓');
    } catch (e) {
      _setStatus('Upload failed: $e', isError: true);
      debugPrint('Upload error: $e');
    } finally {
      // Ensure we never leave the spinner running after the operation ends.
      if (_syncStatus == SyncStatus.syncing) {
        _syncStatus = SyncStatus.idle;
        notifyListeners();
      }
    }
  }

  Future<void> _uploadNote(drive.DriveApi api, Note note) async {
    final encoded = utf8.encode(jsonEncode(note.toJson()));
    final media = drive.Media(
      Stream.value(encoded),
      encoded.length,
      contentType: 'application/json',
    );

    final ns = _syncState.notes[note.id];
    String? fileId = ns?.driveFileId;

    if (fileId != null) {
      final nonNullId = fileId;
      await _retry(
        () => api.files.update(drive.File(), nonNullId, uploadMedia: media),
        name: 'updateNote:${note.id}',
      );
    } else {
      final file = drive.File()
        ..name = '${note.id}.json'
        ..parents = [_syncState.notesFolderId!];
      final created = await _retry(
        () => api.files.create(file, uploadMedia: media),
        name: 'createNote:${note.id}',
      );
      fileId = created.id;
    }

    _syncState.notes[note.id] = NoteSync(
      noteId: note.id,
      driveFileId: fileId,
      lastSyncedAt: DateTime.now(),
      remoteVersion: note.updatedAt,
      pendingUpload: false,
    );
    _persistSyncState();
  }

  Future<void> _uploadImagesForNote(drive.DriveApi api, Note note) async {
    for (final imageId in note.imageIds) {
      final imgSync = _syncState.images[imageId];
      // Skip if already on Drive and not dirty
      if (imgSync?.existsOnDrive == true && imgSync?.pendingUpload == false)
        continue;

      final base64Data = _imagesBox?.get(imageId);
      if (base64Data == null) {
        // Image data missing locally — don't remove the reference; just skip.
        debugPrint('Image $imageId missing locally, skipping upload');
        continue;
      }

      final bytes = base64Decode(base64Data);
      final media = drive.Media(
        Stream.value(bytes),
        bytes.length,
        contentType: 'application/octet-stream',
      );

      String? fileId = imgSync?.driveFileId;
      if (fileId != null) {
        await _retry(
          () => api.files.update(drive.File(), fileId!, uploadMedia: media),
          name: 'updateImage:$imageId',
        );
      } else {
        final file = drive.File()
          ..name = '$imageId.bin'
          ..parents = [_syncState.imagesFolderId!];
        final created = await _retry(
          () => api.files.create(file, uploadMedia: media),
          name: 'createImage:$imageId',
        );
        fileId = created.id;
      }

      _syncState.images[imageId] = ImageSync(
        imageId: imageId,
        driveFileId: fileId,
        pendingUpload: false,
        existsOnDrive: true,
      );
      _persistSyncState();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // DOWNLOAD
  // ─────────────────────────────────────────────────────────────────────────────

  /// Pulls notes from Drive using the manifest as a delta index.
  Future<void> downloadNotes() async {
    if (_currentUser == null || _notesBox == null) {
      _setStatus('Login required', isError: true);
      return;
    }
    if (isSyncing) return;

    _setStatus('Checking for updates…', isSyncing: true);

    try {
      final client = await _googleSignIn.authenticatedClient();
      if (client == null) {
        throw Exception('Authentication failed');
      }
      final api = drive.DriveApi(client);

      await _ensureFolders(api);

      // 1. Fetch the lightweight manifest (one API call)
      final manifest = await _fetchManifest(api);

      // 2. Diff manifest against local state to find what to download
      final toDownload = _diffManifest(manifest);

      if (toDownload.isEmpty) {
        _setStatus('Already up to date ✓');
        return;
      }

      _setStatus('Downloading ${toDownload.length} note(s)…', isSyncing: true);

      // 3. Download each note that changed
      for (final noteId in toDownload) {
        await _downloadNote(api, manifest, noteId);
      }

      // 4. Download any images that are on Drive but missing locally
      await _downloadMissingImages(api, manifest);

      _syncState.lastSyncCompletedAt = DateTime.now();
      _persistSyncState();
      _setStatus('Download complete ✓');
      notifyListeners();
    } catch (e) {
      _setStatus('Download failed: $e', isError: true);
      debugPrint('Download error: $e');
    } finally {
      // Ensure we never leave the spinner running after the operation ends.
      if (_syncStatus == SyncStatus.syncing) {
        _syncStatus = SyncStatus.idle;
        notifyListeners();
      }
    }
  }

  /// Returns note IDs that need to be downloaded based on manifest diff.
  List<String> _diffManifest(DriveManifest manifest) {
    final toDownload = <String>[];

    for (final entry in manifest.noteVersions.entries) {
      final noteId = entry.key;
      final remoteTs = DateTime.tryParse(entry.value);
      if (remoteTs == null) continue;

      final ns = _syncState.notes[noteId];
      final localNote = _notesBox!.get(noteId) as Note?;

      if (localNote == null) {
        // Brand-new note from Drive
        toDownload.add(noteId);
      } else if (ns?.remoteVersion == null ||
          remoteTs.isAfter(ns!.remoteVersion!)) {
        // Remote version is newer than what we last saw
        toDownload.add(noteId);
      }
      // else: already in sync → skip
    }

    return toDownload;
  }

  Future<void> _downloadNote(
    drive.DriveApi api,
    DriveManifest manifest,
    String noteId,
  ) async {
    // Resolve Drive file ID
    String? fileId = _syncState.notes[noteId]?.driveFileId;
    if (fileId == null) {
      // Need to find it by listing the notes folder (only happens on first sync)
      final list = await _retry(
        () => api.files.list(
          q: "name = '$noteId.json' and '${_syncState.notesFolderId}' in parents"
              " and trashed = false",
          $fields: 'files(id)',
          pageSize: 1,
        ),
        name: 'findNote:$noteId',
      );
      if (list.files?.isEmpty ?? true) {
        debugPrint('Note $noteId not found on Drive');
        return;
      }
      fileId = list.files!.first.id!;
    }

    final response = await _retry(
      () => api.files.get(
        fileId!,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ),
      name: 'downloadNote:$noteId',
    );
    if (response is! drive.Media) {
      throw Exception('Unexpected response type');
    }

    final bytes = await response.stream.expand((c) => c).toList();
    final remoteNote = Note.fromJson(
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
    );

    final localNote = _notesBox!.get(noteId) as Note?;
    final ns = _syncState.notes[noteId];

    // ── Conflict detection ──────────────────────────────────────────────────
    // A conflict exists when:
    //   - We have a lastSyncedAt (i.e. we've synced this note before)
    //   - Local was modified after that sync (local is dirty)
    //   - Remote is also newer than what we last pushed
    final localDirty = ns?.pendingUpload == true;
    final remoteNewer = ns?.remoteVersion == null ||
        remoteNote.updatedAt.isAfter(ns!.remoteVersion!);

    if (localNote != null &&
        localDirty &&
        remoteNewer &&
        ns?.lastSyncedAt != null) {
      // Both sides changed → store conflict, keep local active
      debugPrint('Conflict detected on note $noteId');
      _syncState.notes[noteId] = (ns ?? NoteSync(noteId: noteId)).copyWith(
        driveFileId: fileId,
        remoteVersion: remoteNote.updatedAt,
        conflict: SyncConflict(
          remoteVersion: remoteNote,
          detectedAt: DateTime.now(),
        ),
      );
      _persistSyncState();
      return; // Do NOT overwrite local — surface to user instead
    }

    // ── No conflict: accept remote ─────────────────────────────────────────
    // Do NOT strip image IDs for missing images — queue them for download instead
    for (final imgId in remoteNote.imageIds) {
      if (_imagesBox?.get(imgId) == null) {
        final existing = _syncState.images[imgId];
        _syncState.images[imgId] = ImageSync(
          imageId: imgId,
          driveFileId: existing?.driveFileId,
          pendingUpload: false,
          existsOnDrive:
              true, // assume Drive has it; will be verified on download
        );
      }
    }

    await _notesBox!.put(noteId, remoteNote);
    _updateSearchIndex(remoteNote);

    _syncState.notes[noteId] = NoteSync(
      noteId: noteId,
      driveFileId: fileId,
      lastSyncedAt: DateTime.now(),
      remoteVersion: remoteNote.updatedAt,
      pendingUpload: false,
    );
    _persistSyncState();
  }

  /// Downloads any images that are listed in the manifest but absent locally.
  Future<void> _downloadMissingImages(
    drive.DriveApi api,
    DriveManifest manifest,
  ) async {
    for (final imageId in manifest.imageIds) {
      if (_imagesBox?.get(imageId) != null) continue; // already have it

      final imgSync = _syncState.images[imageId];
      String? fileId = imgSync?.driveFileId;

      if (fileId == null) {
        // Look it up in the images folder
        final list = await _retry(
          () => api.files.list(
            q: "name = '$imageId.bin' and '${_syncState.imagesFolderId}' in parents"
                " and trashed = false",
            $fields: 'files(id)',
            pageSize: 1,
          ),
          name: 'findImage:$imageId',
        );
        if (list.files?.isEmpty ?? true) {
          debugPrint('Image $imageId not found on Drive');
          continue;
        }
        fileId = list.files!.first.id!;
      }

      try {
        final response = await _retry(
          () => api.files.get(
            fileId!,
            downloadOptions: drive.DownloadOptions.fullMedia,
          ),
          name: 'downloadImage:$imageId',
        );
        if (response is! drive.Media) continue;

        final bytes = await response.stream.expand((c) => c).toList();
        await _imagesBox?.put(imageId, base64Encode(Uint8List.fromList(bytes)));

        _syncState.images[imageId] = ImageSync(
          imageId: imageId,
          driveFileId: fileId,
          pendingUpload: false,
          existsOnDrive: true,
        );
        _persistSyncState();
      } catch (e) {
        debugPrint('Failed to download image $imageId: $e');
        // Non-fatal: the note reference is preserved; will retry on next sync.
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APP ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(NoteAdapter());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => NotesProvider()..init(),
          lazy: false,
        ),
        ChangeNotifierProvider(create: (_) => AppSettingsProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ROOT WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final seed = AppSettingsProvider.seedColor(settings.appTheme);

    final baseCardTheme = CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    );

    return MaterialApp(
      title: 'noteliha',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: seed,
        brightness: Brightness.light,
        appBarTheme: AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 1,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade900,
            letterSpacing: -0.5,
          ),
        ),
        cardTheme: baseCardTheme.copyWith(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 1,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        cardTheme: baseCardTheme.copyWith(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade800),
          ),
        ),
      ),
      themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const NoteListScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTE LIST SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class NoteListScreen extends StatefulWidget {
  const NoteListScreen({super.key});

  @override
  State<NoteListScreen> createState() => _NoteListScreenState();
}

class _NoteListScreenState extends State<NoteListScreen> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<NotesProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final notes = _searchQuery.isEmpty ? prov.notes : prov.search(_searchQuery);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        title: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'note',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                  letterSpacing: -0.8,
                ),
              ),
              TextSpan(
                text: 'liha',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.primary,
                  letterSpacing: -0.8,
                ),
              ),
            ],
          ),
        ),
        actions: [
          // Conflict badge
          if (prov.syncConflicts.isNotEmpty)
            IconButton(
              onPressed: () => _showConflictsSheet(context, prov),
              icon: Badge(
                label: Text('${prov.syncConflicts.length}'),
                child: const Icon(Icons.warning_amber_rounded),
              ),
              tooltip: 'Sync conflicts',
            ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (q) {
                _debounceTimer?.cancel();
                _debounceTimer = Timer(const Duration(milliseconds: 300), () {
                  setState(() => _searchQuery = q);
                });
              },
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search_rounded,
                    color: colorScheme.onSurfaceVariant),
                hintText: 'Search notes...',
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withAlpha(80),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      BorderSide(color: colorScheme.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
      body: notes.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _searchQuery.isEmpty
                        ? Icons.note_add_outlined
                        : Icons.search_off_rounded,
                    size: 56,
                    color: colorScheme.onSurfaceVariant.withAlpha(100),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _searchQuery.isEmpty
                        ? 'No notes yet.\nTap + to create one.'
                        : 'No notes found.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
              itemCount: notes.length,
              itemBuilder: (c, i) {
                final n = notes[i];
                final hasConflict =
                    prov.syncConflicts.any((ns) => ns.noteId == n.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Dismissible(
                    key: Key(n.id),
                    background: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) async {
                      return await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete Note'),
                              content: const Text('Move to recycle bin?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          ) ??
                          false;
                    },
                    onDismissed: (_) =>
                        Provider.of<NotesProvider>(context, listen: false)
                            .softDelete(n.id),
                    child: Stack(
                      children: [
                        _NoteCard(note: n),
                        if (hasConflict)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Icon(
                              Icons.warning_amber_rounded,
                              size: 16,
                              color: Colors.orange.shade700,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNoteTypeDialog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Note'),
      ),
    );
  }

  void _showNoteTypeDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Choose note type',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              ...NoteType.values.map((type) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: colorScheme.primaryContainer,
                      child: ThemeHelper.getNoteTypeIcon(type),
                    ),
                    title: Text(
                      type.name[0].toUpperCase() + type.name.substring(1),
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NoteEditorScreen(noteType: type),
                        ),
                      );
                    },
                  )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showConflictsSheet(BuildContext context, NotesProvider prov) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Sync Conflicts',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'These notes were modified on multiple devices. Choose how to resolve each conflict.',
                style: TextStyle(
                    fontSize: 13, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  children: prov.syncConflicts.map((ns) {
                    final localNote = prov.notes.firstWhere(
                      (n) => n.id == ns.noteId,
                      orElse: () => Note(
                        id: ns.noteId,
                        title: '(Deleted)',
                        content: '',
                        updatedAt: DateTime.now(),
                      ),
                    );
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localNote.title.isNotEmpty
                                  ? localNote.title
                                  : '(Untitled)',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Local: ${DateFormat('MMM d, HH:mm').format(localNote.updatedAt)}'
                              '  •  Remote: ${DateFormat('MMM d, HH:mm').format(ns.conflict!.remoteVersion.updatedAt)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              children: [
                                FilledButton.tonal(
                                  onPressed: () {
                                    prov.resolveConflictKeepLocal(ns.noteId);
                                    if (prov.syncConflicts.isEmpty) {
                                      Navigator.pop(ctx);
                                    }
                                  },
                                  child: const Text('Keep Local'),
                                ),
                                FilledButton.tonal(
                                  onPressed: () {
                                    prov.resolveConflictKeepRemote(ns.noteId);
                                    if (prov.syncConflicts.isEmpty) {
                                      Navigator.pop(ctx);
                                    }
                                  },
                                  child: const Text('Keep Remote'),
                                ),
                                OutlinedButton(
                                  onPressed: () {
                                    prov.resolveConflictKeepBoth(ns.noteId);
                                    if (prov.syncConflicts.isEmpty) {
                                      Navigator.pop(ctx);
                                    }
                                  },
                                  child: const Text('Keep Both'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTE CARD
// ─────────────────────────────────────────────────────────────────────────────

class _NoteCard extends StatelessWidget {
  final Note note;
  const _NoteCard({required this.note});

  String _previewText() => switch (note.noteType) {
        NoteType.normal => note.content,
        NoteType.checklist => '${note.checklistItems.length} items · '
            '${note.checklistItems.where((i) => i.checked).length} done',
        NoteType.itinerary => '${note.itineraryItems.length} destinations',
        NoteType.mealPlan => '${note.mealPlanItems.length} days planned',
        NoteType.recipe => note.recipeData?.ingredients ?? note.content,
      };

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final noteColor =
        ThemeHelper.getThemeColor(note.colorTheme, isDarkMode: isDarkMode);
    final textColor = ThemeHelper.getTextColorForBackground(noteColor);
    final subColor = ThemeHelper.getSecondaryTextColorForBackground(noteColor);
    final preview = _previewText();

    return Material(
      color: noteColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => NoteEditorScreen(note: note)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  if (note.pinned)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.push_pin_rounded,
                          size: 14, color: textColor),
                    ),
                  Expanded(
                    child: Text(
                      note.title.isNotEmpty ? note.title : '(Untitled)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('MMM d').format(note.updatedAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: subColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              // Preview
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: subColor, height: 1.4),
                ),
              ],
              // Image strip thumbnail
              if (note.imageIds.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.photo_library_outlined,
                        size: 13, color: subColor),
                    const SizedBox(width: 4),
                    Text(
                      '${note.imageIds.length} image${note.imageIds.length == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 11, color: subColor),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              // Tags
              Row(
                children: [
                  _Tag(
                    color: textColor,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ThemeHelper.getNoteTypeIcon(note.noteType),
                        const SizedBox(width: 4),
                        Text(
                          note.noteType.name[0].toUpperCase() +
                              note.noteType.name.substring(1),
                          style: TextStyle(
                            fontSize: 11,
                            color: textColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _Tag(
                    color: textColor,
                    child: Text(
                      note.category,
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor,
                        fontWeight: FontWeight.w500,
                      ),
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
}

class _Tag extends StatelessWidget {
  final Color color;
  final Widget child;
  const _Tag({required this.color, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(6),
        ),
        child: child,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SETTINGS SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<NotesProvider>(context);
    final settings = Provider.of<AppSettingsProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: colorScheme.surface,
      ),
      body: Column(
        children: [
          // Status banner
          if (prov.syncStatusMessage != null)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              color: prov.syncStatus == SyncStatus.error
                  ? colorScheme.errorContainer
                  : colorScheme.primaryContainer,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  prov.isSyncing
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        )
                      : Icon(
                          prov.syncStatus == SyncStatus.error
                              ? Icons.error_outline_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 18,
                          color: prov.syncStatus == SyncStatus.error
                              ? colorScheme.onErrorContainer
                              : colorScheme.onPrimaryContainer,
                        ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      prov.syncStatusMessage ?? '',
                      style: TextStyle(
                        fontSize: 13,
                        color: prov.syncStatus == SyncStatus.error
                            ? colorScheme.onErrorContainer
                            : colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                // ── Account ──────────────────────────────────────────────────
                const _SectionHeader(title: 'Account'),
                Card(
                  child: prov.user == null
                      ? ListTile(
                          leading: CircleAvatar(
                            backgroundColor: colorScheme.primaryContainer,
                            child: Icon(
                              Icons.person_outline_rounded,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          title: const Text(
                            'Sign in with Google',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text('Sync notes across devices'),
                          trailing: FilledButton.tonal(
                            onPressed: prov.signIn,
                            child: const Text('Sign In'),
                          ),
                        )
                      : _LoggedInTile(prov: prov, colorScheme: colorScheme),
                ),

                // ── Appearance ───────────────────────────────────────────────
                const SizedBox(height: 20),
                const _SectionHeader(title: 'Appearance'),
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        secondary: Icon(
                          settings.isDarkMode
                              ? Icons.dark_mode_rounded
                              : Icons.light_mode_rounded,
                          color: colorScheme.primary,
                        ),
                        title: const Text(
                          'Dark Mode',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(settings.isDarkMode ? 'On' : 'Off'),
                        value: settings.isDarkMode,
                        onChanged: (_) => settings.toggleDarkMode(),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                        child: Text(
                          'App Color',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: AppTheme.values.map((theme) {
                            final isSelected = settings.appTheme == theme;
                            final color = AppSettingsProvider.seedColor(theme);
                            return GestureDetector(
                              onTap: () => settings.setAppTheme(theme),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color:
                                      color.withAlpha(isSelected ? 255 : 180),
                                  shape: BoxShape.circle,
                                  border: isSelected
                                      ? Border.all(
                                          color: colorScheme.onSurface,
                                          width: 3,
                                        )
                                      : null,
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: color.withAlpha(120),
                                            blurRadius: 10,
                                            spreadRadius: 2,
                                          )
                                        ]
                                      : null,
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check_rounded,
                                        color: Colors.white,
                                        size: 22,
                                      )
                                    : null,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Center(
                          child: Text(
                            AppSettingsProvider.themeName(settings.appTheme),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── About ────────────────────────────────────────────────────
                const SizedBox(height: 20),
                const _SectionHeader(title: 'About'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.info_outline_rounded,
                            color: colorScheme.primary),
                        title: const Text('Version'),
                        trailing: Text(
                          '2.0.0',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                      ListTile(
                        leading: Icon(Icons.storage_rounded,
                            color: colorScheme.primary),
                        title: const Text('Storage'),
                        subtitle:
                            const Text('Offline-first with Google Drive sync'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Extracted to keep SettingsScreen build method readable
class _LoggedInTile extends StatelessWidget {
  final NotesProvider prov;
  final ColorScheme colorScheme;
  const _LoggedInTile({required this.prov, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // User info
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundImage: prov.user!.photoUrl != null
                    ? NetworkImage(prov.user!.photoUrl!)
                    : null,
                backgroundColor: colorScheme.primaryContainer,
                child: prov.user!.photoUrl == null
                    ? Text(
                        prov.user!.email[0].toUpperCase(),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prov.user!.displayName ?? 'Google User',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      prov.user!.email,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Upload
        ListTile(
          leading:
              Icon(Icons.cloud_upload_outlined, color: colorScheme.primary),
          title: const Text('Upload Backup'),
          subtitle: const Text('Push changed notes & images to Google Drive'),
          onTap: () async {
            final ok = await _confirm(
              context,
              title: 'Upload Backup',
              message: 'Push all pending local changes to Google Drive?',
            );
            if (ok) prov.uploadNotes();
          },
        ),

        // Download
        ListTile(
          leading:
              Icon(Icons.cloud_download_outlined, color: colorScheme.primary),
          title: const Text('Restore from Drive'),
          subtitle: const Text('Pull updates from Google Drive (delta sync)'),
          onTap: () async {
            final ok = await _confirm(
              context,
              title: 'Restore from Drive',
              message:
                  'Download notes changed on Drive? Conflicts will be flagged for review.',
            );
            if (ok) prov.downloadNotes();
          },
        ),

        // Recycle Bin
        ListTile(
          leading:
              Icon(Icons.delete_sweep_outlined, color: colorScheme.primary),
          title: const Text('Recycle Bin'),
          subtitle: const Text('View deleted notes'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RecycleBinScreen()),
          ),
        ),

        const Divider(height: 1),

        // Sign out
        ListTile(
          leading: Icon(Icons.logout_rounded, color: colorScheme.error),
          title: Text('Sign Out', style: TextStyle(color: colorScheme.error)),
          onTap: () async {
            final ok = await _confirm(
              context,
              title: 'Sign Out',
              message: 'Your notes will remain on this device.',
            );
            if (ok) prov.signOut();
          },
        ),
      ],
    );
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTE EDITOR SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class NoteEditorScreen extends StatefulWidget {
  final Note? note;
  final NoteType noteType;

  const NoteEditorScreen({
    super.key,
    this.note,
    this.noteType = NoteType.normal,
  });

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late Note _editing;
  late TextEditingController _titleCtrl;
  late TextEditingController _contentCtrl;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _editing = widget.note != null
        ? widget.note!.copyWith(
            checklistItems: List.from(widget.note!.checklistItems),
            itineraryItems: List.from(widget.note!.itineraryItems),
            mealPlanItems: List.from(widget.note!.mealPlanItems),
            imageIds: List.from(widget.note!.imageIds),
          )
        : Note(
            id: const Uuid().v4(),
            title: '',
            content: '',
            updatedAt: DateTime.now(),
            noteType: widget.noteType,
            colorTheme: _defaultColorForTheme(),
          );

    _titleCtrl = TextEditingController(text: _editing.title);
    _contentCtrl = TextEditingController(text: _editing.content);
  }

  ColorTheme _defaultColorForTheme() {
    final appTheme =
        Provider.of<AppSettingsProvider>(context, listen: false).appTheme;
    return switch (appTheme) {
      AppTheme.amber => ColorTheme.sunset,
      AppTheme.teal => ColorTheme.default_,
      AppTheme.indigo => ColorTheme.lavender,
      AppTheme.rose => ColorTheme.rose,
      AppTheme.slate => ColorTheme.forest,
    };
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      setState(() => _isLoading = true);
      final image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null && mounted) {
        final prov = Provider.of<NotesProvider>(context, listen: false);
        final imageId = await prov.saveImage(File(image.path));
        setState(() => _editing.imageIds.add(imageId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _save() {
    _editing.title = _titleCtrl.text.trim();
    _editing.content = _contentCtrl.text.trim();

    if (_editing.title.isEmpty &&
        _editing.content.isEmpty &&
        _editing.checklistItems.isEmpty &&
        _editing.itineraryItems.isEmpty &&
        _editing.mealPlanItems.isEmpty &&
        _editing.imageIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note cannot be empty')),
      );
      return;
    }

    Provider.of<NotesProvider>(context, listen: false).updateNote(_editing);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final noteColor =
        ThemeHelper.getThemeColor(_editing.colorTheme, isDarkMode: isDarkMode);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note == null ? 'New Note' : 'Edit Note'),
        backgroundColor: noteColor,
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            onPressed: _save,
            icon: const Icon(Icons.check),
            tooltip: 'Save',
          ),
          PopupMenuButton<Object>(
            onSelected: (v) {
              if (v == 'delete') {
                _showDeleteConfirmation();
              }
              if (v == 'toggle_pin') {
                setState(() => _editing.pinned = !_editing.pinned);
              }
              if (v == 'add_image') {
                _pickImage();
              }
              if (v is ColorTheme) {
                setState(() => _editing.colorTheme = v);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'toggle_pin',
                child: Row(
                  children: [
                    Icon(_editing.pinned
                        ? Icons.push_pin
                        : Icons.push_pin_outlined),
                    const SizedBox(width: 8),
                    Text(_editing.pinned ? 'Unpin' : 'Pin'),
                  ],
                ),
              ),
              const PopupMenuItem(value: 'add_image', child: Text('Add Image')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                enabled: false,
                child: Text('Color Theme:', style: TextStyle(fontSize: 12)),
              ),
              ...ColorTheme.values.map((theme) => PopupMenuItem(
                    value: theme,
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: ThemeHelper.getThemeColor(theme,
                                isDarkMode: isDarkMode),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        Text(ThemeHelper.getThemeName(theme)),
                        if (theme == _editing.colorTheme)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(Icons.check, size: 16),
                          ),
                      ],
                    ),
                  )),
              if (widget.note != null) ...[
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: colorScheme.error),
                      const SizedBox(width: 8),
                      Text('Delete',
                          style: TextStyle(color: colorScheme.error)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      body: Container(
        color: noteColor,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // Title
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Title',
                    border: InputBorder.none,
                  ),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                // Category + pin row
                Row(
                  children: [
                    const Text('Category:'),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _editing.category,
                      underline: const SizedBox(),
                      items: ['General', 'Work', 'Personal', 'Ideas']
                          .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(() => _editing.category = v!),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        _editing.pinned
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _editing.pinned = !_editing.pinned),
                    ),
                  ],
                ),
                // Image strip
                if (_editing.imageIds.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _editing.imageIds.length,
                      itemBuilder: (context, index) {
                        final imgId = _editing.imageIds[index];
                        final prov = Provider.of<NotesProvider>(context);
                        final b64 = prov.getImage(imgId);
                        if (b64 == null) {
                          return Container(
                            width: 100,
                            height: 100,
                            margin: const EdgeInsets.all(4),
                            color: Colors.grey.shade300,
                            child:
                                const Icon(Icons.image_not_supported_outlined),
                          );
                        }
                        return Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(4),
                              child: Image.memory(
                                base64Decode(b64),
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () => setState(
                                  () => _editing.imageIds.removeAt(index),
                                ),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  padding: const EdgeInsets.all(2),
                                  child: const Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                // Note body
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Note'),
        content: const Text('Move to recycle bin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Provider.of<NotesProvider>(context, listen: false)
                  .softDelete(_editing.id);
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() => switch (_editing.noteType) {
        NoteType.normal => _buildNormal(),
        NoteType.checklist => _buildChecklist(),
        NoteType.itinerary => _buildItinerary(),
        NoteType.mealPlan => _buildMealPlan(),
        NoteType.recipe => _buildRecipe(),
      };

  Widget _buildNormal() => TextField(
        controller: _contentCtrl,
        maxLines: null,
        expands: true,
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Start typing...',
        ),
      );

  Widget _buildChecklist() => Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _editing.checklistItems.length,
              itemBuilder: (_, i) {
                final item = _editing.checklistItems[i];
                return _ChecklistItemTile(
                  item: item,
                  onChanged: (v) => setState(() => item.checked = v),
                  onDelete: () =>
                      setState(() => _editing.checklistItems.removeAt(i)),
                  onTextChanged: (text) => setState(() => item.text = text),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: ElevatedButton.icon(
              onPressed: () => setState(() => _editing.checklistItems.add(
                    ChecklistItem(id: const Uuid().v4(), text: ''),
                  )),
              icon: const Icon(Icons.add),
              label: const Text('Add Item'),
            ),
          ),
        ],
      );

  Widget _buildItinerary() => Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _editing.itineraryItems.length,
              itemBuilder: (_, i) {
                final item = _editing.itineraryItems[i];
                return _ItineraryItemCard(
                  item: item,
                  onDelete: () =>
                      setState(() => _editing.itineraryItems.removeAt(i)),
                  onChanged: () => setState(() {}),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: ElevatedButton.icon(
              onPressed: () => setState(() => _editing.itineraryItems
                  .add(ItineraryItem(id: const Uuid().v4()))),
              icon: const Icon(Icons.add),
              label: const Text('Add Destination'),
            ),
          ),
        ],
      );

  Widget _buildMealPlan() => Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _editing.mealPlanItems.length,
              itemBuilder: (_, i) {
                final item = _editing.mealPlanItems[i];
                return _MealPlanItemCard(
                  item: item,
                  onDelete: () =>
                      setState(() => _editing.mealPlanItems.removeAt(i)),
                  onChanged: () => setState(() {}),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: ElevatedButton.icon(
              onPressed: () => setState(() => _editing.mealPlanItems
                  .add(MealPlanItem(id: const Uuid().v4()))),
              icon: const Icon(Icons.add),
              label: const Text('Add Day'),
            ),
          ),
        ],
      );

  Widget _buildRecipe() {
    _editing.recipeData ??= RecipeData();
    return _RecipeCard(
      data: _editing.recipeData!,
      onChanged: () => setState(() {}),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CHECKLIST ITEM TILE
// ─────────────────────────────────────────────────────────────────────────────

class _ChecklistItemTile extends StatefulWidget {
  final ChecklistItem item;
  final Function(bool) onChanged;
  final VoidCallback onDelete;
  final Function(String) onTextChanged;

  const _ChecklistItemTile({
    required this.item,
    required this.onChanged,
    required this.onDelete,
    required this.onTextChanged,
  });

  @override
  State<_ChecklistItemTile> createState() => _ChecklistItemTileState();
}

class _ChecklistItemTileState extends State<_ChecklistItemTile> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.item.text);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Checkbox(
            value: widget.item.checked,
            onChanged: (v) => widget.onChanged(v ?? false),
          ),
          Expanded(
            child: TextField(
              controller: _ctrl,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Enter item...',
              ),
              style: TextStyle(
                decoration: widget.item.checked
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
                color: widget.item.checked ? Colors.grey : null,
              ),
              onChanged: widget.onTextChanged,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: widget.onDelete,
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// ITINERARY ITEM CARD
// ─────────────────────────────────────────────────────────────────────────────

class _ItineraryItemCard extends StatefulWidget {
  final ItineraryItem item;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  const _ItineraryItemCard({
    required this.item,
    required this.onDelete,
    required this.onChanged,
  });

  @override
  State<_ItineraryItemCard> createState() => _ItineraryItemCardState();
}

class _ItineraryItemCardState extends State<_ItineraryItemCard> {
  late TextEditingController _loc, _date, _arr, _dep, _notes;

  @override
  void initState() {
    super.initState();
    _loc = TextEditingController(text: widget.item.location);
    _date = TextEditingController(text: widget.item.date);
    _arr = TextEditingController(text: widget.item.arrivalTime);
    _dep = TextEditingController(text: widget.item.departureTime);
    _notes = TextEditingController(text: widget.item.notes);
  }

  @override
  void dispose() {
    _loc.dispose();
    _date.dispose();
    _arr.dispose();
    _dep.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _loc,
                      decoration: const InputDecoration(
                        labelText: 'Location',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        widget.item.location = v;
                        widget.onChanged();
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: widget.onDelete,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _date,
                decoration: const InputDecoration(
                  labelText: 'Date',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  widget.item.date = v;
                  widget.onChanged();
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _arr,
                      decoration: const InputDecoration(
                        labelText: 'Arrival',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        widget.item.arrivalTime = v;
                        widget.onChanged();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _dep,
                      decoration: const InputDecoration(
                        labelText: 'Departure',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        widget.item.departureTime = v;
                        widget.onChanged();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  widget.item.notes = v;
                  widget.onChanged();
                },
              ),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// MEAL PLAN ITEM CARD
// ─────────────────────────────────────────────────────────────────────────────

class _MealPlanItemCard extends StatefulWidget {
  final MealPlanItem item;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  const _MealPlanItemCard({
    required this.item,
    required this.onDelete,
    required this.onChanged,
  });

  @override
  State<_MealPlanItemCard> createState() => _MealPlanItemCardState();
}

class _MealPlanItemCardState extends State<_MealPlanItemCard> {
  late TextEditingController _day, _bfast, _lunch, _dinner, _snacks;

  @override
  void initState() {
    super.initState();
    _day = TextEditingController(text: widget.item.day);
    _bfast = TextEditingController(text: widget.item.breakfast);
    _lunch = TextEditingController(text: widget.item.lunch);
    _dinner = TextEditingController(text: widget.item.dinner);
    _snacks = TextEditingController(text: widget.item.snacks);
  }

  @override
  void dispose() {
    _day.dispose();
    _bfast.dispose();
    _lunch.dispose();
    _dinner.dispose();
    _snacks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _day,
                      decoration: const InputDecoration(
                        labelText: 'Day',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        widget.item.day = v;
                        widget.onChanged();
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: widget.onDelete,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final pair in [
                (_bfast, 'Breakfast', (String v) => widget.item.breakfast = v),
                (_lunch, 'Lunch', (String v) => widget.item.lunch = v),
                (_dinner, 'Dinner', (String v) => widget.item.dinner = v),
                (_snacks, 'Snacks', (String v) => widget.item.snacks = v),
              ]) ...[
                TextField(
                  controller: pair.$1,
                  decoration: InputDecoration(
                    labelText: pair.$2,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    pair.$3(v);
                    widget.onChanged();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// RECIPE CARD
// ─────────────────────────────────────────────────────────────────────────────

class _RecipeCard extends StatefulWidget {
  final RecipeData data;
  final VoidCallback onChanged;

  const _RecipeCard({required this.data, required this.onChanged});

  @override
  State<_RecipeCard> createState() => _RecipeCardState();
}

class _RecipeCardState extends State<_RecipeCard> {
  late TextEditingController _prep, _cook, _serv, _ingr, _inst;

  @override
  void initState() {
    super.initState();
    _prep = TextEditingController(text: widget.data.prepTime);
    _cook = TextEditingController(text: widget.data.cookTime);
    _serv = TextEditingController(text: widget.data.servings);
    _ingr = TextEditingController(text: widget.data.ingredients);
    _inst = TextEditingController(text: widget.data.instructions);
  }

  @override
  void dispose() {
    _prep.dispose();
    _cook.dispose();
    _serv.dispose();
    _ingr.dispose();
    _inst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _prep,
                    decoration: const InputDecoration(
                      labelText: 'Prep Time',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      widget.data.prepTime = v;
                      widget.onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _cook,
                    decoration: const InputDecoration(
                      labelText: 'Cook Time',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      widget.data.cookTime = v;
                      widget.onChanged();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _serv,
              decoration: const InputDecoration(
                labelText: 'Servings',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                widget.data.servings = v;
                widget.onChanged();
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Ingredients',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ingr,
              maxLines: 6,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'List ingredients...',
              ),
              onChanged: (v) {
                widget.data.ingredients = v;
                widget.onChanged();
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Instructions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _inst,
              maxLines: 8,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Step-by-step instructions...',
              ),
              onChanged: (v) {
                widget.data.instructions = v;
                widget.onChanged();
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// RECYCLE BIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class RecycleBinScreen extends StatelessWidget {
  const RecycleBinScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<NotesProvider>(context);
    final items = prov.recycleBin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recycle Bin'),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Empty Recycle Bin'),
                    content: const Text(
                      'Permanently delete all notes? This cannot be undone.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete All'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  for (final n in List.from(items)) {
                    await prov.hardDelete(n.id);
                  }
                }
              },
              icon: const Icon(Icons.delete_forever),
              tooltip: 'Empty Recycle Bin',
            ),
        ],
      ),
      body: items.isEmpty
          ? const Center(child: Text('Recycle bin is empty'))
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) {
                final n = items[i];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: ListTile(
                    title: Text(
                      n.title.isNotEmpty ? n.title : '(Untitled)',
                    ),
                    subtitle: Text(
                      n.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.restore, color: Colors.blue),
                          onPressed: () => prov.restore(n.id),
                          tooltip: 'Restore',
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_forever,
                            color: Colors.red,
                          ),
                          tooltip: 'Delete Permanently',
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Permanently Delete'),
                                content: const Text(
                                  'Are you sure? This cannot be undone.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) prov.hardDelete(n.id);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
