import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_handler/share_handler.dart';

import '../../app.dart';
import '../../core/format/cimbar_spec.dart';
import '../../core/services/incoming_share.dart';
import '../../core/services/share_detection.dart';
import '../../features/camera/camera_controller.dart';
import '../../features/import/import_controller.dart';
import '../../features/photo/data/photo_temp.dart';
import '../../features/photo/presentation/photo_optimiser_screen.dart';
import '../../features/send/present_screen.dart';
import '../../features/send/send_controller.dart';
import '../../l10n/generated/app_localizations.dart';
import '../format_size.dart';
import 'share_routing.dart';

/// The app-wide ScaffoldMessenger, so the share intake (which sits above any
/// Scaffold) can show a SnackBar.
final GlobalKey<ScaffoldMessengerState> appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Asks [message] with Yes/No before a share replaces something; true only
/// for Yes (dismissing the dialog is No). [context] is the root navigator's.
Future<bool> confirmShareReplace(BuildContext context, String message) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx)!;
      return AlertDialog(
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.commonNo)),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.commonYes)),
        ],
      );
    },
  );
  return yes ?? false;
}

/// Receives what other apps share to CimBar — on a cold start (initialMedia)
/// and while running (mediaStream). The first usable item goes where
/// [routeShare] says: a CimBar GIF to Import, a barcode photo to the Camera
/// tab with its decode, any other photo to the optimiser, text and every
/// other file to Send.
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
      final share = await readShare(media);
      final item = share.item;
      if (!mounted || item == null) return;
      final route = await routeShare(
        item,
        decodePixels: ref.read(pixelDecoderProvider),
        stage: _stage,
        release: _release,
        onDetecting: _showChecking,
      );
      _hideChecking();
      if (!mounted) return;
      final loaded = await _act(route);
      if (loaded && mounted && share.count > 1) _snack(AppLocalizations.of(context)!.shareOnlyFirst(share.count));
    } catch (_) {
      // Unreadable/unexpected share payload — nothing to show, nothing to
      // crash.
      _hideChecking();
    }
  }

  /// Copies a shared photo into `temp/share_in` (the optimiser and the
  /// Camera tab keep using it after the plugin's copy is gone).
  Future<String> _stage(SharedFileItem f) async {
    final temp = await ref.read(photoTempDirProvider)();
    // On Android the plugin copies into cacheDir, which is the temp directory.
    return stageSharedFile(f, tempBase: temp, cacheDir: temp.path);
  }

  /// Deletes the plugin's copy of a GIF or other file once it is read.
  Future<void> _release(SharedFileItem f) async {
    final temp = await ref.read(photoTempDirProvider)();
    await deletePluginCopy(f.path, cacheDir: temp.path);
  }

  bool _checking = false;

  void _showChecking() {
    final messenger = appMessengerKey.currentState;
    if (messenger == null || !mounted) return;
    // Drop anything still showing so the "checking" SnackBar is the current
    // one and _hideChecking hides exactly it.
    messenger
      ..clearSnackBars()
      ..removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(context)!.shareChecking),
      duration: const Duration(minutes: 1),
    ));
    _checking = true;
  }

  void _hideChecking() {
    if (!_checking) return;
    _checking = false;
    appMessengerKey.currentState?.hideCurrentSnackBar();
  }

  void _snack(String text) => appMessengerKey.currentState?.showSnackBar(SnackBar(content: Text(text)));

  bool get _presenting => ref.read(presentActiveProvider);

  /// The busy guards (design spec, "Busy guards"), checked after routing and
  /// before [route] is acted on: false drops the share. A decode or encode
  /// in progress refuses it; Present on screen, or typed text the share
  /// would replace, asks first. A staged file is replaced silently (it can
  /// be picked again), and so is the optimiser's photo.
  Future<bool> _clearToLoad(ShareRoute route) async {
    final l10n = AppLocalizations.of(context)!;
    switch (route) {
      case ToImport():
        if (_busyDecoding('/import', ref.read(importControllerProvider).isDecoding)) return false;
      case ToCamera():
        if (_busyDecoding('/camera', ref.read(cameraControllerProvider).isDecoding)) return false;
      case ToSendText() || ToSendFile() || ToOptimiser():
        if (ref.read(sendControllerProvider).busy) {
          _refuse('/send', l10n.shareWhileEncoding);
          return false;
        }
      case ShowTooLarge() || ShowUnreadable():
        return true;
    }
    if (_presenting) {
      if (!await _confirm(l10n.sharePresentConfirm)) return false;
      // Close Present (its dispose restores the screen) before loading; that
      // answer covers any typed text too.
      rootNavigatorKey.currentState?.popUntil((r) => r.isFirst);
      return true;
    }
    // Only a text share replaces typed text: a file or photo switches Send to
    // File mode and leaves the text in place.
    final send = ref.read(sendControllerProvider);
    if (route is ToSendText && send.mode == SendMode.text && send.text.isNotEmpty) {
      return _confirm(l10n.shareReplaceTextConfirm);
    }
    return true;
  }

  Future<bool> _confirm(String message) async {
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return false;
    final yes = await confirmShareReplace(navContext, message);
    return yes && mounted;
  }

  /// Carries out [route] once the busy guards let it; true when the shared
  /// item was loaded somewhere.
  Future<bool> _act(ShareRoute route) async {
    if (!await _clearToLoad(route)) return false;
    if (!mounted) return false;
    final l10n = AppLocalizations.of(context)!;
    switch (route) {
      case ToSendText(:final text):
        ref.read(sendControllerProvider.notifier).loadShared(SendMode.text, text: text);
        _goTo('/send');
      case ToSendFile(:final name, :final bytes):
        ref.read(sendControllerProvider.notifier).loadShared(SendMode.file, name: name, bytes: bytes);
        _goTo('/send');
      case ToImport(:final name, :final bytes):
        ref.read(importControllerProvider.notifier).loadSharedFile(name, bytes);
        _goTo('/import');
      case ToCamera(:final bytes, :final path, :final result):
        // Not awaited: the state is set at once; only the auto-save follows.
        unawaited(ref.read(cameraControllerProvider.notifier).adoptDetected(bytes, path, result));
        _goTo('/camera');
      case ToOptimiser(:final photo):
        // An optimiser already open just takes the new photo; otherwise it
        // opens above the Send tab, where its Continue/Skip land.
        if (!ref.read(photoOptimiserOpenProvider)) _goTo('/send');
        final navContext = rootNavigatorKey.currentContext;
        if (navContext == null || !navContext.mounted) return false;
        unawaited(openPhotoOptimiser(navContext, ref, photo));
      case ShowTooLarge(:final length):
        const max = CimbarSpec.maxInflatedBytes;
        _refuse(
            '/send',
            length == null
                ? l10n.shareTooLarge(formatSize(l10n, max))
                : l10n.sendFileTooBig(formatSize(l10n, length), formatSize(l10n, max)));
        return false;
      case ShowUnreadable():
        _snack(l10n.shareReadFailed);
        return false;
    }
    return true;
  }

  /// A running decode owns its current file, and swapping it would leave the
  /// old decode writing progress/result for a file that's no longer
  /// selected: when [busy], show the running decode at [location] instead.
  bool _busyDecoding(String location, bool busy) {
    if (!busy) return false;
    _refuse(location, AppLocalizations.of(context)!.shareWhileDecoding);
    return true;
  }

  /// Drops the share with [message], showing [location] — unless Present is
  /// on screen: a share that isn't loaded never stops a presentation.
  void _refuse(String location, String message) {
    if (!_presenting) _goTo(location);
    _snack(message);
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
