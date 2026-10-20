import 'package:equatable/equatable.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/outages.dart';
import 'package:lanka_radar/features/power/cubit/power_cubit.dart';
import 'package:lanka_radar/features/power/widgets/power_line.dart';

/// The top card's colors.
enum HeroTone {
  /// Nothing to report yet: setting up, or looking for the first time.
  calm,

  /// No cuts at any place.
  clear,

  /// A cut at a place.
  attention,

  /// EDLCare didn't answer.
  trouble,
}

/// What the top card's button does.
enum HeroAction { add, finish, retry }

/// What the Power tab leads with: a short line on how the places stand, a
/// line more when there is something to say, when it last looked, the power
/// line through the places, and at most one action.
final class HeroStatus extends Equatable {
  const HeroStatus({
    required this.tone,
    required this.title,
    this.detail,
    this.checked,
    this.action,
    this.actionLabel,
    this.checking = false,
    this.live = false,
    this.nodes = const [],
    this.line = LineMode.flowing,
  });

  final HeroTone tone;
  final String title;
  final String? detail;

  /// "Checked 10:50", or "Checking..." while it looks.
  final String? checked;
  final HeroAction? action;
  final String? actionLabel;

  /// It is looking now.
  final bool checking;

  /// The last look is recent enough to count as live.
  final bool live;

  /// The places on the power line, and how the line looks.
  final List<LineNode> nodes;
  final LineMode line;

  @override
  List<Object?> get props => [
    tone,
    title,
    detail,
    checked,
    action,
    actionLabel,
    checking,
    live,
    nodes,
    line,
  ];
}

HeroStatus heroStatusFor(PowerState state, {required DateTime now}) {
  final places = state.setup?.places ?? const <Place>[];
  final ready = [
    for (final place in places)
      if (place.ready) place,
  ];
  final power = state.power;
  final checking = state.check == PowerCheck.checking;
  final failed = state.check == PowerCheck.failed;
  final last = power?.checked;
  // When EDLCare fails, the detail already says which check is showing.
  final live =
      !checking &&
      !failed &&
      last != null &&
      now.difference(last) < const Duration(minutes: 15);
  final checked = checking
      ? 'Checking...'
      : failed || last == null
      ? null
      : 'Checked ${_when(last, now)}';
  final nodes = [
    for (final place in places)
      (name: place.name, state: nodeState(state, place)),
  ];
  final line = failed
      ? LineMode.down
      : checking
      ? LineMode.checking
      : LineMode.flowing;
  HeroStatus status(
    HeroTone tone,
    String title, {
    String? detail,
    HeroAction? action,
    String? actionLabel,
  }) => HeroStatus(
    tone: tone,
    title: title,
    detail: detail,
    checked: checked,
    action: action,
    actionLabel: actionLabel,
    checking: checking,
    live: live,
    nodes: nodes,
    line: line,
  );

  if (places.isEmpty) {
    return const HeroStatus(
      tone: HeroTone.calm,
      title: 'Watch for power cuts',
      detail:
          'Add home, work or any place. Power cuts there show here and on '
          'Today.',
      action: HeroAction.add,
      actionLabel: 'Add a place',
    );
  }
  if (ready.isEmpty) {
    final place = places.first;
    return status(
      HeroTone.calm,
      'Finish setting up ${place.name}',
      detail: place.area == null
          ? 'Pick its CEB area and where it is.'
          : 'Set where it is.',
      action: HeroAction.finish,
      actionLabel: 'Finish',
    );
  }
  if (failed) {
    return status(
      HeroTone.trouble,
      "Couldn't reach EDLCare",
      detail: last == null
          ? 'Check the connection and try again.'
          : 'Showing the check from ${_when(last, now)}.',
      action: HeroAction.retry,
      actionLabel: 'Try again',
    );
  }
  if (power == null) {
    return status(HeroTone.calm, 'Checking for power cuts');
  }
  final cut = power.cut;
  if (cut.isEmpty) {
    // Nothing now, but a cut is coming today: that is what to know.
    final today = cutsAhead(
      power,
      before: DateTime(now.year, now.month, now.day + 1),
    ).firstOrNull;
    if (today case (final place, final next)) {
      return status(
        HeroTone.clear,
        '${next.name} at ${place.name} today',
        detail: cutHours(next),
      );
    }
    return status(
      HeroTone.clear,
      ready.length == 1
          ? 'No cuts reported at ${ready.single.name}'
          : 'No cuts reported at your places',
    );
  }
  if (cut.length == 1) {
    final outages = cut.single.outages;
    final count = outages.length;
    return status(
      HeroTone.attention,
      cutPlacesTitle(cut),
      detail:
          '${outageSentence(outages.first)}'
          '${count > 1 ? ', and ${count - 1} more' : ''}',
    );
  }
  return status(HeroTone.attention, cutPlacesTitle(cut));
}

/// How [place] stands on the line.
NodeState nodeState(PowerState state, Place place) => !place.ready
    ? NodeState.unfinished
    : switch (state.cutsAt(place)) {
        null => NodeState.waiting,
        [] => NodeState.clear,
        _ => NodeState.cut,
      };

/// "A breakdown since 09:24", "Maintenance until 17:00" or "Load shedding
/// (Group V) until 20:30".
String outageSentence(Outage outage) {
  final time = outage.time;
  final at = time == null ? null : clock(time.hour * 60 + time.minute);
  return switch (outage.kind) {
    OutageKind.breakdown =>
      at == null ? 'A breakdown' : 'A breakdown since $at',
    OutageKind.maintenance =>
      at == null
          ? outage.reason ?? 'Maintenance'
          : '${outage.reason ?? 'Maintenance'} until $at',
  };
}

/// "11:44" today, "20 Oct, 11:44" on another day.
String _when(DateTime time, DateTime now) {
  final local = time.toLocal();
  final today =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  return today
      ? clock(local.hour * 60 + local.minute)
      : dayTime(local, today: now);
}
