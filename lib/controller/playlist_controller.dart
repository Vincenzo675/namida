// ignore_for_file: non_constant_identifier_names

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:path/path.dart' as p;
import 'package:playlist_manager/playlist_manager.dart';

import 'package:namida/class/track.dart';
import 'package:namida/controller/generators_controller.dart';
import 'package:namida/controller/indexer_controller.dart';
import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/controller/player_controller.dart';
import 'package:namida/controller/search_sort_controller.dart';
import 'package:namida/controller/settings_controller.dart';
import 'package:namida/core/constants.dart';
import 'package:namida/core/enums.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/functions.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/translations/language.dart';
import 'package:namida/core/utils.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';

typedef LocalPlaylist = GeneralPlaylist<TrackWithDate>;

class PlaylistController extends PlaylistManager<TrackWithDate, Track> {
  static PlaylistController get inst => _instance;
  static final PlaylistController _instance = PlaylistController._internal();
  PlaylistController._internal();

  @override
  Track identifyBy(TrackWithDate item) => item.track;

  final canReorderTracks = false.obs;
  void resetCanReorder() => canReorderTracks.value = false;

  void addNewPlaylist(String name,
      {List<Track> tracks = const <Track>[],
      int? creationDate,
      String comment = '',
      List<String> moods = const [],
      String? m3uPath,
      PlaylistAddDuplicateAction? actionIfAlreadyExists}) async {
    super.addNewPlaylistRaw(
      name,
      tracks: tracks,
      convertItem: (e, dateAdded, playlistID) => TrackWithDate(
        dateAdded: dateAdded,
        track: e,
        source: TrackSource.local,
      ),
      creationDate: creationDate,
      comment: comment,
      moods: moods,
      m3uPath: m3uPath,
      actionIfAlreadyExists: () => actionIfAlreadyExists ?? NamidaOnTaps.inst.showDuplicatedDialogAction(PlaylistAddDuplicateAction.valuesForAdd),
    );
  }

  void addTracksToPlaylist(
    LocalPlaylist playlist,
    List<Track> tracks, {
    TrackSource source = TrackSource.local,
    List<PlaylistAddDuplicateAction> duplicationActions = PlaylistAddDuplicateAction.valuesForAdd,
  }) async {
    final originalModifyDate = playlist.modifiedDate;
    final oldTracksList = List<TrackWithDate>.from(playlist.tracks); // for undo

    final addedTracksLength = await super.addTracksToPlaylistRaw(
      playlist,
      tracks,
      () => NamidaOnTaps.inst.showDuplicatedDialogAction(duplicationActions),
      (e, dateAdded) {
        return TrackWithDate(
          dateAdded: dateAdded,
          track: e,
          source: source,
        );
      },
    );

    if (addedTracksLength == null) return;

    snackyy(
      message: "${lang.ADDED} ${addedTracksLength.displayTrackKeyword}",
      button: addedTracksLength > 0
          ? (
              lang.UNDO,
              () async => await updatePropertyInPlaylist(playlist.name, tracks: oldTracksList, modifiedDate: originalModifyDate),
            )
          : null,
    );
  }

  bool favouriteButtonOnPressed(Track track, {bool refreshNotification = true}) {
    final res = super.toggleTrackFavourite(
      TrackWithDate(dateAdded: currentTimeMS, track: track, source: TrackSource.local),
    );
    if (refreshNotification) {
      final currentItem = Player.inst.currentItem.value;
      if (currentItem is Selectable && currentItem.track == track) {
        Player.inst.refreshNotification();
      }
    }
    return res;
  }

  Future<void> replaceTracksDirectory(String oldDir, String newDir, {Iterable<String>? forThesePathsOnly, bool ensureNewFileExists = false}) async {
    String getNewPath(String old) => old.replaceFirst(oldDir, newDir);

    await replaceTheseTracksInPlaylists(
      (e) {
        final trackPath = e.track.path;
        if (ensureNewFileExists) {
          if (!File(getNewPath(trackPath)).existsSync()) return false;
        }
        final firstC = forThesePathsOnly != null ? forThesePathsOnly.contains(e.track.path) : true;
        final secondC = trackPath.startsWith(oldDir);
        return firstC && secondC;
      },
      (old) => TrackWithDate(
        dateAdded: old.dateAdded,
        track: Track.fromTypeParameter(old.track.runtimeType, getNewPath(old.track.path)),
        source: old.source,
      ),
    );
  }

