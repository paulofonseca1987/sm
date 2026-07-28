# Silent Mesh — Delivery Roadmap

Companion to [architecture.md](./architecture.md). Phases are ordered to de-risk the
three scariest bets early (the relay protocol pivot, the model plane, and the Swift
client), and to keep the server testable at every step even though the GUI clients
are removed in Phase 0.

Each phase lists scope and an exit criterion — the observable thing that must work
before moving on.

## Phase 0 — Reshape the fork

Strip what Silent Mesh will never use, while keeping the server green.

- Delete `apps/web`, `apps/desktop`, `apps/mobile`, `apps/marketing`, `infra/relay`,
  `cloud/*` code paths in the server, Clerk/Cloudflare dependencies,
  `packages/tailscale`, `packages/ssh`, and the **Cursor and OpenCode drivers**
  (D15). Keep Claude, Codex, Grok (ACP), and the ACP layer itself.
- Keep `packages/client-runtime` and the Effect RPC surface temporarily — they are
  the only way to exercise the server until the relay protocol exists (a small CLI
  chat harness replaces the web app for dev testing).
- Rebrand: binary `sm`, home dir `~/.sm` (`T3CODE_HOME` → `SM_HOME`), strip
  marketing/update-server scripts, slim CI to server + packages.

**Exit**: headless server builds, starts, and can run an agent thread end-to-end,
driven by the dev CLI harness. CI green on the slimmed matrix.

## Phase 1 — Relay core and identity

The protocol pivot. New subsystems beside the existing engine, not a big-bang swap.

- NIP-01 event store in SQLite (id/pubkey/kind/tags/content/sig + indexes),
  signature verification, `EVENT/REQ/CLOSE/EOSE/OK` WebSocket handling, NIP-42 auth,
  NIP-98 HTTP auth middleware.
- Community bootstrap (`sm init`), invites (`sm invite`), member registry, channel
  entity + membership tables, roles, membership-checked subscriptions (REQ gating
  before registration, Buzz-style).
- Kind registry module (the table in architecture.md §5) with typed Effect Schema
  codecs per kind.
- Hash-chained audit log.
- Admin CLI grows: members, roles, channels, ACL set/list, backup/restore.
- Bridge: existing orchestration projections re-emitted as relay events signed by
  the server key, so relay subscribers observe real agent activity from day one.

**Exit**: two `nak`-style Nostr clients (or scripted test clients) with different
keys can auth, join channels per role, exchange kind-9 messages, and are correctly
denied on non-member channels. Audit chain verifies.

## Phase 2 — Channels, threads, agents as members, git

Silent Mesh's domain model becomes real.

- Channel = folder = repo: channel creation provisions `repos/<channelId>.git`;
  git smart-HTTP endpoints with NIP-98 auth; pre-receive policy hook enforcing roles
  + per-folder write ACLs; pushes emit NIP-34-flavored events into the stream.
- Work threads as event kinds mapped onto the existing Thread machinery: create
  thread from a stream message, thread turns/activities/approvals/proposed-plans/
  checkpoints all become 47xxx events; worktrees re-parented to channel repos.
- Agents as Bot members: keypair provisioning in the secret store, per-channel
  membership, @mention dispatch in streams (adapt `ProviderRuntimeIngestion` /
  `ProviderCommandReactor`), one in-flight prompt per channel stream (Buzz rule),
  ephemeral-event token streaming.
- Approvals: supervised-mode tool approvals become signed 46011-style events, so
  *who approved what* is provable.
- Blossom blob store endpoints.
- Retire the Effect RPC surface + `packages/client-runtime` once the relay covers
  everything the dev harness needs.

**Exit**: from two test clients — a human posts `@claude fix the parser` in a
channel stream; the agent (its own key) replies in a thread, edits the channel repo
in a worktree, a checkpoint event appears, the human approves a tool call, the
result is pushed, and the push event shows in the stream. A non-member sees none
of it; a member with read-only ACL on that folder gets their push rejected.

## Phase 3 — Model plane: gateway, local models, native harness

Silent Mesh's own identity (architecture.md §9). Runs on the relay + agent
foundations of Phase 2; the Swift client (Phase 4) can start in parallel once the
Phase 2 protocol has stabilized.

- **Model gateway**: internal OpenAI- and Anthropic-compatible endpoints; router;
  per-request attribution `(user, agent, channel, thread, model, backend)` with
  token accounting tables + usage projections; owner-settable per-user budgets.
- **Local serving on the 2× RTX 4060 8 GB GPUs**: stack spike (llama.cpp server vs
  vLLM vs Ollama), model lineup selection within the ~7–14B Q4–Q8 envelope
  (+ embeddings), weights under `models/`, health/VRAM monitoring.
- **Remote inference provider**: single provider abstraction, server-held key,
  routed and metered through the gateway.
- **Vendor proxying**: route Claude/Codex/Grok CLI traffic through the gateway via
  base-URL overrides where auth allows; fall back to harness-reported usage for
  subscription-auth setups (flagged as self-reported in metering).
- **Native harness v1**: Effect-based agent loop against the gateway; tool layer
  from the existing workspace/git/MCP toolkits; per-user agent profiles (persona,
  model route, tool allowlist, limits) bounded by owner policy; harness instances
  as Bot members with their own keypairs.
- **Airgapped channels (D18)**: channel policy flag restricting agents to
  local-backend models; enforced in the gateway router.

