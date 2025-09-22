import 'dart:async';

import 'package:flutter/material.dart';

import 'package:youtipie/class/stream_info_item/stream_info_item.dart';
import 'package:youtipie/class/youtipie_feed/playlist_basic_info.dart';
import 'package:youtipie/youtipie.dart';

import 'package:namida/class/file_parts.dart';
import 'package:namida/class/route.dart';
import 'package:namida/controller/current_color.dart';
import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/controller/settings_controller.dart';
import 'package:namida/core/constants.dart';
import 'package:namida/core/dimensions.dart';
import 'package:namida/core/enums.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/translations/language.dart';
import 'package:namida/core/utils.dart';
import 'package:namida/main.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';
import 'package:namida/youtube/class/download_task_base.dart';
import 'package:namida/youtube/class/youtube_id.dart';
import 'package:namida/youtube/class/youtube_item_download_config.dart';
import 'package:namida/youtube/controller/youtube_controller.dart';
import 'package:namida/youtube/controller/youtube_info_controller.dart';
import 'package:namida/youtube/functions/download_sheet.dart';
import 'package:namida/youtube/functions/video_download_options.dart';
import 'package:namida/youtube/widgets/yt_thumbnail.dart';
import 'package:namida/youtube/yt_utils.dart';

class YTPlaylistDownloadPage extends StatefulWidget with NamidaRouteWidget {
  @override
  String? get name => playlistName;
  @override
  RouteType get route => RouteType.YOUTUBE_PLAYLIST_DOWNLOAD_SUBPAGE;

  final List<YoutubeID> ids;
  final String playlistName;
  final Map<String, StreamInfoItem> infoLookup;
  final PlaylistBasicInfo? playlistInfo;

  const YTPlaylistDownloadPage({
    super.key,
    required this.ids,
    required this.playlistName,
    required this.infoLookup,
    required this.playlistInfo,
  });

  @override
  State<YTPlaylistDownloadPage> createState() => _YTPlaylistDownloadPageState();
}

class _YTPlaylistDownloadPageState extends State<YTPlaylistDownloadPage> {
  final _selectedList = <String>[].obs; // sometimes a yt playlist can have duplicates (yt bug) so a Set wont be useful.
  final _configMap = <String, YoutubeItemDownloadConfig>{}.obs;
  final _groupName = DownloadTaskGroupName(groupName: '').obs;

  final _folderController = GlobalKey<YTDownloadOptionFolderListTileState>();

  bool useCachedVersionsIfAvailable = true;
  final preferredQuality = (settings.youtubeVideoQualities.value.firstOrNull ?? kStockVideoQualities.first).obs;

  bool _didManuallyEditSelection = false;

  void _onItemTap(String id) => _selectedList.addOrRemove(id);

  void _onGroupNameChanged() {
    if (!_didManuallyEditSelection) {
      _addAllYTIDsToSelectedExceptAlrDownloaded();
    }
  }

  @override
  void initState() {
    _groupName.addListener(_onGroupNameChanged);
    _groupName.value = DownloadTaskGroupName(groupName: widget.playlistName.emptyIfHasDefaultPlaylistName());
    onRenameAllTasks(settings.youtube.downloadFilenameBuilder.value); // needed to provide initial data specially original indices
    super.initState();
  }

  @override
  void dispose() {
    _groupName.removeListener(_onGroupNameChanged);
    _selectedList.close();
    _configMap.close();
    _groupName.close();
    preferredQuality.close();
    super.dispose();
  }

  void onRenameAllTasks(String? defaultFilename) {
    final timeNow = DateTime.now();
    final group = _groupName.value;
    widget.ids
        .mapIndexed((ytid, originalIndex) => _configMap.value[ytid.id] = _getDummyDownloadConfig(ytid.id, originalIndex, group, defaultFilename: defaultFilename, timeNow: timeNow))
        .toList();
  }

  void _updateAudioOnly(bool audioOnly) {
    settings.save(downloadAudioOnly: audioOnly);
    _configMap.value.updateAll((key, value) => value.copyWith(fetchMissingVideo: !audioOnly));
    _configMap.refresh();
  }

