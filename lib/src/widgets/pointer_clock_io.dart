import 'dart:ffi';
import 'dart:io';

final int Function(int)? _clockNanoseconds = Platform.isIOS || Platform.isMacOS
    ? DynamicLibrary.process()
          .lookupFunction<Uint64 Function(Uint32), int Function(int)>(
            'clock_gettime_nsec_np',
          )
    : null;

/// How far the engine's frame clock runs ahead of pointer time stamps.
///
/// On iOS and macOS pointer time stamps count CLOCK_UPTIME_RAW, which
/// stops while the device sleeps, and frames CLOCK_MONOTONIC_RAW, which
/// does not: the offset is the sleep so far. Elsewhere both count the same
/// clock.
Duration? pointerClockOffset() {
  final read = _clockNanoseconds;
  if (read == null) return Duration.zero;
  final monotonic = read(4);
  final uptime = read(8);
  return Duration(microseconds: (monotonic - uptime) ~/ 1000);
}
