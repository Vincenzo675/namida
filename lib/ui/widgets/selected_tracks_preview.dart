import 'package:flutter/material.dart';

import 'package:namida/class/track.dart';
import 'package:namida/controller/player_controller.dart';
import 'package:namida/controller/selected_tracks_controller.dart';
import 'package:namida/controller/settings_controller.dart';
import 'package:namida/core/dimensions.dart';
import 'package:namida/core/enums.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/translations/language.dart';
import 'package:namida/core/utils.dart';
import 'package:namida/ui/dialogs/add_to_playlist_dialog.dart';
import 'package:namida/ui/dialogs/edit_tags_dialog.dart';
import 'package:namida/ui/dialogs/general_popup_dialog.dart';
import 'package:namida/ui/widgets/animated_widgets.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';
import 'package:namida/ui/widgets/library/track_tile.dart';

class SelectedTracksPreviewContainer extends StatelessWidget {
  final AnimationController animation;
  final bool isMiniplayerAlwaysVisible;

  const SelectedTracksPreviewContainer({
    super.key,
    required this.animation,
    required this.isMiniplayerAlwaysVisible,
  });

  @override
  Widget build(BuildContext context) {
    final boxHeightMinimized = 80.0.withMaximum(0.2 * context.height);
    final boxHeightMaximized = 425.0.withMaximum(0.8 * context.height);
    final boxWidth = 375.0.withMaximum(context.width);
    final stc = SelectedTracksController.inst;
    final sysNavBar = MediaQuery.paddingOf(context).bottom;
    final child = TrackTilePropertiesProvider(
      configs: const TrackTilePropertiesConfigs(
        displayRightDragHandler: true,
        draggableThumbnail: true,
        horizontalGestures: false,
        queueSource: QueueSource.selectedTracks,
      ),
      builder: (properties) => ObxO(
        rx: SelectedTracksController.inst.selectedTracks,
        builder: (context, selectedTracks) {
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: selectedTracks.isNotEmpty
                ? Center(
                    child: Container(
                      width: context.width,
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end, // bottom align
                        crossAxisAlignment: isMiniplayerAlwaysVisible ? CrossAxisAlignment.end : CrossAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () => stc.isMenuMinimized.value = !stc.isMenuMinimized.value,
                            onTapDown: (value) => stc.isPressed.value = true,
                            onTapUp: (value) => stc.isPressed.value = false,
                            onTapCancel: () => stc.isPressed.value = !stc.isPressed.value,

                            // dragging upwards or downwards
                            onPanEnd: (details) {
                              if (details.velocity.pixelsPerSecond.dy < 0) {
                                stc.isMenuMinimized.value = false;
                              } else if (details.velocity.pixelsPerSecond.dy > 0) {
                                stc.isMenuMinimized.value = true;
                              }
                            },
                            child: ObxO(
                              rx: stc.isPressed,
                              builder: (context, isPressed) => ObxO(
                                rx: stc.isMenuMinimized,
                                builder: (context, isMenuMinimized) {
                                  double extra = isPressed
                                      ? isMenuMinimized
                                          ? 5.0
                                          : -5.0
                                      : 0.0;
                                  return AnimatedSizedBox(
                                    duration: const Duration(seconds: 1),
                                    curve: Curves.fastLinearToSlowEaseIn,
                                    height: isMenuMinimized ? boxHeightMinimized + extra : boxHeightMaximized + extra,
                                    width: boxWidth + extra,
                                    decoration: BoxDecoration(
                                      color: Color.alphaBlend(context.theme.colorScheme.surface.withAlpha(160), context.theme.scaffoldBackgroundColor),
                                      borderRadius: const BorderRadius.all(Radius.circular(20)),
                                      boxShadow: [
                                        BoxShadow(
                                          color: context.theme.shadowColor.withAlpha(30),
                                          blurRadius: 10,
                                          offset: const Offset(0, 5),
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: isMenuMinimized
                                          ? const FittedBox(child: SelectedTracksRow())
                                          : Column(
                                              mainAxisSize: MainAxisSize.max,
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                const FittedBox(child: SelectedTracksRow()),
                                                const SizedBox(
                                                  height: 20,
                                                ),
                                                Expanded(
                                                  child: Container(
                                                    clipBehavior: Clip.antiAlias,
                                                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
                                                    child: NamidaListView(
                                                      itemExtent: Dimensions.inst.trackTileItemExtent,
                                                      itemCount: selectedTracks.length,
                                                      onReorder: (oldIndex, newIndex) => stc.reorderTracks(oldIndex, newIndex),
                                                      listBottomPadding: 0,
                                                      itemBuilder: (context, i) {
                                                        return FadeDismissible(
                                                          key: ValueKey(selectedTracks[i]),
                                                          onDismissed: (direction) => stc.removeTrack(i),
                                                          child: TrackTile(
                                                            properties: properties,
                                                            index: i,
                                                            trackOrTwd: selectedTracks[i],
                                                            tracks: selectedTracks,
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
          );
        },
      ),
    );
    if (isMiniplayerAlwaysVisible) {
      return Obx(
        (context) {
          final boxLeftMargin = !isMiniplayerAlwaysVisible ? 8.0 : 12.0;
          final boxRightMargin = !isMiniplayerAlwaysVisible ? 8.0 : (Dimensions.inst.shouldHideFABR ? 0.0 : kFABSize) + 12.0 * 2;
          return AnimatedPadding(
            duration: Duration(milliseconds: 200),
            curve: Curves.fastEaseInToSlowEaseOut,
            padding: EdgeInsets.only(left: boxLeftMargin, right: boxRightMargin),
            child: child,
          );
        },
      );
    }

    final opacityAnimation = animation.drive(Animatable.fromCallback(
      (animationValue) {
        final isMini = animationValue <= 1.0;
        final isInQueue = !isMini;
        final percentage = isMini ? animationValue : animationValue - 1;
        return (isInQueue ? percentage : 1 - percentage).clampDouble(0, 1);
      },
    ));
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final animationValue = animation.value;
        if (animationValue == 1.0) return const SizedBox();

        final miniHeight = animationValue.clampDouble(0.0, 1.0);
        final queueHeight = animationValue > 1.0 ? animationValue.clampDouble(1.0, 2.0) : 0.0;
        final isMini = animationValue <= 1.0;
        final isInQueue = !isMini;

        final navHeight = (settings.enableBottomNavBar.value ? kBottomNavigationBarHeight : -4.0) - 10.0;
        final initH = isInQueue ? kQueueBottomRowHeight * 2 : 12.0 + (miniHeight * 24.0);

        return AnimatedPositioned(
          duration: const Duration(milliseconds: 100),
          bottom: sysNavBar + initH + (navHeight * (1 - queueHeight)),
          child: FadeIgnoreTransition(
            opacity: opacityAnimation,
            child: child,
          ),
        );
      },
    );
  }
}

class SelectedTracksRow extends StatelessWidget {
  const SelectedTracksRow({super.key});

  List<Track> getSelectedTracks() => SelectedTracksController.inst.selectedTracks.value.tracks.toList();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        IconButton(
          onPressed: () => SelectedTracksController.inst.clearEverything(),
          icon: const Icon(Broken.close_circle),
        ),
        SizedBox(
          width: 6.0,
        ),
        SizedBox(
          width: 140,
          child: Obx(
            (context) {
              final selectedTracks = SelectedTracksController.inst.selectedTracks.valueR.tracks.toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedTracks.displayTrackKeyword,
                    style: context.theme.textTheme.displayLarge!.copyWith(fontSize: 21.0),
                  ),
                  if (!SelectedTracksController.inst.isMenuMinimized.valueR)
                    Text(
                      selectedTracks.totalDurationFormatted,
                      style: context.theme.textTheme.displayMedium,
                    )
                ],
              );
            },
          ),
        ),
        const SizedBox(
          width: 32,
        ),
        ObxO(
          rx: SelectedTracksController.inst.didInsertTracks,
          builder: (context, didInsertTracks) => AnimatedOpacity(
            duration: const Duration(milliseconds: 400),
            opacity: didInsertTracks ? 0.5 : 1.0,
            child: IgnorePointer(
              ignoring: didInsertTracks,
              child: IconButton(
                onPressed: () {
                  SelectedTracksController.inst.didInsertTracks.value = true;
                  Player.inst.addToQueue(getSelectedTracks());
                },
                icon: const Icon(Broken.play_cricle),
                tooltip: lang.PLAY_LAST,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: () => showEditTracksTagsDialog(getSelectedTracks(), null),
          tooltip: lang.EDIT_TAGS,
          icon: const Icon(Broken.edit),
        ),
        IconButton(
          onPressed: () => showAddToPlaylistDialog(getSelectedTracks()),
          tooltip: lang.ADD_TO_PLAYLIST,
          icon: const Icon(Broken.music_playlist),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () {
            final tracks = getSelectedTracks();
            final selectedPl = SelectedTracksController.inst.selectedPlaylistsNames.values.toList();
            selectedPl.removeDuplicates();
            showGeneralPopupDialog(
              tracks,
              tracks.displayTrackKeyword,
              [
                tracks.totalSizeFormatted,
                tracks.totalDurationFormatted,
              ].join(' • '),
              QueueSource.selectedTracks,
              thirdLineText: tracks.length == 1
                  ? tracks.first.title
                  : tracks.map((e) {
                      final title = e.toTrackExt().title;
                      final maxLet = 20 - tracks.length.clampInt(0, 17);
                      return '${title.substring(0, (title.length > maxLet ? maxLet : title.length))}..';
                    }).join(', '),
              tracksWithDates: SelectedTracksController.inst.selectedTracks.value.tracksWithDates.toList(),
              playlistName: selectedPl.length == 1 ? selectedPl.first : null,
            );
          },
          tooltip: lang.MORE,
          icon: const RotatedBox(quarterTurns: 1, child: Icon(Broken.more)),
        ),
        IconButton(
          onPressed: () => SelectedTracksController.inst.selectAllTracks(),
          icon: const Icon(Broken.category),
          tooltip: lang.SELECT_ALL,
        ),
        SelectedTracksController.inst.isMenuMinimized.value ? const Icon(Broken.arrow_up_3) : const Icon(Broken.arrow_down_2)
      ],
    );
  }
}
