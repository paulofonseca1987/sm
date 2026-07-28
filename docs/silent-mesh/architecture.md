# Silent Mesh — Target Architecture

Silent Mesh is a **fork of Buzz (block/buzz)** that absorbs **T3 Code's governed
agent-work model**: a self-hosted, private workspace where a team of humans and AI
agents build together — Buzz's relay, channels, identity, and git forge underneath;
T3-style work threads with worktrees, checkpoints, and human-approved agent actions
on top; privacy-tiered model routing and a native Swift client as Silent Mesh's own
contribution.

This document records the agreed direction and the target architecture. The phased
delivery plan lives in [roadmap.md](./roadmap.md).

## 1. Decision log

Decisions taken with the owner (2026-07-28), in the order they were made. D1–D32
were taken against a T3-Code-base assumption; after a comparative analysis of both
codebases, D33 re-decided the foundation. **All D1–D32 product semantics survive**
— what changed is which half is inherited versus built.

| # | Decision | Choice |
|---|---|---|
| D1 | Base | ~~Fork of the T3 Code monorepo~~ *(superseded by D33)* |
| D2 | Identity | Nostr identity like Buzz: every human and agent has a keypair; every action is a signed event *(now inherited)* |
| D3 | Nostr depth | **Full relay wire compatibility** *(now inherited — this was the maximal-cost item on the T3 base and is free on the Buzz base)* |
| D4 | Team model | One community per server; channels with explicit membership; roles Owner / Admin / Member / Guest / Bot; owner controls per-user permissions and per-folder/file access *(roles/membership/tenancy inherited; folder ACLs new)* |
| D5 | Sidebar mapping | **Channel = folder on the server; LLM thread = Slack-style thread inside the channel** |
| D6 | Repo topology | One git repository per channel *(implemented as a channel↔repo binding convention on Buzz's forge)* |
| D7 | Channel conversation | Main message stream (kind 9) + branching LLM work threads *(stream inherited; work threads new)* |
| D8 | Agent execution | Server-side only *(inherited — buzz-acp spawns agents as server-side child processes)* |
| D9 | File sync | Git-native: clients sync channel repos through ACL-enforcing git endpoints; offline edits are local commits *(transport inherited; client sync new)* |
| D10 | Clients | Native Swift/SwiftUI macOS app first, native iOS later; server is headless for us — inherited Buzz clients are **not shipped** (D36) |
| D11 | Remote access | VPN only (LAN / Tailscale / WireGuard / SSH); no third-party relay services |
| D12 | Server platform | Linux |
| D13 | Client security | Files encrypted at rest on the client, accessible only inside the app; app lock via Face ID / Touch ID / PIN |
| D14 | Offline | Synced files remain editable offline; local on-device models handle summarize, translate, and voice-to-text |
| D15 | Vendor harnesses | **Claude, Codex, and Grok CLI** — via buzz-acp's existing `claude-code-acp` / `codex-acp` adapters and its BYOH generic-runtime support for Grok |
| D16 | Model plane | All model traffic routes through a **server-side model gateway with per-user token metering** *(builds on buzz-acp's usage metering and buzz-agent's provider layer)* |
| D17 | Native harness | Silent Mesh's own user-customizable agent harness *(realized by extending **buzz-agent** — Buzz's in-house 19k-line agent — with per-user profiles and gateway routing)* |
| D18 | Airgapped agent | V1 requirement — server-local models make zero-egress channels possible from launch |
| D19 | Client local models | Bundled open models (whisper.cpp + llama.cpp/MLX); macOS 14+ floor |
| D20 | Kind registry | Standard NIPs + Buzz's kinds *(now native — Silent Mesh's own 47xxx block rides alongside)* |
| D21 | Privacy tiers | **owned** (client-local — the only offline mode — or server GPUs), **private** (owned + TEE-attested provider), **open** (member's own vendor subscriptions) |
| D22 | Private complex tasks | TEE-based confidential inference provider, routed and metered by the gateway |
| D23 | Non-private inference | Each member's **own Claude Code / Codex / Grok subscription**, per-user credentials isolated server-side *(buzz-acp already runs these CLIs; per-user credential isolation is the addition)* |
| D24 | Channel privacy policy | Every channel declares a minimum tier; the gateway router refuses routes below it |
| D25 | Prompt Copilot | A private local model that sees task files, takes voice/text intent, refines prompts, asks clarifying questions, and queues jobs for the most adequate model within channel policy |
| D26 | Immutable channel tier | Tier fixed at creation; the only re-tiering path is an **owner-only channel clone** (repo forks, conversation stays behind) |
| D27 | Thread forking | Any member clones a thread at head or any checkpoint into a variation (branch + worktree) in the same channel; conversation inherited by reference |
| D28 | Thread archiving | Settled / snoozed / archived as core lifecycle states, signed events; losing forks archive |
| D29 | Personal channels + promotion | Every member gets a private personal channel (self + their agents); private thread work **promotes** into team channels — files transplant, conversation stays behind |
| D30 | Privacy Gate | Mandatory local-model review (summary, flagged spans, approved obfuscations) before any privacy-weakening movement |
| D31 | Content Seals | Owner seals any word/value/component at a minimum tier, **workspace-wide**: sweep, ingestion guards, delivery redaction, gateway scrub, token-by-reference |
| D32 | Deep seal | Optional retroactive git-history purge as the leak-correction mechanism; owner-only, blast-radius-confirmed, heavily audited |
| **D33** | **Base (final)** | **Fork block/buzz (v0.5.x)**. T3 Code becomes the **design blueprint** for the work-thread + approval layer, not the code base. Rationale: the two projects have complementary holes — Buzz's hardened relay/forge/tenancy (~110k lines, 3,717 tests) is the bigger, subtler half to rebuild; T3's work-thread + approval design is the smaller port and is exactly Buzz's one unfinished area |
| D34 | Stack | Rust-first backend accepted; TS only where inherited surfaces need it; Swift for clients |
| D35 | Fork posture | **Track upstream**: additive crates/middleware/new kinds over invasive edits; no mass renames (brand at config/deploy level); upstream-owned trees (desktop/mobile/web) stay in-tree **unbuilt** rather than deleted, so rebases stay clean; upstream our governance work where Block will take it |
| D36 | Interim client | **CLI-only until the Swift MVP** (buzz-cli + scripted/test clients + admin CLI). Inherited Buzz clients are not shipped or supported, though the in-tree desktop app remains available as a developer debugging tool |

## 2. The core mapping

```
Buzz community          →  Silent Mesh server (one team per server)
Buzz Stream channel     →  Channel = a folder on the server = one bound git repo
Buzz kind-9 stream      →  Channel conversation (humans + agents, @mentions)
Slack thread            →  Work thread (NEW: worktree, checkpoints, approvals — T3's design)
Buzz Bot member         →  Agent (buzz-acp harness or buzz-agent instance, own keypair)
Buzz DM-with-self       →  Personal channel (membership of one + your agents, own repo)
Buzz desktop sidebar    →  Reference UX only — Silent Mesh ships the Swift client
```

The core product invariant survives the base flip: **channel membership _is_ the
file ACL**. A member sees the repos of the channels they belong to, and syncs
exactly those.

## 3. Provenance: inherited / ported / new / not shipped

### Inherited from Buzz (keep, configure, harden)

| Component | Where | Notes |
|---|---|---|
| Relay: Nostr WS (NIP-01/42), REST, subscription fan-out, membership-checked delivery | `crates/buzz-relay` (61.8k lines) | the foundation D2/D3/D4 wanted |
| Multi-tenant isolation + conformance suite | `docs/multi-tenant-*.md`, `conformance_multitenant.rs` | we run single-community but keep the fencing rigor |
| Git forge: smart-HTTP, CAS-on-object-storage, pre-receive policy hook, NIP-34 kinds, ref-pattern protections | `crates/buzz-relay/src/api/git/` (9.4k lines), `buzz-core/git_perms.rs` | the hardest-to-rebuild asset |
| ACP agent host: process pool, work queue, crash recovery, mid-turn steering, workspace layout (OUTBOX/REPOS), usage metering | `crates/buzz-acp` (34k lines) | runs claude-code / codex / goose / BYOH today |
| buzz-agent: in-house LLM agent (providers, MCP client, catalog, personas) | `crates/buzz-agent` (19k lines) | becomes the D17 native harness's chassis |
| Identity plumbing: keys, invites, pairing, `git-credential-nostr`, `git-sign-nostr` | `buzz-core`, `git-*-nostr` crates | agents sign commits as their Nostr identity — already real |
| Media (Blossom), search (Postgres FTS), audit hash chain, push gateway, workflows engine | respective crates | workflows kept but not a v1 focus |
| buzz-cli + test-client harness | `crates/buzz-cli`, `buzz-test-client` | the D36 interim surface and our conformance safety net |
| Ops: docker-compose, Helm charts, migrations, observability | `deploy/`, `migrations/` | single Linux server via the compose profile |

### Ported from T3 Code (design blueprint, reimplemented on Buzz)

| Capability | T3 reference | Silent Mesh home |
|---|---|---|
| Work threads: worktree per thread, per-turn **checkpoints** (hidden git refs), diff/revert, turn/activity model | `apps/server/src/{orchestration,checkpointing,vcs}/**` | new crate(s), e.g. `sm-work`, driving Buzz's forge storage |
| **Supervised approvals**: runtime modes (full-access vs supervised), per-tool-call pending approvals | `runtime-modes.md`, `projection_pending_approvals` | wired into buzz-acp's permission path + relay approval kinds (§8) |
| Thread fork / archive / promotion semantics (D27–D29) | T3 thread lifecycle + our D-decisions | `sm-work` + new 47xxx kinds |
| Plan-then-execute interaction mode, settled/snoozed inbox semantics | T3 threads | `sm-work` |
| Prompt-shaping UX detail (composer, per-turn diffs) | T3 web/mobile UI patterns | Swift client design reference |

### New (Silent Mesh's own)

1. **Governance completion** — end-to-end approvals (Buzz's one consistently
   unfinished area; §8). Candidate upstream contribution.
2. **Model gateway + privacy tiers + metering** (D16, D21–D24) and the
   **Prompt Copilot + inference queue** (D25) — §11.
3. **Folder/file write ACLs** inside a channel (D4) — extending the pre-receive
   policy hook from ref-patterns to file paths, plus agent tool-layer enforcement.
4. **Personal channels + promotion + Privacy Gate + Content Seals + deep seal**
   (D29–D32) — §7, §10.
5. **Channel↔repo binding + channel privacy tiers, immutable, with owner-only
   clone** (D5/D6/D24/D26).
6. **Swift macOS client** (vault, biometrics, git sync, offline local models,
   artifact viewer with durable comments) and later iOS — §12.
7. **Durable anchored comments on artifacts** (Buzz has frame-anchored media
   comments and canvases; we extend the pattern to HTML artifacts and files).

### Not shipped (kept in-tree, unbuilt — D35/D36)

Buzz's desktop (Tauri), mobile (Flutter), web repo-browser, and admin-web are
excluded from our build/CI but not deleted, keeping upstream rebases clean. The
desktop app doubles as a developer debugging tool. Keycloak and enterprise SSO are
disabled in our deploy profile. Huddles/audio, forum channels, canvases, and the
mesh-compute P2P feature stay upstream-maintained and dormant until wanted.

## 4. Server architecture (Linux)

The Buzz stack, single-host via compose, plus Silent Mesh's additive services:

```
                   ┌────────────────────────────────────────────────────────┐
                   │  silent-mesh server (Buzz fork, Rust, Linux host)      │
                   │                                                        │
  Swift client ────┤  WS: Nostr relay (NIP-01/42) ── buzz-relay             │
  (via VPN)        │  HTTP: git smart-HTTP (NIP-98) ── CAS on MinIO         │
  buzz-cli ────────┤  HTTP: Blossom media (NIP-98)                          │
  Nostr tooling ───┤                                                        │
                   │  ├─ membership/tenancy enforcement (inherited)         │
                   │  ├─ kind dispatch → side-effect handlers               │
                   │  │    ├─ sm-work: work threads, worktrees,             │
                   │  │    │   checkpoints, forks, promotion   (NEW)        │
                   │  │    ├─ approvals: wired end-to-end      (NEW §8)     │
                   │  │    ├─ buzz-acp: claude-code / codex / grok(BYOH)    │
                   │  │    ├─ buzz-agent: native harness, per-user profiles │
                   │  │    └─ audit hash chain (inherited)                  │
                   │  ├─ sm-gateway: privacy tiers · per-user metering (NEW)│
                   │  │    ├─ owned:   local models ── 2× RTX 4060 8 GB     │
                   │  │    ├─ private: TEE inference provider (attested)    │
                   │  │    └─ open:    per-user vendor subscriptions        │
                   │  ├─ sm-seals: sweep · ingestion guards · delivery      │
                   │  │    envelopes · gateway scrub               (NEW)    │
                   │  └─ Prompt Copilot + inference job queue      (NEW)    │
                   │                                                        │
                   │  Postgres (events, projections) · Redis (fan-out)      │
                   │  MinIO (git CAS, media, model weights)                 │
                   └────────────────────────────────────────────────────────┘
```

Everything reaches the server over the owner's VPN (D11). Silent Mesh services are
**additive crates and middleware** (D35): `sm-work`, `sm-gateway`, `sm-seals` hook
the relay's ingest/delivery/policy extension points rather than rewriting them.

## 5. Protocol: events and kinds

Inherited wire protocol: NIP-01 events, NIP-42 WS auth, NIP-98 HTTP auth, Buzz's
kind registry (kind 9 streams, NIP-34 git kinds, 45xxx forum, 46xxx workflow/
approval, kind 40100 canvases, Blossom media). Standard Nostr tooling connects,
subject to membership.

Silent Mesh adds its **47000–47999 block**: work-thread lifecycle (incl.
settled/snoozed/archived), thread fork, thread promotion, turn/activity, proposed
plan, checkpoint ref, artifact published, anchored comment, inference job
queued/dispatched/completed, content seal, sync marker, ACL change notice, usage
summary. Agent token-streaming uses ephemeral kinds (20000–29999); final messages
persist as one signed event. Approval kinds 46010/46011 are inherited names that
we actually wire (§8).

Offline writes remain a first-class property: client-signed events authored
offline are valid on replay — the Swift client's outbox is "signed events + local
git commits".

## 6. Team layer: identity, roles, ACLs

Inherited: keypair identity, invites (wiring the currently-deferred side-effect
handler if upstream hasn't), channel membership with Owner/Admin/Member/Guest/Bot,
TOCTOU-safe membership checks on REQ and delivery, last-owner guards, moderation,
audit chain, community isolation.

Silent Mesh additions:

- **Channel = folder = repo (D5/D6)**: channel creation provisions and binds a
  repo on the forge; the binding is the unit of sync and ACL.
- **Folder/file write ACLs (D4)**: the pre-receive policy hook gains file-path
  rules (member → paths → read-write | read-only) alongside upstream's
  ref-pattern protections; the same rules bind the agent tool layer. The honest
  v1 read boundary is unchanged: read = channel membership; need read-secrecy →
  separate channel.
- **Personal channels (D29)** and **promotion**, **Privacy Gate (D30)**,
  **Content Seals (D31/D32)** — semantics exactly as decided (see the D-log);
  seals are enforced at four points (render, inference, movement, sync) with
  workspace-wide sweep, ingestion guards, delivery redaction envelopes for signed
  events, and server-side-only literal matching. Deep seal purges history with an
  old→new SHA remap table and forced client re-sync.
- **Agents as members**: inherited outright — bots have keypairs, roles, channel
  memberships, sign their commits, and are auditable. Per-user operated-for
  tagging and per-user vendor credentials (D23) are the additions.

## 7. Work threads: T3's model on Buzz's forge

The `sm-work` layer gives Buzz what T3 had and Buzz lacks:

- A work thread binds a **worktree** on the channel's repo; every agent turn ends
  in a **checkpoint** (hidden ref); diffs/revert per turn and per thread.
- **Fork (D27)**: any member, at head or any checkpoint → sibling variation,
  conversation inherited by reference, merge-back via normal git flow.
- **Lifecycle (D28)**: settled / snoozed / archived as signed events; losing
  variations archive.
- **Promotion (D29)** out of personal channels, through the Privacy Gate (D30).
- Buzz's existing agent workspace convention (OUTBOX/, REPOS/) is aligned with
  worktree binding so buzz-acp agents operate inside the thread's worktree.

## 8. Governance: wiring approvals end-to-end

The comparative analysis found Buzz's single biggest gap, and it is the center of
Silent Mesh's thesis, so it is the **first build** (roadmap Phase 1):

- Today upstream **auto-approves** agent permission requests (buzz-acp selects
  `allow_once` programmatically) and the workflow approval gate returns a token
  that is never persisted or emitted. DB CRUD for approvals exists; HTTP
  grant/deny routes and kind-46010 emission do not.
- Silent Mesh wires the full loop: ACP permission request → **runtime mode
  policy** (T3's full-access vs supervised, per thread) → pending-approval record
  → kind-46010 event to the channel/thread → human grants or denies (signed
  kind-46011, "who approved what" provable) → decision returned to the agent →
  audit chain.
- Grant/deny surfaces: buzz-cli (interim, D36), then the Swift client.
- This work is deliberately structured for **upstreaming** (D35): Block's own
  architecture docs claim the endpoints should exist, so the contribution has a
  natural home.

## 9. Files, git, and sync

- Forge storage, smart-HTTP transport, policy hook, NIP-34 review kinds:
  inherited. Push events already land in channels.
- **Client sync = git** (D9): the Swift client clones/pulls the member's channel
  repos into the encrypted vault via the inherited endpoints (NIP-98-authed),
  pushes local commits when online; conflicts are ordinary merges surfaced in UI.
- Large media and model weights ride Blossom/MinIO, referenced by hash.

## 10. Privacy posture

Unchanged from the D-decisions, restated on the new base: no third-party service
in the loop (Keycloak disabled; no telemetry we ship). Buzz's server-readable
design is **not a conflict for Silent Mesh** — the owner owns the relay; our
privacy model defends against third parties, looser inference backends, and lost
devices, via: privacy tiers with channel-immutable minimums (D21/D24/D26), the
Privacy Gate (D30), Content Seals + deep seal (D31/D32), the encrypted
biometric-gated client vault (D13), and VPN-only reachability (D11). The two
controlled egresses (member vendor subscriptions; the attested TEE provider) and
the `owned-only` zero-egress guarantee are exactly as decided.

## 11. Model plane: tiers, gateway, copilot, native harness

Semantics exactly as D16–D25; the base flip changes the substrate:

- **sm-gateway** fronts: server-local models (2× RTX 4060 8 GB — llama.cpp/vLLM/
  Ollama, spike; Buzz already has Ollama plumbing in buzz-agent), the TEE
  provider (attestation-then-send), and per-user vendor subscriptions (buzz-acp
  already spawns those CLIs; we add per-user credential isolation and
  operated-for attribution).
- **Metering** extends buzz-acp's existing usage accounting into per-request
  `(user, agent, channel, thread, model, tier, backend)` attribution with
  owner-set budgets.
- **Native harness (D17)** = buzz-agent + per-user profiles (persona, tier/model
  route, tool allowlist, limits, owner-bounded) + gateway-only model access.
  Buzz's agent catalog and persona system give this a head start.
- **Prompt Copilot (D25)** and the signed inference-job queue as decided; gate
  and copilot inference pinned to the owned tier in the router.

## 12. Swift macOS client (and the iOS path)

Unchanged in design (macOS 14+, D19): `MeshProtocol` (NIP-01/10/42/98 — now
testable against Buzz's conformance suite and interop E2E, a real gift),
`MeshVault` (SE-wrapped master key, biometric/PIN unlock, encrypted store),
`MeshSync` (libgit2 against the inherited forge endpoints + signed-event outbox),
`MeshIntelligence` (whisper.cpp + llama.cpp/MLX; client-side copilot; offline
Privacy Gate). UI as decided: channels/streams/threads with fork/archive/promote,
approvals, file browser, artifact viewer with seal-aware rendering and durable
comments, gate review flow, owner admin incl. usage dashboards.

Until it ships: **buzz-cli and scripted clients are the only supported surface**
(D36).

## 13. Fork discipline (D35)

- Silent Mesh changes live in **additive crates** (`sm-work`, `sm-gateway`,
  `sm-seals`) and registered extension points; invasive relay edits only when
  unavoidable, kept small and rebase-friendly.
- **No mass renames**: crate and binary names stay upstream; branding happens at
  the config/deploy/client layer.
- Upstream-owned trees we don't ship stay in-tree, unbuilt.
- Scheduled upstream rebases (e.g. biweekly); the conformance + E2E harness is
  the rebase safety net.
- Governance/approvals work is written to upstream-quality and offered to Block.
