import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:namida/class/track.dart';
import 'package:namida/class/video.dart';
import 'package:namida/controller/history_controller.dart';
import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/controller/notification_controller.dart';
import 'package:namida/core/constants.dart';
import 'package:namida/core/enums.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/translations/language.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';

class JsonToHistoryParser {
  static JsonToHistoryParser get inst => _instance;
  static final JsonToHistoryParser _instance = JsonToHistoryParser._internal();
  JsonToHistoryParser._internal();

  final RxInt parsedHistoryJson = 0.obs;
  final RxInt totalJsonToParse = 0.obs;
  final RxInt addedHistoryJsonToPlaylist = 0.obs;
  final RxBool isParsing = false.obs;
  final RxBool isLoadingFile = false.obs;
  final RxInt _updatingYoutubeStatsDirectoryProgress = 0.obs;
  final RxInt _updatingYoutubeStatsDirectoryTotal = 0.obs;
  final Rx<TrackSource> currentParsingSource = TrackSource.local.obs;
  final _currentOldestDate = Rxn<DateTime>();
  final _currentNewestDate = Rxn<DateTime>();

  String get parsedProgress => '${parsedHistoryJson.value.formatDecimal()} / ${totalJsonToParse.value.formatDecimal()}';
  String get parsedProgressPercentage => '${(_percentage * 100).round()}%';
  String get addedHistoryJson => addedHistoryJsonToPlaylist.value.formatDecimal();
  double get _percentage {
    final p = parsedHistoryJson.value / totalJsonToParse.value;
    return p.isFinite ? p : 0;
  }

  bool _isShowingParsingMenu = false;

  void _hideParsingDialog() => _isShowingParsingMenu = false;

