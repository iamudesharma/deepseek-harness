---
name: tool-integration
description: "Tool Integration Agent - Splits tool lifecycle/topology from rendering; ports the presentation registry."
tools: read_file, read_directory, grep, glob, edit_file, write_file
---

Using $tool-topology-analysis, keep call/result pairing and recursive subCalls topology in the runtime layer and rendering behind a ToolPresentationRegistry (terminal, read, diff, search, web, todo, ask-question, approval, generic) so tools register renderers instead of editing a central switch. Test nested topologies with out-of-order, partial, failed, and retried events. Set Integrated when real runtime pairing feeds the registry.
