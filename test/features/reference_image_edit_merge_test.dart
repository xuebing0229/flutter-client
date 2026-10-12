import 'package:flutter_app/features/orders/domain/queue_order.dart';
import 'package:flutter_app/features/orders/presentation/order_reference_image_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  OrderReferenceImage image(String id) => OrderReferenceImage(
        id: id,
        fileName: '$id.png',
        relativePath: 'assets/order-reference-images/order/$id.png',
        addedAt: DateTime.utc(2026, 10, 11),
        sizeBytes: 123,
      );

  test('local removal preserves an image added remotely during editing', () {
    final a = image('a');
    final b = image('b');

    final merged = mergeReferenceImageEdits(
      baseline: <OrderReferenceImage>[a],
      draft: const <OrderReferenceImage>[],
      current: <OrderReferenceImage>[a, b],
    );

    expect(merged.map((item) => item.id), <String>['b']);
  });

  test('local additions are merged once with current remote images', () {
    final a = image('a');
    final b = image('b');
    final c = image('c');

    final merged = mergeReferenceImageEdits(
      baseline: <OrderReferenceImage>[a],
      draft: <OrderReferenceImage>[a, c],
      current: <OrderReferenceImage>[a, b],
    );

    expect(merged.map((item) => item.id), <String>['a', 'b', 'c']);
  });
}