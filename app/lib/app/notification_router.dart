import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lanka_radar/core/alerts/notifier.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/data/now_repository.dart';
import 'package:lanka_radar/core/links.dart';
import 'package:lanka_radar/features/home/widgets/now_card.dart';
import 'package:lanka_radar/features/item/view/item_page.dart';

/// Opens what a tapped notification is about over the feed: the item, the fuel
/// prices or the holidays.
class NotificationRouter {
  NotificationRouter(this._feed, this._phone);

  final FeedRepository _feed;
  final NowRepository _phone;
  final navigatorKey = GlobalKey<NavigatorState>();

  /// The payload of a notification that started the app, opened once the app
  /// is on screen.
  String? pending;

  Future<void> open(String? payload) async {
    switch (payload) {
      case fuelPayload:
        await _sheet(
          (context, now) => showFuelSheet(context, now, openExternally),
        );
      case holidaysPayload:
        await _sheet(showHolidaysSheet);
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

  Future<void> _sheet(
    Future<void> Function(BuildContext context, NowData now) show,
  ) async {
    final now = await _phone.load(await _feed.watchItems().first);
    final context = navigatorKey.currentState?.overlay?.context;
    if (context != null && context.mounted) {
      unawaited(show(context, now));
    }
  }
}