  Future<void> replaceTrackInAllPlaylists(Track oldTrack, Track newTrack) async {
    await replaceTheseTracksInPlaylists(
      (e) => e.track == oldTrack,
      (old) => TrackWithDate(
        dateAdded: old.dateAdded,
        track: newTrack,
        source: old.source,
      ),
    );
  }

  Future<void> replaceTrackInAllPlaylistsBulk(Map<Track, Track> oldNewTrack) async {
    final fnList = <MapEntry<bool Function(TrackWithDate e), TrackWithDate Function(TrackWithDate old)>>[];
    for (final entry in oldNewTrack.entries) {
      fnList.add(
        MapEntry(
          (e) => e.track == entry.key,
          (old) => TrackWithDate(
            dateAdded: old.dateAdded,
            track: entry.value,
            source: old.source,
          ),
        ),
      );
    }
    await replaceTheseTracksInPlaylistsBulk(fnList);
  }

  @override
  Future<bool> renamePlaylist(String playlistName, String newName) async {
    final didRename = await super.renamePlaylist(playlistName, newName);
    if (didRename) _popPageIfCurrent(() => playlistName);
    return didRename;
  }

  /// Returns number of generated tracks.
  int generateRandomPlaylist() {
    final rt = NamidaGenerator.inst.getRandomTracks();
    if (rt.isEmpty) return 0;

    final l = playlistsMap.keys.where((name) => name.startsWith(k_PLAYLIST_NAME_AUTO_GENERATED)).length;
    addNewPlaylist('$k_PLAYLIST_NAME_AUTO_GENERATED ${l + 1}', tracks: rt.toList());

    return rt.length;
  }

  Future<void> exportPlaylistToM3UFile(LocalPlaylist playlist, String path) async {
    await _saveM3UPlaylistToFile.thready({
      'path': path,
      'tracks': playlist.tracks,
      'infoMap': _pathsM3ULookup,
    });
  }

  Future<void> prepareAllPlaylists() async {
    await super.prepareAllPlaylistsFile();
    // -- preparing all playlist is awaited, for cases where
    // -- similar name exists, so m3u overrides it
    // -- this can produce in an outdated playlist version in cache
    // -- which will be seen if the m3u file got deleted/renamed
    await prepareM3UPlaylists();
    if (!_m3uPlaylistsCompleter.isCompleted) _m3uPlaylistsCompleter.complete(true);
  }

  Future<List<Track>> readM3UFiles(Set<String> filesPaths) async {
    final resBoth = await _parseM3UPlaylistFiles.thready({
      'paths': filesPaths,
      'libraryTracks': allTracksInLibrary,
      'backupDirPath': AppDirs.M3UBackup,
    });
    final infoMap = resBoth['infoMap'] as Map<String, String?>;
    _pathsM3ULookup.addAll(infoMap);

    final paths = resBoth['paths'] as Map<String, (String, List<Track>)>;
    final listy = <Track>[];
    for (final p in paths.entries) {
      listy.addAll(p.value.$2);
    }

    return listy;
  }

  void removeM3UPlaylists() {
    final keysToRemove = <String>[];
    for (final e in playlistsMap.value.entries) {
      final isM3U = e.value.m3uPath?.isNotEmpty == true;
      if (isM3U) keysToRemove.add(e.key);
    }
    keysToRemove.loop(
      (key) {
        final pl = playlistsMap.value[key]!;
        final canRemove = canRemovePlaylist(pl);
        if (canRemove) {
          onPlaylistRemovedFromMap(pl);
          playlistsMap.value.remove(key);
        }
      },
    );
    playlistsMap.refresh();
  }

