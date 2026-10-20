import 'package:flutter/material.dart';

/// The home screen's tabs, in the bottom bar's order.
enum HomeTab {
  today('Today', Icons.home_outlined, Icons.home),
  prices('Prices', Icons.sell_outlined, Icons.sell),
  notices('Notices', Icons.article_outlined, Icons.article),
  dates('Dates', Icons.event_outlined, Icons.event),
  power('Power', Icons.power_outlined, Icons.power);

  const HomeTab(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// The tab on show, which a tapped notification can change too.
/// The tab a home-screen widget tap asks for, as in `lankaradar://prices`.
HomeTab? tabFromWidget(Uri? link) => link?.scheme == 'lankaradar'
    ? HomeTab.values.where((tab) => tab.name == link!.host).firstOrNull
    : null;

class TabSelection extends ValueNotifier<HomeTab> {
  TabSelection([super.value = HomeTab.today]);
}
