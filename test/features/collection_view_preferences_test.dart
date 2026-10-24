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

  test('invalid shared view settings are rejected', () {
    expect(
      () => const CollectionViewPreferences().applySettings(
        const <String, dynamic>{
          CollectionViewPreferences.orderOverviewViewKey: 'yes',
        },
      ),
      throwsFormatException,
    );
    expect(
      () => const CollectionViewPreferences().applySettings(
        const <String, dynamic>{
          CollectionViewPreferences.productOverviewColumnsKey: 'four',
        },
      ),
      throwsFormatException,
    );
  });
}