  final _m3uPlaylistsCompleter = Completer<bool>();
  Future<bool> get waitForM3UPlaylistsLoad => _m3uPlaylistsCompleter.future;

  bool _addedM3UPlaylists = false;
  Future<int?> prepareM3UPlaylists({Set<String> forPaths = const {}, bool addAsM3U = true}) async {
    if (forPaths.isEmpty && addAsM3U && !settings.enableM3USyncStartup.value) {
      if (_addedM3UPlaylists) removeM3UPlaylists();

      _addedM3UPlaylists = false;
      return null;
    }

    if (addAsM3U) _addedM3UPlaylists = true;

    try {
      late final Set<String> allPaths;
      if (forPaths.isNotEmpty) {
        allPaths = forPaths;
      } else {
        final allAvailableDirectories = await Indexer.inst.getAvailableDirectories(strictNoMedia: false);
        final parameters = {
          'allAvailableDirectories': allAvailableDirectories,
          'directoriesToExclude': <String>[],
          'extensions': NamidaFileExtensionsWrapper.m3u,
          'respectNoMedia': false,
        };
        final mapResult = await getFilesTypeIsolate.thready(parameters);
        allPaths = mapResult['allPaths'] as Set<String>;
      }

      final resBoth = await _parseM3UPlaylistFiles.thready({
        'paths': allPaths,
        'libraryTracks': allTracksInLibrary,
        'backupDirPath': AppDirs.M3UBackup,
      });
      final paths = resBoth['paths'] as Map<String, (String, List<Track>)>;
      final infoMap = resBoth['infoMap'] as Map<String, String?>;

      // -- removing old m3u playlists (only if preparing all)
      if (forPaths.isEmpty) {
        removeM3UPlaylists();
      }

      for (final e in paths.entries) {
        try {
          final plName = e.key;
          final m3uPath = e.value.$1;
          final trs = e.value.$2;
          final creationDate = File(m3uPath).statSync().creationDate.millisecondsSinceEpoch;
          this.addNewPlaylist(
            plName,
            tracks: trs,
            m3uPath: addAsM3U ? m3uPath : null,
            creationDate: creationDate,
            actionIfAlreadyExists: PlaylistAddDuplicateAction.deleteAndCreateNewPlaylist,
          );
        } catch (_) {}
      }

      if (_pathsM3ULookup.isEmpty) {
        _pathsM3ULookup = infoMap;
      } else {
        _pathsM3ULookup.addAll(infoMap);
      }

      return paths.length;
    } catch (_) {}
    return null;
  }

  /// saves each track m3u info for writing back
  var _pathsM3ULookup = <String, String?>{}; // {trackPath: EXTINFO}

  static Map _parseM3UPlaylistFiles(Map params) {
    final paths = params['paths'] as Set<String>;
    final allTracksPaths = params['libraryTracks'] as List<Track>; // used as a fallback lookup
    final backupDirPath = params['backupDirPath'] as String; // used as a backup for newly found m3u files.

    bool pathExists(String path) => File(path).existsSync();

    final pathSep = Platform.pathSeparator;

    final all = <String, (String, List<Track>)>{};
    final infoMap = <String, String?>{};
    for (final path in paths) {
      final file = File(path);
      final filename = file.path.getFilenameWOExt;
      final fileParentDirectory = file.path.getDirectoryPath;
      final fullTracks = <Track>[];
      String? latestInfo;
      for (String line in file.readAsLinesSync()) {
        if (line.startsWith("#")) {
          latestInfo = line;
        } else if (line.isNotEmpty) {
          if (line.startsWith('primary/')) {
            line = line.replaceFirst('primary/', '');
          }

          String fullPath = line; // maybe is absolute path
          bool fileExists = false;

          if (pathExists(fullPath)) fileExists = true;

          if (!fileExists) {
            fullPath = p.relative(p.join(fileParentDirectory, p.normalize(line))); // maybe was relative
            if (pathExists(fullPath)) fileExists = true;
          }

          if (!fileExists) {
            final maybeTrack = allTracksPaths.firstWhereEff((e) => e.path.endsWith(line)); // no idea, trying to get from library
            if (maybeTrack != null) {
              fullPath = maybeTrack.path;
              // if (pathExists(fullPath)) fileExists = true; // no further checks
            }
          }
          final fullPathFinal = fullPath.startsWith(pathSep) ? fullPath : '$pathSep$fullPath';
          fullTracks.add(Track.orVideo(fullPathFinal));
          infoMap[fullPathFinal] = latestInfo;
        }
      }
      if (all[filename] == null) {
        all[filename] = (path, fullTracks);
      } else {
        // -- filename already exists
        all[file.path.formatPath()] = (path, fullTracks);
      }

      latestInfo = null; // resetting info between each file looping
    }
    // -- copying newly found m3u files as a backup
    for (final m3u in all.entries) {
      final backupFile = File("$backupDirPath${m3u.key}.m3u");
      if (!backupFile.existsSync()) {
        File(m3u.value.$1).copySync(backupFile.path);
      }
    }
    return {
      'paths': all,
      'infoMap': infoMap,
    };
  }