**Exit**: a member chats with their personalized harness agent in an airgapped
channel backed by a local model — with the server's WAN disconnected — and the full
loop works (thread, tools, checkpoint, push). Reconnect WAN: the same profile
re-routed to the remote provider works identically. The owner's usage query shows
per-user token totals broken down by backend, including vendor-harness usage.

## Phase 4 — Swift macOS client MVP

Start the client once the Phase 2 protocol has stabilized against test clients
(overlappable with Phase 3). Vault and app lock are foundations here, not
retrofits. macOS 14+ floor (D19).

- Packages: `MeshProtocol` (NIP-01/10/42/98, kind codecs), `MeshVault` (encrypted
  store — spike: APFS encrypted sparse bundle vs file-level AES-GCM; SE-resident
  master key, biometric/PIN-gated unlock), app-lock flow.
- Onboarding: enter server URL (VPN assumed) + invite code → local keypair
  generation → enrolled.
- UI: channel sidebar with badges, channel stream + threads, agent interaction
  (streaming, approvals, per-turn diffs), basic file browser reading via relay/git,
  markdown/image viewing, owner admin screens (members, roles, channel ACLs, agent
  profiles, usage dashboards).

**Exit**: a two-person team + one agent runs a real working session entirely from
the macOS app; the app relaunches locked and requires Touch ID/PIN; the vault is
unreadable outside the app.

## Phase 5 — Sync, offline, client local models

- `MeshSync`: libgit2 clone/pull/push of all member channels into the vault;
  background sync; conflict surfacing as ordinary merges in UI.
- Offline outbox: signed events queued locally (valid because client-signed),
  replayed on reconnect; offline edits are local commits.
- `MeshIntelligence` (D19): bundled open models — whisper.cpp voice-to-text, a
  llama.cpp/MLX small model for offline summarize/translate. Weights fetched on
  first run from the owner's server blob store (no third party) into the vault;
  quality spike picks the lineup.

**Exit**: pull the network cable — browse, edit, record-and-transcribe a voice
note, summarize a doc; reconnect — commits push, events replay, conflicts (one
seeded deliberately) resolve through the UI.

## Phase 6 — Artifact viewer and durable comments

- Sandboxed WKWebView HTML rendering (strict CSP, no network), selection → robust
  anchors (text-quote + position), anchored comment events bound to
  `(channel, path, blob hash, anchor)`, re-anchoring on file change.
- Regenerate-with-AI: selection/comment escalates to a work thread carrying the
  anchor context; resulting diff returns as a proposal in the channel.
- Server-side headless Chromium for the agent MCP preview toolkit (agents verify
  their own artifacts again).

**Exit**: agent produces an HTML report; a member selects a chart, comments, and
requests regeneration; a second member sees the anchored comment on the exact
selection; the regenerated artifact lands as a new version with the comment
history intact.

## Phase 7 — Hardening and iOS

- Key lifecycle: multi-device key transfer (QR/manual), rotation and revocation
  story, server backup/restore drills, LUKS + deployment guide.
- Read-hiding within a channel via filtered mirror repos (the v1 boundary lift), if
  still wanted once channel-granularity has been lived with.
- Harness customization surface expansion (skills/plugins), informed by v1 usage.
- iOS client reusing `MeshProtocol`/`MeshVault`/`MeshSync`/`MeshIntelligence`
  (Face ID, Data Protection classes, background sync constraints).

## Standing risks

| Risk | Mitigation |
|---|---|
| Effect v4 is beta; upstream T3 moves fast | pin versions at fork point; cherry-pick upstream server fixes deliberately, not continuously |
| Full relay compatibility is the maximal-cost Nostr option | Phases 1–2 build it beside the working engine; test clients validate before any GUI depends on it |
| No GUI between Phase 0 and Phase 4 ("dark period") | accepted by decision D10; CLI harness + scripted clients keep every phase demonstrable |
| 16 GB total VRAM caps local model quality (~7–14B class) | airgapped channels knowingly trade capability for privacy; remote provider and vendor harnesses cover the high end; GPU upgrade changes nothing architecturally |
| Proxying vendor subscription (OAuth) auth through the gateway may be fragile | metering falls back to harness-reported usage, flagged as self-reported |
| Own-harness scope creep | v1 = one agent loop + existing tools + per-user profiles; plugins/skills deferred to Phase 7 |
| Git can't hide paths within one repo | scoped out of v1 explicitly (architecture §6); channel granularity is the read boundary, filtered mirrors in Phase 7 |
| secp256k1 keys can't live in the Secure Enclave | SE-wrapped master key + Keychain biometric access control (architecture §10); documented rather than discovered late |
| Cloud egress (vendor APIs, remote provider) | per-channel Bot membership + airgapped channel flag from v1; both paths metered |
| Swift client is a full rebuild by a small team | protocol-first sequencing; shared packages sized for iOS reuse; MVP scope cut to one working team session |

## Open questions (deliberately deferred)

1. Remote inference provider choice (OpenRouter / Together / Fireworks / direct)
   and initial hosted-model lineup.
2. Local serving stack (llama.cpp server / vLLM / Ollama) and model lineup for the
   2× 8 GB GPUs — Phase 3 spike.
3. Metering policy detail: budgets vs reporting-only, per-user vs per-channel caps,
   what the non-owner members get to see.
4. Harness customization surface for v1 (persona + model route + tool allowlist is
   the baseline; anything more waits for Phase 7).
5. Vault implementation (APFS encrypted sparse bundle vs file-level crypto) —
   Phase 4 spike.
6. Client local-model lineup (which whisper size, which small LLM) — Phase 5
   quality spike.
7. Forum-style channels (Buzz kinds 45001/45003) — not in v1.
