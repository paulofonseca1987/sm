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
- **Thread forking (D27)**: any member clones a thread at head or at any
  checkpoint → new branch + worktree + thread with a fork event referencing the
  origin; inherited conversation rendered by reference (agent gets it as context),
  never copied or re-signed; sibling variations listed against the origin; merge
  back via the normal git flow.
- **Thread lifecycle (D28)**: settled / snoozed / archived as signed lifecycle
  events (archive graduates from T3-nightly experimental to core); archived
  threads drop from default views, stay searchable; losing forks auto-archive.
- **Personal channels + promotion (D29/D30)**: personal channel auto-provisioned
  at enrollment (tier picked during onboarding, more creatable at will); promotion
  transplants a private thread's branch state onto the target channel's repo as a
  new thread + worktree with a promotion event; private conversation never
  crosses. The **Privacy Gate scaffold is mandatory from day one** for
  privacy-weakening movements: explicit review/confirm step with a
  member-written summary and deterministic secret scanning of outgoing files —
  local-model summarization and redaction suggestions arrive in Phase 3, the
  offline client variant in Phase 5.
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
result is pushed, and the push event shows in the stream. A second member forks
that thread at an earlier checkpoint, drives a competing variation in its own
worktree without disturbing the original, then archives the losing variation. A
member promotes a thread from their personal channel into the team channel —
files and summary arrive, the private conversation doesn't — and a teammate forks
the promoted thread. A non-member sees none of it; a member with read-only ACL on
that folder gets their push rejected.

## Phase 3 — Model plane: tiers, gateway, copilot, native harness

Silent Mesh's own identity (architecture.md §9). Runs on the relay + agent
foundations of Phase 2; the Swift client (Phase 4) can start in parallel once the
Phase 2 protocol has stabilized.

- **Model gateway + privacy tiers (D21/D24/D26)**: internal OpenAI- and
  Anthropic-compatible endpoints; tier-aware router (owned / private / open);
  channel privacy policy enforcement (a route below the channel's tier is refused
  at the gateway, not by convention); tier immutable at creation, with the
  **owner-only channel-clone operation** (repo forked with history, membership
  copied, fresh stream with provenance link, jobs never migrate) as the only
  re-tiering path; per-request attribution
  `(user, agent, channel, thread, model, tier, backend)` with token accounting
  tables + usage projections; owner-settable per-user budgets.
- **Local serving on the 2× RTX 4060 8 GB GPUs**: stack spike (llama.cpp server vs
  vLLM vs Ollama), model lineup selection within the ~7–14B Q4–Q8 envelope
  (+ embeddings, + a server-side whisper for voice jobs arriving from clients),
  weights under `models/`, health/VRAM monitoring.
- **TEE inference provider (D22)**: provider spike (attestation model, GPU TEE
  maturity, model lineup); gateway integration = verify attestation evidence, then
  send; metered like every other backend.
- **Per-user vendor subscriptions (D23)**: member-linked Claude/Codex/Grok logins
  via each CLI's native auth flow, stored per member in the secret store with
  strict isolation; agents operated-for a user run only under that user's
  subscription; usage metered from harness-reported counts (self-reported flag).
- **Native harness v1**: Effect-based agent loop against the gateway; tool layer
  from the existing workspace/git/MCP toolkits; per-user agent profiles (persona,
  tier/model route, tool allowlist, limits) bounded by owner policy; harness
  instances as Bot members with their own keypairs.
- **Prompt Copilot (server-side) + inference queue (D25)**: copilot loop on the
  server GPUs — file-context retrieval within ACL scope, prompt refinement,
  clarifying-question dialogue, route proposal (complexity × channel policy × user
  preference); inference-job events (queued/dispatched/completed kinds); dispatch
  creates or continues work threads through normal orchestration.
- **Privacy Gate assist (D30)**: server-GPU local models generate the promotion
  summary from the private conversation and suggest redaction spans over
  everything that would cross (paired with the deterministic scanners from
  Phase 2); user-approved obfuscations applied to the outgoing copy only; gate
  inference is pinned to the owned tier in the router — it can never route
  remotely regardless of profile or channel settings.
- **Content Seals (D31)**: owner-managed seal registry (raw values encrypted in
  the secret store); sealing triggers a **workspace-wide sweep** (a tokenizing
  commit per channel repo + artifact scan); delivery-time redaction envelopes for
  signed events below the seal's tier; **ingestion guards** — pre-receive and
  event-ingestion scanning that auto-tokenizes new occurrences (server-side
  matching only; raw literals never distributed); tier-checked token resolution
  in relay rendering and gateway inference paths; outbound scrubbing of sealed
  literals below their tier; gate integration as mandatory, non-overridable
  redactions; a pre-receive lint rejecting malformed or duplicated seal tokens.

