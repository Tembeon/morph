import 'package:material_ui/material_ui.dart';
import 'package:morph_example/gallery/gallery.dart';

/// The morph engine under the widgets: a widget becoming a dialog, a page
/// or a sheet, shared elements and a liquid skin.
class EnginePage extends StatelessWidget {
  /// Creates the page.
  const EnginePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const GalleryPage(
      title: 'Morph engine',
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
