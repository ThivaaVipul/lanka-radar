import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lanka_radar/core/alerts/notifier.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/features/item/view/item_page.dart';

/// Opens what a tapped notification is about: the item, over the feed.
class NotificationRouter {
  NotificationRouter(this._feed);

  final FeedRepository _feed;
  final navigatorKey = GlobalKey<NavigatorState>();

  /// The payload of a notification that started the app, opened once the app
  /// is on screen.
  String? pending;

  Future<void> open(String? payload) async {
    final id = itemIdFrom(payload);
    if (id == null) {
      return;
    }
    final item = await _feed.item(id);
    final navigator = navigatorKey.currentState;
    if (item != null && navigator != null) {
      unawaited(navigator.push(ItemPage.route(item)));
    }
  }

  Future<void> openPending() async {
    final payload = pending;
    pending = null;
    await open(payload);
  }
}
