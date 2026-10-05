import 'dart:ffi';

final int Function(int) _clockNanoseconds = DynamicLibrary.process()
    .lookupFunction<Uint64 Function(Uint32), int Function(int)>(
      'clock_gettime_nsec_np',
    );

/// The Darwin uptime clock (CLOCK_UPTIME_RAW, mach_absolute_time, stops
/// while the device sleeps), in microseconds.
int labUptimeMicros() => _clockNanoseconds(8) ~/ 1000;

/// The Darwin monotonic clock (CLOCK_MONOTONIC_RAW, counts sleep), in
/// microseconds.
int labMonotonicMicros() => _clockNanoseconds(4) ~/ 1000;