**Exit**: in an `owned-only` channel with the server's WAN disconnected, a member
speaks a rough request; the copilot (server GPUs) refines it, asks one clarifying
question, and queues the job; the harness agent completes it on a local model
(thread, tools, checkpoint, push all work). Reconnect WAN: the same request in a
`private` channel routes to the TEE provider after attestation, and in an `open`
channel to the member's own Claude subscription. A route below a channel's tier is
refused by the gateway; changing a channel's tier is impossible, and the owner
clones an `owned-only` channel into an `open` one (repo forked, fresh stream)
while a non-owner's clone attempt is refused. Promoting a private thread into an
`open` channel triggers the Privacy Gate: a locally generated summary, flagged
spans (model + scanners), and per-item obfuscation approval — with the gate's own
inference verifiably never leaving owned hardware. A value sealed at `private`
resolves inside the TEE-routed request, arrives scrubbed in any vendor-routed
request, and renders as a placeholder in the `open` channel; sealing it sweeps
every existing occurrence workspace-wide, and pasting the raw value into an
`open` channel's stream afterwards is caught at ingestion and auto-tokenized.
The owner's usage query shows per-user totals broken down by tier and backend.

## Phase 4 — Swift macOS client MVP

Start the client once the Phase 2 protocol has stabilized against test clients
(overlappable with Phase 3). Vault and app lock are foundations here, not
retrofits. macOS 14+ floor (D19).

- Packages: `MeshProtocol` (NIP-01/10/42/98, kind codecs), `MeshVault` (encrypted
  store — spike: APFS encrypted sparse bundle vs file-level AES-GCM; SE-resident
  master key, biometric/PIN-gated unlock), app-lock flow.
- Onboarding: enter server URL (VPN assumed) + invite code → local keypair
  generation → enrolled.
- UI: channel sidebar with badges and the personal space, channel stream +
  threads, agent interaction (streaming, approvals, per-turn diffs),
  fork/archive/promote affordances on threads, basic file browser reading via
  relay/git, markdown/image viewing, owner admin screens (members, roles, channel
  ACLs, agent profiles, usage dashboards).

**Exit**: a two-person team + one agent runs a real working session entirely from
the macOS app; the app relaunches locked and requires Touch ID/PIN; the vault is
unreadable outside the app.

## Phase 5 — Sync, offline, client local models

- `MeshSync`: libgit2 clone/pull/push of all member channels into the vault;
  background sync; conflict surfacing as ordinary merges in UI.
- Offline outbox: signed events queued locally (valid because client-signed),
  replayed on reconnect; offline edits are local commits.
- `MeshIntelligence` (D19/D25/D30): bundled open models — whisper.cpp
  voice-to-text, a llama.cpp/MLX small model for offline summarize/translate —
  plus the **client-side Prompt Copilot**: push-to-talk intent capture, local
  refinement and clarifying questions against synced files, jobs signed into the
  offline outbox (client-local is the only offline mode; online, the copilot can
  ride the server GPUs instead) — plus the **offline Privacy Gate**: when
  promoting while offline, summary and redaction suggestions run client-local and
  the reviewed promotion queues in the outbox. Weights fetched on first run from
  the owner's server blob store (no third party) into the vault; quality spike
  picks the lineup.

**Exit**: pull the network cable — browse, edit, record-and-transcribe a voice
note, summarize a doc, and speak a work request that the copilot refines into a
queued job; reconnect — commits push, events replay, the queued job dispatches to
the right tier, and conflicts (one seeded deliberately) resolve through the UI.

## Phase 6 — Artifact viewer and durable comments

- Sandboxed WKWebView HTML rendering (strict CSP, no network), selection → robust
  anchors (text-quote + position), anchored comment events bound to
  `(channel, path, blob hash, anchor)`, re-anchoring on file change.
- Regenerate-with-AI: selection/comment escalates to a work thread carrying the
  anchor context; resulting diff returns as a proposal in the channel.