  static Future<void> _saveM3UPlaylistToFile(Map params) async {
    final path = params['path'] as String;
    final tracks = params['tracks'] as List<TrackWithDate>;
    final infoMap = params['infoMap'] as Map<String, String?>;
    final relative = params['relative'] as bool? ?? true;

    final file = File(path);
    file.deleteIfExistsSync();
    file.createSync(recursive: true);
    final sink = file.openWrite(mode: FileMode.append);
    sink.write('#EXTM3U\n');
    for (int i = 0; i < tracks.length; i++) {
      var trwd = tracks[i];
      final tr = trwd.track;
      final trext = tr.track.toTrackExt();
      final infoLine = infoMap[tr.path] ?? '#EXTINF:${trext.durationMS / 1000},${trext.originalArtist} - ${trext.title}';
      final pathLine = relative ? tr.path.replaceFirst(path.getDirectoryPath, '') : tr.path;
      sink.write("$infoLine\n$pathLine\n");
    }

    await sink.flush();
    await sink.close();
  }

  Future<bool> _requestM3USyncPermission() async {
    if (settings.enableM3USync.value) return true;

    final didRead = false.obs;

    await NamidaNavigator.inst.navigateDialog(
      onDisposing: () {
        didRead.close();
      },
      dialog: CustomBlurryDialog(
        actions: [
          const CancelButton(),
          const SizedBox(width: 8.0),
          ObxO(
            rx: didRead,
            builder: (context, didRead) => NamidaButton(
              enabled: didRead,
              text: lang.CONFIRM,
              onPressed: () {
                settings.save(enableM3USync: true);
                NamidaNavigator.inst.closeDialog();
              },
            ),
          )
        ],
        title: lang.NOTE,
        child: Column(
          children: [
            Text(
              '${lang.ENABLE_M3U_SYNC}?\n\n${lang.ENABLE_M3U_SYNC_NOTE_1}\n\n${lang.ENABLE_M3U_SYNC_NOTE_2.replaceFirst('_PLAYLISTS_BACKUP_PATH_', AppDirs.M3UBackup)}\n\n${lang.WARNING.toUpperCase()}: ${lang.ENABLE_M3U_SYNC_SUBTITLE}',
              style: namida.textTheme.displayMedium,
            ),
            const SizedBox(height: 12.0),
            ListTileWithCheckMark(
              activeRx: didRead,
              icon: Broken.info_circle,
              title: lang.I_READ_AND_AGREE,
              onTap: didRead.toggle,
            ),
          ],
        ),
      ),
    );
    return settings.enableM3USync.value;
  }

  Timer? writeTimer;

