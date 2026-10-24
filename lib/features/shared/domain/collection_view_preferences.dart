class CollectionViewPreferences {
  const CollectionViewPreferences({
    this.orderCardView = false,
    this.orderOverviewView = false,
    this.orderOverviewColumns = 3,
    this.productCardView = false,
    this.productOverviewView = false,
    this.productOverviewColumns = 3,
  });

  static const orderCardViewKey = 'orderCardView';
  static const orderOverviewViewKey = 'orderOverviewView';
  static const orderOverviewColumnsKey = 'orderOverviewColumns';
  static const productCardViewKey = 'productCardView';
  static const productOverviewViewKey = 'productOverviewView';
  static const productOverviewColumnsKey = 'productOverviewColumns';

  final bool orderCardView;
  final bool orderOverviewView;
  final int orderOverviewColumns;
  final bool productCardView;
  final bool productOverviewView;
  final int productOverviewColumns;

  Map<String, dynamic> toSettings() => <String, dynamic>{
        orderCardViewKey: orderCardView,
        orderOverviewViewKey: orderOverviewView,
        orderOverviewColumnsKey: orderOverviewColumns,
        productCardViewKey: productCardView,
        productOverviewViewKey: productOverviewView,
        productOverviewColumnsKey: productOverviewColumns,
      };

  CollectionViewPreferences applySettings(Map<String, dynamic> settings) {
    return copyWith(
      orderCardView: _boolValue(
        settings,
        orderCardViewKey,
        orderCardView,
      ),
      orderOverviewView: _boolValue(
        settings,
        orderOverviewViewKey,
        orderOverviewView,
      ),
      orderOverviewColumns: _columnsValue(
        settings,
        orderOverviewColumnsKey,
        orderOverviewColumns,
        '同步排单总概览列数格式无效。',
      ),
      productCardView: _boolValue(
        settings,
        productCardViewKey,
        productCardView,
      ),
      productOverviewView: _boolValue(
        settings,
        productOverviewViewKey,
        productOverviewView,
      ),
      productOverviewColumns: _columnsValue(
        settings,
        productOverviewColumnsKey,
        productOverviewColumns,
        '同步成品总概览列数格式无效。',
      ),
    );
  }

  CollectionViewPreferences copyWith({
    bool? orderCardView,
    bool? orderOverviewView,
    int? orderOverviewColumns,
    bool? productCardView,
    bool? productOverviewView,
    int? productOverviewColumns,
  }) {
    return CollectionViewPreferences(
      orderCardView: orderCardView ?? this.orderCardView,
      orderOverviewView: orderOverviewView ?? this.orderOverviewView,
      orderOverviewColumns:
          _normalizeColumns(orderOverviewColumns ?? this.orderOverviewColumns),
      productCardView: productCardView ?? this.productCardView,
      productOverviewView: productOverviewView ?? this.productOverviewView,
      productOverviewColumns: _normalizeColumns(
        productOverviewColumns ?? this.productOverviewColumns,
      ),
    );
  }

  static bool _boolValue(
    Map<String, dynamic> settings,
    String key,
    bool fallback,
  ) {
    final raw = settings[key];
    if (raw == null) return fallback;
    if (raw is! bool) {
      throw FormatException('同步视图设置 $key 格式无效。');
    }
    return raw;
  }

  static int _columnsValue(
    Map<String, dynamic> settings,
    String key,
    int fallback,
    String invalidMessage,
  ) {
    final raw = settings[key];
    if (raw == null) return fallback;
    if (raw is! num || !raw.isFinite) {
      throw FormatException(invalidMessage);
    }
    return _normalizeColumns(raw.round());
  }

  static int _normalizeColumns(int value) => value < 1 ? 1 : value;

  @override
  bool operator ==(Object other) {
    return other is CollectionViewPreferences &&
        other.orderCardView == orderCardView &&
        other.orderOverviewView == orderOverviewView &&
        other.orderOverviewColumns == orderOverviewColumns &&
        other.productCardView == productCardView &&
        other.productOverviewView == productOverviewView &&
        other.productOverviewColumns == productOverviewColumns;
  }

  @override
  int get hashCode => Object.hash(
        orderCardView,
        orderOverviewView,
        orderOverviewColumns,
        productCardView,
        productOverviewView,
        productOverviewColumns,
      );
}
