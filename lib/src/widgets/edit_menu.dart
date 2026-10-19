import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// The edit menu (Cut, Copy, Paste, Select All) of morph's text inputs,
/// or null where none is drawn.
///
/// Where the platform draws its own edit menu - iOS, through
/// `UIEditMenuInteraction` - the inputs show it, as UIKit's text fields
/// do. Elsewhere they show none yet: the iOS 27 edit menu is a glass
/// presentation of its own that morph does not draw.
@internal
EditableTextContextMenuBuilder? morphEditMenuBuilder(BuildContext context) {
  if (!SystemContextMenu.isSupported(context)) return null;
  return (BuildContext context, EditableTextState state) =>
      SystemContextMenu.editableText(editableTextState: state);
}
