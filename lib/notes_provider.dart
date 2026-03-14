import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show pow, min;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

const String kNotesBox = 'notes_box_v4';
const String kImagesBox = 'images_box_v1';
const String kSearchIndexBox = 'search_index_box_v2';
const String kSyncStateBox = 'sync_state_box_v3';

const String kDriveRootName = '.liha_notes_app';
const String kDriveNotesDir = 'notes';
const String kDriveImagesDir = 'images';
const String kManifestName = 'manifest.json';

const int kInitialBackoffMs = 500;
const double kBackoffMultiplier = 1.5;
const int kMaxRetries = 5;
const int kMaxBackoffMs = 30000;

class NotesProvider extends ChangeNotifier {
  Box<dynamic>? _notesBox;
  Box<String>? _imagesBox;
  Box<String>? _searchIndexBox;
  Box<dynamic>? _syncStateBox;

  late final GoogleSignIn _googleSignIn;
  GoogleSignInAccount? _currentUser;

  SyncState _syncState = SyncState();
  SyncStatus _syncStatus = SyncStatus.idle;
  String? _syncStatusMessage;
  Timer? _syncStatusTimer;

  DriveAccountState _driveAccountState = DriveAccountState.unknown;
  bool _isCheckingDrive = false;

  DriveAccountState get driveAccountState => _driveAccountState;
  bool get isCheckingDrive => _isCheckingDrive;

  GoogleSignInAccount? get user => _currentUser;
  SyncStatus get syncStatus => _syncStatus;
  String? get syncStatusMessage => _syncStatusMessage;
  bool get isSyncing => _syncStatus == SyncStatus.syncing;
  List<NoteSync> get syncConflicts => _syncState.conflicts;

  List<Note> get notes {
    if (_notesBox == null) return [];
    return _notesBox!.values.cast<Note>().where((n) => !n.deleted).toList()
      ..sort((a, b) => a.pinned != b.pinned
          ? (a.pinned ? -1 : 1)
          : b.updatedAt.compareTo(a.updatedAt));
  }

  List<Note> get recycleBin =>
      _notesBox?.values.cast<Note>().where((n) => n.deleted).toList() ?? [];

  NotesProvider() {
    _googleSignIn = GoogleSignIn(scopes: [drive.DriveApi.driveFileScope]);
  }

  Future<void> init() async {
    try {
      _notesBox = await Hive.openBox<dynamic>(kNotesBox);
      _imagesBox = await Hive.openBox<String>(kImagesBox);
      _searchIndexBox = await Hive.openBox<String>(kSearchIndexBox);
      _syncStateBox = await Hive.openBox<dynamic>(kSyncStateBox);

      _loadSyncState();
      _rebuildSearchIndex();

      _googleSignIn.onCurrentUserChanged.listen((account) async {
        _currentUser = account;
        if (account != null) {
          final alreadySyncedOnThisDevice = _syncState.manifestFileId != null &&
              _syncState.accountEmail == account.email;

          if (alreadySyncedOnThisDevice) {
            _driveAccountState = DriveAccountState.returningUser;
          } else {
            await _checkDriveManifestExists();
          }
        } else {
          _driveAccountState = DriveAccountState.unknown;
        }
        notifyListeners();
      });

      _currentUser = await _googleSignIn.signInSilently();
      if (_currentUser == null) notifyListeners();
    } catch (e) {
      debugPrint('Init error: $e');
    }
  }

