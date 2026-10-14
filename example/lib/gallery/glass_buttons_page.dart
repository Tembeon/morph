import 'package:material_ui/material_ui.dart';
import 'package:morph_example/gallery/gallery.dart';

/// Every glass button constructor, enabled and disabled, with a menu, a
/// minimum size and an appearance.
class GlassButtonsPage extends StatelessWidget {
  /// Creates the page.
  const GlassButtonsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const GalleryPage(
      title: 'Glass buttons',
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
