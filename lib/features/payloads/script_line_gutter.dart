import 'package:flutter/rendering.dart' show RenderEditable;
import 'package:material_ui/material_ui.dart';

List<int> scriptLineOffsets(String text) => [
  0,
  for (final newline in RegExp(r'\r\n?|\n').allMatches(text)) newline.end,
];

EditableTextState? findScriptEditable(BuildContext? root) {
  EditableTextState? editable;
  void visit(Element element) {
    if (editable != null) return;
    if (element is StatefulElement && element.state is EditableTextState) {
      editable = element.state as EditableTextState;
    } else {
      element.visitChildren(visit);
    }
  }

  root?.visitChildElements(visit);
  return editable;
}

class ScriptLineGutter extends CustomPainter {
  ScriptLineGutter({
    required this.editor,
    required this.offsets,
    required this.style,
    required this.textScaler,
    required ScrollController scrollController,
  }) : super(repaint: scrollController);

  final GlobalKey editor;
  final List<int> offsets;
  final TextStyle style;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    final context = editor.currentContext;
    final container = context?.findRenderObject();
    final RenderEditable? editable = findScriptEditable(
      context,
    )?.renderEditable;
    if (container is! RenderBox || editable == null || !editable.hasSize) {
      return;
    }

    final topLeft = editable.localToGlobal(Offset.zero);
    final origin = container.globalToLocal(topLeft);
    final visibleTop = editable.getPositionForPoint(topLeft).offset;
    final last = editable
        .getPositionForPoint(topLeft + Offset(0, editable.size.height))
        .offset;
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    );
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        0,
        origin.dy,
        origin.dx - 4,
        origin.dy + editable.size.height,
      ),
    );
    for (
      var i = _lineAt(visibleTop);
      i < offsets.length && offsets[i] <= last;
      i++
    ) {
      final caret = editable.getLocalRectForCaret(
        TextPosition(offset: offsets[i]),
      );
      painter.text = TextSpan(text: '${i + 1}', style: style);
      painter.layout();
      painter.paint(
        canvas,
        Offset(
          origin.dx - 10 - painter.width,
          origin.dy + caret.center.dy - painter.height / 2,
        ),
      );
    }
    canvas.restore();
    painter.dispose();
  }

  int _lineAt(int textOffset) {
    var low = 0;
    var high = offsets.length;
    while (low + 1 < high) {
      final mid = (low + high) ~/ 2;
      if (offsets[mid] <= textOffset) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return low;
  }

  @override
  bool shouldRepaint(ScriptLineGutter oldDelegate) =>
      oldDelegate.offsets != offsets ||
      oldDelegate.style != style ||
      oldDelegate.textScaler != textScaler;
}