  YoutubeItemDownloadConfig _getDummyDownloadConfig(String id, int originalIndex, DownloadTaskGroupName group, {String? defaultFilename, required DateTime timeNow}) {
    final streamInfoItem = widget.infoLookup[id];
    final filenameBuilderSettings = settings.youtube.downloadFilenameBuilder.value;
    final filename =
        filenameBuilderSettings.isNotEmpty ? filenameBuilderSettings : (defaultFilename ?? streamInfoItem?.title ?? YoutubeInfoController.utils.getVideoNameSync(id) ?? id);
    return YoutubeItemDownloadConfig(
      originalIndex: originalIndex,
      totalLength: widget.playlistInfo?.videosCount ?? widget.ids.length,
      playlistId: widget.playlistInfo?.id,
      playlistInfo: widget.playlistInfo,
      id: DownloadTaskVideoId(videoId: id),
      groupName: group,
      filename: DownloadTaskFilename.create(initialFilename: filename),
      ffmpegTags: {},
      fileDate: null,
      videoStream: null,
      audioStream: null,
      streamInfoItem: streamInfoItem,
      prefferedVideoQualityID: null,
      prefferedAudioQualityID: null,
      fetchMissingAudio: true,
      fetchMissingVideo: !settings.downloadAudioOnly.value,
      addedAt: timeNow,
    );
  }

  void _addAllYTIDsToSelected() {
    _selectedList.assignAll(widget.ids.map((e) => e.id));
    _didManuallyEditSelection = false;
  }

  void _addAllYTIDsToSelectedExceptAlrDownloaded() {
    _selectedList.assignAll(widget.ids.map((e) => e.id).where((id) => YoutubeController.inst.doesIDHasFileDownloadedInGroup(id, _groupName.value) == null));
    _didManuallyEditSelection = false;
  }

  Future<void> _onEditIconTap({
    required String id,
    required int originalIndex,
  }) async {
    await showDownloadVideoBottomSheet(
      originalIndex: _configMap.value[id]?.originalIndex,
      totalLength: _configMap.value[id]?.totalLength,
      streamInfoItem: widget.infoLookup[id],
      playlistInfo: widget.playlistInfo,
      playlistId: widget.playlistInfo?.id,
      initialGroupName: widget.playlistName.emptyIfHasDefaultPlaylistName(),
      showSpecificFileOptionsInEditTagDialog: false,
      videoId: id,
      initialItemConfig: _configMap[id],
      confirmButtonText: lang.CONFIRM,
      onConfirmButtonTap: (groupName, config) {
        _configMap.value[id] = config;
        return true;
      },
    );
  }