  void showParsingProgressDialog() {
    if (_isShowingParsingMenu) return;
    Widget getTextWidget(String text, {TextStyle? style}) {
      return Text(text, style: style ?? Get.textTheme.displayMedium);
    }

    _isShowingParsingMenu = true;
    final dateText = _currentNewestDate.value != null
        ? "(${_currentOldestDate.value!.millisecondsSinceEpoch.dateFormattedOriginal} → ${_currentNewestDate.value!.millisecondsSinceEpoch.dateFormattedOriginal})"
        : '';

    NamidaNavigator.inst.navigateDialog(
      onDismissing: _hideParsingDialog,
      dialog: CustomBlurryDialog(
        normalTitleStyle: true,
        titleWidgetInPadding: Obx(
          () {
            final title = '${isParsing.value ? Language.inst.EXTRACTING_INFO : Language.inst.DONE} ($parsedProgressPercentage)';
            return Text(
              "$title ${isParsing.value ? '' : ' ✓'}",
              style: Get.textTheme.displayLarge,
            );
          },
        ),
        actions: [
          TextButton(
            child: Text(Language.inst.CONFIRM),
            onPressed: () {
              _hideParsingDialog();
              NamidaNavigator.inst.closeDialog();
            },
          )
        ],
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Obx(() => getTextWidget('${Language.inst.LOADING_FILE}... ${isLoadingFile.value ? '' : Language.inst.DONE}')),
              const SizedBox(height: 10.0),
              Obx(() => getTextWidget('$parsedProgress ${Language.inst.PARSED}')),
              const SizedBox(height: 10.0),
              Obx(() => getTextWidget('$addedHistoryJson ${Language.inst.ADDED}')),
              const SizedBox(height: 4.0),
              if (dateText != '') ...[
                getTextWidget(dateText, style: Get.textTheme.displaySmall),
                const SizedBox(height: 4.0),
              ],
              const SizedBox(height: 4.0),
              Obx(() {
                final shouldShow = currentParsingSource.value == TrackSource.youtube || currentParsingSource.value == TrackSource.youtubeMusic;
                return shouldShow
                    ? getTextWidget('${Language.inst.STATS}: ${_updatingYoutubeStatsDirectoryProgress.value}/${_updatingYoutubeStatsDirectoryTotal.value}')
                    : const SizedBox();
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _resetValues() {
    totalJsonToParse.value = 0;
    parsedHistoryJson.value = 0;
    addedHistoryJsonToPlaylist.value = 0;
    _updatingYoutubeStatsDirectoryProgress.value = 0;
    _updatingYoutubeStatsDirectoryTotal.value = 0;
    _currentOldestDate.value = null;
    _currentNewestDate.value = null;
  }

  Timer? _notificationTimer;

  Future<void> addFileSourceToNamidaHistory(
    File file,
    TrackSource source, {
    bool matchAll = false,
    bool isMatchingTypeLink = true,
    bool matchYT = true,
    bool matchYTMusic = true,
    DateTime? oldestDate,
    DateTime? newestDate,
  }) async {
    _resetValues();
    isParsing.value = true;
    isLoadingFile.value = true;
    _currentOldestDate.value = oldestDate;
    _currentNewestDate.value = newestDate;
    showParsingProgressDialog();

    // TODO: warning to backup history

    final isytsource = source == TrackSource.youtube || source == TrackSource.youtubeMusic;

    // -- Removing previous source tracks.
    if (isytsource) {
      HistoryController.inst.removeSourcesTracksFromHistory(
        [TrackSource.youtube, TrackSource.youtubeMusic],
        oldestDate: oldestDate,
        newestDate: newestDate,
        andSave: false,
      );
    } else {
      HistoryController.inst.removeSourcesTracksFromHistory(
        [source],
        oldestDate: oldestDate,
        newestDate: newestDate,
        andSave: false,
      );
    }

    await Future.delayed(Duration.zero);
    _notificationTimer?.cancel();
    _notificationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      NotificationService.inst.importHistoryNotification(parsedHistoryJson.value, totalJsonToParse.value);
    });

    final datesAdded = <int>[];

    if (isytsource) {
      currentParsingSource.value = TrackSource.youtube;
      final res = await _parseYTHistoryJsonAndAdd(
        file: file,
        isMatchingTypeLink: isMatchingTypeLink,
        matchYT: matchYT,
        matchYTMusic: matchYTMusic,
        oldestDate: oldestDate,
        newestDate: newestDate,
        matchAll: matchAll,
      );
      datesAdded.addAll(res);
      // await _addYoutubeSourceFromDirectory(isMatchingTypeLink, matchYT, matchYTMusic);
    }
    if (source == TrackSource.lastfm) {
      currentParsingSource.value = TrackSource.lastfm;
      final res = await _addLastFmSource(
        file: file,
        matchAll: matchAll,
        oldestDate: oldestDate,
        newestDate: newestDate,
      );
      datesAdded.addAll(res);
    }
    isParsing.value = false;
    HistoryController.inst.sortHistoryTracks(datesAdded);
    await HistoryController.inst.saveHistoryToStorage(datesAdded);
    HistoryController.inst.updateMostPlayedPlaylist();
    _notificationTimer?.cancel();
    NotificationService.inst.doneImportingHistoryNotification(parsedHistoryJson.value, addedHistoryJsonToPlaylist.value);
  }

  /// Returns a map of {`trackYTID`: `List<Track>`}
  Map<String, List<Track>> _getTrackIDsMap() {
    final map = <String, List<Track>>{};
    allTracksInLibrary.loop((t, index) {
      map.addForce(t.youtubeID, t);
    });
    return map;
  }

  /// Returns [daysToSave] to be used by [sortHistoryTracks] && [saveHistoryToStorage].
  Future<List<int>> _parseYTHistoryJsonAndAdd({
    required File file,
    required bool isMatchingTypeLink,
    required bool matchYT,
    required bool matchYTMusic,
    required DateTime? oldestDate,
    required DateTime? newestDate,
    required bool matchAll,
  }) async {
    isParsing.value = true;
    await Future.delayed(const Duration(milliseconds: 300));

    Map<String, List<Track>>? tracksIdsMap;
    if (isMatchingTypeLink) tracksIdsMap = _getTrackIDsMap();

    final datesToSave = <int>[];
    final jsonResponse = await file.readAsJson() as List?;

    totalJsonToParse.value = jsonResponse?.length ?? 0;
    isLoadingFile.value = false;
    if (jsonResponse != null) {
      final mapOfAffectedIds = <String, YoutubeVideoHistory>{};
      for (int i = 0; i <= jsonResponse.length - 1; i++) {
        try {
          final p = jsonResponse[i];
          final link = utf8.decode((p['titleUrl']).toString().codeUnits);
          final id = link.length >= 11 ? link.substring(link.length - 11) : link;
          final z = List<Map<String, dynamic>>.from((p['subtitles'] ?? []));

          /// matching in real time, each object.
          await Future.delayed(Duration.zero);
          final yth = YoutubeVideoHistory(
            id: id,
            title: (p['title'] as String).replaceFirst('Watched ', ''),
            channel: z.isNotEmpty ? z.first['name'] : '',
            channelUrl: z.isNotEmpty ? utf8.decode((z.first['url']).toString().codeUnits) : '',
            watches: [
              YTWatch(
                date: DateTime.parse(p['time'] ?? 0).millisecondsSinceEpoch,
                isYTMusic: p['header'] == "YouTube Music",
              )
            ],
          );
          // -- updating affected ids map, used to update youtube stats
          if (mapOfAffectedIds[id] != null) {
            mapOfAffectedIds[id]!.watches.addAllNoDuplicates(yth.watches.map((e) => YTWatch(date: e.date, isYTMusic: e.isYTMusic)));
          } else {
            mapOfAffectedIds[id] = yth;
          }
          // ---------------------------------------------------------
          final addedDates = _matchYTVHToNamidaHistory(
            vh: yth,
            matchYT: matchYT,
            matchYTMusic: matchYTMusic,
            oldestDate: oldestDate,
            newestDate: newestDate,
            matchAll: matchAll,
            tracksIdsMap: tracksIdsMap,
          );
          datesToSave.addAll(addedDates);

          parsedHistoryJson.value++;
        } catch (e) {
          printy(e, isError: true);
          continue;
        }
      }
      _updatingYoutubeStatsDirectoryTotal.value = mapOfAffectedIds.length;
      await _updateYoutubeStatsDirectory(
        affectedIds: mapOfAffectedIds,
        onProgress: (updatedIds) {
          _updatingYoutubeStatsDirectoryProgress.value += updatedIds.length;
          printy('updatedIds: ${updatedIds.length}');
        },
      );
    }

    isParsing.value = false;
    return datesToSave;
  }

  /// Returns [daysToSave].
  List<int> _matchYTVHToNamidaHistory({
    required YoutubeVideoHistory vh,
    required bool matchYT,
    required bool matchYTMusic,
    required DateTime? oldestDate,
    required DateTime? newestDate,
    required bool matchAll,
    required Map<String, List<Track>>? tracksIdsMap,
  }) {
    final oldestDay = oldestDate?.millisecondsSinceEpoch.toDaysSinceEpoch();
    final newestDay = newestDate?.millisecondsSinceEpoch.toDaysSinceEpoch();
    late Iterable<Track> tracks;
    if (tracksIdsMap != null) {
      final match = tracksIdsMap[vh.id] ?? [];
      if (match.isNotEmpty) {
        tracks = matchAll ? match : [match.first];
      } else {
        tracks = [];
      }
    } else {
      tracks = allTracksInLibrary.firstWhereOrWhere(matchAll, (trPre) {
        final element = trPre.toTrackExt();

        /// matching has to meet 2 conditons:
        /// 1. [json title] contains [track.title]
        /// 2. - [json title] contains [track.artistsList.first]
        ///     or
        ///    - [json channel] contains [track.album]
        ///    (useful for nightcore channels, album has to be the channel name)
        ///     or
        ///    - [json channel] contains [track.artistsList.first]
        return vh.title.cleanUpForComparison.contains(element.title.cleanUpForComparison) &&
            (vh.title.cleanUpForComparison.contains(element.artistsList.first.cleanUpForComparison) ||
                vh.channel.cleanUpForComparison.contains(element.album.cleanUpForComparison) ||
                vh.channel.cleanUpForComparison.contains(element.artistsList.first.cleanUpForComparison));
      });
    }

    final tracksToAdd = <TrackWithDate>[];
    if (tracks.isNotEmpty) {
      for (int i = 0; i < vh.watches.length; i++) {
        final d = vh.watches[i];

        // ---- sussy checks ----

        // -- if the watch day is outside range specified
        if (oldestDay != null && newestDay != null) {
          final watchAsDSE = d.date.toDaysSinceEpoch();
          if (watchAsDSE < oldestDay || watchAsDSE > newestDay) continue;
        }

        // -- if the type is youtube music, but the user dont want ytm.
        if (d.isYTMusic && !matchYTMusic) continue;

        // -- if the type is youtube, but the user dont want yt.
        if (!d.isYTMusic && !matchYT) continue;

        tracksToAdd.addAll(
          tracks.map((tr) => TrackWithDate(
                dateAdded: d.date,
                track: tr,
                source: d.isYTMusic ? TrackSource.youtubeMusic : TrackSource.youtube,
              )),
        );

        addedHistoryJsonToPlaylist.value += tracks.length;
      }
    }
    final daysToSave = HistoryController.inst.addTracksToHistoryOnly(tracksToAdd);
    return daysToSave;
  }

  /// Returns [daysToSave] to be used by [sortHistoryTracks] && [saveHistoryToStorage].
  Future<List<int>> _addLastFmSource({
    required File file,
    required bool matchAll,
    required DateTime? oldestDate,
    required DateTime? newestDate,
  }) async {
    final oldestDay = oldestDate?.millisecondsSinceEpoch.toDaysSinceEpoch();
    final newestDay = newestDate?.millisecondsSinceEpoch.toDaysSinceEpoch();

    totalJsonToParse.value = file.readAsLinesSync().length;
    isLoadingFile.value = false;

    final stream = file.openRead();
    final lines = stream.transform(utf8.decoder).transform(const LineSplitter());

    final totalDaysToSave = <int>[];
    final tracksToAdd = <TrackWithDate>[];

    // used for cases where date couldnt be parsed, so it uses this one as a reference
    int? lastDate;
    await for (final line in lines) {
      parsedHistoryJson.value++;

      /// updates history every 10 tracks
      if (tracksToAdd.length == 10) {
        totalDaysToSave.addAll(HistoryController.inst.addTracksToHistoryOnly(tracksToAdd));
        tracksToAdd.clear();
      }

      // pls forgive me
      await Future.delayed(Duration.zero);

      /// artist, album, title, (dd MMM yyyy HH:mm);
      try {
        final pieces = line.split(',');

        // success means: date == trueDate && lastDate is updated.
        // failure means: date == lastDate - 30 seconds || date == 0
        // this is used for cases where date couldn't be parsed, so it'll add the track with (date == lastDate - 30 seconds)
        int date = 0;
        try {
          date = DateFormat('dd MMM yyyy HH:mm').parseLoose(pieces.last).millisecondsSinceEpoch;
        } catch (e) {
          if (lastDate != null) {
            date = lastDate - 30000;
          }
        }
        lastDate = date;

        // -- skips if the date is not inside date range specified.
        if (oldestDay != null && newestDay != null) {
          final watchAsDSE = date.toDaysSinceEpoch();
          if (watchAsDSE < oldestDay || watchAsDSE > newestDay) continue;
        }

        /// matching has to meet 2 conditons:
        /// [csv artist] contains [track.artistsList.first]
        /// [csv title] contains [track.title], anything after ( or [ is ignored.
        final tracks = allTracksInLibrary.firstWhereOrWhere(
          matchAll,
          (trPre) {
            final track = trPre.toTrackExt();
            final matchingArtist = track.artistsList.isNotEmpty && pieces[0].cleanUpForComparison.contains(track.artistsList.first.cleanUpForComparison);
            final matchingTitle = pieces[2].cleanUpForComparison.contains(track.title.split('(').first.split('[').first.cleanUpForComparison);
            return matchingArtist && matchingTitle;
          },
        );
        tracksToAdd.addAll(
          tracks.map((tr) => TrackWithDate(
                dateAdded: date,
                track: tr,
                source: TrackSource.lastfm,
              )),
        );
        addedHistoryJsonToPlaylist.value += tracks.length;
      } catch (e) {
        printy(e, isError: true);
        continue;
      }
    }
    // normally the loop automatically adds every 10 tracks, this one is to ensure adding any tracks left.
    totalDaysToSave.addAll(HistoryController.inst.addTracksToHistoryOnly(tracksToAdd));

    return totalDaysToSave;
  }

  Future<void> _updateYoutubeStatsDirectory({required Map<String, YoutubeVideoHistory> affectedIds, required void Function(List<String> updatedIds) onProgress}) async {
    // ===== Getting affected files (which are arranged by id[0])
    final fileIdentifierMap = <String, Map<String, YoutubeVideoHistory>>{}; // {id[0]: {id: YoutubeVideoHistory}}
    for (final entry in affectedIds.entries) {
      final id = entry.key;
      final video = entry.value;
      final filename = id[0];
      if (fileIdentifierMap[filename] == null) {
        fileIdentifierMap[filename] = {id: video};
      } else {
        fileIdentifierMap[filename]!.addAll({id: video});
      }
    }
    // ==================================================

    // ===== looping each file and getting all videos inside
    // then mapping all to a map for instant lookup
    // then merging affected videos inside [fileIdentifierMap]
    for (final entry in fileIdentifierMap.entries) {
      final filename = entry.key; // id[0]
      final videos = entry.value; // {id: YoutubeVideoHistory}

      final file = File('$k_DIR_YOUTUBE_STATS$filename.json');
      final res = await file.readAsJson();
      final videosInStorage = (res as List?)?.map((e) => YoutubeVideoHistory.fromJson(e)) ?? [];
      final videosMapInStorage = <String, YoutubeVideoHistory>{};
      for (final videoStor in videosInStorage) {
        videosMapInStorage[videoStor.id] = videoStor;
      }

      // ===========
      final updatedIds = <String>[];
      for (final affectedv in videos.entries) {
        final id = affectedv.key;
        final video = affectedv.value;
        if (videosMapInStorage[id] != null) {
          // -- video exists inside the file, so we add only new watches
          videosMapInStorage[id]!.watches.addAllNoDuplicates(video.watches.map((e) => YTWatch(date: e.date, isYTMusic: e.isYTMusic)));
        } else {
          // -- video does NOT exist, so the whole video is added with all its watches.
          videosMapInStorage[id] = video;
        }
        updatedIds.add(id);
      }
      await file.writeAsJson(videosMapInStorage.values.toList());
      onProgress(updatedIds);
    }
  }
}

extension _FWORWHERE<E> on List<E> {
  Iterable<E> firstWhereOrWhere(bool matchAll, bool Function(E e) test) {
    if (matchAll) {
      return where(test);
    } else {
      final item = firstWhereEff(test);
      if (item != null) {
        return [item];
      } else {
        return [];
      }
    }
  }
}
