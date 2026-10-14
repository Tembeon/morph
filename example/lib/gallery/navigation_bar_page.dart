import 'package:material_ui/material_ui.dart';
import 'package:morph_example/gallery/gallery.dart';

/// The navigation bar beyond the scaffold defaults: subtitles, back
/// button modes, bar button badges, and the bars, large title, toolbar
/// and scroll edge effect on their own.
class NavigationBarPage extends StatelessWidget {
  /// Creates the page.
  const NavigationBarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const GalleryPage(
      title: 'Navigation bar',
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
