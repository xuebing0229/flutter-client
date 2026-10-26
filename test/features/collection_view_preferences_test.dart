import 'package:flutter_app/features/shared/domain/collection_view_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('collection view preferences round-trip all shared fields', () {
    const source = CollectionViewPreferences(
      orderCardView: true,
      orderOverviewView: true,
      orderOverviewColumns: 5,
      productCardView: false,
      productOverviewView: true,
      productOverviewColumns: 4,
      orderSortMode: 'deadline',
      productSortMode: 'soldCount',
    );

    final restored =
        const CollectionViewPreferences().applySettings(source.toSettings());

    expect(restored, source);
  });

  test('missing collection view settings keep existing values', () {
    const source = CollectionViewPreferences(
      orderCardView: true,
      orderOverviewColumns: 7,
      productOverviewView: true,
    );

    expect(source.applySettings(const <String, dynamic>{}), source);
  });

  test('overview columns are normalized identically for all platforms', () {
    final restored = const CollectionViewPreferences().applySettings(
      const <String, dynamic>{
        CollectionViewPreferences.orderOverviewColumnsKey: 0,
        CollectionViewPreferences.productOverviewColumnsKey: -3,
      },
    );

    expect(restored.orderOverviewColumns, 1);
    expect(restored.productOverviewColumns, 1);
  });

  test('invalid booleans keep current value but invalid columns are rejected', () {
    const source = CollectionViewPreferences(orderOverviewView: true);
    final restored = source.applySettings(
      const <String, dynamic>{
        CollectionViewPreferences.orderOverviewViewKey: 'yes',
      },
    );
    expect(restored.orderOverviewView, isTrue);

    expect(
      () => const CollectionViewPreferences().applySettings(
        const <String, dynamic>{
          CollectionViewPreferences.productOverviewColumnsKey: 'four',
        },
      ),
      throwsFormatException,
    );
  });

  test('legacy order sort and invalid sort values normalize in one place', () {
    final restored = const CollectionViewPreferences().applySettings(
      const <String, dynamic>{
        CollectionViewPreferences.orderSortModeKey: 'remainingTime',
        CollectionViewPreferences.productSortModeKey: 'not-a-mode',
      },
    );

    expect(restored.orderSortMode, 'deadline');
    expect(restored.productSortMode, 'defaultOrder');
  });
}
