// noteliha - Complete Refactor with Granular Delta Sync
// Single-file architecture with:
// - Granular delta sync (individual {noteId}.json files on Drive)
// - Exponential backoff (500ms → 750ms → 1.1s → 1.65s → 2.5s)
// - High-performance search index (denormalized Hive box)
// - Last-Write-Wins conflict resolution (timestamp-based)
// - All model logic integrated (Checklist, Itinerary, MealPlan, Recipe)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show pow;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

// ==================== CONSTANTS ====================

const String kNotesBox = 'notes_box_v4';
const String kImagesBox = 'images_box_v1';
const String kSearchIndexBox = 'search_index_box_v2';
const String kSyncMetaBox = 'sync_meta_box_v2';
const String kDriveFolderName = '.lihuka_notes_app';

// Exponential backoff configuration
const int kInitialBackoffMs = 500;
const double kBackoffMultiplier = 1.5;
const int kMaxRetries = 5;
const int kMaxBackoffMs = 30000;

enum NoteType { normal, checklist, itinerary, mealPlan, recipe }
enum ColorTheme { default_, sunset, ocean, forest, lavender, rose }
enum SyncStatus { idle, syncing, error }
enum AppTheme { amber, teal, indigo, rose, slate }

// ==================== APP SETTINGS PROVIDER ====================

class AppSettingsProvider extends ChangeNotifier {
  AppTheme _appTheme = AppTheme.amber;
  bool _isDarkMode = false;

  AppTheme get appTheme => _appTheme;
  bool get isDarkMode => _isDarkMode;

  static Color seedColor(AppTheme theme) => switch (theme) {
    AppTheme.amber  => Colors.amber,
    AppTheme.teal   => Colors.teal,
    AppTheme.indigo => Colors.indigo,
    AppTheme.rose   => Colors.pink,
    AppTheme.slate  => Colors.blueGrey,
  };

  static String themeName(AppTheme theme) => switch (theme) {
    AppTheme.amber  => 'Amber',
    AppTheme.teal   => 'Teal',
    AppTheme.indigo => 'Indigo',
    AppTheme.rose   => 'Rose',
    AppTheme.slate  => 'Slate',
  };

