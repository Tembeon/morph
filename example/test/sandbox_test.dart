import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph_example/playground/sandbox.dart';

void main() {
  group('SandboxController', () {
    test('initial scene: 3 pieces and both keyframes preconfigured', () {
      final SandboxController c = SandboxController();
      expect(c.pieces, hasLength(3));
      expect(c.keyA, isNotNull);
      expect(c.keyB, isNotNull);
      expect(c.keyA!.geoms.keys, unorderedEquals(<int>[1, 2, 3]));
      expect(c.keyB!.geoms.keys, unorderedEquals(<int>[1, 2, 3]));
    });

    test('addPiece adds and selects, removeSelected clears links', () {
      final SandboxController c = SandboxController();
      c.addPiece(.circle);
      expect(c.pieces, hasLength(4));
      final int added = c.selectedId!;

      c
        ..select(1)
        ..armLink()
        ..tapPiece(added);
      expect(c.links, hasLength(1));

      c
        ..select(added)
        ..removeSelected();
      expect(c.pieces, hasLength(3));
      expect(c.links, isEmpty);
      expect(c.selectedId, isNull);
    });

    test('the last piece cannot be removed', () {
      final SandboxController c = SandboxController();
      for (int i = 0; i < 5; i++) {
        c
          ..select(c.pieces.first.id)
          ..removeSelected();
      }
      expect(c.pieces, hasLength(1));
    });

    test('linking the same pair again unlinks it', () {
      final SandboxController c = SandboxController();
      c
        ..select(1)
        ..armLink()
        ..tapPiece(2);
      expect(c.links, hasLength(1));
      c
        ..select(2)
        ..armLink()
        ..tapPiece(1);
      expect(c.links, isEmpty);
    });

    test('tap in arming mode does not link a piece to itself', () {
      final SandboxController c = SandboxController();
      c
        ..select(1)
        ..armLink()
        ..tapPiece(1);
      expect(c.links, isEmpty);
      expect(c.selectedId, 1);
    });

    test('drag is clamped to the canvas bounds with slack', () {
      final SandboxController c = SandboxController();
      c.stageSize = const Size(500, 300);
      c.dragBy(3, const Offset(5000, 5000));
      final Rect r = c.pieces.firstWhere((SandboxPiece p) => p.id == 3).rect;
      final double slack = 500 * 0.03;
      expect(r.left, closeTo(500 - r.width + slack, 0.001));
      expect(r.top, closeTo(300 - r.height + slack, 0.001));
    });

    test('resizeSelected keeps the circle square', () {
      final SandboxController c = SandboxController();
      c.select(3);
      c.resizeSelected(width: 90);
      final Rect r = c.selected!.rect;
      expect(r.width, 90);
      expect(r.height, 90);
    });

    test('setKey captures the current scene', () {
      final SandboxController c = SandboxController();
      c.dragBy(1, const Offset(10, 10));
      c.setBlend(33);
      c.setKey('A');
      final SandboxScene a = c.keyA!;
      expect(a.blend, 33);
      expect(a.geoms[1]!.$1, c.pieces.first.rect);
    });

    test('effectiveRadius: stadium and circle derive radius from geometry', () {
      final SandboxPiece stadium = SandboxPiece(
        id: 9,
        kind: .stadium,
        rect: const .fromLTWH(0, 0, 120, 44),
      );
      expect(stadium.effectiveRadius, 22);
      final SandboxPiece box = SandboxPiece(
        id: 10,
        kind: .box,
        rect: const .fromLTWH(0, 0, 120, 44),
        radius: 12,
      );
      expect(box.effectiveRadius, 12);
    });
  });
}
