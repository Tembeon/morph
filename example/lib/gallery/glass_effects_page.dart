import 'package:material_ui/material_ui.dart';
import 'package:morph_example/gallery/gallery.dart';

/// Glass effects in every shape, style and tint, interactive or not, with
/// and without a shared glass container.
class GlassEffectsPage extends StatelessWidget {
  /// Creates the page.
  const GlassEffectsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const GalleryPage(
      title: 'Glass effects',
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
