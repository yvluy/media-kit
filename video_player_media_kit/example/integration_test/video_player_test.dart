// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';

const Duration _playDuration = Duration(seconds: 1);

// Use WebM for web to allow CI to use Chromium.
const String _videoAssetKey =
    kIsWeb ? 'assets/Butterfly-209.webm' : 'assets/Butterfly-209.mp4';

// Returns the URL to load an asset from this example app as a network source.
//
// assets directly, https://github.com/flutter/flutter/issues/95420
String getUrlForAssetAsNetworkSource(String assetKey) {
  return 'https://github.com/flutter/packages/blob/'
      // This hash can be rolled forward to pick up newly-added assets.
      '2e1673307ff7454aff40b47024eaed49a9e77e81'
      '/packages/video_player/video_player/example/'
      '$assetKey'
      '?raw=true';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // --------------------------------------------------
  VideoPlayerMediaKit.ensureInitialized(
    android: true,
    iOS: true,
    macOS: true,
    windows: true,
    linux: true,
  );
  // --------------------------------------------------

  late VideoPlayerController controller;
  tearDown(() async => controller.dispose());

  group('asset videos', () {
    setUp(() {
      controller = VideoPlayerController.asset(_videoAssetKey);
    });

    testWidgets(
      'can be initialized',
      (WidgetTester tester) async {
        await controller.initialize();

        expect(controller.value.isInitialized, true);
        expect(controller.value.position, Duration.zero);
        expect(controller.value.isPlaying, false);
        expect(controller.value.duration.inSeconds, 7);
      },
    );

    testWidgets(
      'live stream duration != 0',
      (WidgetTester tester) async {
        final networkController = VideoPlayerController.networkUrl(
          Uri.parse(
            'https://flutter.github.io/assets-for-api-docs/assets/videos/hls/bee.m3u8',
          ),
        );
        await networkController.initialize();

        expect(networkController.value.isInitialized, true);
        expect(
          networkController.value.duration,
          (Duration duration) => duration != Duration.zero,
        );
      },
    );

    testWidgets(
      'can be played',
      (WidgetTester tester) async {
        await controller.initialize();
        // Mute to allow playing without DOM interaction on Web.
        // See https://developers.google.com/web/updates/2017/09/autoplay-policy-changes
        await controller.setVolume(0);

        await controller.play();
        await tester.pumpAndSettle(_playDuration);

        expect(controller.value.isPlaying, true);
        expect(
          controller.value.position,
          (Duration position) => position > Duration.zero,
        );
      },
    );

    testWidgets(
      'can seek',
      (WidgetTester tester) async {
        await controller.initialize();

        await controller.seekTo(const Duration(seconds: 3));

        expect(controller.value.position, const Duration(seconds: 3));
      },
    );

    testWidgets(
      'can be paused',
      (WidgetTester tester) async {
        await controller.initialize();
        // Mute to allow playing without DOM interaction on Web.
        // See https://developers.google.com/web/updates/2017/09/autoplay-policy-changes
        await controller.setVolume(0);

        // Play for a second, then pause, and then wait a second.
        await controller.play();
        await tester.pumpAndSettle(_playDuration);
        await controller.pause();
        final Duration pausedPosition = controller.value.position;
        await tester.pumpAndSettle(_playDuration);

        // Verify that we stopped playing after the pause.
        expect(controller.value.isPlaying, false);
        expect(controller.value.position, pausedPosition);
      },
    );

    testWidgets(
      'stay paused when seeking after video completed',
      (WidgetTester tester) async {
        await controller.initialize();
        // Mute to allow playing without DOM interaction on Web.
        // See https://developers.google.com/web/updates/2017/09/autoplay-policy-changes
        await controller.setVolume(0);
        final Duration tenMillisBeforeEnd =
            controller.value.duration - const Duration(milliseconds: 10);
        await controller.seekTo(tenMillisBeforeEnd);
        await controller.play();
        await tester.pumpAndSettle(_playDuration);
        expect(controller.value.isPlaying, false);
        expect(controller.value.position, controller.value.duration);

        await controller.seekTo(tenMillisBeforeEnd);
        await tester.pumpAndSettle(_playDuration);

        expect(controller.value.isPlaying, false);
        expect(controller.value.position, tenMillisBeforeEnd);
      },
    );

    testWidgets(
      'do not exceed duration on play after video completed',
      (WidgetTester tester) async {
        await controller.initialize();
        // Mute to allow playing without DOM interaction on Web.
        // See https://developers.google.com/web/updates/2017/09/autoplay-policy-changes
        await controller.setVolume(0);
        await controller.seekTo(
          controller.value.duration - const Duration(milliseconds: 10),
        );
        await controller.play();
        await tester.pumpAndSettle(_playDuration);
        expect(controller.value.isPlaying, false);
        expect(controller.value.position, controller.value.duration);

        await controller.play();
        await tester.pumpAndSettle(_playDuration);

        expect(
          controller.value.position,
          lessThanOrEqualTo(controller.value.duration),
        );
      },
    );

    testWidgets(
      'test video player view with local asset',
      (WidgetTester tester) async {
        Future<bool> started() async {
          await controller.initialize();
          await controller.play();
          return true;
        }

        await tester.pumpWidget(
          Material(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: FutureBuilder<bool>(
                  future: started(),
                  builder:
                      (BuildContext context, AsyncSnapshot<bool> snapshot) {
                    if (snapshot.data ?? false) {
                      return AspectRatio(
                        aspectRatio: controller.value.aspectRatio,
                        child: VideoPlayer(controller),
                      );
                    } else {
                      return const Text('waiting for video to load');
                    }
                  },
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
      },
    );
  });

  group('file-based videos', () {
    setUp(() async {
      // Load the data from the asset.
      final String tempDir = (await getTemporaryDirectory()).path;
      final ByteData bytes = await rootBundle.load(_videoAssetKey);

      // Write it to a file to use as a source.
      final String filename = _videoAssetKey.split('/').last;
      final File file = File('$tempDir/$filename');
      await file.writeAsBytes(bytes.buffer.asInt8List());

      controller = VideoPlayerController.file(file);
    });

    testWidgets(
      'test video player using static file() method as constructor',
      (WidgetTester tester) async {
        await controller.initialize();

        await controller.play();
        expect(controller.value.isPlaying, true);

        await controller.pause();
        expect(controller.value.isPlaying, false);
      },
    );
  });

  group('network videos', () {
    setUp(() {
      controller = VideoPlayerController.networkUrl(
          Uri.parse(getUrlForAssetAsNetworkSource(_videoAssetKey)));
    });

    testWidgets(
      'reports buffering status',
      (WidgetTester tester) async {
        final Completer<void> started = Completer<void>();
        final Completer<void> ended = Completer<void>();
        controller.addListener(() {
          if (!started.isCompleted && controller.value.isBuffering) {
            //debugPrint('STARTED!');
            started.complete();
          }
          if (started.isCompleted &&
              !controller.value.isBuffering &&
              !ended.isCompleted) {
            //debugPrint('ENDED!');
            ended.complete();
          }
        });

        await controller.initialize();
        // Mute to allow playing without DOM interaction on Web.
        // See https://developers.google.com/web/updates/2017/09/autoplay-policy-changes
        await controller.setVolume(0);

        await controller.play();
        await controller.seekTo(const Duration(seconds: 5));
        await tester.pumpAndSettle(_playDuration);
        await controller.pause();

        expect(controller.value.isPlaying, false);
        expect(
          controller.value.position,
          (Duration position) => position > Duration.zero,
        );

        await expectLater(started.future, completes);
        await expectLater(ended.future, completes);
      },
    );
  });

  // Audio playback is tested to prevent accidental regression,
  // but could be removed in the future.
  group('asset audios', () {
    setUp(() {
      controller = VideoPlayerController.asset('assets/Audio.mp3');
    });

    testWidgets(
      'can be initialized',
      (WidgetTester tester) async {
        await controller.initialize();

        expect(controller.value.isInitialized, true);
        expect(controller.value.position, Duration.zero);
        expect(controller.value.isPlaying, false);
        expect(
          controller.value.duration.inSeconds,
          5,
        );
      },
    );

    testWidgets(
      'can be played',
      (WidgetTester tester) async {
        await controller.initialize();
        // Mute to allow playing without DOM interaction on Web.
        // See https://developers.google.com/web/updates/2017/09/autoplay-policy-changes
        await controller.setVolume(0);

        await controller.play();
        await tester.pumpAndSettle(_playDuration);

        expect(controller.value.isPlaying, true);
        expect(
          controller.value.position,
          (Duration position) => position > Duration.zero,
        );
      },
    );

    testWidgets(
      'can seek',
      (WidgetTester tester) async {
        await controller.initialize();
        await controller.seekTo(const Duration(seconds: 3));

        expect(controller.value.position, const Duration(seconds: 3));
      },
    );

    testWidgets(
      'can be paused',
      (WidgetTester tester) async {
        await controller.initialize();
        // Mute to allow playing without DOM interaction on Web.
        // See https://developers.google.com/web/updates/2017/09/autoplay-policy-changes
        await controller.setVolume(0);

        // Play for a second, then pause, and then wait a second.
        await controller.play();
        await tester.pumpAndSettle(_playDuration);
        await controller.pause();
        final Duration pausedPosition = controller.value.position;
        await tester.pumpAndSettle(_playDuration);

        // Verify that we stopped playing after the pause.
        expect(controller.value.isPlaying, false);
        expect(controller.value.position, pausedPosition);
      },
    );
  });
}
