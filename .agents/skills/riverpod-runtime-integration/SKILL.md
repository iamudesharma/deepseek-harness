---
name: riverpod-runtime-integration
description: Use when wiring Flutter widgets to runtime state — Riverpod providers over Connection/Session/Workspace/Projection/Interaction runtimes without synthetic fallbacks.
---

# Riverpod Runtime Integration

1. Expose each runtime as a Riverpod provider family/notifier fed by real streams; widgets never own sockets, timers, or polling.
2. useSyncExternalStore semantics map to provider subscriptions: same-store identity, synchronous first frame, dispose-safe.
3. Explicit > implicit: defaults resolve in an explicit resolve(request): Spec step in the owning implementation, never hidden `?? default` inside run().
4. Production synthetic fallback is forbidden; replay/offline adapters only via declared runtimeMode.
5. Test: provider state transitions driven by replayed frames; widget rebuilds without manual refresh.
