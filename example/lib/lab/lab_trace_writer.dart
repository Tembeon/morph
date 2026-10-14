import 'dart:convert';
import 'dart:io';

/// Buffers telemetry while earlier batches flush, preserving their order.
///
/// IOSink forbids writes until its flush future completes. Capture callbacks
/// keep appending to a separate buffer while that future is pending.
class LabTraceWriter {
  /// Writes JSONL to [sink] without overlapping writes and flushes.
  LabTraceWriter(IOSink sink) : _sink = sink;

  final IOSink _sink;
  final StringBuffer _buffer = StringBuffer();
  Future<void> _pending = Future<void>.value();
  bool _closed = false;

  /// Queues one telemetry row in arrival order.
  void add(Map<String, Object?> row) {
    if (_closed) throw StateError('The capture writer is closed');
    _buffer.writeln(jsonEncode(row));
  }

  /// Persists the current batch after earlier batches have completed.
  Future<void> flush() {
    final text = _buffer.toString();
    _buffer.clear();
    if (text.isEmpty) return _pending;
    _pending = _pending.then((_) async {
      _sink.write(text);
      await _sink.flush();
    });
    return _pending;
  }

  /// Persists all queued rows and then closes the sink.
  Future<void> close() {
    _closed = true;
    return flush().then((_) => _sink.close());
  }
}
