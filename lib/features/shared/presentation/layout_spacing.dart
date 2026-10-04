import 'package:flutter/material.dart';

abstract final class AppLayoutSpacing {
  static const double pageBottomExtra = 32;
  static const double pageBottomExtraWithAction = 96;
  static const double tabBottomClearance = 96;
  static const double tabBottomClearanceWithFab = 110;
  static const double bottomSheetExtra = 12;

  static EdgeInsets pageScrollPadding(
    BuildContext context, {
    required double left,
    required double top,
    required double right,
  }) {
    return EdgeInsets.fromLTRB(
      left,
      top,
      right,
      MediaQuery.viewPaddingOf(context).bottom + pageBottomExtra,
    );
  }

  static EdgeInsets pageScrollPaddingWithAction(
    BuildContext context, {
    required double left,
    required double top,
    required double right,
  }) {
    return EdgeInsets.fromLTRB(
      left,
      top,
      right,
      MediaQuery.viewPaddingOf(context).bottom + pageBottomExtraWithAction,
    );
  }

  static EdgeInsets tabScrollPadding({
    required double left,
    required double top,
    required double right,
  }) {
    return EdgeInsets.fromLTRB(
      left,
      top,
      right,
      tabBottomClearance,
    );
  }

  static EdgeInsets tabScrollPaddingWithFab({
    required double left,
    required double top,
    required double right,
  }) {
    return EdgeInsets.fromLTRB(
      left,
      top,
      right,
      tabBottomClearanceWithFab,
    );
  }

  static const EdgeInsets bottomSheetContentPadding =
      EdgeInsets.only(bottom: bottomSheetExtra);

  static const EdgeInsets bulkSheetFooterPadding =
      EdgeInsets.fromLTRB(16, 10, 16, 16);
}
