import 'package:firecheck/core/geo/polygon_validator.dart' show LngLat;

sealed class ReshapeOp {
  const ReshapeOp({required this.ringIdx, required this.vertexIdx});
  final int ringIdx;
  final int vertexIdx;
}

class Move extends ReshapeOp {
  const Move({
    required super.ringIdx,
    required super.vertexIdx,
    required this.prev,
    required this.next,
  });
  final LngLat prev;
  final LngLat next;
}

class Add extends ReshapeOp {
  const Add({
    required super.ringIdx,
    required super.vertexIdx,
    required this.lngLat,
  });
  final LngLat lngLat;
}

class Remove extends ReshapeOp {
  const Remove({
    required super.ringIdx,
    required super.vertexIdx,
    required this.removed,
  });
  final LngLat removed;
}

/// Whole-shape translation. ringIdx/vertexIdx are sentinel -1 since the op
/// applies uniformly to every vertex of every ring.
class Translate extends ReshapeOp {
  const Translate({required this.dLng, required this.dLat})
      : super(ringIdx: -1, vertexIdx: -1);
  final double dLng;
  final double dLat;
}