  void _showAllConfigDialog(BuildContext context) {
    const visualDensity = null;

    List<NamidaPopupItem> qualityMenuChildren() => [
          NamidaPopupItem(
            icon: Broken.musicnote,
            title: lang.AUDIO,
            onTap: () {
              _updateAudioOnly(true);
            },
          ),
          ...kStockVideoQualities.map(
            (e) => NamidaPopupItem(
              icon: Broken.story,
              title: e,
              onTap: () {
                _updateAudioOnly(false);
                preferredQuality.value = e;
              },
            ),
          )
        ];

    NamidaNavigator.inst.navigateDialog(
      dialog: CustomBlurryDialog(
        title: lang.CONFIGURE,
        titleWidgetInPadding: Row(
          children: [
            const Icon(Broken.setting_3, size: 28.0),
            const SizedBox(width: 8.0),
            Expanded(
              child: Text(
                lang.CONFIGURE,
                style: context.textTheme.displayLarge,
              ),
            ),
          ],
        ),
        normalTitleStyle: true,
        actions: [
          NamidaButton(
            text: lang.CONFIRM,
            onPressed: NamidaNavigator.inst.closeDialog,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12.0),
            YTDownloadOptionFolderListTile(
              maxTrailingWidth: context.width * 0.2,
              visualDensity: visualDensity,
              playlistName: widget.playlistName.translatePlaylistName(),
              initialFolder: _groupName.value.groupName,
              onDownloadGroupNameChanged: (newGroupName) {
                _groupName.value = DownloadTaskGroupName(groupName: newGroupName);
                _folderController.currentState?.onGroupNameChanged(newGroupName);
              },
              onDownloadFolderAdded: (newFolderName) {
                _folderController.currentState?.onFolderAdd(newFolderName);
              },
            ),
            ObxO(
              rx: settings.youtube.autoExtractVideoTagsFromInfo,
              builder: (context, autoExtractVideoTagsFromInfo) => CustomSwitchListTile(
                visualDensity: visualDensity,
                icon: Broken.magicpen,
                title: lang.AUTO_EXTRACT_TITLE_AND_ARTIST_FROM_VIDEO_TITLE,
                value: autoExtractVideoTagsFromInfo,
                onChanged: (isTrue) => settings.youtube.save(autoExtractVideoTagsFromInfo: !isTrue),
              ),
            ),
            ObxO(
              rx: settings.downloadFilesKeepCachedVersions,
              builder: (context, downloadFilesKeepCachedVersions) => CustomSwitchListTile(
                visualDensity: visualDensity,
                icon: Broken.copy,
                title: lang.KEEP_CACHED_VERSIONS,
                value: downloadFilesKeepCachedVersions,
                onChanged: (isTrue) => settings.save(downloadFilesKeepCachedVersions: !isTrue),
              ),
            ),
            ObxO(
              rx: settings.downloadFilesWriteUploadDate,
              builder: (context, downloadFilesWriteUploadDate) => CustomSwitchListTile(
                visualDensity: visualDensity,
                icon: Broken.document_code,
                title: lang.SET_FILE_LAST_MODIFIED_AS_VIDEO_UPLOAD_DATE,
                value: downloadFilesWriteUploadDate,
                onChanged: (isTrue) => settings.save(downloadFilesWriteUploadDate: !isTrue),
              ),
            ),
            ObxO(
              rx: settings.downloadAddAudioToLocalLibrary,
              builder: (context, addAudioToLocalLibrary) => CustomSwitchListTile(
                visualDensity: visualDensity,
                enabled: true,
                icon: Broken.music_library_2,
                title: lang.ADD_AUDIO_TO_LOCAL_LIBRARY,
                value: addAudioToLocalLibrary,
                onChanged: (isTrue) => settings.save(downloadAddAudioToLocalLibrary: !isTrue),
              ),
            ),
            ObxO(
              rx: settings.downloadOverrideOldFiles,
              builder: (context, override) => CustomSwitchListTile(
                visualDensity: visualDensity,
                icon: Broken.danger,
                title: lang.OVERRIDE_OLD_FILES_IN_THE_SAME_FOLDER,
                value: override,
                onChanged: (isTrue) => settings.save(downloadOverrideOldFiles: !isTrue),
              ),
            ),
            NamidaPopupWrapper(
              childrenDefault: qualityMenuChildren,
              child: CustomListTile(
                visualDensity: visualDensity,
                icon: Broken.story,
                title: lang.VIDEO_QUALITY,
                trailing: NamidaPopupWrapper(
                  childrenDefault: qualityMenuChildren,
                  child: Obx((context) => Text(settings.downloadAudioOnly.valueR ? lang.AUDIO_ONLY : preferredQuality.valueR)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double get _bottomPaddingEffective => Dimensions.inst.globalBottomPaddingEffectiveR;

  double _hmultiplier = 0.9;
  double _previousScale = 0.9;

  @override
  Widget build(BuildContext context) {
    final thumHeight = _hmultiplier * Dimensions.youtubeThumbnailHeight;
    final thumWidth = thumHeight * 16 / 9;
    const cardBorderRadiusRaw = 12.0;
    return BackgroundWrapper(
      child: Stack(
        children: [
          Column(
            children: [
              Obx(
                (context) => CustomListTile(
                  icon: Broken.music_playlist,
                  title: widget.playlistName.translatePlaylistName(),
                  subtitle: "${_selectedList.length.formatDecimal()}/${widget.ids.length.formatDecimal()}",
                  visualDensity: VisualDensity.compact,
                  trailingRaw: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      NamidaIconButton(
                        tooltip: () => lang.OUTPUT,
                        icon: Broken.edit_2,
                        onPressed: () {
                          YTUtils.showFilenameBuilderOutputSheet(
                            showEditTags: true,
                            groupName: _groupName.value.groupName,
                            onChanged: (text) => onRenameAllTasks(text),
                          );
                        },
                      ),
                      NamidaIconButton(
                        tooltip: () => lang.INVERT_SELECTION,
                        icon: Broken.recovery_convert,
                        onPressed: () {
                          widget.ids.loop((e) => _onItemTap(e.id));
                          _didManuallyEditSelection = true;
                        },
                      ),
                      Obx(
                        (context) => Checkbox.adaptive(
                          splashRadius: 28.0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4.0.multipliedRadius),
                          ),
                          tristate: true,
                          value: _selectedList.isEmpty
                              ? false
                              : _selectedList.length != widget.ids.length
                                  ? null
                                  : true,
                          onChanged: (value) {
                            if (_selectedList.length != widget.ids.length) {
                              _addAllYTIDsToSelected();
                            } else {
                              _selectedList.clear();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              YTDownloadOptionFolderListTile(
                key: _folderController,
                visualDensity: VisualDensity.compact,
                trailingPadding: 12.0,
                playlistName: widget.playlistName.translatePlaylistName(),
                initialFolder: _groupName.value.groupName,
                subtitle: (value) => FileParts.joinPath(AppDirs.YOUTUBE_DOWNLOADS, value),
                onDownloadGroupNameChanged: (newGroupName) {
                  _groupName.value = DownloadTaskGroupName(groupName: newGroupName);
                },
              ),
              ObxO(
                rx: settings.youtube.downloadFilenameBuilder,
                builder: (context, value) {
                  return value.isEmpty
                      ? const SizedBox()
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 6.0),
                          child: Row(
                            children: [
                              const SizedBox(width: 18.0),
                              const Icon(
                                Broken.document_code,
                                size: 20.0,
                              ),
                              const SizedBox(width: 12.0),
                              Expanded(
                                child: Text(
                                  value,
                                  style: context.textTheme.displaySmall,
                                ),
                              ),
                              const SizedBox(width: 18.0),
                            ],
                          ),
                        );
                },
              ),
              Expanded(
                child: NamidaScrollbarWithController(
                  child: (sc) => CustomScrollView(
                    controller: sc,
                    slivers: [
                      const SliverPadding(padding: EdgeInsets.only(bottom: 12.0)),
                      SliverFixedExtentList.builder(
                        itemExtent: Dimensions.youtubeCardItemExtent * _hmultiplier,
                        itemCount: widget.ids.length,
                        itemBuilder: (context, originalIndex) {
                          final id = widget.ids[originalIndex].id;
                          final info = widget.infoLookup[id] ?? YoutubeInfoController.utils.getStreamInfoSync(id);
                          final duration = info?.durSeconds?.secondsLabel;

                          return Obx(
                            (context) {
                              final isSelected = _selectedList.contains(id);
                              final filename = _configMap[id]?.filenameR;
                              final fileExists = filename == null ? false : YoutubeController.inst.doesIDHasFileDownloadedInGroup(id, _groupName.valueR) != null;
                              return NamidaInkWell(
                                animationDurationMS: 200,
                                height: Dimensions.youtubeCardItemHeight * _hmultiplier,
                                margin: EdgeInsets.symmetric(horizontal: 12.0, vertical: Dimensions.youtubeCardItemVerticalPadding * _hmultiplier),
                                borderRadius: cardBorderRadiusRaw,
                                bgColor: context.theme.cardColor.withValues(alpha: 0.3),
                                decoration: isSelected
                                    ? BoxDecoration(
                                        border: Border.all(
                                        color: context.theme.colorScheme.secondary.withValues(alpha: 0.5),
                                        width: 2.0,
                                      ))
                                    : const BoxDecoration(),
                                onTap: () {
                                  _onItemTap(id);
                                  _didManuallyEditSelection = true;
                                },
                                onLongPress: () {
                                  if (_selectedList.isEmpty) return;
                                  int? latestIndex;
                                  for (int i = widget.ids.length - 1; i >= 0; i--) {
                                    final item = widget.ids[i];
                                    if (_selectedList.contains(item.id)) {
                                      latestIndex = i;
                                      break;
                                    }
                                  }
                                  if (latestIndex != null && originalIndex > latestIndex) {
                                    final selectedRange = widget.ids.getRange(latestIndex + 1, originalIndex + 1);
                                    selectedRange.toList().loop((e) {
                                      if (!_selectedList.contains(e.id)) _selectedList.add(e.id);
                                    });
                                  } else {
                                    _onItemTap(id);
                                  }
                                  _didManuallyEditSelection = true;
                                },
                                child: Stack(
                                  children: [
                                    Row(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.all(4.0),
                                          child: YoutubeThumbnail(
                                            type: ThumbnailType.video,
                                            key: Key(id),
                                            borderRadius: 8.0,
                                            width: thumWidth - 4.0,
                                            height: thumHeight - 4.0,
                                            isImportantInCache: false,
                                            videoId: id,
                                            customUrl: info?.liveThumbs.pick()?.url,
                                            smallBoxText: duration,
                                          ),
                                        ),
                                        const SizedBox(width: 4.0),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const SizedBox(height: 6.0),
                                              Text(
                                                info?.title ?? id,
                                                style: context.textTheme.displayMedium?.copyWith(fontSize: 15.0 * _hmultiplier),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4.0),
                                              Row(
                                                children: [
                                                  NamidaIconButton(
                                                    horizontalPadding: 0.0,
                                                    icon: fileExists ? Broken.tick_circle : Broken.import_2,
                                                    iconSize: 15.0,
                                                  ),
                                                  const SizedBox(width: 2.0),
                                                  _VideoIdToChannelNameWidget(
                                                    channelName: info?.channelName ?? info?.channel?.title,
                                                    videoId: id,
                                                    style: context.textTheme.displaySmall?.copyWith(fontSize: 14.0 * _hmultiplier),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6.0),
                                            ],
                                          ),
                                        ),
                                        NamidaIconButton(
                                          verticalPadding: 4.0,
                                          horizontalPadding: 4.0,
                                          icon: Broken.edit_2,
                                          iconSize: 20.0,
                                          onPressed: () => _onEditIconTap(id: id, originalIndex: originalIndex),
                                        ),
                                        Checkbox.adaptive(
                                          visualDensity: VisualDensity.compact,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(4.0.multipliedRadius),
                                          ),
                                          value: isSelected,
                                          onChanged: (value) {
                                            _onItemTap(id);
                                            _didManuallyEditSelection = true;
                                          },
                                        ),
                                        const SizedBox(width: 8.0),
                                      ],
                                    ),
                                    Positioned(
                                      right: 0,
                                      child: NamidaBlurryContainer(
                                        borderRadius: BorderRadius.only(
                                          bottomLeft: Radius.circular(6.0.multipliedRadius),
                                          topRight: Radius.circular(cardBorderRadiusRaw.multipliedRadius),
                                        ),
                                        padding: const EdgeInsets.only(top: 2.0, right: 8.0, left: 6.0, bottom: 2.0),
                                        child: Text(
                                          '${originalIndex + 1}',
                                          style: context.textTheme.displaySmall,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                      Obx((context) => SliverPadding(padding: EdgeInsets.only(bottom: _bottomPaddingEffective + 56.0 + 4.0))),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Obx(
            (context) => AnimatedPositioned(
              curve: Curves.fastEaseInToSlowEaseOut,
              duration: const Duration(milliseconds: 400),
              bottom: _bottomPaddingEffective,
              right: 12.0,
              child: Row(
                children: [
                  FloatingActionButton.small(
                    backgroundColor: context.theme.disabledColor.withValues(alpha: 1.0),
                    heroTag: 'config_fab',
                    child: Icon(Broken.setting_3, color: Colors.white.withValues(alpha: 0.8)),
                    onPressed: () {
                      _showAllConfigDialog(context);
                    },
                  ),
                  const SizedBox(width: 8.0),
                  Obx(
                    (context) => FloatingActionButton.extended(
                      heroTag: 'download_fab',
                      backgroundColor: (_selectedList.isEmpty ? context.theme.disabledColor : CurrentColor.inst.color).withValues(alpha: 1.0),
                      isExtended: true,
                      icon: Icon(
                        Broken.import_2,
                        size: 28.0,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                      label: Text(
                        lang.DOWNLOAD,
                        style: context.textTheme.displayMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      onPressed: () async {
                        if (_selectedList.isEmpty) return;
                        if (!await requestManageStoragePermission()) return;
                        final timeNow = DateTime.now();
                        final group = _groupName.value;
                        final itemsConfig = _selectedList.value
                            .map(
                              (id) =>
                                  _configMap.value[id] ??

                                  // -- this is not really used since initState() calls onRenameAllTasks() which fills _configMap
                                  _getDummyDownloadConfig(
                                    id,
                                    widget.ids.indexWhere((element) => element.id == id),
                                    group,
                                    timeNow: timeNow,
                                  ),
                            )
                            .toList();
                        NamidaNavigator.inst.popPage();
                        YoutubeController.inst.downloadYoutubeVideos(
                          groupName: group,
                          itemsConfig: itemsConfig,
                          useCachedVersionsIfAvailable: useCachedVersionsIfAvailable,
                          autoExtractTitleAndArtist: settings.youtube.autoExtractVideoTagsFromInfo.value,
                          keepCachedVersionsIfDownloaded: settings.downloadFilesKeepCachedVersions.value,
                          downloadFilesWriteUploadDate: settings.downloadFilesWriteUploadDate.value,
                          addAudioToLocalLibrary: settings.downloadAddAudioToLocalLibrary.value,
                          deleteOldFile: settings.downloadOverrideOldFiles.value,
                          audioOnly: settings.downloadAudioOnly.value,
                          preferredQualities: () {
                            final list = <String>[];
                            for (final q in kStockVideoQualities) {
                              list.add(q);
                              if (q == preferredQuality.value) break;
                            }
                            return list;
                          }(),
                          playlistInfo: widget.playlistInfo,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: ScaleDetector(
              onScaleStart: (details) => _previousScale = _hmultiplier,
              onScaleUpdate: (details) => setState(() => _hmultiplier = (details.scale * _previousScale).clampDouble(0.5, 2.0)),
            ),
          ),
        ],
      ),
    );
  }
}

class YTDownloadFilenameBuilderRow extends StatelessWidget {
  final TextEditingController? controller;
  final TextEditingController? Function()? controllerCallback;
  final Function(String text)? onChanged;
  const YTDownloadFilenameBuilderRow({super.key, required this.controller, this.controllerCallback, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: YoutubeController.filenameBuilder.availableEncodedParams
            .map(
              (e) => NamidaInkWell(
                borderRadius: 4.0,
                bgColor: context.theme.cardColor,
                margin: const EdgeInsets.symmetric(horizontal: 2.0),
                padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.0),
                onTap: () {
                  final controller = this.controller ?? controllerCallback?.call();
                  if (controller == null) return;
                  var cursorPos = controller.selection.base.offset;
                  if (cursorPos < 0) return; // require cursor to be active, avoid accidents and whatever
                  String textAfterCursor = controller.text.substring(cursorPos);
                  String textBeforeCursor = controller.text.substring(0, cursorPos);
                  final toAdd = YoutubeController.filenameBuilder.buildParamForFilename(e);
                  controller.text = "$textBeforeCursor$toAdd$textAfterCursor";
                  controller.selection = TextSelection.collapsed(offset: textBeforeCursor.length + toAdd.length);
                  onChanged?.call(controller.text);
                },
                child: Text(
                  e,
                  style: context.textTheme.displaySmall,
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _VideoIdToChannelNameWidget extends StatefulWidget {
  final String? channelName;
  final String videoId;
  final TextStyle? style;

  const _VideoIdToChannelNameWidget({
    required this.channelName,
    required this.videoId,
    required this.style,
  });

  @override
  State<_VideoIdToChannelNameWidget> createState() => _VideoIdToTitleWidgetState();
}

class _VideoIdToTitleWidgetState extends State<_VideoIdToChannelNameWidget> {
  String? _channelName;

  @override
  void initState() {
    super.initState();
    final channelName = widget.channelName;
    if (channelName == null || channelName.isEmpty) {
      initValues();
    } else {
      _channelName = channelName;
    }
  }

  void initValues() async {
    final id = widget.videoId;
    if (id.isEmpty) return;
    final newChannelName = await YoutubeInfoController.utils.getVideoChannelName(id);
    if (mounted) {
      if (newChannelName != _channelName) {
        setState(() => _channelName = newChannelName);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _channelName ?? '',
      style: widget.style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
