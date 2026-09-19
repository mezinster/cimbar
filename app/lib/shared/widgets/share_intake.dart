import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_handler/share_handler.dart';

import '../../app.dart';
import '../../core/services/incoming_share.dart';
import '../../core/utils/byte_utils.dart';
import '../../features/camera/camera_controller.dart';
import '../../features/import/import_controller.dart';
import '../../l10n/generated/app_localizations.dart';

/// The app-wide ScaffoldMessenger, so the share intake (which sits above any
/// Scaffold) can show a SnackBar.
final GlobalKey<ScaffoldMessengerState> appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Receives files other apps share to CimBar — on a cold start
/// (initialMedia) and while running (mediaStream). The first readable file
/// goes by content: a GIF to the Import tab, anything else (a photo of a
/// barcode) to the Camera tab's photo decoder.
class ShareIntake extends ConsumerStatefulWidget {
  final Widget child;
  const ShareIntake({super.key, required this.child});

  @override
  ConsumerState<ShareIntake> createState() => _ShareIntakeState();
}

class _ShareIntakeState extends ConsumerState<ShareIntake> {
  StreamSubscription<SharedMedia>? _sub;

  @override
  void initState() {
    super.initState();
    final source = ref.read(shareSourceProvider);
    // A platform without the plugin (e.g. widget tests using the real
    // source) reports MissingPluginException; sharing is then simply absent.
    _sub = source.mediaStream.listen(_handle, onError: (Object _) {});
    source.initialMedia().then((media) async {
      if (media == null) return;
      await source.resetInitialMedia();
      await _handle(media);
    }, onError: (Object _) {});
  }

  Future<void> _handle(SharedMedia media) async {
    // Nothing from here should escape as an unhandled zone error — a
    // malformed attachment or a mid-teardown provider read must not crash
    // the app; it's simply reported as unreadable / dropped.
    try {
      final result = await firstSharedFile(media);
      if (!mounted) return;
      final file = result.file;
      if (file != null) {
        final gif = isGif(file.bytes);
        final route = gif ? '/import' : '/camera';
        // Checked after the (async) read, against the tab that would take
        // the file: a running decode owns its current file, and swapping it
        // would leave the old decode writing progress/result for a file
        // that's no longer selected. Show the running decode instead.
        final busy = gif
            ? ref.read(importControllerProvider).isDecoding
            : ref.read(cameraControllerProvider).isDecoding;
        if (busy) {
          _goTo(route);
          appMessengerKey.currentState?.showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.shareWhileDecoding)),
          );
          return;
        }
        if (gif) {
          ref.read(importControllerProvider.notifier).loadSharedFile(file.name, file.bytes);
        } else {
          ref.read(cameraControllerProvider.notifier).setPhoto(file.bytes);
        }
        _goTo(route);
      } else if (result.unreadable) {
        appMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.shareReadFailed)),
        );
      }
    } catch (_) {
      // Unreadable/unexpected share payload — nothing to show, nothing to
      // crash.
    }
  }

  /// Switches to the tab at [location], first popping the root navigator back to
  /// the shell so a full-screen route pushed above it (Live Scan, Photo
  /// Capture) doesn't hide the switch.
  void _goTo(String location) {
    rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    ref.read(routerProvider).go(location);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
