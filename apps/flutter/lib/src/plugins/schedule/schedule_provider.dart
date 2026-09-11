/// Live schedule projection seat — the `useProjection('schedule')` face.
///
/// The host computes schedule records; `live_sync` feeds this provider from
/// follow-snapshot seeds and `session/projection` push frames (the same
/// push model as the todos projection). Empty until the first snapshot or
/// frame lands, matching React's undefined-until-projected behavior.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'schedule_models.dart';

/// Active reminders per session id.
final scheduleProjectionProvider =
    StateProvider.family<List<ScheduleRecord>, String>(
      (ref, _) => const <ScheduleRecord>[],
    );
