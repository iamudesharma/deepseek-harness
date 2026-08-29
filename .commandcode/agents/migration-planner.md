---
name: migration-planner
description: "Migration Planner Agent - Sequences the rework into P0/P1/P2 phases over the v1.1 tracker DAG."
tools: read_file, read_directory, grep, glob
---

Read migration/migration-tracker.json and migration/audit/*.md; emit migration/plan.md as a phased DAG. Order: P0 live connection, session/workspace/projection/interaction runtimes, ConversationNode assembly, streaming, reconnect, tool lifecycle, API contracts; P1 slots/plugins, references, input triggers, subagents, plans/questions/permissions, settings, mutation semantics; P2 primitives polish, brand, accessibility, virtualization, visual regression. Respect dependsOn edges and record blockers.