  static IconData themeIcon(AppTheme theme) => switch (theme) {
    AppTheme.amber  => Icons.wb_sunny_rounded,
    AppTheme.teal   => Icons.waves_rounded,
    AppTheme.indigo => Icons.nights_stay_rounded,
    AppTheme.rose   => Icons.local_florist_rounded,
    AppTheme.slate  => Icons.terrain_rounded,
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

// ==================== DATA MODELS ====================

class ChecklistItem {
  String id;
  String text;
  bool checked;

  ChecklistItem({required this.id, required this.text, this.checked = false});

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'checked': checked};
  factory ChecklistItem.fromJson(Map<String, dynamic> json) => ChecklistItem(
    id: json['id'] ?? const Uuid().v4(),
    text: json['text'] ?? '',
    checked: json['checked'] ?? false,
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
  factory ItineraryItem.fromJson(Map<String, dynamic> json) => ItineraryItem(
    id: json['id'] ?? const Uuid().v4(),
    location: json['location'] ?? '',
    date: json['date'] ?? '',
    arrivalTime: json['arrivalTime'] ?? '',
    departureTime: json['departureTime'] ?? '',
    notes: json['notes'] ?? '',
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
  factory MealPlanItem.fromJson(Map<String, dynamic> json) => MealPlanItem(
    id: json['id'] ?? const Uuid().v4(),
    day: json['day'] ?? '',
    breakfast: json['breakfast'] ?? '',
    lunch: json['lunch'] ?? '',
    dinner: json['dinner'] ?? '',
    snacks: json['snacks'] ?? '',
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
  factory RecipeData.fromJson(Map<String, dynamic> json) => RecipeData(
    ingredients: json['ingredients'] ?? '',
    instructions: json['instructions'] ?? '',
    prepTime: json['prepTime'] ?? '',
    cookTime: json['cookTime'] ?? '',
    servings: json['servings'] ?? '',
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

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    id: json['id'] ?? const Uuid().v4(),
    title: json['title'] ?? '',
    content: json['content'] ?? '',
    updatedAt: DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
    deleted: json['deleted'] ?? false,
    category: json['category'] ?? 'General',
    pinned: json['pinned'] ?? false,
    noteType: NoteType.values[json['noteType'] ?? 0],
    colorTheme: ColorTheme.values[json['colorTheme'] ?? 0],
    checklistItems: (json['checklistItems'] as List?)
        ?.map((i) => ChecklistItem.fromJson(i))
        .toList() ?? [],
    itineraryItems: (json['itineraryItems'] as List?)
        ?.map((i) => ItineraryItem.fromJson(i))
        .toList() ?? [],
    mealPlanItems: (json['mealPlanItems'] as List?)
        ?.map((i) => MealPlanItem.fromJson(i))
        .toList() ?? [],
    recipeData: json['recipeData'] != null
        ? RecipeData.fromJson(json['recipeData'])
        : null,
    imageIds: (json['imageIds'] as List?)?.cast<String>() ?? [],
  );
}

class NoteAdapter extends TypeAdapter<Note> {
  @override
  final typeId = 100;

  @override
  Note read(BinaryReader reader) =>
      Note.fromJson(Map<String, dynamic>.from(reader.read() as Map));

  @override
  void write(BinaryWriter writer, Note obj) => writer.write(obj.toJson());
}

// ==================== SYNC METADATA & TRACKING ====================

class SyncMetadata {
  String noteId;
  DateTime lastSyncedAt;
  String? driveFileId;
  DateTime? cloudUpdatedAt;

  SyncMetadata({
    required this.noteId,
    required this.lastSyncedAt,
    this.driveFileId,
    this.cloudUpdatedAt,
  });

  Map<String, dynamic> toJson() => {
    'noteId': noteId,
    'lastSyncedAt': lastSyncedAt.toIso8601String(),
    'driveFileId': driveFileId,
    'cloudUpdatedAt': cloudUpdatedAt?.toIso8601String(),
  };

  factory SyncMetadata.fromJson(Map<String, dynamic> json) => SyncMetadata(
    noteId: json['noteId'] ?? '',
    lastSyncedAt: DateTime.tryParse(json['lastSyncedAt'] ?? '') ?? DateTime.now(),
    driveFileId: json['driveFileId'],
    cloudUpdatedAt: json['cloudUpdatedAt'] != null
        ? DateTime.tryParse(json['cloudUpdatedAt'])
        : null,
  );
}

class DeltaSyncTracker {
  // FIX 1: Added default unnamed constructor so DeltaSyncTracker() works
  DeltaSyncTracker();

  DateTime? lastFullSyncAt;
  DateTime? lastDeltaSyncAt;
  Set<String> pendingUploads = {};
  Map<String, DateTime> noteVersions = {};

  Map<String, dynamic> toJson() => {
    'lastFullSyncAt': lastFullSyncAt?.toIso8601String(),
    'lastDeltaSyncAt': lastDeltaSyncAt?.toIso8601String(),
    'pendingUploads': pendingUploads.toList(),
    'noteVersions': noteVersions.map((k, v) => MapEntry(k, v.toIso8601String())),
  };

  factory DeltaSyncTracker.fromJson(Map<String, dynamic> json) {
    final tracker = DeltaSyncTracker();
    tracker.lastFullSyncAt = json['lastFullSyncAt'] != null
        ? DateTime.tryParse(json['lastFullSyncAt'])
        : null;
    tracker.lastDeltaSyncAt = json['lastDeltaSyncAt'] != null
        ? DateTime.tryParse(json['lastDeltaSyncAt'])
        : null;
    tracker.pendingUploads =
    Set<String>.from((json['pendingUploads'] as List?) ?? []);
    final versions = json['noteVersions'] as Map?;
    if (versions != null) {
      versions.forEach((k, v) {
        final dt = DateTime.tryParse(v);
        if (dt != null) tracker.noteVersions[k] = dt;
      });
    }
    return tracker;
  }
}

// ==================== THEME HELPER ====================

class ThemeHelper {
  static Color getThemeColor(ColorTheme theme) => switch (theme) {
    ColorTheme.default_ => Colors.amber.shade100,
    ColorTheme.sunset => Colors.orange.shade200,
    ColorTheme.ocean => Colors.blue.shade200,
    ColorTheme.forest => Colors.green.shade200,
    ColorTheme.lavender => Colors.purple.shade200,
    ColorTheme.rose => Colors.pink.shade200,
  };

  static String getThemeName(ColorTheme theme) => switch (theme) {
    ColorTheme.default_ => 'Default',
    ColorTheme.sunset => 'Sunset',
    ColorTheme.ocean => 'Ocean',
    ColorTheme.forest => 'Forest',
    ColorTheme.lavender => 'Lavender',
    ColorTheme.rose => 'Rose',
  };

  static Icon getNoteTypeIcon(NoteType type) => switch (type) {
    NoteType.normal    => const Icon(Icons.note_rounded, size: 14),
    NoteType.checklist => const Icon(Icons.check_box_rounded, size: 14),
    NoteType.itinerary => const Icon(Icons.flight_rounded, size: 14),
    NoteType.mealPlan  => const Icon(Icons.restaurant_menu_rounded, size: 14),
    NoteType.recipe    => const Icon(Icons.menu_book_rounded, size: 14),
  };
}

// ==================== ENHANCED NOTES PROVIDER ====================

class NotesProvider extends ChangeNotifier {
  // Storage boxes
  Box<dynamic>? _notesBox;
  Box<String>? _imagesBox;
  Box<String>? _searchIndexBox;
  Box<dynamic>? _syncMetaBox;

  // State
  GoogleSignInAccount? _currentUser;
  SyncStatus _syncStatus = SyncStatus.idle;
  String? _syncStatusMessage;
  Timer? _syncStatusTimer;
  Timer? _autoSyncTimer;
  late GoogleSignIn _googleSignIn;

  // Sync tracking
  late DeltaSyncTracker _deltaTracker;
  String? _driveFolderId;
  final Duration _autoSyncInterval = const Duration(minutes: 5);

  // Exponential backoff state
  int _currentRetryCount = 0;
  // FIX 4 (warning): Removed unused _currentBackoffMs field

  // Getters
  List<Note> get notes {
    if (_notesBox == null) return [];
    final list = _notesBox!.values.cast<Note>().where((n) => !n.deleted).toList();
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  List<Note> get recycleBin =>
      _notesBox?.values.cast<Note>().where((n) => n.deleted).toList() ?? [];

  GoogleSignInAccount? get user => _currentUser;
  SyncStatus get syncStatus => _syncStatus;
  String? get syncStatusMessage => _syncStatusMessage;
  bool get isSyncing => _syncStatus == SyncStatus.syncing;

  NotesProvider() {
    _googleSignIn = GoogleSignIn(scopes: [drive.DriveApi.driveFileScope]);
    // FIX 1: DeltaSyncTracker() now works with the added default constructor
    _deltaTracker = DeltaSyncTracker();
  }

  // ==================== INITIALIZATION ====================

  Future<void> init() async {
    try {
      _notesBox = await Hive.openBox<dynamic>(kNotesBox);
      _imagesBox = await Hive.openBox<String>(kImagesBox);
      _searchIndexBox = await Hive.openBox<String>(kSearchIndexBox);
      _syncMetaBox = await Hive.openBox<dynamic>(kSyncMetaBox);

      _loadDeltaSyncTracker();
      _rebuildSearchIndex();

      // FIX 2: The listener callback receives GoogleSignInAccount? directly,
      // not a GoogleSignIn object. Use the parameter directly as the account.
      _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount? account) {
        _currentUser = account;
        notifyListeners();
        if (_currentUser != null) {
          _startAutoSync();
        } else {
          _stopAutoSync();
        }
      });

      _currentUser = await _googleSignIn.signInSilently();
      if (_currentUser != null) _startAutoSync();
      notifyListeners();
    } catch (e) {
      debugPrint('Init error: $e');
    }
  }

  @override
  void dispose() {
    _syncStatusTimer?.cancel();
    _stopAutoSync();
    super.dispose();
  }

  // ==================== AUTO SYNC ====================

  void _startAutoSync() {
    _stopAutoSync();
    _autoSyncTimer = Timer.periodic(_autoSyncInterval, (_) {
      if (_currentUser != null && !isSyncing) {
        syncNotes();
      }
    });
  }

  void _stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  // ==================== SEARCH INDEX MANAGEMENT ====================

  void _rebuildSearchIndex() {
    if (_notesBox == null || _searchIndexBox == null) return;
    _searchIndexBox!.clear();
    for (final note in _notesBox!.values.cast<Note>()) {
      _updateSearchIndex(note);
    }
  }

  void _updateSearchIndex(Note note) {
    if (_searchIndexBox == null) return;
    final searchText =
    '${note.title} ${note.content} ${note.category}'.toLowerCase();
    _searchIndexBox!.put(note.id, searchText);
  }

  List<Note> search(String query) {
    if (_searchIndexBox == null || _notesBox == null) return notes;
    if (query.trim().isEmpty) return notes;

    final q = query.toLowerCase();
    final results = <Note>[];

    for (final key in _searchIndexBox!.keys) {
      final text = _searchIndexBox!.get(key);
      if (text?.contains(q) ?? false) {
        final note = _notesBox!.get(key);
        if (note is Note && !note.deleted) {
          results.add(note);
        }
      }
    }

    results.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });

    return results;
  }

  // ==================== NOTE CRUD ====================

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
    _deltaTracker.pendingUploads.add(note.id);
    _saveDeltaSyncTracker();
    notifyListeners();
  }

