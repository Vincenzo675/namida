import 'package:flutter/material.dart';

import 'package:jiffy/jiffy.dart';
import 'package:playlist_manager/module/playlist_id.dart';

import 'package:namida/class/route.dart';
import 'package:namida/controller/file_browser.dart';
import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/controller/settings_controller.dart';
import 'package:namida/core/constants.dart';
import 'package:namida/core/dimensions.dart';
import 'package:namida/core/enums.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/namida_converter_ext.dart';
import 'package:namida/core/translations/language.dart';
import 'package:namida/core/utils.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';
import 'package:namida/youtube/class/youtube_id.dart';
import 'package:namida/youtube/controller/youtube_history_controller.dart';
import 'package:namida/youtube/controller/youtube_import_controller.dart';
import 'package:namida/youtube/controller/youtube_playlist_controller.dart';
import 'package:namida/youtube/pages/yt_history_page.dart';
import 'package:namida/youtube/pages/yt_playlist_subpage.dart';
import 'package:namida/youtube/widgets/yt_card.dart';
import 'package:namida/youtube/widgets/yt_history_video_card.dart';
import 'package:namida/youtube/widgets/yt_thumbnail.dart';
import 'package:namida/youtube/yt_utils.dart';

class YoutubePlaylistsView extends StatelessWidget with NamidaRouteWidget {
  @override
  RouteType get route => RouteType.YOUTUBE_PLAYLISTS;

  final Iterable<String> idsToAdd;
  final bool displayMenu;
  final bool? minimalView;

  const YoutubePlaylistsView({
    super.key,
    this.idsToAdd = const <String>[],
    this.displayMenu = true,
    this.minimalView,
  });

  Iterable<YoutubeID> getHistoryVideos(Map<int, List<YoutubeID>> map) {
    final videos = <String, YoutubeID>{};
    for (final trs in map.values) {
      trs.loop((e) {
        videos[e.id] ??= e;
      });
      if (videos.length >= 50) break;
    }
    return videos.values;
  }

  List<YoutubeID> getFavouriteVideos(YoutubePlaylist playlist) {
    final videos = <YoutubeID>[];
    final all = playlist.tracks;
    for (int i = all.length - 1; i >= 0; i--) {
      videos.add(all[i]);
      if (videos.length >= 50) break;
    }

    return videos;
  }

  List<NamidaPopupItem> getMenuItems(BuildContext context, YoutubePlaylist playlist) {
    return YTUtils.getVideosMenuItems(
      context: context,
      videos: playlist.tracks,
      playlistName: '',
      playlistToRemove: playlist,
    );
  }

