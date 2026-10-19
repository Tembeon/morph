import 'package:flutter/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';

/// Any widget as the source of its own menu: tap or hold triggers, a
/// primary action, dividers, hidden and deferred rows.
class MenuSourcePage extends StatelessWidget {
  /// Creates the page.
  const MenuSourcePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const GalleryPage(
      title: 'Menu source',
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
