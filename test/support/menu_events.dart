import 'package:morph/src/widgets/menu_motion.dart';

/// The rows of the root list whose actions [motion] ran since its events
/// were last drained, in order; drains every event.
List<int> menuSelections(MorphMenuMotion motion) => [
  for (final event in motion.drainEvents())
    if (event case MorphMenuActivated(card: 0, :final index)) index,
];
