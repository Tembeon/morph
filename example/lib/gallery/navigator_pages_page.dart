import 'package:material_ui/material_ui.dart';
import 'package:morph_example/gallery/gallery.dart';

/// A navigation stack driven by a list of pages in state: each page
/// slides in, or zooms out of its source.
class NavigatorPagesPage extends StatelessWidget {
  /// Creates the page.
  const NavigatorPagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const GalleryPage(
      title: 'Navigator pages',
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