  void _onAddToPlaylist({required YoutubePlaylist playlist, required bool? idsExist}) {
    if (idsExist == true) {
      final indexes = <int>[];
      playlist.tracks.loopAdv((e, index) {
        if (idsToAdd.contains(e.id)) {
          indexes.add(index);
        }
      });
      NamidaNavigator.inst.navigateDialog(
        dialog: CustomBlurryDialog(
          isWarning: true,
          normalTitleStyle: true,
          bodyText: "${lang.REMOVE_FROM_PLAYLIST} ${playlist.name.addDQuotation()}?",
          actions: [
            const CancelButton(),
            const SizedBox(width: 6.0),
            NamidaButton(
              text: lang.REMOVE.toUpperCase(),
              onPressed: () {
                NamidaNavigator.inst.closeDialog();
                YoutubePlaylistController.inst.removeTracksFromPlaylist(playlist, indexes);
              },
            )
          ],
        ),
      );
    } else {
      YoutubePlaylistController.inst.addTracksToPlaylist(playlist, idsToAdd);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMinimalView = minimalView ?? idsToAdd.isNotEmpty;

    const playlistsItemExtent = Dimensions.youtubeCardItemExtent * 0.9;
    const playlistThumbnailHeight = playlistsItemExtent - Dimensions.tileBottomMargin - (Dimensions.youtubeCardItemVerticalPadding * 2);
    const playlistThumbnailWidth = playlistThumbnailHeight * 16 / 9;

    return NamidaScrollbarWithController(
      child: (sc) => CustomScrollView(
        controller: sc,
        slivers: [
          const SliverPadding(padding: EdgeInsets.only(bottom: 12.0)),
          if (!isMinimalView) ...[
            Obx(
              (context) {
                final history = YoutubeHistoryController.inst.historyMap.valueR;
                final length = YoutubeHistoryController.inst.totalHistoryItemsCount.valueR;
                final lengthDummy = length == -1;
                return _HorizontalSliverList(
                  title: lang.HISTORY,
                  icon: Broken.refresh,
                  viewAllPage: () => const YoutubeHistoryPage(),
                  videos: getHistoryVideos(history),
                  playlistName: k_PLAYLIST_NAME_HISTORY,
                  playlistID: k_PLAYLIST_NAME_HISTORY,
                  displayTimeAgo: true,
                  totalVideosCountInMainList: lengthDummy ? 0 : length,
                  displayShimmer: lengthDummy,
                );
              },
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 8.0)),
            ObxO(
              rx: YoutubeHistoryController.inst.totalHistoryItemsCount,
              builder: (context, totalLength) => ObxO(
                rx: YoutubeHistoryController.inst.currentMostPlayedTimeRange,
                builder: (context, currentMostPlayedTimeRange) => ObxO(
                  rx: YoutubeHistoryController.inst.currentTopTracksMapListensReactive(currentMostPlayedTimeRange),
                  builder: (context, listensMap) {
                    final videos = listensMap.keys
                        .map((e) => YoutubeID(
                              id: e,
                              playlistID: const PlaylistID(id: k_PLAYLIST_NAME_MOST_PLAYED),
                            ))
                        .toList();
                    return _HorizontalSliverList(
                      title: lang.MOST_PLAYED,
                      icon: Broken.crown_1,
                      viewAllPage: () => const YTMostPlayedVideosPage(),
                      padding: const EdgeInsets.only(top: 8.0),
                      videos: videos,
                      subHeader: YTMostPlayedVideosPage.getChipRow(context),
                      playlistName: '',
                      playlistID: k_PLAYLIST_NAME_MOST_PLAYED,
                      totalVideosCountInMainList: videos.length,
                      displayShimmer: totalLength == -1,
                      listensMap: listensMap,
                    );
                  },
                ),
              ),
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 8.0)),
            ObxOClass(
              rx: YoutubePlaylistController.inst.favouritesPlaylist,
              builder: (context, favs) {
                return _HorizontalSliverList(
                  title: lang.FAVOURITES,
                  icon: Broken.heart_circle,
                  viewAllPage: () => const YTLikedVideosPage(),
                  videos: getFavouriteVideos(favs.value),
                  playlistName: k_PLAYLIST_NAME_FAV,
                  playlistID: k_PLAYLIST_NAME_FAV,
                  displayTimeAgo: false,
                  totalVideosCountInMainList: favs.value.tracks.length,
                );
              },
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 8.0)),
          ],
          const SliverPadding(padding: EdgeInsets.only(bottom: 12.0)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
              child: Row(
                children: [
                  Expanded(
                    child: Obx(
                      (context) => SearchPageTitleRow(
                        title: "${lang.PLAYLISTS} - ${YoutubePlaylistController.inst.playlistsMap.length}",
                        icon: Broken.music_library_2,
                        trailing: const SizedBox(),
                        subtitleWidget: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            NamidaPopupWrapper(
                              useRootNavigator: true,
                              children: () => [
                                Column(
                                  children: [
                                    ListTileWithCheckMark(
                                      activeRx: settings.ytPlaylistSortReversed,
                                      onTap: () => YoutubePlaylistController.inst.sortYTPlaylists(reverse: !settings.ytPlaylistSortReversed.value),
                                    ),
                                    ...[
                                      GroupSortType.title,
                                      GroupSortType.creationDate,
                                      GroupSortType.modifiedDate,
                                      GroupSortType.numberOfTracks,
                                      GroupSortType.shuffle,
                                    ].map(
                                      (e) => ObxO(
                                        rx: settings.ytPlaylistSort,
                                        builder: (context, ytPlaylistSort) => SmallListTile(
                                          title: e.toText(),
                                          active: ytPlaylistSort == e,
                                          onTap: () => YoutubePlaylistController.inst.sortYTPlaylists(sortBy: e),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              child: ObxO(
                                rx: settings.ytPlaylistSort,
                                builder: (context, ytPlaylistSort) => Text(
                                  ytPlaylistSort.toText(),
                                  style: context.textTheme.displaySmall?.copyWith(
                                    color: context.theme.colorScheme.secondary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4.0),
                            NamidaInkWell(
                              onTap: () => YoutubePlaylistController.inst.sortYTPlaylists(reverse: !settings.ytPlaylistSortReversed.value),
                              child: ObxO(
                                rx: settings.ytPlaylistSortReversed,
                                builder: (context, ytPlaylistSortReversed) => Icon(
                                  ytPlaylistSortReversed ? Broken.arrow_up_3 : Broken.arrow_down_2,
                                  size: 16.0,
                                  color: context.theme.colorScheme.secondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4.0),
                  ObxO(
                    rx: YoutubeImportController.inst.isImportingPlaylists,
                    builder: (context, isImportingPlaylists) => NamidaInkWellButton(
                      icon: Broken.add_circle,
                      text: lang.IMPORT,
                      enabled: !isImportingPlaylists,
                      onTap: () {
                        NamidaNavigator.inst.navigateDialog(
                          dialog: CustomBlurryDialog(
                            title: lang.NOTE,
                            normalTitleStyle: true,
                            bodyText:
                                'Importing takeout playlists works by picking a single playlists directory, or a main directory that contains multiple takeouts, in that case playlists will be merged and video-sorted by date added',
                            actions: [
                              NamidaButton(
                                onPressed: () async {
                                  NamidaNavigator.inst.closeDialog();

                                  final dirPath = await NamidaFileBrowser.getDirectory(note: 'choose playlist directory from a google takeout');
                                  if (dirPath == null) return;

                                  final details = await YoutubeImportController.inst.importPlaylists(dirPath);
                                  if (details == null) {
                                    snackyy(
                                      icon: Broken.forbidden,
                                      message: "Operation Canceled",
                                    );
                                    return;
                                  }
                                  if (details.totalCount <= 0) {
                                    snackyy(
                                      icon: Broken.danger,
                                      message: "Failed to import\nPlease choose a valid playlists directory taken from google takeout",
                                      isError: true,
                                    );
                                    return;
                                  }

                                  final importedSucessText = lang.IMPORTED_N_PLAYLISTS_SUCCESSFULLY.replaceFirst('_NUM_', '${details.countAfterMerging}');
                                  final detailsText = 'Total Count: ${details.totalCount} | Merged Count: ${details.mergedCount} | Final Count: ${details.countAfterMerging}';
                                  snackyy(
                                    icon: Broken.copy_success,
                                    message: '$importedSucessText\n$detailsText',
                                    borderColor: Colors.green.withOpacity(0.8),
                                  );
                                },
                                text: lang.PICK_FROM_STORAGE,
                              )
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 4.0),
                ],
              ),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 8.0)),
          if (idsToAdd.isNotEmpty)
            SliverToBoxAdapter(
              child: ObxOClass(
                rx: YoutubePlaylistController.inst.favouritesPlaylist,
                builder: (context, favouritesPlaylist) => YoutubeCard(
                  thumbnailType: ThumbnailType.playlist,
                  isImageImportantInCache: true,
                  extractColor: true,
                  thumbnailWidthPercentage: 0.75,
                  videoId: favouritesPlaylist.value.tracks.firstOrNull?.id,
                  thumbnailUrl: null,
                  shimmerEnabled: false,
                  title: favouritesPlaylist.value.name.translatePlaylistName(),
                  subtitle: favouritesPlaylist.value.creationDate.dateFormattedOriginal,
                  displaythirdLineText: true,
                  thirdLineText: Jiffy.parseFromMillisecondsSinceEpoch(favouritesPlaylist.value.modifiedDate).fromNow(),
                  displayChannelThumbnail: false,
                  channelThumbnailUrl: '',
                  thumbnailHeight: playlistThumbnailHeight,
                  thumbnailWidth: playlistThumbnailWidth,
                  onTap: () {
                    final idsExists = favouritesPlaylist.isSubItemFavourite(idsToAdd.first);
                    _onAddToPlaylist(
                      playlist: favouritesPlaylist.value,
                      idsExist: idsExists,
                    );
                  },
                  smallBoxText: favouritesPlaylist.value.tracks.length.formatDecimal(),
                  smallBoxIcon: Broken.play_cricle,
                  checkmarkStatus: favouritesPlaylist.isSubItemFavourite(idsToAdd.first),
                  menuChildrenDefault: displayMenu ? () => getMenuItems(context, favouritesPlaylist.value) : null,
                ),
              ),
            ),
          if (idsToAdd.isNotEmpty)
            const SliverToBoxAdapter(
              child: NamidaContainerDivider(margin: EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0)),
            ),
          Obx(
            (context) {
              final playlistsMap = YoutubePlaylistController.inst.playlistsMap.valueR;
              final playlistsNames = playlistsMap.keys.toList();
              return SliverFixedExtentList.builder(
                itemExtent: playlistsItemExtent,
                itemCount: playlistsNames.length,
                itemBuilder: (context, index) {
                  final name = playlistsNames[index];
                  final playlist = playlistsMap[name]!;
                  bool? idsExist;
                  if (idsToAdd.isNotEmpty) {
                    final firstId = idsToAdd.firstOrNull;
                    if (firstId != null) idsExist = playlist.tracks.firstWhereEff((e) => e.id == firstId) != null;
                  }

                  return NamidaPopupWrapper(
                    childrenDefault: displayMenu ? () => getMenuItems(context, playlist) : null,
                    openOnTap: false,
                    child: YoutubeCard(
                      thumbnailType: ThumbnailType.playlist,
                      isImageImportantInCache: true,
                      extractColor: true,
                      thumbnailWidthPercentage: 0.75,
                      videoId: playlist.tracks.firstOrNull?.id,
                      thumbnailUrl: null,
                      shimmerEnabled: false,
                      title: playlist.name,
                      subtitle: playlist.creationDate.dateFormattedOriginal,
                      displaythirdLineText: true,
                      thirdLineText: Jiffy.parseFromMillisecondsSinceEpoch(playlist.modifiedDate).fromNow(),
                      displayChannelThumbnail: false,
                      channelThumbnailUrl: '',
                      thumbnailHeight: playlistThumbnailHeight,
                      thumbnailWidth: playlistThumbnailWidth,
                      onTap: () {
                        if (idsToAdd.isNotEmpty) {
                          _onAddToPlaylist(playlist: playlist, idsExist: idsExist);
                        } else {
                          YTNormalPlaylistSubpage(playlistName: playlist.name).navigate();
                        }
                      },
                      smallBoxText: playlist.tracks.length.formatDecimal(),
                      smallBoxIcon: Broken.play_cricle,
                      checkmarkStatus: idsExist,
                      menuChildrenDefault: displayMenu ? () => getMenuItems(context, playlist) : null,
                    ),
                  );
                },
              );
            },
          ),
          if (!isMinimalView) kBottomPaddingWidgetSliver,
        ],
      ),
    );
  }
}

class _HorizontalSliverList extends StatelessWidget {
  final String title;
  final IconData icon;
  final NamidaRouteWidget Function() viewAllPage;
  final Iterable<YoutubeID> videos;
  final String playlistName;
  final String playlistID;
  final int totalVideosCountInMainList;
  final Widget? subHeader;
  final EdgeInsets padding;
  final bool displayTimeAgo;
  final bool displayShimmer;
  final Map<String, List<int>>? listensMap;

  const _HorizontalSliverList({
    required this.title,
    required this.icon,
    required this.viewAllPage,
    required this.videos,
    required this.playlistName,
    required this.playlistID,
    required this.totalVideosCountInMainList,
    this.subHeader,
    this.padding = const EdgeInsets.symmetric(vertical: 8.0),
    this.displayTimeAgo = false,
    this.displayShimmer = false,
    this.listensMap,
  });

  void onTap() => viewAllPage().navigate();

  @override
  Widget build(BuildContext context) {
    final finalVideos = videos is List<YoutubeID> ? videos as List<YoutubeID> : videos.toList();
    final remainingVideosCount = totalVideosCountInMainList - finalVideos.length;

    const thumbHeight = 24.0 * 3.2;
    const thumbWidth = thumbHeight * 16 / 9;

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NamidaInkWell(
            margin: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
            padding: padding,
            onTap: onTap,
            child: Column(
              children: [
                SearchPageTitleRow(
                  title: title,
                  subtitle: totalVideosCountInMainList.displayVideoKeyword,
                  icon: icon,
                  trailing: const Icon(Broken.arrow_right_3),
                  onPressed: onTap,
                ),
                if (subHeader != null) subHeader!,
              ],
            ),
          ),
          SizedBox(
            height: displayTimeAgo ? 132.0 : 124.0,
            child: displayShimmer
                ? ShimmerWrapper(
                    shimmerEnabled: true,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      scrollDirection: Axis.horizontal,
                      itemCount: 10,
                      itemBuilder: (context, index) {
                        return NamidaInkWell(
                          animationDurationMS: 200,
                          margin: const EdgeInsets.symmetric(horizontal: 4.0),
                          width: thumbWidth,
                          bgColor: context.theme.cardColor,
                        );
                      },
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    scrollDirection: Axis.horizontal,
                    itemCount: finalVideos.length + 1,
                    itemBuilder: (context, index) {
                      if (index == finalVideos.length + 1 - 1) {
                        return remainingVideosCount <= 0
                            ? const SizedBox()
                            : NamidaInkWell(
                                onTap: onTap,
                                margin: const EdgeInsets.all(12.0),
                                padding: const EdgeInsets.all(12.0),
                                child: Center(
                                  child: Text(
                                    "+${remainingVideosCount.formatDecimalShort()}",
                                    style: context.textTheme.displayMedium,
                                  ),
                                ),
                              );
                      }
                      return YTHistoryVideoCard(
                        minimalCard: true,
                        videos: finalVideos,
                        index: index,
                        day: null,
                        playlistName: playlistName,
                        playlistID: PlaylistID(id: playlistID),
                        displayTimeAgo: displayTimeAgo,
                        minimalCardWidth: thumbWidth,
                        thumbnailHeight: thumbHeight,
                        overrideListens: listensMap?[finalVideos[index].id] ?? [],
                        canHaveDuplicates: false, // its history but filtered
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
