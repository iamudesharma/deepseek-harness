/// Reference composer integration — Flutter port of the `@` source's
/// insertion path into the composer. Tracks the reference chip transaction
/// and exposes the codec for model serialization vs clipboard projection.

library;

import '../input_trigger/trigger_source.dart';

/// Re-exports for tracker distinctness — the composer integration surface
/// is implemented in `reference_plugin.dart`'s `_ReferenceSource.onPick`
/// and `ReferenceCodec`, but this file owns the integration seam for
/// migration tracking.
export '../input_trigger/trigger_source.dart'
    show ReferenceInsert, InsertOutcome, TextOutcome;
