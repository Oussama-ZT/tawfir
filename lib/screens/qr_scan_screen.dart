import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// Full-screen camera that returns the text of the first QR code it sees.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  static Future<String?> open(BuildContext context) => Navigator.of(context)
      .push<String>(MaterialPageRoute(builder: (_) => const QrScanScreen(), fullscreenDialog: true));

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final value = code.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        _done = true;
        HapticFeedback.mediumImpact();
        Navigator.pop(context, value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final eco = context.eco;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(tr('Scanner un QR code'), style: context.type.titleLarge?.copyWith(color: Colors.white)),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) => state.torchState == TorchState.unavailable
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: tr('Lampe'),
                    color: Colors.white,
                    icon: Icon(state.torchState == TorchState.on ? Icons.flash_on_rounded : Icons.flash_off_rounded),
                    onPressed: _controller.toggleTorch,
                  ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraError(error),
          ),
          IgnorePointer(child: CustomPaint(painter: _FramePainter(accent: eco.yellow))),
          PositionedDirectional(
            start: 32,
            end: 32,
            bottom: 48 + MediaQuery.paddingOf(context).bottom,
            child: Text(
              tr('Placez le QR code du ticket ou du paiement dans le cadre. Le montant sera rempli pour vous.'),
              textAlign: TextAlign.center,
              style: context.type.bodyMedium?.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError(this.error);

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(denied ? Icons.no_photography_outlined : Icons.videocam_off_outlined, color: Colors.white70, size: 48),
              const SizedBox(height: 16),
              Text(
                denied
                    ? tr("Tawfir n'a pas accès à la caméra. Autorisez-la dans les réglages du téléphone pour scanner un QR code.")
                    : tr("La caméra n'a pas pu démarrer. Saisissez la dépense à la main."),
                textAlign: TextAlign.center,
                style: context.type.bodyLarge?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Fermer'))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dims everything around a centred square and marks its corners.
class _FramePainter extends CustomPainter {
  _FramePainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final side = (size.shortestSide * 0.68).clamp(180.0, 320.0);
    final rect = Rect.fromCenter(center: size.center(Offset.zero).translate(0, -24), width: side, height: side);
    final hole = RRect.fromRectAndRadius(rect, const Radius.circular(28));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(hole)),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    final corner = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const arm = 34.0, r = 28.0;
    final l = rect.left, t = rect.top, rr = rect.right, b = rect.bottom;
    for (final p in [
      Path()..moveTo(l, t + arm)..lineTo(l, t + r)..arcToPoint(Offset(l + r, t), radius: const Radius.circular(r))..lineTo(l + arm, t),
      Path()..moveTo(rr - arm, t)..lineTo(rr - r, t)..arcToPoint(Offset(rr, t + r), radius: const Radius.circular(r))..lineTo(rr, t + arm),
      Path()..moveTo(rr, b - arm)..lineTo(rr, b - r)..arcToPoint(Offset(rr - r, b), radius: const Radius.circular(r))..lineTo(rr - arm, b),
      Path()..moveTo(l + arm, b)..lineTo(l + r, b)..arcToPoint(Offset(l, b - r), radius: const Radius.circular(r))..lineTo(l, b - arm),
    ]) {
      canvas.drawPath(p, corner);
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.accent != accent;
}
