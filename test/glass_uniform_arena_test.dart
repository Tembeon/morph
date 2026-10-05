import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/internal/flutter_gpu_geometry_renderer_native.dart';

final class _Block {
  _Block(this.length);

  final int length;
  final List<(int, int)> writes = [];
}

MorphUniformArena<_Block> _arena(List<_Block> allocated, {int slots = 32}) =>
    MorphUniformArena<_Block>(
      blockLength: 2368 * slots,
      alignment: 256,
      allocate: (int length) {
        final block = _Block(length);
        allocated.add(block);
        return block;
      },
      write: (_Block block, ByteData data, int offset) {
        if (offset < 0 || offset + data.lengthInBytes > block.length) {
          return false;
        }
        block.writes.add((offset, data.lengthInBytes));
        return true;
      },
    );

void main() {
  test('a frame of any number of geometry passes gets all its uniforms', () {
    final allocated = <_Block>[];
    final arena = _arena(allocated);
    final data = ByteData(2352);
    final placed = <({_Block buffer, int offset})>[];
    for (var i = 0; i < 200; i++) {
      placed.add(arena.emplace(data));
    }
    for (final (:buffer, :offset) in placed) {
      expect(offset % 256, 0);
      expect(offset + data.lengthInBytes, lessThanOrEqualTo(buffer.length));
    }
    for (final block in allocated) {
      final writes = [...block.writes];
      writes.sort((a, b) => a.$1.compareTo(b.$1));
      for (var i = 1; i < writes.length; i++) {
        expect(writes[i].$1, greaterThanOrEqualTo(writes[i - 1].$1 + 2352));
      }
    }
    expect(allocated.length, greaterThan(1));
  });

  test('later frames reuse the blocks a frame slot already holds', () {
    final allocated = <_Block>[];
    final arena = _arena(allocated);
    final data = ByteData(2352);
    for (var frame = 0; frame < 40; frame++) {
      arena.nextFrame();
      for (var i = 0; i < 100; i++) {
        arena.emplace(data);
      }
    }
    final perFrame = allocated.length ~/ arena.frameCount;
    expect(allocated.length, arena.frameCount * perFrame);
    expect(arena.blockCount, allocated.length);
    expect(perFrame, lessThanOrEqualTo(4));
  });

  test('data longer than a block gets a block of its own', () {
    final allocated = <_Block>[];
    final arena = _arena(allocated, slots: 1);
    final placed = arena.emplace(ByteData(4096));
    expect(placed.offset, 0);
    expect(placed.buffer.length, 4096);
  });

  test('a failed write is an error, never a silent view', () {
    final arena = MorphUniformArena<_Block>(
      blockLength: 1024,
      alignment: 256,
      allocate: _Block.new,
      write: (_Block block, ByteData data, int offset) => false,
    );
    expect(() => arena.emplace(ByteData(16)), throwsStateError);
  });
}
