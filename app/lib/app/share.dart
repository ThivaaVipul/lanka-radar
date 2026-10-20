import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/sharing.dart';

/// Opens the share sheet with [text]: what a long press on a notice, a price
/// or a power cut does.
void shareText(BuildContext context, String text) =>
    unawaited(context.read<Sharing>().share(text));
