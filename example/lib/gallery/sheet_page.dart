import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';

/// Sheets the way UIKit presents them: a floating glass sheet at the
/// medium detent that docks edge to edge at the large one, a large-only
/// sheet, an undimmed medium detent over a live page, a sheet with a
/// list that hands its drags to the sheet, and a sheet that zooms out of
/// the button that presents it.
class SheetPage extends StatefulWidget {
  /// Creates the page.
  const SheetPage({super.key});

  @override
  State<SheetPage> createState() => _SheetPageState();
}

class _SheetPageState extends State<SheetPage> {
  String _last = 'Present a sheet';
  int _taps = 0;

  Future<void> _present(
    String name,
    List<MorphSheetDetent> detents, {
    MorphSheetDetent? undimmed,
    bool list = false,
    Object? from,
  }) async {
    final result = await presentMorphSheet<String>(
      context,
      from: from,
      detents: detents,
      largestUndimmedDetent: undimmed,
      grabberVisible: detents.length > 1,
      semanticLabel: name,
      builder: (BuildContext context) => Material(
        type: .transparency,
        child: list ? const _ListSheet() : _PlainSheet(title: name),
      ),
    );
    if (!mounted) return;
    setState(() => _last = result ?? '$name dismissed');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GalleryBar(title: 'Sheets'),
      body: _list(context),
    );
  }

  Widget _list(BuildContext context) {
    return ListView(
      padding: const .all(20),
      children: [
        Text(_last, style: const TextStyle(color: Color(0xFF8E8E93))),
        const SizedBox(height: 16),
        for (final (label, onTap) in <(String, VoidCallback)>[
          (
            'Medium and large',
            () => _present('Medium and large', const [
              MorphSheetDetent.medium,
              MorphSheetDetent.large,
            ]),
          ),
          (
            'Large only',
            () => _present('Large only', const [MorphSheetDetent.large]),
          ),
          (
            'Small, medium, large',
            () => _present('Three detents', const [
              MorphSheetDetent.height(200),
              MorphSheetDetent.medium,
              MorphSheetDetent.large,
            ]),
          ),
          (
            'Undimmed medium',
            () => _present('Undimmed medium', const [
              MorphSheetDetent.medium,
              MorphSheetDetent.large,
            ], undimmed: MorphSheetDetent.medium),
          ),
          (
            'List that drags the sheet',
            () => _present('List', const [
              MorphSheetDetent.medium,
              MorphSheetDetent.large,
            ], list: true),
          ),
        ])
          Padding(
            padding: const .only(bottom: 12),
            child: SizedBox(
              height: 48,
              child: MorphGlassButton(onPressed: onTap, child: Text(label)),
            ),
          ),
        Padding(
          padding: const .only(bottom: 12),
          child: SizedBox(
            height: 48,
            child: MorphTag(
              id: 'zoom',
              shape: const StadiumBorder(),
              child: MorphGlassButton(
                onPressed: () => _present('Zoomed from its button', const [
                  MorphSheetDetent.medium,
                  MorphSheetDetent.large,
                ], from: 'zoom'),
                child: const Text('Zoom from this button'),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Taps on the page behind an undimmed sheet: $_taps',
          style: const TextStyle(color: Color(0xFF8E8E93)),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: MorphGlassButton(
            onPressed: () => setState(() => _taps++),
            child: const Text('Tap me through the sheet'),
          ),
        ),
      ],
    );
  }
}

class _PlainSheet extends StatelessWidget {
  const _PlainSheet({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final sheet = MorphSheet.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const .fromLTRB(24, 32, 24, 16),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: .w700),
            ),
            const SizedBox(height: 16),
            for (final detent in sheet.detents)
              Padding(
                padding: const .only(bottom: 10),
                child: SizedBox(
                  height: 44,
                  child: MorphGlassButton(
                    onPressed: () => sheet.animateTo(detent),
                    child: Text('Go to $detent'),
                  ),
                ),
              ),
            SizedBox(
              height: 44,
              child: MorphGlassButton(
                onPressed: () => Navigator.of(context).pop('Done in $title'),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListSheet extends StatelessWidget {
  const _ListSheet();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: MorphSheet.scrollControllerOf(context),
      padding: const .only(top: 24),
      itemCount: 40,
      itemBuilder: (BuildContext context, int i) => ListTile(
        title: Text('Row $i'),
        onTap: () => Navigator.of(context).pop('Row $i'),
      ),
    );
  }
}
