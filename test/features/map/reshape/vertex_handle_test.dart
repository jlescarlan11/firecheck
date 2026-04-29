import 'package:firecheck/features/map/reshape/presentation/vertex_handle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('VertexHandle has 44x44 hit area', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(child: VertexHandle()),
      ),
    ));
    final size = tester.getSize(find.byType(VertexHandle));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });
}
