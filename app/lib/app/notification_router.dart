import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lanka_radar/app/home_tabs.dart';
import 'package:lanka_radar/core/alerts/notifier.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/features/item/view/item_page.dart';

/// Opens what a tapped notification is about: the item over the home screen,
/// or the Prices or Dates tab for fuel prices and holidays. A tap on the
/// home-screen widget opens its tab the same way.
class NotificationRouter {
  NotificationRouter(this._feed, this.tabs);

  final FeedRepository _feed;
  final TabSelection tabs;
  final navigatorKey = GlobalKey<NavigatorState>();

  /// The payload of a notification that started the app, opened once the app
  /// is on screen.
  String? pending;

  Future<void> open(String? payload) async {
    switch (payload) {
      case fuelPayload:
        showTab(HomeTab.prices);
      case holidaysPayload:
        showTab(HomeTab.dates);
      default:
        await _item(itemIdFrom(payload));
    }
  }

  Future<void> openPending() async {
    final payload = pending;
    pending = null;
    await open(payload);
  }

  Future<void> _item(String? id) async {
    final item = id == null ? null : await _feed.item(id);
    final navigator = navigatorKey.currentState;
    if (item != null && navigator != null) {
      unawaited(navigator.push(ItemPage.route(item)));
    }
  }

  void showTab(HomeTab tab) {
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    tabs.value = tab;
  }
}
