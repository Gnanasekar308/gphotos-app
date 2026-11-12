import 'package:flutter_test/flutter_test.dart';
import 'package:gphotos/selection/selection_model.dart';

String id(int i) => 'a$i';

void main() {
  group('SelectionModel slide-to-select', () {
    test('drag selects the range and shrinks back when sliding back', () {
      final s = SelectionModel();
      expect(s.startDrag(3, id), isTrue);
      expect(s.ids, {'a3'});
      expect(s.updateDrag(7, id), isTrue);
      expect(s.ids, {'a3', 'a4', 'a5', 'a6', 'a7'});
      expect(s.updateDrag(5, id), isTrue);
      expect(s.ids, {'a3', 'a4', 'a5'});
      expect(s.updateDrag(1, id), isTrue);
      expect(s.ids, {'a1', 'a2', 'a3'});
      expect(s.updateDrag(1, id), isFalse, reason: 'same index = no change, no haptic');
      s.endDrag();
      expect(s.count, 3);
    });

    test('starting on a selected item deselects (slide-to-deselect) and keeps others', () {
      final s = SelectionModel()..selectAll([for (var i = 0; i < 10; i++) id(i)]);
      s.startDrag(4, id);
      s.updateDrag(6, id);
      expect(s.contains('a4') || s.contains('a5') || s.contains('a6'), isFalse);
      expect(s.count, 7);
      s.updateDrag(4, id);
      expect(s.count, 9, reason: 'sliding back restores a5, a6');
      s.endDrag();
    });

    test('a second drag adds to the earlier selection', () {
      final s = SelectionModel();
      s.startDrag(0, id);
      s.updateDrag(1, id);
      s.endDrag();
      s.startDrag(10, id);
      s.updateDrag(11, id);
      s.endDrag();
      expect(s.ids, {'a0', 'a1', 'a10', 'a11'});
    });

    test('toggle and clear', () {
      final s = SelectionModel()..toggle('x');
      expect(s.active, isTrue);
      s.toggle('x');
      expect(s.active, isFalse);
      s.selectAll(['a', 'b']);
      s.clear();
      expect(s.count, 0);
    });
  });

  group('gridIndexAt', () {
    int? at(double x, double y, {double off = 0, bool clamp = false}) => gridIndexAt(
        dx: x, dy: y, scrollOffset: off, width: 300, columns: 3, spacing: 0, childAspectRatio: 1, itemCount: 20, clampToEdges: clamp);

    test('maps points to cells', () {
      expect(at(10, 10), 0);
      expect(at(150, 10), 1);
      expect(at(299, 10), 2);
      expect(at(10, 110), 3);
      expect(at(250, 250), 8);
    });
    test('accounts for scroll offset', () {
      expect(at(10, 10, off: 200), 6);
    });
    test('past the end is null or clamped', () {
      expect(at(10, 2000), isNull);
      expect(at(10, 2000, clamp: true), 19);
    });
    test('with spacing', () {
      final i = gridIndexAt(dx: 105, dy: 5, scrollOffset: 0, width: 304, columns: 3, spacing: 2, childAspectRatio: 1, itemCount: 9);
      expect(i, 1);
    });
  });
}