  @override
  FutureOr<void> onPlaylistTracksChanged(LocalPlaylist playlist) async {
    final m3uPath = playlist.m3uPath;
    if (m3uPath != null && await File(m3uPath).exists()) {
      final didAgree = await _requestM3USyncPermission();

      if (didAgree) {
        // -- using IOSink sometimes produces errors when succesively opened/closed
        // -- not ideal for cases where u constantly add/remove tracks
        // -- so we save with only 2 seconds limit.
        writeTimer?.cancel();
        writeTimer = null;
        writeTimer = Timer(const Duration(seconds: 2), () async {
          await _saveM3UPlaylistToFile.thready({
            'path': m3uPath,
            'tracks': playlist.tracks,
            'infoMap': _pathsM3ULookup,
          });
        });
      }
    }
  }

  @override
  FutureOr<bool> canSavePlaylist(LocalPlaylist playlist) {
    final m3uPath = playlist.m3uPath;
    return m3uPath == null || m3uPath.isEmpty; // dont save m3u-based playlists;
  }

  @override
  void sortPlaylists() => SearchSortController.inst.sortMedia(MediaType.playlist);

  @override
  String get playlistsDirectory => AppDirs.PLAYLISTS;

  @override
  String get favouritePlaylistPath => AppPaths.FAVOURITES_PLAYLIST;

  @override
  String get EMPTY_NAME => lang.PLEASE_ENTER_A_NAME;

  @override
  String get NAME_CONTAINS_BAD_CHARACTER => lang.NAME_CONTAINS_BAD_CHARACTER;

  @override
  String get SAME_NAME_EXISTS => lang.PLEASE_ENTER_A_DIFFERENT_NAME;

  @override
  String get NAME_IS_NOT_ALLOWED => lang.PLEASE_ENTER_A_DIFFERENT_NAME;

  @override
  String get PLAYLIST_NAME_FAV => k_PLAYLIST_NAME_FAV;

  @override
  String get PLAYLIST_NAME_HISTORY => k_PLAYLIST_NAME_HISTORY;

  @override
  String get PLAYLIST_NAME_MOST_PLAYED => k_PLAYLIST_NAME_MOST_PLAYED;

  @override
  Map<String, dynamic> itemToJson(TrackWithDate item) => item.toJson();

  @override
  bool canRemovePlaylist(GeneralPlaylist<TrackWithDate> playlist) {
    _popPageIfCurrent(() => playlist.name);
    return true;
  }

  @override
  void onPlaylistRemovedFromMap(GeneralPlaylist<TrackWithDate> playlist) {
    final plIndex = SearchSortController.inst.playlistSearchList.value.indexWhere((element) => playlist.name == element);
    if (plIndex > -1) SearchSortController.inst.playlistSearchList.removeAt(plIndex);
  }

  /// Navigate back in case the current route is this playlist.
  void _popPageIfCurrent(String Function() playlistName) {
    final lastPage = NamidaNavigator.inst.currentRoute;
    if (lastPage?.route == RouteType.SUBPAGE_playlistTracks) {
      if (lastPage?.name == playlistName()) {
        NamidaNavigator.inst.popPage();
      }
    }
  }

  @override
  Future<Map<String, GeneralPlaylist<TrackWithDate>>> prepareAllPlaylistsFunction() async {
    return await _readPlaylistFilesCompute.thready(playlistsDirectory);
  }

  @override
  GeneralPlaylist<TrackWithDate>? prepareFavouritePlaylistFunction() {
    return _prepareFavouritesFile(favouritePlaylistPath);
  }

  static LocalPlaylist? _prepareFavouritesFile(String path) {
    try {
      final response = File(path).readAsJsonSync();
      return LocalPlaylist.fromJson(response, TrackWithDate.fromJson);
    } catch (_) {}
    return null;
  }

  static Future<Map<String, LocalPlaylist>> _readPlaylistFilesCompute(String path) async {
    final map = <String, LocalPlaylist>{};
    final files = Directory(path).listSyncSafe();
    final filesL = files.length;
    for (int i = 0; i < filesL; i++) {
      var f = files[i];
      if (f is File) {
        try {
          final response = f.readAsJsonSync();
          final pl = LocalPlaylist.fromJson(response, TrackWithDate.fromJson);
          map[pl.name] = pl;
        } catch (_) {}
      }
    }
    return map;
  }
}
