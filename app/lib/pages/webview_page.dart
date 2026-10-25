import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../theme/app_theme.dart';

/// In-app browser for source links (tap a source card or a [1] citation).
class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key, required this.url, this.title = ''});
  final String url;
  final String title;
  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _c;
  late String _url;
  String _title = '';
  int _progress = 0;
  bool _error = false;

  static String normalize(String u) {
    final t = u.trim();
    if (t.startsWith('http://') || t.startsWith('https://')) return t;
    return 'https://$t';
  }

  @override
  void initState() {
    super.initState();
    _url = normalize(widget.url);
    _title = widget.title;
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setUserAgent('Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36')
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onPageStarted: (u) {
          if (mounted) {
            setState(() {
              _url = u;
              _error = false;
            });
          }
        },
        onPageFinished: (u) async {
          final t = await _c.getTitle();
          if (mounted) {
            setState(() {
              _progress = 100;
              if (t != null && t.isNotEmpty) _title = t;
            });
          }
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) {
            if (mounted) setState(() => _error = true);
          }
        },
        onNavigationRequest: (r) {
          if (r.url.startsWith('http://') || r.url.startsWith('https://') || r.url.startsWith('about:')) return NavigationDecision.navigate;
          _external(r.url); // app deep links (tiktok://, intent://, mailto:)
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(Uri.parse(_url));
  }

  Future<void> _external(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open this link')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final host = Uri.tryParse(_url)?.host.replaceFirst('www.', '') ?? '';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _c.canGoBack()) {
          _c.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: pal.bg,
        appBar: AppBar(
          backgroundColor: pal.bg,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop()),
          titleSpacing: 0,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_title.isEmpty ? host : _title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.text, fontSize: 15, fontWeight: FontWeight.w600)),
            Row(children: [
              Icon(Icons.lock_outline_rounded, size: 11, color: pal.dim),
              const SizedBox(width: 4),
              Flexible(child: Text(host, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.dim, fontSize: 11.5))),
            ]),
          ]),
          actions: [
            IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh_rounded), onPressed: () => _c.reload()),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'browser') {
                  _external(_url);
                } else if (v == 'copy') {
                  await Clipboard.setData(ClipboardData(text: _url));
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied'), duration: Duration(seconds: 1)));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'browser', child: Text('Open in browser')),
                PopupMenuItem(value: 'copy', child: Text('Copy link')),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2.5),
            child: _progress < 100 ? LinearProgressIndicator(value: _progress / 100, minHeight: 2.5, backgroundColor: Colors.transparent) : const SizedBox(height: 2.5),
          ),
        ),
        body: _error
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.wifi_off_rounded, size: 46, color: pal.dim),
                    const SizedBox(height: 14),
                    Text("This page couldn't load", style: TextStyle(color: pal.text, fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(host, style: TextStyle(color: pal.dim)),
                    const SizedBox(height: 18),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      OutlinedButton(onPressed: () => _c.reload(), child: const Text('Retry')),
                      const SizedBox(width: 10),
                      FilledButton(onPressed: () => _external(_url), child: const Text('Open in browser')),
                    ]),
                  ]),
                ),
              )
            : WebViewWidget(controller: _c),
      ),
    );
  }
}