  Future<void> _checkDriveManifestExists() async {
    if (_currentUser == null) return;
    _isCheckingDrive = true;
    _setStatus('Checking Drive for existing backup…',
        isSyncing: true, persistent: true);
    notifyListeners();

    try {
      final client = await _googleSignIn.authenticatedClient();
      if (client == null) throw Exception('Authentication failed');

      final api = drive.DriveApi(client);

      final rootList = await _retry(
        () => api.files.list(
          q: "name = '$kDriveRootName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
          $fields: 'files(id)',
          pageSize: 1,
        ),
        name: 'checkRootFolder',
      );

      if (rootList.files?.isEmpty ?? true) {
        _driveAccountState = DriveAccountState.newUser;
        _setStatus('No backup found. Upload to create first backup.',
            persistent: true);
        return;
      }

      final rootId = rootList.files!.first.id!;

      final manifestList = await _retry(
        () => api.files.list(
          q: "name = '$kManifestName' and '$rootId' in parents and trashed = false",
          $fields: 'files(id)',
          pageSize: 1,
        ),
        name: 'checkManifest',
      );

      if (manifestList.files?.isNotEmpty ?? false) {
        _syncState.rootFolderId = rootId;
        _syncState.manifestFileId = manifestList.files!.first.id;
        _persistSyncState();
        _driveAccountState = DriveAccountState.returningUser;
        _setStatus('Existing backup found. Sync to merge notes from cloud.',
            persistent: true);
      } else {
        _syncState.rootFolderId = rootId;
        _persistSyncState();
        _driveAccountState = DriveAccountState.newUser;
        _setStatus('No backup found. Upload to create first backup.',
            persistent: true);
      }
    } catch (e) {
      debugPrint('Drive check error: $e');
      _driveAccountState = DriveAccountState.unknown;
      _setStatus('Could not check Drive: $e', isError: true);
    } finally {
      _isCheckingDrive = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _syncStatusTimer?.cancel();
    super.dispose();
  }

  void _rebuildSearchIndex() {
    if (_notesBox == null || _searchIndexBox == null) return;
    _searchIndexBox!.clear();
    for (final note in _notesBox!.values.cast<Note>()) {
      _updateSearchIndex(note);
    }
  }

  void _updateSearchIndex(Note note) {
    if (_searchIndexBox == null) return;
    if (note.deleted) {
      _searchIndexBox!.delete(note.id);
    } else {
      _searchIndexBox!.put(note.id,
          '${note.title} ${note.content} ${note.category}'.toLowerCase());
    }
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
      ..sort((a, b) => a.pinned != b.pinned
          ? (a.pinned ? -1 : 1)
          : b.updatedAt.compareTo(a.updatedAt));
  }

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
      final allImageRefs = <String>{};
      for (final n in _notesBox!.values.cast<Note>()) {
        if (n.id != id && !n.deleted) allImageRefs.addAll(n.imageIds);
      }
      for (final imgId in note.imageIds) {
        if (!allImageRefs.contains(imgId)) {
          await deleteImage(imgId);
        }
      }
    }
    await _notesBox!.delete(id);
    _searchIndexBox?.delete(id);
    if (_syncState.notes[id] != null) {
      _syncState.notes[id] =
          _syncState.notes[id]!.copyWith(pendingUpload: true);
    }
    _persistSyncState();
    notifyListeners();
  }

  Future<String> saveImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final imageId = const Uuid().v4();
    await _imagesBox?.put(imageId, _encodeImage(Uint8List.fromList(bytes)));
    _syncState.markImageDirty(imageId);
    _persistSyncState();
    return imageId;
  }

  String? getImage(String imageId) {
    final encoded = _imagesBox?.get(imageId);
    if (encoded == null) return null;
    return base64Encode(_decodeImage(encoded));
  }

  Future<void> deleteImage(String imageId) async {
    await _imagesBox?.delete(imageId);
    _syncState.images.remove(imageId);
    _persistSyncState();
  }

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
      _driveAccountState = DriveAccountState.unknown;
      notifyListeners();
    } catch (e) {
      debugPrint('Sign out error: $e');
    }
  }

  Future<void> resolveConflictKeepLocal(String noteId) async {
    final ns = _syncState.notes[noteId];
    if (ns == null) return;
    _syncState.notes[noteId] =
        ns.copyWith(clearConflict: true, pendingUpload: true);
    _persistSyncState();
    notifyListeners();
  }

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

  Future<void> resolveConflictKeepBoth(String noteId) async {
    final ns = _syncState.notes[noteId];
    if (ns?.conflict == null) return;
    final remote = ns!.conflict!.remoteVersion;
    final duplicate = remote.copyWith(
      id: const Uuid().v4(),
      title: '${remote.title} (Conflict copy)',
    );
    await _notesBox?.put(duplicate.id, duplicate);
    _updateSearchIndex(duplicate);
    _syncState.markNoteDirty(duplicate.id);
    _syncState.notes[noteId] = ns.copyWith(clearConflict: true);
    _persistSyncState();
    notifyListeners();
  }

  void _setStatus(String? msg,
      {bool isError = false, bool isSyncing = false, bool persistent = false}) {
    _syncStatusTimer?.cancel();
    _syncStatusMessage = msg;
    _syncStatus = msg == null
        ? SyncStatus.idle
        : (isError
            ? SyncStatus.error
            : (isSyncing ? SyncStatus.syncing : SyncStatus.idle));
    notifyListeners();

    if (msg != null && !isSyncing && !persistent) {
      _syncStatusTimer = Timer(const Duration(seconds: 4), () {
        _syncStatusMessage = null;
        _syncStatus = SyncStatus.idle;
        notifyListeners();
      });
    }
  }

  Future<T> _retry<T>(Future<T> Function() op,
      {String? name, int maxRetries = kMaxRetries}) async {
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

  void _loadSyncState() {
    final raw = _syncStateBox?.get('state');
    if (raw != null) {
      try {
        _syncState = SyncState.fromJson(
            raw is Map ? Map<String, dynamic>.from(raw) : {});
      } catch (e) {
        debugPrint('Failed to load sync state: $e');
        _syncState = SyncState();
      }
    }
  }

  void _persistSyncState() => _syncStateBox?.put('state', _syncState.toJson());

  String _encodeImage(Uint8List bytes) => jsonEncode(bytes);

  Uint8List _decodeImage(String encoded) {
    final list = jsonDecode(encoded) as List;
    return Uint8List.fromList(list.cast<int>());
  }

  Future<void> _ensureFolders(drive.DriveApi api) async {
    _syncState.rootFolderId ??=
        await _findOrCreateFolder(api, kDriveRootName, parentId: null);
    _syncState.notesFolderId ??= await _findOrCreateFolder(api, kDriveNotesDir,
        parentId: _syncState.rootFolderId!);
    _syncState.imagesFolderId ??= await _findOrCreateFolder(
        api, kDriveImagesDir,
        parentId: _syncState.rootFolderId!);
    _persistSyncState();
  }

  Future<String> _findOrCreateFolder(drive.DriveApi api, String name,
      {required String? parentId}) async {
    final parentClause = parentId != null ? " and '$parentId' in parents" : '';
    final list = await _retry(
      () => api.files.list(
        q: "name = '$name' and mimeType = 'application/vnd.google-apps.folder' and trashed = false$parentClause",
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
    final created =
        await _retry(() => api.files.create(meta), name: 'createFolder:$name');
    return created.id!;
  }

  Future<DriveManifest> _fetchManifest(drive.DriveApi api) async {
    if (_syncState.manifestFileId == null) {
      final list = await _retry(
        () => api.files.list(
          q: "name = '$kManifestName' and '${_syncState.rootFolderId}' in parents and trashed = false",
          $fields: 'files(id)',
          pageSize: 1,
        ),
        name: 'findManifest',
      );
      if (list.files?.isEmpty ?? true) {
        return DriveManifest.empty();
      }
      _syncState.manifestFileId = list.files!.first.id;
      _persistSyncState();
    }

    try {
      final response = await _retry(
        () => api.files.get(_syncState.manifestFileId!,
            downloadOptions: drive.DownloadOptions.fullMedia),
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

  Future<void> _deleteOrphanedImagesFromDrive(drive.DriveApi api) async {
    final referencedImages = <String>{};
    if (_notesBox != null) {
      for (final note in _notesBox!.values.cast<Note>()) {
        if (!note.deleted) referencedImages.addAll(note.imageIds);
      }
    }

    for (final entry in _syncState.images.entries) {
      if (!referencedImages.contains(entry.key) && entry.value.existsOnDrive) {
        try {
          await _retry(
            () => api.files.delete(entry.value.driveFileId!),
            name: 'deleteOrphanedImage:${entry.key}',
          );
          _syncState.images.remove(entry.key);
          debugPrint('Deleted orphaned image ${entry.key} from Drive');
        } catch (e) {
          debugPrint('Failed to delete orphaned image ${entry.key}: $e');
        }
      }
    }
  }

  Future<void> _pushManifest(drive.DriveApi api) async {
    final allNotes = _notesBox?.values.cast<Note>().toList() ?? [];
    final noteMetadata = <String, Map<String, dynamic>>{};
    for (final n in allNotes) {
      noteMetadata[n.id] = {
        'updatedAt': n.updatedAt.toIso8601String(),
        'deleted': n.deleted,
      };
    }

    final allImageIds = _syncState.images.entries
        .where((e) => e.value.existsOnDrive)
        .map((e) => e.key)
        .toSet();

    final manifest = DriveManifest(
      generatedAt: DateTime.now(),
      noteMetadata: noteMetadata,
      imageIds: allImageIds,
    );
    final encoded = utf8.encode(jsonEncode(manifest.toJson()));
    final media = drive.Media(Stream.value(encoded), encoded.length,
        contentType: 'application/json');

    if (_syncState.manifestFileId != null) {
      await _retry(
        () => api.files.update(drive.File(), _syncState.manifestFileId!,
            uploadMedia: media),
        name: 'updateManifest',
      );
    } else {
      final file = drive.File()
        ..name = kManifestName
        ..parents = [_syncState.rootFolderId!];
      final created = await _retry(
          () => api.files.create(file, uploadMedia: media),
          name: 'createManifest');
      _syncState.manifestFileId = created.id;
      _persistSyncState();
    }
  }

  Future<void> uploadNotes() async {
    if (_currentUser == null || _notesBox == null) {
      _setStatus('Login required', isError: true);
      return;
    }
    if (isSyncing) return;

    _setStatus('Uploading…', isSyncing: true);

    try {
      final client = await _googleSignIn.authenticatedClient();
      if (client == null) throw Exception('Authentication failed');

      final api = drive.DriveApi(client);
      await _ensureFolders(api);

      final dirtyNoteIds = _syncState.pendingNoteUploads;
      final dirtyImageIds = _syncState.pendingImageUploads;

      if (dirtyNoteIds.isEmpty && dirtyImageIds.isEmpty) {
        _setStatus('Nothing to upload');
        return;
      }

      for (final noteId in dirtyNoteIds) {
        final note = _notesBox!.get(noteId) as Note?;
        if (note == null) continue;
        await _uploadImagesForNote(api, note);
        await _uploadNote(api, note);
      }

      final notesWithImages = <String>{};
      if (_notesBox != null) {
        for (final note in _notesBox!.values.cast<Note>()) {
          if (!note.deleted) notesWithImages.addAll(note.imageIds);
        }
      }

      for (final imageId in dirtyImageIds) {
        if (!notesWithImages.contains(imageId)) {
          await _uploadImage(api, imageId);
        }
      }

      await _deleteOrphanedImagesFromDrive(api);
      await _pushManifest(api);

      _syncState.lastSyncCompletedAt = DateTime.now();
      _syncState.accountEmail = _currentUser?.email;
      _persistSyncState();

      _driveAccountState = DriveAccountState.returningUser;

      _setStatus('Upload complete ✓');
      notifyListeners();
    } catch (e) {
      _setStatus('Upload failed: $e', isError: true);
      debugPrint('Upload error: $e');
    } finally {
      if (_syncStatus == SyncStatus.syncing) {
        _syncStatus = SyncStatus.idle;
        notifyListeners();
      }
    }
  }

  Future<void> _uploadImage(drive.DriveApi api, String imageId) async {
    final imgSync = _syncState.images[imageId];
    if (imgSync?.existsOnDrive == true && imgSync?.pendingUpload == false) {
      return;
    }

    final rawData = _imagesBox?.get(imageId);
    if (rawData == null) {
      debugPrint('Image $imageId missing locally, skipping upload');
      return;
    }

    final bytes = _decodeImage(rawData);
    final media = drive.Media(Stream.value(bytes), bytes.length,
        contentType: 'application/octet-stream');

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
          name: 'createImage:$imageId');
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

  Future<void> _uploadNote(drive.DriveApi api, Note note) async {
    final encoded = utf8.encode(jsonEncode(note.toJson()));
    final media = drive.Media(Stream.value(encoded), encoded.length,
        contentType: 'application/json');

    final ns = _syncState.notes[note.id];
    String? fileId = ns?.driveFileId;

    if (fileId != null) {
      await _retry(
        () => api.files.update(drive.File(), fileId!, uploadMedia: media),
        name: 'updateNote:${note.id}',
      );
    } else if (!note.deleted) {
      final file = drive.File()
        ..name = '${note.id}.json'
        ..parents = [_syncState.notesFolderId!];
      final created = await _retry(
          () => api.files.create(file, uploadMedia: media),
          name: 'createNote:${note.id}');
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
    const maxConcurrent = 3;
    final imageIds = note.imageIds.toList();

    for (int i = 0; i < imageIds.length; i += maxConcurrent) {
      final batch =
          imageIds.sublist(i, min(i + maxConcurrent, imageIds.length));
      await Future.wait(
        batch.map((imgId) async {
          final imgSync = _syncState.images[imgId];
          if (imgSync?.existsOnDrive == true &&
              imgSync?.pendingUpload == false) {
            return;
          }

          final rawData = _imagesBox?.get(imgId);
          if (rawData == null) {
            debugPrint('Image $imgId missing locally, skipping upload');
            return;
          }

          final bytes = _decodeImage(rawData);
          final media = drive.Media(Stream.value(bytes), bytes.length,
              contentType: 'application/octet-stream');

          String? fileId = imgSync?.driveFileId;
          if (fileId != null) {
            await _retry(
              () => api.files.update(drive.File(), fileId!, uploadMedia: media),
              name: 'updateImage:$imgId',
            );
          } else {
            final file = drive.File()
              ..name = '$imgId.bin'
              ..parents = [_syncState.imagesFolderId!];
            final created = await _retry(
                () => api.files.create(file, uploadMedia: media),
                name: 'createImage:$imgId');
            fileId = created.id;
          }

          _syncState.images[imgId] = ImageSync(
            imageId: imgId,
            driveFileId: fileId,
            pendingUpload: false,
            existsOnDrive: true,
          );
        }),
      );
    }
    _persistSyncState();
  }

  Future<void> downloadNotes() async {
    if (_currentUser == null || _notesBox == null) {
      _setStatus('Login required', isError: true);
      return;
    }
    if (isSyncing) return;

    _setStatus('Checking for updates…', isSyncing: true);

    try {
      final client = await _googleSignIn.authenticatedClient();
      if (client == null) throw Exception('Authentication failed');

      final api = drive.DriveApi(client);
      await _ensureFolders(api);

      final manifest = await _fetchManifest(api);
      final toDownload = _diffManifest(manifest);

      if (toDownload.isEmpty) {
        _setStatus('Already up to date ✓');
        return;
      }

      _setStatus('Downloading ${toDownload.length} note(s)…', isSyncing: true);
      for (final noteId in toDownload) {
        await _downloadNote(api, manifest, noteId);
      }

      await _reconcileDeletedNotes(manifest);
      await _downloadMissingImages(api, manifest);
      _rebuildSearchIndex();

      _syncState.lastSyncCompletedAt = DateTime.now();
      _syncState.accountEmail = _currentUser?.email;
      _persistSyncState();
      _setStatus('Download complete ✓');
      notifyListeners();
    } catch (e) {
      _setStatus('Download failed: $e', isError: true);
      debugPrint('Download error: $e');
    } finally {
      if (_syncStatus == SyncStatus.syncing) {
        _syncStatus = SyncStatus.idle;
        notifyListeners();
      }
    }
  }

  List<String> _diffManifest(DriveManifest manifest) {
    final toDownload = <String>[];

    for (final entry in manifest.noteMetadata.entries) {
      final noteId = entry.key;
      final metadata = entry.value;
      final remoteTs = DateTime.tryParse(metadata['updatedAt'] ?? '');
      if (remoteTs == null) continue;

      final ns = _syncState.notes[noteId];
      final localNote = _notesBox!.get(noteId) as Note?;

      if (localNote == null) {
        toDownload.add(noteId);
      } else if (ns?.remoteVersion == null ||
          remoteTs.isAfter(ns!.remoteVersion!)) {
        toDownload.add(noteId);
      }
    }

    return toDownload;
  }

  Future<void> _downloadNote(
      drive.DriveApi api, DriveManifest manifest, String noteId) async {
    final metadata = manifest.noteMetadata[noteId];
    String? fileId = _syncState.notes[noteId]?.driveFileId;
    if (fileId == null) {
      final list = await _retry(
        () => api.files.list(
          q: "name = '$noteId.json' and '${_syncState.notesFolderId}' in parents and trashed = false",
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
      () => api.files
          .get(fileId!, downloadOptions: drive.DownloadOptions.fullMedia),
      name: 'downloadNote:$noteId',
    );
    if (response is! drive.Media) throw Exception('Unexpected response type');

    final bytes = await response.stream.expand((c) => c).toList();
    final remoteNote =
        Note.fromJson(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);

    final localNote = _notesBox!.get(noteId) as Note?;
    final ns = _syncState.notes[noteId];

    final localDirty = ns?.pendingUpload == true;
    final remoteNewer = ns?.remoteVersion == null ||
        remoteNote.updatedAt.isAfter(ns!.remoteVersion!);

    if (localNote != null &&
        localDirty &&
        remoteNewer &&
        ns?.lastSyncedAt != null) {
      debugPrint('Conflict detected on note $noteId');
      _syncState.notes[noteId] = (ns ?? NoteSync(noteId: noteId)).copyWith(
        driveFileId: fileId,
        remoteVersion: remoteNote.updatedAt,
        conflict:
            SyncConflict(remoteVersion: remoteNote, detectedAt: DateTime.now()),
      );
      _persistSyncState();
      return;
    }

    for (final imgId in remoteNote.imageIds) {
      if (_imagesBox?.get(imgId) == null) {
        final existing = _syncState.images[imgId];
        _syncState.images[imgId] = ImageSync(
          imageId: imgId,
          driveFileId: existing?.driveFileId,
          pendingUpload: false,
          existsOnDrive: true,
        );
      }
    }

    if (metadata?['deleted'] == true) {
      remoteNote.deleted = true;
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

  Future<void> _reconcileDeletedNotes(DriveManifest manifest) async {
    final localNoteIds = (_notesBox?.keys.cast<dynamic>().toList() ?? [])
        .whereType<String>()
        .toList();

    for (final noteId in localNoteIds) {
      if (!manifest.noteMetadata.containsKey(noteId)) {
        final ns = _syncState.notes[noteId];
        if (ns?.pendingUpload == false) {
          await hardDelete(noteId);
        }
      }
    }
  }

  Future<void> _downloadMissingImages(
      drive.DriveApi api, DriveManifest manifest) async {
    for (final imageId in manifest.imageIds) {
      if (_imagesBox?.get(imageId) != null) continue;

      final imgSync = _syncState.images[imageId];
      String? fileId = imgSync?.driveFileId;

      if (fileId == null) {
        final list = await _retry(
          () => api.files.list(
            q: "name = '$imageId.bin' and '${_syncState.imagesFolderId}' in parents and trashed = false",
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
          () => api.files
              .get(fileId!, downloadOptions: drive.DownloadOptions.fullMedia),
          name: 'downloadImage:$imageId',
        );
        if (response is! drive.Media) continue;

        final buffer = <int>[];
        const chunkSize = 64 * 1024;

        await for (final chunk in response.stream) {
          buffer.addAll(chunk);
          if (buffer.length > chunkSize) {
            await Future.delayed(Duration.zero);
          }
        }

        await _imagesBox?.put(
            imageId, _encodeImage(Uint8List.fromList(buffer)));

        _syncState.images[imageId] = ImageSync(
          imageId: imageId,
          driveFileId: fileId,
          pendingUpload: false,
          existsOnDrive: true,
        );
        _persistSyncState();
      } catch (e) {
        debugPrint('Failed to download image $imageId: $e');
      }
    }
  }

  void refreshNotes() {
    _rebuildSearchIndex();
    notifyListeners();
  }
}
