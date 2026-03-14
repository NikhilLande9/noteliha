import 'package:uuid/uuid.dart';
import 'package:hive/hive.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────

enum NoteType { normal, checklist, itinerary, mealPlan, recipe }

enum ColorTheme { default_, sunset, orange, forest, lavender, rose }

enum SyncStatus { idle, syncing, error }

enum AppTheme { amber, teal, indigo, rose, slate }

enum DriveAccountState {
  unknown, // Not yet checked (checking in progress)
  newUser, // Signed in, no manifest found on Drive → first-time user
  returningUser // Signed in, manifest found on Drive → existing backup present
}

// ─────────────────────────────────────────────────────────────────────────────
// Checklist Item
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

// ─────────────────────────────────────────────────────────────────────────────
// Itinerary Item
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Meal Plan Item
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Recipe Data
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Main Note Model
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Hive Adapter
// ─────────────────────────────────────────────────────────────────────────────

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
// Sync Models
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

  ImageSync copyWith(
          {String? driveFileId, bool? pendingUpload, bool? existsOnDrive}) =>
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
      accountEmail: j['accountEmail'],
    );
  }
}

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

  factory DriveManifest.fromJson(Map<String, dynamic> j) => DriveManifest(
        schemaVersion: j['schemaVersion'] ?? 1,
        generatedAt:
            DateTime.tryParse(j['generatedAt'] ?? '') ?? DateTime.now(),
        noteMetadata: Map<String, Map<String, dynamic>>.from(
            (j['noteMetadata'] as Map?)?.map((k, v) =>
                    MapEntry(k, Map<String, dynamic>.from(v as Map))) ??
                {}),
        imageIds: Set<String>.from((j['imageIds'] as List?) ?? []),
      );

  factory DriveManifest.empty() => DriveManifest(
        schemaVersion: 1,
        generatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        noteMetadata: {},
        imageIds: {},
      );
}
