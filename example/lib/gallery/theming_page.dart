import 'package:material_ui/material_ui.dart';
import 'package:morph_example/gallery/gallery.dart';

/// The widgets theme: an accent over every accented control, per-control
/// looks, high contrast, reduced motion and haptics.
class ThemingPage extends StatelessWidget {
  /// Creates the page.
  const ThemingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const GalleryPage(
      title: 'Theming',
      slivers: [
        SliverPadding(
          padding: .symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: GalleryCaption('This page is being built.'),
          ),
        ),
      ],
    );
  }
}
