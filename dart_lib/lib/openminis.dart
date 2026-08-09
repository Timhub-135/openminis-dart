// Core re-write of OpenMinis in Dart.
//
// Targets **Windows + Android only** (no iOS). The agent core is platform
// agnostic; platform specifics (Docker-Alpine sandbox on Windows, PRoot on
// Android) are supplied as adapters. The on-disk Linux sandbox is represented
// by the `sandbox/` module. See README.md for the full source-mapping table.
library openminis_core;

// ---- models ---------------------------------------------------------------
export 'src/models/chat_message.dart';
export 'src/models/roles.dart';
export 'src/models/token_usage.dart';
export 'src/models/assistant_block.dart';
export 'src/models/attachment.dart';
export 'src/models/minis_url.dart';
export 'src/models/session.dart';
export 'src/models/platform_info.dart';

// ---- store (persistence, cross-platform via sqlite adapter) ---------------
export 'src/store/chat_store.dart';
export 'src/store/message_store.dart';
export 'src/store/persistence_adapter.dart';

// ---- skills & memory ------------------------------------------------------
export 'src/skills/skill_store.dart';
export 'src/skills/soul_store.dart';

// ---- session / integrations (MCP) -------------------------------------------
export 'src/session/mcp_store.dart';

// ---- share-inbox (accept incoming shares → session) -------------------------
export 'src/share/pending_share.dart';

// ---- tools -----------------------------------------------------------------
export 'src/tools/tool.dart';
export 'src/tools/tool_registry.dart';
export 'src/tools/builtin_tools.dart';
export 'src/tools/agent_tools.dart';

// ---- providers (LLM client + SSE streaming) --------------------------------
export 'src/providers/llm_client.dart';
export 'src/providers/llm_message.dart';
export 'src/providers/llm_usage.dart';
export 'src/providers/sse_stream.dart';
export 'src/providers/provider_factory.dart';
export 'src/providers/http_llm_client.dart';
export 'src/providers/provider_config.dart';

// ---- agent loop -------------------------------------------------------------
export 'src/agent/agent_loop.dart';
export 'src/agent/request_budget.dart';
export 'src/agent/tool_preflight.dart';
export 'src/agent/compaction.dart';
export 'src/agent/title_generation.dart';

// ---- sync (cross-platform conversation/history/output sync - new feature) --
export 'src/sync/message_id.dart';
export 'src/sync/sync_config.dart';
export 'src/sync/sync_engine.dart';
export 'src/sync/sync_peer.dart';
export 'src/sync/sync_manifest.dart';
export 'src/sync/sync_message.dart';

// ---- sandbox (Linux shell; Docker Alpine on Windows, Termux on Android) -----
export 'src/sandbox/sandbox.dart';
export 'src/sandbox/sandbox_factory.dart';
export 'src/sandbox/windows_docker_sandbox.dart';
export 'src/sandbox/android_termux_sandbox.dart';
export 'src/sandbox/sandbox_tool.dart';

// ---- server support (EchoLlm default + LAN web chat UI) --------------------
export 'server_support.dart';

// ---- wiki (Markdown file store + LLM distillation) -------------------------
export 'src/wiki/md_file_store.dart';
export 'src/wiki/md_wiki.dart';
