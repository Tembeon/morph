import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/internal/ancestor_clip.dart';

Rect? _referenceLocal(RenderObject node) {
  Rect? result;
  var toAncestor = Matrix4.identity();
  var child = node;
  for (
    var ancestor = child.parent;
    ancestor != null && ancestor.parent != null;
    child = ancestor, ancestor = ancestor.parent
  ) {
    final step = Matrix4.identity();
    ancestor.applyPaintTransform(child, step);
    step.multiply(toAncestor);
    toAncestor = step;
    final clip = paintClipOfAncestor(ancestor, child);
    final m = toAncestor.storage;
    final rectilinear =
        m[1].abs() < 1e-9 &&
        m[4].abs() < 1e-9 &&
        m[3].abs() < 1e-9 &&
        m[7].abs() < 1e-9;
    if (clip != null && rectilinear) {
      final toNode = Matrix4.tryInvert(toAncestor);
      if (toNode != null) {
        final local = MatrixUtils.transformRect(toNode, clip);
        result = result?.intersect(local) ?? local;
      }
    }
  }
  return result;
}

Rect? _referenceScreen(RenderObject node) {
  Rect? result;
  var child = node;
  for (
    var ancestor = child.parent;
    ancestor != null;
    child = ancestor, ancestor = ancestor.parent
  ) {
    final clip = clipOfAncestor(ancestor, child);
    if (clip == null) continue;
    final screenClip = MatrixUtils.transformRect(
      ancestor.getTransformTo(null),
      clip,
    );
    result = result?.intersect(screenClip) ?? screenClip;
  }
  return result;
}

void main() {
  testWidgets('the scratch walks match the allocating reference exactly', (
    tester,
  ) async {
    const target = Key('target');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13.3, 7.7, 0, 0),
          child: Align(
            alignment: Alignment.topLeft,
            child: ClipRect(
              child: SizedBox(
                width: 301.5,
                height: 211.25,
                child: Transform.scale(
                  scale: 1.37,
                  child: Transform.translate(
                    offset: const Offset(-17.1, 9.3),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(5.5),
                        child: ClipRect(
                          clipper: const _Inset(),
                          child: Transform.rotate(
                            angle: 0.2,
                            child: const ClipOval(
                              child: Center(
                                child: SizedBox(
                                  key: target,
                                  width: 40.3,
                                  height: 30.1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final node = tester.renderObject(find.byKey(target));
    final local = localPaintClipAbove(node);
    final screen = screenClipAbove(node);
    expect(local, isNotNull);
    expect(screen, isNotNull);
    expect(local, _referenceLocal(node));
    expect(screen, _referenceScreen(node));
    expect(localPaintClipAbove(node), local);
    expect(screenClipAbove(node), screen);
  });
}

class _Inset extends CustomClipper<Rect> {
  const _Inset();

  @override
  Rect getClip(Size size) => (Offset.zero & size).deflate(3.25);

  @override
  bool shouldReclip(_Inset oldClipper) => false;
}
