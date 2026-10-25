import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import '../config.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import 'logo.dart';

/// Blocking update dialog: cannot be dismissed, back button is disabled.
/// Upgrade -> downloads the APK inside this dialog (progress bar) -> at 100% Android's installer opens.
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.info});
  final UpdateInfo info;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

enum _Phase { ready, downloading, installing, error }

class _UpdateDialogState extends State<UpdateDialog> {
  _Phase _phase = _Phase.ready;
  double _progress = 0;
  String _error = '';

  void _start() {
    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
      _error = '';
    });
    try {
      OtaUpdate().execute(widget.info.apkUrl, destinationFilename: 'CourseDeep_update.apk').listen(
        (OtaEvent e) {
          if (!mounted) return;
          switch (e.status) {
            case OtaStatus.DOWNLOADING:
              final v = double.tryParse(e.value ?? '0') ?? 0;
              setState(() {
                _phase = _Phase.downloading;
                _progress = (v / 100).clamp(0.0, 1.0);
              });
              break;
            case OtaStatus.INSTALLING:
              setState(() {
                _phase = _Phase.installing;
                _progress = 1;
              });
              break;
            case OtaStatus.INSTALLATION_DONE:
              break;
            default:
              final permission = e.status == OtaStatus.PERMISSION_NOT_GRANTED_ERROR;
              setState(() {
                _phase = _Phase.error;
                _error = permission
                    ? 'Allow "Install unknown apps" for CourseDeep in Android settings, then tap Try again.'
                    : 'The update could not finish (${e.status.name}). Check your connection and try again.';
              });
          }
        },
        onError: (Object err) {
          if (!mounted) return;
          setState(() {
            _phase = _Phase.error;
            _error = 'Download failed. Check your connection and try again.';
          });
        },
      );
    } catch (_) {
      setState(() {
        _phase = _Phase.error;
        _error = 'Could not start the download. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final cs = Theme.of(context).colorScheme;
    final busy = _phase == _Phase.downloading || _phase == _Phase.installing;
    final pct = (_progress * 100).round();
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: pal.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28), side: BorderSide(color: pal.border)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Center(child: CourseDeepLogo(size: 64)),
            const SizedBox(height: 16),
            Text('Update required',
                textAlign: TextAlign.center, style: TextStyle(color: pal.text, fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Version $kAppVersion  →  ${widget.info.version}',
                textAlign: TextAlign.center, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 130),
              child: SingleChildScrollView(
                child: Text(widget.info.notes, textAlign: TextAlign.center, style: TextStyle(color: pal.dim, height: 1.45, fontSize: 14)),
              ),
            ),
            const SizedBox(height: 20),
            if (busy) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(value: _phase == _Phase.installing ? null : _progress, minHeight: 10),
              ),
              const SizedBox(height: 10),
              Text(
                _phase == _Phase.installing ? 'Download complete - opening the installer…' : 'Downloading update… $pct%',
                textAlign: TextAlign.center,
                style: TextStyle(color: pal.text, fontWeight: FontWeight.w600),
              ),
              if (_phase == _Phase.installing)
                TextButton(onPressed: _start, child: const Text('Installer did not open? Tap to retry')),
            ] else ...[
              if (_phase == _Phase.error)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error, textAlign: TextAlign.center, style: TextStyle(color: cs.error, fontSize: 13.5, height: 1.4)),
                ),
              GestureDetector(
                onTap: _start,
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(gradient: Brand.gradient, borderRadius: BorderRadius.circular(18)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.system_update_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(_phase == _Phase.error ? 'Try again' : 'Upgrade now',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