  Future<void> updateNote(Note note) async {
    if (_notesBox == null) return;
    note.updatedAt = DateTime.now();
    await _notesBox!.put(note.id, note);
    _updateSearchIndex(note);
    _deltaTracker.pendingUploads.add(note.id);
    _saveDeltaSyncTracker();
    notifyListeners();
  }

  Future<void> softDelete(String id) async {
    final note = _notesBox?.get(id);
    if (note != null) {
      note.deleted = true;
      note.updatedAt = DateTime.now();
      await _notesBox!.put(id, note);
      _updateSearchIndex(note);
      _deltaTracker.pendingUploads.add(id);
      _saveDeltaSyncTracker();
      notifyListeners();
    }
  }

  Future<void> restore(String id) async {
    final note = _notesBox?.get(id);
    if (note != null) {
      note.deleted = false;
      note.updatedAt = DateTime.now();
      await _notesBox!.put(id, note);
      _updateSearchIndex(note);
      _deltaTracker.pendingUploads.add(id);
      _saveDeltaSyncTracker();
      notifyListeners();
    }
  }

  Future<void> hardDelete(String id) async {
    if (_notesBox == null) return;
    final note = _notesBox!.get(id);
    if (note != null) {
      for (final imgId in note.imageIds) {
        await deleteImage(imgId);
      }
    }
    await _notesBox!.delete(id);
    _searchIndexBox?.delete(id);
    _deltaTracker.pendingUploads.remove(id);
    _deltaTracker.noteVersions.remove(id);
    await _syncMetaBox?.delete(id);
    _saveDeltaSyncTracker();
    notifyListeners();
  }

  // ==================== IMAGE MANAGEMENT ====================

