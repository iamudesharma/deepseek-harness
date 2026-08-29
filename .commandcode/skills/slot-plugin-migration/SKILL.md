---
name: slot-plugin-migration
description: Use when porting ui-slots or plugin composition — SlotRegistry declarations, dynamic registration, teardown, renderer composition, and the capability registry replacing the module loader.
---

# Slot/Plugin Migration

1. Port DshSlotRegistry: register/unregister/inject/resolve/render with teardown on plugin disposal.
2. Replace `__DSH_BOOT__`/module loading with a Flutter capability registry: host capabilities -> feature registry -> lazy/conditional initialization.
3. Features contribute through slots and services; direct feature-to-feature imports are forbidden.
4. Compose renderers deterministically (documented slot precedence); unknown slots fail loud.
5. Test: registration order independence, disposal removes contributions, conversation/tool/sidebar/settings slots resolve.
