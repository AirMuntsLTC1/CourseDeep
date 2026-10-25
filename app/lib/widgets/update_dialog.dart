import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';

class UpdateDialog extends StatefulWidget {
  final String latestVersion;
  final String downloadUrl;
  final String description;

  const UpdateDialog({
    super.key,
    required this.latestVersion,
    required this.downloadUrl,
    required this.description,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  double _progress = 0.0;
  bool _isDownloading = false;
  String _status = 'Ready to download';

  void _startUpdate() {
    setState(() {
      _isDownloading = true;
      _status = 'Connecting...';
    });

    try {
      OtaUpdate()
          .execute(
            widget.downloadUrl,
            destinationFilename: 'CourseDeep_update.apk',
          )
          .listen(
        (OtaEvent event) {
          if (!mounted) return;
          if (event.status == OtaStatus.DOWNLOADING) {
            setState(() {
              _progress = (double.tryParse(event.value ?? '0') ?? 0) / 100;
              _status = 'Downloading: ${(double.tryParse(event.value ?? '0') ?? 0).toStringAsFixed(0)}%';
            });
          } else if (event.status == OtaStatus.INSTALLING) {
            setState(() {
              _status = 'Installing update...';
            });
          } else if (event.status == OtaStatus.ERROR) {
            setState(() {
              _status = 'Error: ${event.value}';
              _isDownloading = false;
            });
          }
        },
      );
    } catch (e) {
      setState(() {
        _status = 'Failed: $e';
        _isDownloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false, // Prevents back button from closing dialog
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.system_update_rounded, color: cs.primary),
            const SizedBox(width: 10),
            const Text('Update Required'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CourseDeep v${widget.latestVersion} is available. You must update to continue using the app.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(widget.description, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 24),
            if (_isDownloading) ...[
              LinearProgressIndicator(value: _progress, minHeight: 8, borderRadius: BorderRadius.circular(4)),
              const SizedBox(height: 8),
              Center(child: Text(_status, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600))),
            ] else ...[
              Text(_status, style: TextStyle(color: cs.error)),
            ]
          ],
        ),
        actions: [
          if (!_isDownloading)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _startUpdate,
              icon: const Icon(Icons.download_rounded),
              label: const Text('Upgrade Now'),
            ),
        ],
      ),
    );
  }
}
