import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';
import 'package:morph_example/gallery/knobs.dart';

/// The morph engine under the widgets: a widget becoming a dialog, a page
/// or a sheet, shared elements and a liquid skin.
///
/// Every demo here is engine-only (no glass), so the page runs the same on
/// every glass tier and on the web. The page options set a [MorphTheme]
/// over the page (the motion profile and the scrim of every flight) and
/// the skin's blend.
class EnginePage extends StatefulWidget {
  /// Creates the page.
  const EnginePage({super.key});

  @override
  State<EnginePage> createState() => _EnginePageState();
}

const _blue = Color(0xFF007AFF);
const _indigo = Color(0xFF5856D6);
const _orange = Color(0xFFFF9500);

class _EnginePageState extends State<EnginePage> {
  MorphMotion _motion = MorphMotion.liquid;
  double _scrim = MorphTheme.defaultMaxScrimOpacity;
  double _blend = 20;
  bool _linked = false;
  bool _sharing = false;
  String _last = 'Tap a card, a tile or a capsule';
  StreamSubscription<MorphFlightEvent>? _events;

  final _channels = [MorphPieceChannel(), MorphPieceChannel()];
  final _positions = [const Offset(40, 60), const Offset(150, 90)];
  final _drags = [Offset.zero, Offset.zero];
  Size _skinSize = Size.zero;

  static final _motions = {
    MorphMotion.liquid: 'Liquid',
    MorphMotion.glacial: 'Glacial',
    MorphMotion.instant: 'Instant',
  };

  static const _pieceSize = 72.0;

  @override
  void dispose() {
    _events?.cancel();
    for (final channel in _channels) {
      channel.dispose();
    }
    super.dispose();
  }

  void _follow(MorphFlight flight, String name) {
    _events?.cancel();
    _events = flight.events.listen((MorphFlightEvent event) {
      if (mounted) setState(() => _last = '$name: ${event.name}');
    });
  }

  List<Widget> _options(BuildContext context) => [
    MorphListSection(
      header: const Text('MorphTheme'),
      footer: const Text(
        'A MorphTheme over this page sets the motion and the scrim of '
        'every flight launched from it. Glacial is the liquid spring five '
        'times slower; instant is a short critically damped spring.',
      ),
      children: [
        GalleryChoice<MorphMotion>(
          label: 'Motion',
          options: _motions,
          value: _motion,
          onChanged: (MorphMotion m) => setState(() => _motion = m),
        ),
        GallerySliderKnob(
          label: 'Scrim',
          value: _scrim,
          max: 0.8,
          onChanged: (double v) => setState(() => _scrim = v),
        ),
      ],
    ),
    MorphListSection(
      header: const Text('MorphSkin'),
      children: [
        GallerySliderKnob(
          label: 'Blend',
          value: _blend,
          max: 48,
          fractionDigits: 0,
          onChanged: (double v) => setState(() => _blend = v),
        ),
        GalleryToggle(
          label: 'Link the pieces',
          value: _linked,
          onChanged: (bool v) => setState(() => _linked = v),
        ),
      ],
    ),
  ];

