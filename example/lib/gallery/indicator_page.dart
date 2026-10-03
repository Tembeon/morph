import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';

/// The progress view, the activity indicator and the page control:
/// animated progress changes, the eight-spoke spinner in both sizes, and
/// page dots, plain, on their platter and with a timed progress. Start
/// runs the spinners and the timed page control.
class IndicatorPage extends StatefulWidget {
  /// Creates the page.
  const IndicatorPage({super.key});

  @override
  State<IndicatorPage> createState() => _IndicatorPageState();
}

class _IndicatorPageState extends State<IndicatorPage>
    with SingleTickerProviderStateMixin<IndicatorPage> {
  double _progress = 0.2;
  bool _spinning = false;
  int _page = 0;
  int _timedPage = 0;
  double _timed = 0;
  Duration _pageStart = Duration.zero;
  late final Ticker _timer = createTicker(_tick);

  static const _pageDuration = Duration(seconds: 3);

  @override
  void dispose() {
    _timer.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _spinning = !_spinning);
    if (_spinning) {
      _pageStart = Duration.zero;
      _timer.start();
    } else {
      _timer.stop();
    }
  }

  void _tick(Duration elapsed) {
    var f =
        (elapsed - _pageStart).inMicroseconds / _pageDuration.inMicroseconds;
    if (f >= 1) {
      _pageStart = elapsed;
      f = 0;
      _timedPage = (_timedPage + 1) % 5;
    }
    setState(() => _timed = f);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GalleryBar(title: 'Indicators'),
      body: ListView(
        padding: const .all(20),
        children: [
          _Caption('Progress: ${(_progress * 100).round()}%'),
          MorphProgressView(value: _progress, semanticLabel: 'Download'),
          const SizedBox(height: 20),
          MorphProgressView(
            value: _progress,
            viewStyle: MorphProgressViewStyle.bar,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final v in const [0.0, 0.05, 0.3, 0.8, 1.0])
                SizedBox(
                  width: 72,
                  height: 40,
                  child: MorphGlassButton(
                    padding: .zero,
                    onPressed: () => setState(() => _progress = v),
                    child: Text('${(v * 100).round()}%'),
                  ),
                ),
            ],
          ),
          _Caption('Page control: page ${_page + 1} of 5'),
          Center(
            child: MorphPageControl(
              count: 5,
              page: _page,
              semanticLabel: 'Pages',
              onChanged: (int p) => setState(() => _page = p),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: MorphPageControl(
              count: 5,
              page: _page,
              background: MorphPageControlBackground.prominent,
              onChanged: (int p) => setState(() => _page = p),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: ColoredBox(
              color: const Color(0xFF3A3A3C),
              child: Padding(
                padding: const .all(8),
                child: MorphPageControl(
                  count: 5,
                  page: _timedPage,
                  progress: _timed,
                  onChanged: (int p) => setState(() => _timedPage = p),
                ),
              ),
            ),
          ),
          const _Caption('Activity indicators'),
          Row(
            children: [
              MorphActivityIndicator(animating: _spinning),
              const SizedBox(width: 32),
              MorphActivityIndicator(
                animating: _spinning,
                size: MorphActivityIndicatorSize.large,
              ),
              const SizedBox(width: 32),
              SizedBox(
                width: 100,
                height: 40,
                child: MorphGlassButton(
                  padding: .zero,
                  onPressed: _toggle,
                  child: Text(_spinning ? 'Stop' : 'Start'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const .only(left: 4, bottom: 10, top: 24),
      child: Text(text, style: const TextStyle(color: Color(0xFF8E8E93))),
    );
  }
}