  Future<String> saveImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final imageId = const Uuid().v4();
    await _imagesBox?.put(imageId, base64Encode(bytes));
    return imageId;
  }

  String? getImage(String imageId) => _imagesBox?.get(imageId);

  Future<void> deleteImage(String imageId) =>
      _imagesBox?.delete(imageId) ?? Future.value();

  // ==================== AUTH ====================

  Future<void> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      notifyListeners();
      if (_currentUser != null) {
        _startAutoSync();
        await syncNotes();
      }
    } catch (e) {
      _setStatus('Sign in failed: $e', isError: true);
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.disconnect();
      _currentUser = null;
      _stopAutoSync();
      notifyListeners();
    } catch (e) {
      debugPrint('Sign out error: $e');
    }
  }

  // ==================== STATUS MANAGEMENT ====================

  void _setStatus(String? msg, {bool isError = false}) {
    _syncStatusTimer?.cancel();
    _syncStatusMessage = msg;
    _syncStatus = isError
        ? SyncStatus.error
        : (msg != null ? SyncStatus.syncing : SyncStatus.idle);
    notifyListeners();

    if (msg != null && !isSyncing) {
      _syncStatusTimer = Timer(const Duration(seconds: 4), () {
        _syncStatusMessage = null;
        _syncStatus = SyncStatus.idle;
        notifyListeners();
      });
    }
  }

  // ==================== EXPONENTIAL BACKOFF RETRY ====================

  /// Retries operation with exponential backoff: 500ms → 750ms → 1.1s → 1.65s → 2.5s
  /// Max 5 retries, capped at 30 seconds
  Future<T> _retryWithBackoff<T>(
      Future<T> Function() operation, {
        int maxRetries = kMaxRetries,
        String? operationName,
      }) async {
    _currentRetryCount = 0;

    while (true) {
      try {
        return await operation();
      } catch (e) {
        _currentRetryCount++;
        if (_currentRetryCount >= maxRetries) {
          debugPrint('$operationName failed after $maxRetries retries: $e');
          rethrow;
        }

        // Calculate exponential backoff: 500ms * 1.5^(retryCount-1)
        final delayMs = (kInitialBackoffMs * pow(kBackoffMultiplier, _currentRetryCount - 1))
            .toInt()
            .clamp(kInitialBackoffMs, kMaxBackoffMs);

        debugPrint('$operationName retry $_currentRetryCount/$maxRetries after ${delayMs}ms');
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
  }

  // ==================== DRIVE FOLDER MANAGEMENT ====================

  Future<String> _ensureAppFolder(drive.DriveApi driveApi) async {
    if (_driveFolderId != null) return _driveFolderId!;

    final cached = _syncMetaBox?.get('_driveFolderId') as String?;
    if (cached != null) {
      _driveFolderId = cached;
      return _driveFolderId!;
    }

    try {
      final fileList = await _retryWithBackoff(
            () => driveApi.files.list(
          q: "name = '$kDriveFolderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
          $fields: 'files(id)',
          pageSize: 1,
        ),
        operationName: 'Find app folder',
      );

      if (fileList.files?.isNotEmpty ?? false) {
        _driveFolderId = fileList.files!.first.id;
      } else {
        final folder = drive.File()
          ..name = kDriveFolderName
          ..mimeType = 'application/vnd.google-apps.folder'
          ..properties = {'app': 'noteliha', 'version': '1'};

        final created = await _retryWithBackoff(
              () => driveApi.files.create(folder),
          operationName: 'Create app folder',
        );

        _driveFolderId = created.id;
      }

      await _syncMetaBox?.put('_driveFolderId', _driveFolderId!);
      return _driveFolderId!;
    } catch (e) {
      debugPrint('Error ensuring app folder: $e');
      rethrow;
    }
  }

  // ==================== GRANULAR DELTA SYNC ====================

  Future<void> syncNotes({bool forceFull = false}) async {
    if (_currentUser == null || _notesBox == null) {
      _setStatus('Login required', isError: true);
      return;
    }

    if (isSyncing) return;

    _setStatus('Syncing notes...');
    notifyListeners();

    try {
      final authHeaders = await _googleSignIn.authenticatedClient();
      if (authHeaders == null) throw Exception('Authentication failed');

      final driveApi = drive.DriveApi(authHeaders);
      final folderId = await _ensureAppFolder(driveApi);

      // Decide between delta and full sync
      final shouldDoDelta = !forceFull &&
          _deltaTracker.lastDeltaSyncAt != null &&
          DateTime.now().difference(_deltaTracker.lastDeltaSyncAt!) <
              const Duration(hours: 1);

      if (shouldDoDelta) {
        await _performDeltaSync(driveApi, folderId);
      } else {
        await _performFullSync(driveApi, folderId);
      }

      _deltaTracker.lastDeltaSyncAt = DateTime.now();
      _deltaTracker.pendingUploads.clear();
      _saveDeltaSyncTracker();

      _setStatus('Sync complete');
    } catch (e) {
      _setStatus('Sync failed: $e', isError: true);
      debugPrint('Sync error: $e');
    } finally {
      _syncStatus = SyncStatus.idle;
      notifyListeners();
    }
  }

  /// Delta sync: Upload pending changes + download recent cloud changes
  Future<void> _performDeltaSync(drive.DriveApi driveApi, String folderId) async {
    debugPrint('Performing delta sync for ${_deltaTracker.pendingUploads.length} notes');

    // Upload pending local changes
    for (final noteId in _deltaTracker.pendingUploads) {
      final note = _notesBox!.get(noteId);
      if (note != null) {
        await _uploadNoteToDrive(driveApi, folderId, note);
      }
    }

    // Download recently changed cloud notes
    await _downloadChangedNotesFromDrive(driveApi, folderId);
  }

  /// Full sync: Upload all notes + download all cloud notes
  Future<void> _performFullSync(drive.DriveApi driveApi, String folderId) async {
    debugPrint('Performing full sync');

    // Upload all local notes
    for (final note in _notesBox!.values.cast<Note>()) {
      await _uploadNoteToDrive(driveApi, folderId, note);
    }

    // Download all cloud notes
    await _downloadAllNotesFromDrive(driveApi, folderId);

    _deltaTracker.lastFullSyncAt = DateTime.now();
  }

  /// Upload individual note to Drive as {noteId}.json
  Future<void> _uploadNoteToDrive(
      drive.DriveApi driveApi,
      String folderId,
      Note note,
      ) async {
    try {
      final fileName = '${note.id}.json';
      final fileContent = jsonEncode(note.toJson());
      // FIX 3: utf8.encode returns List<int>; wrap in Stream.value correctly
      // drive.Media expects Stream<List<int>>, so pass the bytes directly.
      final encodedBytes = utf8.encode(fileContent);
      final media = drive.Media(
        Stream.value(encodedBytes),
        encodedBytes.length,
      );

      final syncMetaJson = _syncMetaBox?.get(note.id);
      SyncMetadata? syncMeta;
      if (syncMetaJson != null) {
        syncMeta = SyncMetadata.fromJson(
            syncMetaJson is Map ? Map<String, dynamic>.from(syncMetaJson) : {});
      }

      if (syncMeta?.driveFileId != null) {
        // Update existing file with exponential backoff
        await _retryWithBackoff(
              () => driveApi.files.update(
            drive.File(),
            syncMeta!.driveFileId!,
            uploadMedia: media,
          ),
          operationName: 'Update note file: ${note.id}',
        );
      } else {
        // Create new file with exponential backoff
        final file = drive.File()
          ..name = fileName
          ..parents = [folderId];

        final created = await _retryWithBackoff(
              () => driveApi.files.create(file, uploadMedia: media),
          operationName: 'Create note file: ${note.id}',
        );

        syncMeta = SyncMetadata(
          noteId: note.id,
          lastSyncedAt: DateTime.now(),
          driveFileId: created.id,
          cloudUpdatedAt: note.updatedAt,
        );
      }

      // Update sync metadata
      syncMeta ??= SyncMetadata(noteId: note.id, lastSyncedAt: DateTime.now());
      syncMeta.lastSyncedAt = DateTime.now();
      syncMeta.cloudUpdatedAt = note.updatedAt;
      syncMeta.driveFileId ??= syncMeta.driveFileId;

      await _syncMetaBox?.put(note.id, syncMeta.toJson());
      _deltaTracker.noteVersions[note.id] = note.updatedAt;
    } catch (e) {
      debugPrint('Error uploading note ${note.id}: $e');
      rethrow;
    }
  }

  /// Download all notes from Drive
  Future<void> _downloadAllNotesFromDrive(
      drive.DriveApi driveApi,
      String folderId,
      ) async {
    try {
      final fileList = await _retryWithBackoff(
            () => driveApi.files.list(
          q: "'$folderId' in parents and mimeType = 'application/json' and trashed = false",
          $fields: 'files(id, name, modifiedTime)',
          pageSize: 1000,
        ),
        operationName: 'List drive notes',
      );

      final cloudFiles = fileList.files ?? [];
      debugPrint('Found ${cloudFiles.length} notes on Drive');

      for (final file in cloudFiles) {
        if (file.name?.endsWith('.json') ?? false) {
          final noteId = file.name!.replaceAll('.json', '');
          await _downloadNoteFromDrive(driveApi, file.id!, noteId);
        }
      }
    } catch (e) {
      debugPrint('Error downloading notes from drive: $e');
      rethrow;
    }
  }

  /// Download only notes changed since lastDeltaSyncAt
  Future<void> _downloadChangedNotesFromDrive(
      drive.DriveApi driveApi,
      String folderId,
      ) async {
    try {
      final lastSync = _deltaTracker.lastDeltaSyncAt ?? DateTime(2020);
      final rfc3339LastSync = lastSync.toUtc().toIso8601String();

      final fileList = await _retryWithBackoff(
            () => driveApi.files.list(
          q: "'$folderId' in parents and mimeType = 'application/json' and trashed = false and modifiedTime > '$rfc3339LastSync'",
          $fields: 'files(id, name, modifiedTime)',
          pageSize: 1000,
        ),
        operationName: 'List changed drive notes',
      );

      final changedFiles = fileList.files ?? [];
      debugPrint('Found ${changedFiles.length} changed notes on Drive');

      for (final file in changedFiles) {
        if (file.name?.endsWith('.json') ?? false) {
          final noteId = file.name!.replaceAll('.json', '');
          await _downloadNoteFromDrive(driveApi, file.id!, noteId);
        }
      }
    } catch (e) {
      debugPrint('Error downloading changed notes: $e');
      rethrow;
    }
  }

  /// Download individual note from Drive and apply LWW conflict resolution
  Future<void> _downloadNoteFromDrive(
      drive.DriveApi driveApi,
      String fileId,
      String noteId,
      ) async {
    try {
      final media = await _retryWithBackoff(
            () => driveApi.files.get(
          fileId,
          downloadOptions: drive.DownloadOptions.fullMedia,
        ) as Future<drive.Media>,
        operationName: 'Download note: $noteId',
      );

      final bytes = await media.stream.expand((chunk) => chunk).toList();
      final jsonStr = utf8.decode(bytes);
      final cloudNote = Note.fromJson(jsonDecode(jsonStr));

      // LWW: Compare timestamps, cloud wins if newer
      final localNote = _notesBox!.get(noteId);
      if (localNote == null ||
          cloudNote.updatedAt.isAfter(localNote.updatedAt)) {
        // Cloud version is newer or doesn't exist locally
        // Validate image IDs exist locally
        cloudNote.imageIds
            .removeWhere((imgId) => _imagesBox!.get(imgId) == null);

        await _notesBox!.put(noteId, cloudNote);
        _updateSearchIndex(cloudNote);
      }
      // else: local version is newer, keep it (will sync on next update)

      // Update sync metadata
      final meta = SyncMetadata(
        noteId: noteId,
        lastSyncedAt: DateTime.now(),
        driveFileId: fileId,
        cloudUpdatedAt: cloudNote.updatedAt,
      );
      await _syncMetaBox?.put(noteId, meta.toJson());
    } catch (e) {
      debugPrint('Error downloading note $noteId: $e');
      rethrow;
    }
  }

  // ==================== DELTA TRACKER PERSISTENCE ====================

  void _loadDeltaSyncTracker() {
    final trackerJson = _syncMetaBox?.get('_deltaTracker');
    if (trackerJson != null) {
      _deltaTracker = DeltaSyncTracker.fromJson(
          trackerJson is Map ? Map<String, dynamic>.from(trackerJson) : {});
    } else {
      // FIX 1: DeltaSyncTracker() now works with the added default constructor
      _deltaTracker = DeltaSyncTracker();
    }
  }

  void _saveDeltaSyncTracker() {
    _syncMetaBox?.put('_deltaTracker', _deltaTracker.toJson());
  }
}

// ==================== MAIN APP & UI ====================

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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final seed = AppSettingsProvider.seedColor(settings.appTheme);
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
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
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
        cardTheme: CardThemeData(
          elevation: 0,
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

// ==================== NOTE LIST SCREEN ====================

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
          if (prov.isSyncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              ),
            ),
          if (prov.user != null)
            IconButton(
              onPressed: () => prov.syncNotes(),
              icon: const Icon(Icons.sync_rounded),
              tooltip: 'Sync Now',
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
                prefixIcon: Icon(Icons.search_rounded, color: colorScheme.onSurfaceVariant),
                hintText: 'Search notes...',
                hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withAlpha(80),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
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
      body: Column(
        children: [
          if (prov.syncStatusMessage != null && !prov.isSyncing)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              color: prov.syncStatus == SyncStatus.error
                  ? colorScheme.errorContainer
                  : colorScheme.primaryContainer,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    prov.syncStatus == SyncStatus.error
                        ? Icons.error_outline_rounded
                        : Icons.check_circle_outline_rounded,
                    size: 16,
                    color: prov.syncStatus == SyncStatus.error
                        ? colorScheme.onErrorContainer
                        : colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    prov.syncStatusMessage ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      color: prov.syncStatus == SyncStatus.error
                          ? colorScheme.onErrorContainer
                          : colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: notes.isEmpty
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
                        builder: (context) => AlertDialog(
                          title: const Text('Delete Note'),
                          content: const Text('Move to recycle bin?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      ) ??
                          false;
                    },
                    onDismissed: (_) => Provider.of<NotesProvider>(
                      context,
                      listen: false,
                    ).softDelete(n.id),
                    child: _NoteCard(note: n),
                  ),
                );
              },
            ),
          ),
        ],
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
}

