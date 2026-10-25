import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'brand.dart';

/// Home screen of a new chat: greeting, capability cards and prompt shortcuts (ChatGPT / DeepSeek style).
class HomeView extends StatelessWidget {
  const HomeView({super.key, required this.onPick, this.name = ''});
  final void Function([String? preset]) onPick;
  final String name;

  static const _cards = <_Card>[
    _Card(Icons.image_outlined, 'Create image', 'Generate a stunning picture', 'Generate an image of a futuristic city at sunset, ultra detailed, cinematic lighting', [Color(0xFFFF6BCB), Color(0xFF7C5CFF)]),
    _Card(Icons.travel_explore_rounded, 'Search the web', 'Live news and facts', "What's the latest tech news today?", [Color(0xFF22D3EE), Color(0xFF4F8CFF)]),
    _Card(Icons.code_rounded, 'Build a file', 'Code, pages, ZIP projects', 'Create a simple HTML landing page and give me the file', [Color(0xFF34D399), Color(0xFF22D3EE)]),
    _Card(Icons.school_outlined, 'Study helper', 'Explain, then quiz me', 'Explain photosynthesis simply, then quiz me', [Color(0xFFFFB347), Color(0xFFFF6B6B)]),
  ];

  static const _chips = [
    'Summarize a PDF I attach',
    'Make a weekly study schedule',
    'Write a Python script that renames files',
    'Draw a logo for my brand',
  ];

  String get _hello {
    final h = DateTime.now().hour;
    final g = h < 5 ? 'Good night' : h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening';
    return name.isEmpty ? g : '$g, $name';
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight - 20),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const AiOrb(size: 64),
            const SizedBox(height: 4),
            ShaderMask(
              shaderCallback: (r) => Brand.gradient.createShader(r),
              child: Text(_hello,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.6)),
            ),
            const SizedBox(height: 6),
            Text('What can I help you with today?', style: TextStyle(color: pal.dim, fontSize: 15)),
            const SizedBox(height: 24),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.35,
              children: [for (final c in _cards) _CardView(card: c, onTap: () => onPick(c.prompt))],
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _chips)
                  ActionChip(
                    label: Text(t, style: TextStyle(color: pal.text, fontSize: 12.5)),
                    backgroundColor: pal.surface,
                    side: BorderSide(color: pal.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    onPressed: () => onPick(t),
                  ),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

class _Card {
  const _Card(this.icon, this.title, this.sub, this.prompt, this.colors);
  final IconData icon;
  final String title, sub, prompt;
  final List<Color> colors;
}

class _CardView extends StatelessWidget {
  const _CardView({required this.card, required this.onTap});
  final _Card card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Material(
      color: pal.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: pal.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: card.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(card.icon, color: Colors.white, size: 21),
            ),
            const Spacer(),
            Text(card.title, style: TextStyle(color: pal.text, fontWeight: FontWeight.w700, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text(card.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.dim, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}