- Seal-from-selection (D31): the owner's selection menu gains "seal at tier…";
  seal-aware rendering in the viewer and file browser (resolved vs placeholder by
  viewing channel's tier); seal registry management UI.
- Server-side headless Chromium for the agent MCP preview toolkit (agents verify
  their own artifacts again).

**Exit**: agent produces an HTML report; a member selects a chart, comments, and
requests regeneration; a second member sees the anchored comment on the exact
selection; the regenerated artifact lands as a new version with the comment
history intact. The owner seals a figure in the report at `private`; in an `open`
clone of the channel the same region renders as a placeholder, and a vendor-routed
regeneration request goes out scrubbed.

## Phase 7 — Hardening and iOS

- Key lifecycle: multi-device key transfer (QR/manual), rotation and revocation
  story, server backup/restore drills, LUKS + deployment guide.
- **Deep seal (D32)**: retroactive history purge for leak correction — filter
  pass across affected repos + blob store, old→new SHA remap table (checkpoints,
  fork points, and event references resolve through it), forced client re-sync
  with vault purge of stale objects, in-flight worktree rebase, blast-radius
  confirmation UI, and a rehearsed drill (seed a leak, deep-seal it, verify every
  surface).
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
| 16 GB total VRAM caps local model quality (~7–14B class) | owned-tier channels knowingly trade capability for privacy; TEE provider and vendor subscriptions cover the high end; GPU upgrade changes nothing architecturally |
| TEE inference is a young market (attestation verification, GPU TEE maturity, model availability) | provider abstraction keys on attestation-then-send; if no provider passes the Phase 3 spike, `private`-tier complex tasks degrade to server GPUs until one does |
| Per-user vendor subscription auth on the server (OAuth flows, token refresh, ToS drift) | mirrors Buzz's proven pattern; credentials isolated per member; metering is self-reported by design, not proxied |
| Copilot quality on small models (refinement, clarifying questions, routing) | it drafts and routes, humans confirm before dispatch; routing rules are policy code, not model output, so a weak copilot degrades UX, never privacy |
| Privacy Gate redaction assist misses secrets (small-model false negatives) | model suggestions are paired with deterministic secret scanners; the human review is the decision point, the model only assists; audit records gate outcomes without private content |
| Seal tokens must survive agent edits and git merges | tokens are plain-text markers robust to diff/merge; a pre-receive lint rejects malformed or duplicated tokens; agents in looser contexts only ever see placeholders, so they cannot leak what they never held |
| Deep-seal history rewrites invalidate clones and SHA references | old→new SHA remap table kept server-side; forced client re-sync purges stale vault objects; worktrees rebased; owner-only with blast-radius confirmation, so it stays a rare correction tool, not a routine one |
| Own-harness scope creep | v1 = one agent loop + existing tools + per-user profiles; plugins/skills deferred to Phase 7 |
| Git can't hide paths within one repo | scoped out of v1 explicitly (architecture §6); channel granularity is the read boundary, filtered mirrors in Phase 7 |
| secp256k1 keys can't live in the Secure Enclave | SE-wrapped master key + Keychain biometric access control (architecture §10); documented rather than discovered late |
| Cloud egress (vendor APIs, remote provider) | per-channel Bot membership + airgapped channel flag from v1; both paths metered |
| Swift client is a full rebuild by a small team | protocol-first sequencing; shared packages sized for iOS reuse; MVP scope cut to one working team session |

## Open questions (deliberately deferred)

1. TEE inference provider choice (attestation model, GPU TEE stack, hosted-model
   lineup, pricing) — Phase 3 spike.
2. Local serving stack (llama.cpp server / vLLM / Ollama) and model lineup for the
   2× 8 GB GPUs — Phase 3 spike.
3. Copilot model choice (shared or distinct between client and server variants)
   and how much routing intelligence lives in the model vs in policy code —
   Phase 3/5 spikes.
4. Inference-queue semantics: retention of undispatched jobs and cancellation UX.
   (Cross-tier re-routing is settled by D26 — tiers never change; jobs are
   re-queued in a cloned channel if needed.)
5. Metering policy detail: budgets vs reporting-only, per-user vs per-channel caps,
   what the non-owner members get to see.
6. Harness customization surface for v1 (persona + tier/model route + tool
   allowlist is the baseline; anything more waits for Phase 7).
7. Vault implementation (APFS encrypted sparse bundle vs file-level crypto) —
   Phase 4 spike.
8. Client local-model lineup (which whisper size, which small LLM) — Phase 5
   quality spike.
9. Privacy Gate obfuscation mechanics: placeholder tokens vs generalized rewrites,
   and whether file redactions rewrite only the transplanted copy's history or
   also its future merges back.
10. Deep-seal mechanics detail: rewrite tooling (git-filter-repo vs custom
    filter), whether the SHA remap table is retained forever or expires, and how
    redaction envelopes interact with events that quoted the leaked value
    verbatim. (The history-semantics question is settled by D32: standard seals
    are forward-looking; deep seals purge history.)
11. Forum-style channels (Buzz kinds 45001/45003) — not in v1.