// ==================== NOTE CARD WIDGET ====================

class _NoteCard extends StatelessWidget {
  final Note note;
  const _NoteCard({required this.note});

  String _getPreviewText() => switch (note.noteType) {
    NoteType.normal => note.content,
    NoteType.checklist =>
    '${note.checklistItems.length} items · ${note.checklistItems.where((i) => i.checked).length} done',
    NoteType.itinerary => '${note.itineraryItems.length} destinations',
    NoteType.mealPlan => '${note.mealPlanItems.length} days planned',
    NoteType.recipe => note.recipeData?.ingredients ?? note.content,
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final noteColor = ThemeHelper.getThemeColor(note.colorTheme);
    final preview = _getPreviewText();

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
              Row(
                children: [
                  if (note.pinned)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.push_pin_rounded, size: 14),
                    ),
                  Expanded(
                    child: Text(
                      note.title.isNotEmpty ? note.title : '(Untitled)',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
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
                      color: colorScheme.onSurface.withAlpha(120),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface.withAlpha(160),
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withAlpha(18),
                      borderRadius: BorderRadius.circular(6),
                    ),
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
                            color: colorScheme.onSurface.withAlpha(160),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withAlpha(18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      note.category,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurface.withAlpha(160),
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

// ==================== SETTINGS SCREEN ====================

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
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ── Profile Section ──────────────────────────────────
          _SectionHeader(title: 'Account'),
          Card(
            child: prov.user == null
                ? ListTile(
              leading: CircleAvatar(
                backgroundColor: colorScheme.primaryContainer,
                child: Icon(Icons.person_outline_rounded,
                    color: colorScheme.onPrimaryContainer),
              ),
              title: const Text('Sign in with Google',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Sync notes across devices'),
              trailing: FilledButton.tonal(
                onPressed: () => prov.signIn(),
                child: const Text('Sign In'),
              ),
            )
                : Column(
              children: [
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
                ListTile(
                  leading: Icon(Icons.sync_rounded,
                      color: colorScheme.primary),
                  title: const Text('Sync Now'),
                  subtitle: const Text('Upload & download latest changes'),
                  onTap: () {
                    prov.syncNotes();
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_sweep_outlined,
                      color: colorScheme.primary),
                  title: const Text('Recycle Bin'),
                  subtitle: const Text('View deleted notes'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RecycleBinScreen()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.logout_rounded,
                      color: colorScheme.error),
                  title: Text('Sign Out',
                      style: TextStyle(color: colorScheme.error)),
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Sign Out'),
                        content: const Text(
                            'Your notes will remain on this device.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Sign Out'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      prov.signOut();
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Appearance Section ───────────────────────────────
          _SectionHeader(title: 'Appearance'),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Dark mode toggle
                SwitchListTile(
                  secondary: Icon(
                    settings.isDarkMode
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    color: colorScheme.primary,
                  ),
                  title: const Text('Dark Mode',
                      style: TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(settings.isDarkMode ? 'On' : 'Off'),
                  value: settings.isDarkMode,
                  onChanged: (_) => settings.toggleDarkMode(),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),

                // App color theme picker
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
                            color: color.withAlpha(isSelected ? 255 : 180),
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
                              ? const Icon(Icons.check_rounded,
                              color: Colors.white, size: 22)
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
          const SizedBox(height: 20),

          // ── About Section ────────────────────────────────────
          _SectionHeader(title: 'About'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.info_outline_rounded,
                      color: colorScheme.primary),
                  title: const Text('Version'),
                  trailing: Text(
                    '1.0.0',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.storage_rounded,
                      color: colorScheme.primary),
                  title: const Text('Storage'),
                  subtitle: const Text('Offline-first with Google Drive sync'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
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
}

// ==================== NOTE EDITOR SCREEN ====================

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
  late Note _editingNote;
  late TextEditingController _titleCtrl;
  late TextEditingController _contentCtrl;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _editingNote = widget.note != null
        ? Note(
      id: widget.note!.id,
      title: widget.note!.title,
      content: widget.note!.content,
      updatedAt: widget.note!.updatedAt,
      deleted: widget.note!.deleted,
      category: widget.note!.category,
      pinned: widget.note!.pinned,
      noteType: widget.note!.noteType,
      colorTheme: widget.note!.colorTheme,
      checklistItems: List.from(widget.note!.checklistItems),
      itineraryItems: List.from(widget.note!.itineraryItems),
      mealPlanItems: List.from(widget.note!.mealPlanItems),
      recipeData: widget.note!.recipeData,
      imageIds: List.from(widget.note!.imageIds),
    )
        : Note(
      id: const Uuid().v4(),
      title: '',
      content: '',
      updatedAt: DateTime.now(),
      noteType: widget.noteType,
    );
    _titleCtrl = TextEditingController(text: _editingNote.title);
    _contentCtrl = TextEditingController(text: _editingNote.content);
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
        setState(() => _editingNote.imageIds.add(imageId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _save() {
    _editingNote.title = _titleCtrl.text.trim();
    _editingNote.content = _contentCtrl.text.trim();

    if (_editingNote.title.isEmpty && _editingNote.content.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Note cannot be empty')));
      return;
    }

    Provider.of<NotesProvider>(context, listen: false)
        .updateNote(_editingNote);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note == null ? 'New Note' : 'Edit Note'),
        backgroundColor: ThemeHelper.getThemeColor(_editingNote.colorTheme),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
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
          PopupMenuButton(
            onSelected: (v) {
              if (v == 'delete') _showDeleteConfirmation();
              if (v == 'toggle_pin') {
                setState(() => _editingNote.pinned = !_editingNote.pinned);
              }
              if (v == 'add_image') _pickImage();
              if (v is ColorTheme) {
                setState(() => _editingNote.colorTheme = v);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'toggle_pin',
                child: Row(
                  children: [
                    Icon(_editingNote.pinned
                        ? Icons.push_pin
                        : Icons.push_pin_outlined),
                    const SizedBox(width: 8),
                    Text(_editingNote.pinned ? 'Unpin' : 'Pin'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'add_image',
                child: Text('Add Image'),
              ),
              const PopupMenuItem(
                enabled: false,
                child: Text('Color Theme:'),
              ),
              ...ColorTheme.values
                  .map((theme) => PopupMenuItem(
                value: theme,
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      color: ThemeHelper.getThemeColor(theme),
                      margin: const EdgeInsets.only(right: 8),
                    ),
                    Text(ThemeHelper.getThemeName(theme)),
                    if (theme == _editingNote.colorTheme)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.check, size: 16),
                      ),
                  ],
                ),
              )),
              if (widget.note != null)
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: Container(
        color: ThemeHelper.getThemeColor(_editingNote.colorTheme),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
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
              Row(
                children: [
                  const Text('Category:'),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _editingNote.category,
                    items: ['General', 'Work', 'Personal', 'Ideas']
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _editingNote.category = v!),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(_editingNote.pinned
                        ? Icons.push_pin
                        : Icons.push_pin_outlined),
                    onPressed: () => setState(
                            () => _editingNote.pinned = !_editingNote.pinned),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_editingNote.imageIds.isNotEmpty)
                SizedBox(
                  height: 120,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _editingNote.imageIds.length,
                    itemBuilder: (context, index) {
                      final imageId = _editingNote.imageIds[index];
                      final prov = Provider.of<NotesProvider>(context);
                      final base64Image = prov.getImage(imageId);
                      if (base64Image == null) return const SizedBox();

                      return Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Image.memory(
                              base64Decode(base64Image),
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  _editingNote.imageIds.removeAt(index);
                                });
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(child: _buildNoteContent()),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Note'),
        content: const Text('Move to recycle bin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Provider.of<NotesProvider>(context, listen: false)
                  .softDelete(_editingNote.id);
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteContent() => switch (_editingNote.noteType) {
    NoteType.normal => _buildNormalNote(),
    NoteType.checklist => _buildChecklist(),
    NoteType.itinerary => _buildItinerary(),
    NoteType.mealPlan => _buildMealPlan(),
    NoteType.recipe => _buildRecipe(),
  };

  Widget _buildNormalNote() => TextField(
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
          itemCount: _editingNote.checklistItems.length,
          itemBuilder: (context, index) {
            final item = _editingNote.checklistItems[index];
            return _ChecklistItemTile(
              item: item,
              onChanged: (checked) {
                setState(() => item.checked = checked);
              },
              onDelete: () {
                setState(() =>
                    _editingNote.checklistItems.removeAt(index));
              },
              onTextChanged: (text) {
                setState(() => item.text = text);
              },
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: ElevatedButton.icon(
          onPressed: () {
            setState(() {
              _editingNote.checklistItems
                  .add(ChecklistItem(id: const Uuid().v4(), text: ''));
            });
          },
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
          itemCount: _editingNote.itineraryItems.length,
          itemBuilder: (context, index) {
            final item = _editingNote.itineraryItems[index];
            return _ItineraryItemCard(
              item: item,
              onDelete: () {
                setState(() =>
                    _editingNote.itineraryItems.removeAt(index));
              },
              onChanged: () => setState(() {}),
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: ElevatedButton.icon(
          onPressed: () {
            setState(() {
              _editingNote.itineraryItems
                  .add(ItineraryItem(id: const Uuid().v4()));
            });
          },
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
          itemCount: _editingNote.mealPlanItems.length,
          itemBuilder: (context, index) {
            final item = _editingNote.mealPlanItems[index];
            return _MealPlanItemCard(
              item: item,
              onDelete: () {
                setState(() =>
                    _editingNote.mealPlanItems.removeAt(index));
              },
              onChanged: () => setState(() {}),
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: ElevatedButton.icon(
          onPressed: () {
            setState(() {
              _editingNote.mealPlanItems
                  .add(MealPlanItem(id: const Uuid().v4()));
            });
          },
          icon: const Icon(Icons.add),
          label: const Text('Add Day'),
        ),
      ),
    ],
  );

  Widget _buildRecipe() {
    _editingNote.recipeData ??= RecipeData();
    return _RecipeCard(
      data: _editingNote.recipeData!,
      onChanged: () => setState(() {}),
    );
  }
}

// ==================== ITEM WIDGETS ====================

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
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.item.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(
          value: widget.item.checked,
          onChanged: (v) => widget.onChanged(v ?? false),
        ),
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'Enter item...',
              hintStyle: TextStyle(color: Colors.grey.shade400),
            ),
            style: TextStyle(
              decoration: widget.item.checked
                  ? TextDecoration.lineThrough
                  : TextDecoration.none,
              color: widget.item.checked ? Colors.grey : Colors.black,
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
}

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
  late TextEditingController _locationCtrl;
  late TextEditingController _dateCtrl;
  late TextEditingController _arrivalCtrl;
  late TextEditingController _departureCtrl;
  late TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _locationCtrl = TextEditingController(text: widget.item.location);
    _dateCtrl = TextEditingController(text: widget.item.date);
    _arrivalCtrl = TextEditingController(text: widget.item.arrivalTime);
    _departureCtrl = TextEditingController(text: widget.item.departureTime);
    _notesCtrl = TextEditingController(text: widget.item.notes);
  }

  @override
  void dispose() {
    _locationCtrl.dispose();
    _dateCtrl.dispose();
    _arrivalCtrl.dispose();
    _departureCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _locationCtrl,
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
                  icon: const Icon(Icons.delete),
                  onPressed: widget.onDelete,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _dateCtrl,
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
                    controller: _arrivalCtrl,
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
                    controller: _departureCtrl,
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
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
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
}

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
  late TextEditingController _dayCtrl;
  late TextEditingController _breakfastCtrl;
  late TextEditingController _lunchCtrl;
  late TextEditingController _dinnerCtrl;
  late TextEditingController _snacksCtrl;

  @override
  void initState() {
    super.initState();
    _dayCtrl = TextEditingController(text: widget.item.day);
    _breakfastCtrl = TextEditingController(text: widget.item.breakfast);
    _lunchCtrl = TextEditingController(text: widget.item.lunch);
    _dinnerCtrl = TextEditingController(text: widget.item.dinner);
    _snacksCtrl = TextEditingController(text: widget.item.snacks);
  }

  @override
  void dispose() {
    _dayCtrl.dispose();
    _breakfastCtrl.dispose();
    _lunchCtrl.dispose();
    _dinnerCtrl.dispose();
    _snacksCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dayCtrl,
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
                  icon: const Icon(Icons.delete),
                  onPressed: widget.onDelete,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _breakfastCtrl,
              decoration: const InputDecoration(
                labelText: 'Breakfast',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                widget.item.breakfast = v;
                widget.onChanged();
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _lunchCtrl,
              decoration: const InputDecoration(
                labelText: 'Lunch',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                widget.item.lunch = v;
                widget.onChanged();
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _dinnerCtrl,
              decoration: const InputDecoration(
                labelText: 'Dinner',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                widget.item.dinner = v;
                widget.onChanged();
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _snacksCtrl,
              decoration: const InputDecoration(
                labelText: 'Snacks',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                widget.item.snacks = v;
                widget.onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipeCard extends StatefulWidget {
  final RecipeData data;
  final VoidCallback onChanged;

  const _RecipeCard({
    required this.data,
    required this.onChanged,
  });

  @override
  State<_RecipeCard> createState() => _RecipeCardState();
}

class _RecipeCardState extends State<_RecipeCard> {
  late TextEditingController _prepTimeCtrl;
  late TextEditingController _cookTimeCtrl;
  late TextEditingController _servingsCtrl;
  late TextEditingController _ingredientsCtrl;
  late TextEditingController _instructionsCtrl;

  @override
  void initState() {
    super.initState();
    _prepTimeCtrl = TextEditingController(text: widget.data.prepTime);
    _cookTimeCtrl = TextEditingController(text: widget.data.cookTime);
    _servingsCtrl = TextEditingController(text: widget.data.servings);
    _ingredientsCtrl = TextEditingController(text: widget.data.ingredients);
    _instructionsCtrl = TextEditingController(text: widget.data.instructions);
  }

  @override
  void dispose() {
    _prepTimeCtrl.dispose();
    _cookTimeCtrl.dispose();
    _servingsCtrl.dispose();
    _ingredientsCtrl.dispose();
    _instructionsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _prepTimeCtrl,
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
                  controller: _cookTimeCtrl,
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
            controller: _servingsCtrl,
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
          const Text('Ingredients',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _ingredientsCtrl,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'List ingredients...',
            ),
            maxLines: 8,
            onChanged: (v) {
              widget.data.ingredients = v;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 16),
          const Text('Instructions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _instructionsCtrl,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Step-by-step instructions...',
            ),
            maxLines: 10,
            onChanged: (v) {
              widget.data.instructions = v;
              widget.onChanged();
            },
          ),
        ],
      ),
    );
  }
}

// ==================== RECYCLE BIN SCREEN ====================

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
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Empty Recycle Bin'),
                    content: const Text(
                        'Permanently delete all notes? This cannot be undone.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete All'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  for (final n in items) {
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
        itemBuilder: (c, i) {
          final n = items[i];
          return Card(
            margin: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            child: ListTile(
              title: Text(n.title.isNotEmpty ? n.title : '(Untitled)'),
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
                    icon: const Icon(Icons.delete_forever,
                        color: Colors.red),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Permanently Delete'),
                          content: const Text(
                              'Are you sure? This cannot be undone.'),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        prov.hardDelete(n.id);
                      }
                    },
                    tooltip: 'Delete Permanently',
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