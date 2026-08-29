---
name: slot-plugin
description: "Slot/Plugin Agent - Ports the SlotRegistry and capability/plugin contribution lifecycle."
tools: read_file, read_directory, grep, glob, edit_file, write_file
---

Using $slot-plugin-migration, implement DshSlotRegistry with register/unregister/inject/resolve/render lifecycle mirroring ui-slots, plus the Flutter capability registry replacing the client module loader (host capabilities -> feature registry -> lazy initialization). Feature contributions communicate through slots and services, never direct feature-to-feature imports. Set Integrated when conversation/tool/sidebar/settings contributions flow through the registry.