  Widget _card(BuildContext context, Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      color: galleryCardColor(context),
      borderRadius: const .all(.circular(MorphListMetrics.cornerRadius)),
    ),
    child: child,
  );

  void _openAlbum(BuildContext context) {
    final card = galleryCardColor(context);
    _follow(
      showMorph(
        context,
        from: 'engine-album',
        target: MorphTargetSpec.dialog(
          width: 340,
          height: 460,
          surfaceColor: card,
        ),
        semanticLabel: 'Album',
        builder: (BuildContext context, MorphFlight flight) =>
            _AlbumDetail(onClose: flight.close),
      ),
      'Album',
    );
  }

  Widget _album(BuildContext context) {
    T? on<T extends Function>(T callback) =>
        GalleryGlassScope.enabled(context, callback);
    return MorphTag(
      id: 'engine-album',
      shape: const RoundedRectangleBorder(
        borderRadius: .all(.circular(MorphListMetrics.cornerRadius)),
      ),
      surfaceColor: galleryCardColor(context),
      child: Builder(
        builder: (BuildContext context) => GestureDetector(
          behavior: .opaque,
          onTap: on(() => _openAlbum(context)),
          child: _card(
            context,
            Padding(
              padding: const .all(12),
              child: Row(
                children: [
                  const MorphSharedElement(
                    id: 'engine-cover',
                    fade: .none,
                    child: _Cover(size: 56),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        const Text(
                          'Liquid Days',
                          style: TextStyle(fontWeight: .w600),
                        ),
                        Text(
                          'Tap: the card becomes a dialog',
                          style: TextStyle(
                            color: gallerySecondaryColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _anchor(BuildContext context) {
    T? on<T extends Function>(T callback) =>
        GalleryGlassScope.enabled(context, callback);
    final card = galleryCardColor(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: MorphAnchor(
        isOpen: _sharing,
        onDismiss: () => setState(() => _sharing = false),
        target: MorphTargetSpec.sheet(heightFactor: 0.4, surfaceColor: card),
        shape: const StadiumBorder(),
        surfaceColor: _blue,
        semanticLabel: 'Share sheet',
        closedBuilder: (BuildContext context) => _Capsule(
          label: 'Share with MorphAnchor',
          color: _blue,
          onTap: on(() => setState(() => _sharing = true)),
        ),
        openBuilder: (BuildContext context, MorphFlight flight) =>
            _ShareSheet(onClose: () => setState(() => _sharing = false)),
      ),
    );
  }

  Widget _routes(BuildContext context) {
    T? on<T extends Function>(T callback) =>
        GalleryGlassScope.enabled(context, callback);
    final background = galleryBackgroundColor(Theme.of(context).brightness);
    final card = galleryCardColor(context);
    return Row(
      children: [
        Expanded(
          child: _Tile(
            id: 'engine-route',
            label: 'showMorphRoute',
            color: _indigo,
            onTap: on((BuildContext context) {
              unawaited(
                showMorphRoute<void>(
                  context,
                  from: 'engine-route',
                  target: MorphTargetSpec.fullscreen(surfaceColor: background),
                  semanticLabel: 'Full screen page',
                  builder: (BuildContext context, MorphFlight flight) =>
                      _FullPage(onClose: flight.close),
                ),
              );
              setState(() => _last = 'Route pushed');
            }),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Tile(
            id: 'engine-page-route',
            label: 'MorphPageRoute',
            color: _orange,
            onTap: on((BuildContext context) {
              unawaited(
                Navigator.of(context).push(
                  MorphPageRoute<void>(
                    from: 'engine-page-route',
                    target: MorphTargetSpec.dialog(
                      width: 320,
                      height: 300,
                      surfaceColor: card,
                    ),
                    motion: _motion,
                    maxScrimOpacity: _scrim,
                    semanticLabel: 'Page route',
                    builder: (BuildContext context, MorphFlight flight) =>
                        _Message(
                          title: 'A Navigator route',
                          body:
                              'MorphPageRoute pushed with Navigator.push: '
                              'Back and predictive back close it like any '
                              'route.',
                          onClose: flight.close,
                        ),
                  ),
                ),
              );
              setState(() => _last = 'Page route pushed');
            }),
          ),
        ),
      ],
    );
  }

  Widget _flights(BuildContext context) {
    T? on<T extends Function>(T callback) =>
        GalleryGlassScope.enabled(context, callback);
    final card = galleryCardColor(context);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        MorphTag(
          id: 'engine-dialog',
          shape: const StadiumBorder(),
          surfaceColor: _indigo,
          child: Builder(
            builder: (BuildContext context) => _Capsule(
              label: 'Dialog flight',
              color: _indigo,
              onTap: on(
                () => _follow(
                  showMorphDialogFlight(
                    context,
                    from: 'engine-dialog',
                    width: 320,
                    fitContent: true,
                    surfaceColor: card,
                    semanticLabel: 'Dialog',
                    builder: (BuildContext context, MorphFlight flight) =>
                        _Message(
                          title: 'showMorphDialogFlight',
                          body:
                              'A dialog as tall as its content, grown out '
                              'of the capsule.',
                          onClose: flight.close,
                        ),
                  ),
                  'Dialog',
                ),
              ),
            ),
          ),
        ),
        MorphTag(
          id: 'engine-sheet',
          shape: const StadiumBorder(),
          surfaceColor: _orange,
          child: Builder(
            builder: (BuildContext context) => _Capsule(
              label: 'Sheet flight',
              color: _orange,
              onTap: on(
                () => _follow(
                  showMorphSheetFlight(
                    context,
                    from: 'engine-sheet',
                    fitContent: true,
                    heightFactor: 0.6,
                    surfaceColor: card,
                    semanticLabel: 'Sheet',
                    builder: (BuildContext context, MorphFlight flight) =>
                        _Message(
                          title: 'showMorphSheetFlight',
                          body:
                              'A sheet at the bottom, as tall as its '
                              'content. Tap outside to close it.',
                          onClose: flight.close,
                        ),
                  ),
                  'Sheet',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _drag(int i, Offset delta) {
    final max = Offset(
      _skinSize.width - _pieceSize,
      _skinSize.height - _pieceSize,
    );
    final at = _positions[i] + _drags[i] + delta;
    final clamped = Offset(
      at.dx.clamp(0, max.dx < 0 ? 0 : max.dx),
      at.dy.clamp(0, max.dy < 0 ? 0 : max.dy),
    );
    _drags[i] = clamped - _positions[i];
    _channels[i].update(offset: _drags[i]);
  }

  void _drop(int i) {
    setState(() {
      _positions[i] += _drags[i];
      _drags[i] = Offset.zero;
    });
    _channels[i].reset();
  }

  Widget _skin(BuildContext context) {
    final enabled = !GalleryGlassScope.of(context, .disabled).disabled;
    final card = galleryCardColor(context);
    return _card(
      context,
      SizedBox(
        height: 220,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            _skinSize = box.biggest;
            final open = Offset(box.maxWidth - _pieceSize - 32, 120);
            return MorphSkin(
              color: _blue,
              blend: _blend,
              elevation: 4,
              links: [
                if (_linked) const MorphLink(from: 'engine-a', to: 'engine-b'),
              ],
              pieces: [
                for (final (i, id) in const [(0, 'engine-a'), (1, 'engine-b')])
                  MorphPiece(
                    id: id,
                    rect: _positions[i] & const Size.square(_pieceSize),
                    radius: _pieceSize / 2,
                    channel: _channels[i],
                    child: GestureDetector(
                      behavior: .opaque,
                      dragStartBehavior: .down,
                      onPanUpdate: enabled
                          ? (DragUpdateDetails d) => _drag(i, d.delta)
                          : null,
                      onPanEnd: enabled ? (DragEndDetails _) => _drop(i) : null,
                      child: const Center(
                        child: Icon(Icons.open_with, color: Colors.white),
                      ),
                    ),
                  ),
                MorphPiece.morphable(
                  id: 'engine-skin-open',
                  rect: open & const Size(_pieceSize, 56),
                  radius: 28,
                  child: Builder(
                    builder: (BuildContext context) => GestureDetector(
                      behavior: .opaque,
                      onTap: enabled
                          ? () => _follow(
                              showMorphDialogFlight(
                                context,
                                from: 'engine-skin-open',
                                width: 300,
                                fitContent: true,
                                surfaceColor: card,
                                semanticLabel: 'Skin dialog',
                                builder:
                                    (BuildContext context, MorphFlight f) =>
                                        _Message(
                                          title: 'Out of the skin',
                                          body:
                                              'A morphable piece is a flight '
                                              'source: the skin draws the '
                                              'neck as it leaves.',
                                          onClose: f.close,
                                        ),
                              ),
                              'Skin',
                            )
                          : null,
                      child: const Center(
                        child: Text(
                          'Open',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: .w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        extensions: [
          for (final extension in theme.extensions.values)
            if (extension is! MorphTheme) extension,
          MorphTheme(motion: _motion, maxScrimOpacity: _scrim),
        ],
      ),
      child: Builder(
        builder: (BuildContext context) => GalleryPage(
          title: 'Morph engine',
          options: _options,
          slivers: [
            SliverPadding(
              padding: const .fromLTRB(16, 0, 16, 120),
              sliver: SliverList.list(
                children: [
                  GalleryCaption(_last),
                  const GalleryCaption('showMorph, MorphTag, shared element'),
                  _album(context),
                  const GalleryCaption('MorphAnchor: a flight as state'),
                  _anchor(context),
                  const GalleryCaption('A card becomes a route'),
                  _routes(context),
                  const GalleryCaption('Dialog and sheet flights'),
                  _flights(context),
                  const GalleryCaption('MorphSkin: drag the pieces together'),
                  _skin(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: .all(.circular(size / 6)),
      gradient: const LinearGradient(
        begin: .topLeft,
        end: .bottomRight,
        colors: [Color(0xFFFF2D55), _indigo],
      ),
    ),
    child: Icon(Icons.music_note, color: Colors.white, size: size / 2),
  );
}

class _Capsule extends StatelessWidget {
  const _Capsule({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    child: GestureDetector(
      behavior: .opaque,
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: color,
          ),
          child: Padding(
            padding: const .symmetric(horizontal: 20, vertical: 12),
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontWeight: .w600),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.id,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String id;
  final String label;
  final Color color;
  final void Function(BuildContext context)? onTap;

  static const _shape = RoundedRectangleBorder(
    borderRadius: .all(.circular(20)),
  );

  @override
  Widget build(BuildContext context) {
    final onTap = this.onTap;
    return MorphTag(
      id: id,
      shape: _shape,
      surfaceColor: color,
      child: Builder(
        builder: (BuildContext context) => GestureDetector(
          behavior: .opaque,
          onTap: onTap == null ? null : () => onTap(context),
          child: DecoratedBox(
            decoration: ShapeDecoration(shape: _shape, color: color),
            child: SizedBox(
              height: 96,
              child: Center(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: .w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerEnd,
    child: _Capsule(label: 'Close', color: _blue, onTap: onClose),
  );
}

class _AlbumDetail extends StatelessWidget {
  const _AlbumDetail({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .all(24),
    child: Column(
      children: [
        const MorphSharedElement(
          id: 'engine-cover',
          fade: .none,
          child: _Cover(size: 200),
        ),
        const SizedBox(height: 20),
        const Text(
          'Liquid Days',
          style: TextStyle(fontSize: 22, fontWeight: .w700),
        ),
        const SizedBox(height: 6),
        Text(
          'The cover is a MorphSharedElement: it travels from the card '
          'instead of fading through.',
          textAlign: .center,
          style: TextStyle(color: gallerySecondaryColor(context)),
        ),
        const Spacer(),
        _CloseButton(onClose: onClose),
      ],
    ),
  );
}

class _ShareSheet extends StatelessWidget {
  const _ShareSheet({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .all(24),
    child: Column(
      crossAxisAlignment: .start,
      children: [
        const Text(
          'MorphAnchor',
          style: TextStyle(fontSize: 22, fontWeight: .w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Open while a bool is true: flip it mid-flight and the spring '
          'turns around with its velocity.',
          style: TextStyle(color: gallerySecondaryColor(context)),
        ),
        const Spacer(),
        _CloseButton(onClose: onClose),
      ],
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    required this.body,
    required this.onClose,
  });

  final String title;
  final String body;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .all(24),
    child: Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: .w700)),
        const SizedBox(height: 8),
        Text(body, style: TextStyle(color: gallerySecondaryColor(context))),
        const SizedBox(height: 20),
        _CloseButton(onClose: onClose),
      ],
    ),
  );
}

class _FullPage extends StatelessWidget {
  const _FullPage({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const .all(24),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          _CloseButton(onClose: onClose),
          const SizedBox(height: 24),
          const Text(
            'A whole page',
            style: TextStyle(fontSize: 34, fontWeight: .w700),
          ),
          const SizedBox(height: 8),
          Text(
            'showMorphRoute pushed a real route whose transition is a '
            'flight: the tile grew into this page, and Back or Close '
            'shrinks it home.',
            style: TextStyle(color: gallerySecondaryColor(context)),
          ),
        ],
      ),
    ),
  );
}
