# Silent Mesh — Target Architecture

Silent Mesh is a fork of T3 Code that turns a single-user coding-agent GUI into a
self-hosted, private workspace where a team of humans and AI agents build together —
Slack-shaped channels, Buzz-shaped identity and sovereignty, T3-shaped agent
orchestration, and its own user-customizable agent harness.

This document records the agreed direction and the target architecture. The phased
delivery plan lives in [roadmap.md](./roadmap.md).

## 1. Decision log

Decisions taken with the owner (2026-07-28), in the order they were made:

| # | Decision | Choice |
|---|---|---|
| D1 | Base | Fork of the T3 Code monorepo |
| D2 | Identity | Nostr identity like Buzz: every human and agent has a keypair; every action is a signed event |
| D3 | Nostr depth | **Full relay wire compatibility** (NIP-01 REQ/EVENT/OK over WebSocket), not just a signing layer |
| D4 | Team model | Buzz-style: one community per server; channels with explicit membership; roles Owner / Admin / Member / Guest / Bot; owner controls per-user permissions and per-folder/file access |
| D5 | Sidebar mapping | **Channel = folder on the server; LLM thread = Slack-style thread inside the channel** |
| D6 | Repo topology | One git repository per channel |
| D7 | Channel conversation | Main message stream (all members, humans and agents) + branching LLM work threads |
| D8 | Agent execution | Server-side only (unchanged from T3) |
| D9 | File sync | Git-native: clients sync channel repos through ACL-enforcing git endpoints on the server; offline edits are local commits |
| D10 | Clients | Native Swift/SwiftUI macOS app first, native iOS later. **apps/web, apps/desktop, apps/mobile, apps/marketing are removed**; the server is headless and admin goes through the CLI |
| D11 | Remote access | VPN only (LAN / Tailscale / WireGuard / SSH). The T3 Connect cloud relay (Clerk + Cloudflare) is deleted |
| D12 | Server platform | Linux |
| D13 | Client security | Files encrypted at rest on the client, accessible only inside the app; app lock via Face ID / Touch ID / PIN |
| D14 | Offline | Synced files remain editable offline; local on-device models handle summarize, translate, and voice-to-text |
| D15 | Vendor harnesses | Keep **Claude, Codex, and Grok CLI** (Grok via the existing ACP driver). Drop the Cursor and OpenCode drivers |
| D16 | Model plane | All model traffic routes through a **server-side model gateway with per-user token metering**. Three backends: server-local GPUs (2× RTX 4060 8 GB), a remote inference provider, and the vendor harness APIs |
| D17 | Native harness | Silent Mesh builds **its own agent harness** on top of the gateway; each user customizes their agent (persona, tools, model routing) within owner-set bounds |
| D18 | Airgapped agent | **V1 requirement** — server-local models make zero-egress channels possible from launch |
| D19 | Client local models | **Bundled open models** (whisper.cpp for transcription, llama.cpp/MLX for summarize/translate); macOS 14+ floor |
| D20 | Kind registry | Standard NIPs + Buzz's kinds where semantics genuinely match; Silent Mesh's own 47xxx block for the rest |

## 2. The core mapping

```
Buzz community          →  Silent Mesh server (one team per server)
Buzz channel            →  Channel = a folder on the server = one git repo
Slack channel messages  →  Channel stream (kind-9 events; humans + agents)
Slack thread            →  Work thread (T3 Thread machinery: worktree, checkpoints, approvals)
Buzz bot member         →  Agent (harness instance with its own keypair + Bot role)
Slack sidebar           →  Channel list, scoped to the member's channel memberships
```

The elegant consequence of D5 + D6: **channel membership _is_ the file ACL**. A member
sees exactly the folders (repos) of the channels they belong to, and syncs exactly
those. Finer-grained control inside a channel is a write-side ACL (see §6).

## 3. What happens to each existing component

### Kept (the T3 crown jewels)

| Component | Where | Notes |
|---|---|---|
| Effect 4 stack, `vp` toolchain, monorepo layout | everywhere | unchanged |
| SQLite persistence + migration framework | `apps/server/src/persistence/**` | new tables added, pattern unchanged |
| Event-sourced decider/projector pattern | `apps/server/src/orchestration/**` | re-founded on signed Nostr events (§5) |
| Provider drivers: Claude (agent SDK), Codex (app-server), Grok (ACP) | `apps/server/src/provider/**`, `packages/effect-acp`, `packages/effect-codex-app-server` | driver SPI unchanged; the ACP layer stays (it also future-proofs adding agents like Goose). The native Silent Mesh harness becomes a fourth driver behind the same SPI (§9) |
| Git/VCS services, worktrees, checkpoints | `apps/server/src/{vcs,git,checkpointing}/**` | worktrees re-parented to channel repos |
| Workspace FS + search | `apps/server/src/workspace/**` | scoped per channel repo |
| Server secret store | `apps/server/src/auth/ServerSecretStore.ts` | now also holds agent keypairs and inference-provider keys |
| MCP toolkit for agents | `apps/server/src/mcp/**` | preview automation re-targeted at a server-side headless browser (§8); also the tool layer of the native harness |

### Removed

| Component | Reason |
|---|---|
| `apps/web`, `apps/desktop`, `apps/mobile`, `apps/marketing` | D10 — native Swift client only; server is headless |
| `infra/relay`, all `cloud/*` code paths, Clerk dependencies | D11 — no third-party services |
| Cursor and OpenCode drivers | D15 — provider lineup is Claude, Codex, Grok + the native harness |
| Pairing-link / device-scope auth (`auth_pairing_links`, scopes, `/pair` flow) | replaced by Nostr identity: NIP-42 for WebSocket, NIP-98 for HTTP, invites for enrollment |
| `packages/tailscale`, `packages/ssh`, desktop backend pool / WSL | VPN is deployment guidance now, not app code |
| `packages/client-runtime` (eventually) | its connection/state logic informs the Swift port, then it goes |
| Effect RPC contract (`packages/contracts/src/rpc.ts`, `ws.ts`) (eventually) | replaced by the relay protocol; kept alive during the transition as a dev/test harness (see roadmap Phase 1–2) |

### Built new

1. **Relay core** — NIP-01 event store + WebSocket relay with NIP-42 auth (§4, §5).
2. **Identity, membership, channels, ACLs** — the team layer (§6).
3. **Git smart-HTTP endpoints with policy hooks** — repo-per-channel serving + sync (§7).
4. **Blob store** — Blossom-compatible content-addressed media endpoints (voice memos, images, large artifacts) backed by server disk.
5. **Model gateway** — routing + per-user token metering across local GPUs, a remote inference provider, and vendor APIs (§9).
6. **Native Silent Mesh harness** — Silent Mesh's own agent loop, per-user customizable (§9).
7. **Admin CLI** — community init, invites, members, roles, channels, ACLs, agent provisioning, model/usage admin, backup.
8. **Swift macOS client** — the whole thing (§10).
9. **Durable comments/annotations** — anchored, signed comment events on artifacts and files (§8). T3's UI-only comments become real entities.
10. **Server-side headless browser** — replaces the client-webview preview automation so agents can still inspect what they build.

## 4. Server architecture (Linux)

One process (evolved `apps/server`), one SQLite database, per-channel bare git repos,
a blob store, and a local model server on the GPUs:

```
                    ┌──────────────────────────────────────────────────────┐
                    │  silent-mesh server (Node + Effect, Linux)           │
                    │                                                      │
  Swift client ─────┤  WS: Nostr relay (NIP-01 REQ/EVENT/OK, NIP-42)       │
  (via VPN)         │  HTTP: git smart-HTTP (NIP-98)                       │
                    │  HTTP: Blossom blob endpoints (NIP-98)               │
  Nostr tooling ────┤                                                      │
  (nak, etc.)       │  ├─ Event store (SQLite, signature-verified)         │
                    │  ├─ Membership/ACL enforcement on REQ + EVENT        │
                    │  ├─ Kind dispatch → domain reactors                  │
                    │  │    ├─ Orchestration (threads, turns,              │
                    │  │    │   approvals, checkpoints)                    │
                    │  │    ├─ Agent drivers                               │
                    │  │    │    ├─ native harness (per-user profiles)     │
                    │  │    │    └─ vendor CLIs: claude / codex / grok     │
                    │  │    ├─ Git reactor (push events, worktrees)        │
                    │  │    └─ Audit hash chain                            │
                    │  ├─ Model gateway (per-user token metering)          │
                    │  │    ├─ local models ── 2× RTX 4060 8 GB            │
                    │  │    ├─ remote inference provider (server-held key) │
                    │  │    └─ vendor APIs (proxied where possible)        │
                    │  └─ Projections (streams, threads, members,          │
                    │       files, usage) for fast client snapshots        │
                    │                                                      │
                    │  disk: state.sqlite · repos/<channel>.git ·          │
                    │        worktrees/ · blobs/ · secrets/ · models/      │
                    └──────────────────────────────────────────────────────┘
```

Everything reaches the server over the owner's VPN. The server binds to the VPN
interface; TLS with an owner-managed CA is recommended but not load-bearing for
authentication (that's NIP-42/98 signatures).

## 5. Protocol: events and kinds

Wire format is NIP-01: `{id, pubkey, created_at, kind, tags, content, sig}` with
Schnorr signatures over secp256k1. The relay implements `EVENT`, `REQ`, `CLOSE`,
`EOSE`, `OK`, `AUTH` (NIP-42). Standard Nostr tooling can connect, subject to
membership checks.

Kind registry (per D20 — Buzz-compatible where semantics match; Silent Mesh-specific
kinds in a dedicated 47000–47999 block):

| Kind | Meaning | Origin |
|---|---|---|
| 0 | Member/agent profile | NIP-01 |
| 7 | Reaction | NIP-25 / Buzz |
| 9 | Channel stream message (threading via NIP-10 `e`-tags) | Buzz |
| 1617 / 30617 | Git patch / repo announcement | NIP-34 / Buzz Forge |
| 27235 | HTTP auth | NIP-98 |
| 20000–29999 | Ephemeral: typing, presence, **agent token-stream deltas** | NIP-16 |
| 45001 / 45003 | Forum post / reply (if forum channels are wanted later) | Buzz |
| 46001–46012 | Workflow/approval state (46011 = approval) | Buzz |
| 47000–47999 | Silent Mesh: thread lifecycle, turn/activity, proposed plan, checkpoint ref, artifact published, **anchored comment**, sync marker, ACL change notice, usage summary (optional visibility of metering) | new |

Two details worth calling out:

- **Streaming**: agent output streams as *ephemeral* events (not persisted), and the
  final message is persisted as one signed event. This keeps the event log clean
  while preserving live typing UX.
- **Offline writes**: because events are client-signed, a client can author valid
  events while offline and replay them on reconnect. The offline outbox is "a queue
  of already-signed events + local git commits" — no special server trust needed.

The event log is the write model. T3's decider/projector pattern survives: deciders
validate commands arriving as events, projections (`projection_*` tables) serve
snapshots. The existing `orchestration_events` table is superseded; since the fork
starts with fresh data, no migration of legacy rows is needed.

## 6. Team layer: identity, roles, ACLs

- **One community per server.** No multi-tenancy; the hostname/VPN is the boundary.
- **Enrollment**: the owner mints an invite (CLI or client). The new member's device
  generates a keypair locally; the invite code + pubkey registers the member. Keys
  never leave the device. Multi-device for one member = transferring the key via
  QR/manual export (v1); key rotation is a hardening-phase concern.
- **Roles** (per channel, like Buzz): Owner, Admin, Member, Guest (read-only),
  Bot. The community owner is Owner everywhere.
- **Agents are Bot members**: every agent — vendor-harness or native — gets a
  server-held keypair (in the secret store), a profile, channel memberships, and an
  audit trail. A user's personal harness agent is tagged as operated-for that user,
  so the audit trail distinguishes "the human said" from "their agent did", and
  metering attributes the tokens to the user (§9). The owner decides which agents
  are in which channels — which also bounds what files an agent can touch, because
  the agent's worktree comes from the channel repo.
- **Read access = channel membership.** The relay checks membership on every REQ and
  before every event delivery (Buzz's TOCTOU-safe pattern). Git fetch of a channel
  repo requires membership.
- **Write ACLs refine within a channel**: per-folder/file rules (member → paths →
  read-write | read-only) enforced at three chokepoints: git `pre-receive` (diff path
  inspection), the agent tool layer (workspace writes), and thread-level actions.
- **Honest v1 boundary**: hiding *reads* of a subfolder from a channel member is not
  in v1 — git history makes partial read-hiding within one repo genuinely hard
  (filtered mirror repos are the eventual mechanism, noted in the roadmap). The v1
  model is: *"you can read whatever is in channels you belong to; what you can write
  is per-folder"*. Need read-secrecy? Make it its own channel. This is also exactly
  Buzz's boundary (private channels), so it composes cleanly.
- **Audit**: every action is already a signed event; the relay additionally keeps a
  Buzz-style hash-chained audit log so tampering with SQLite is evident.

## 7. Files, git, and sync

- Each channel owns a bare repo: `repos/<channelId>.git`. Threads get worktrees off
  it (existing `vcs.createWorktree` machinery). Turn checkpoints stay as hidden git
  refs (existing `checkpointing/**`).
- The server exposes `GET /git/<channel>/info/refs`, `POST /git/<channel>/git-upload-pack`,
  `POST /git/<channel>/git-receive-pack`, authenticated with NIP-98, authorized by
  membership + write ACLs in a pre-receive policy hook. A push emits a git event into
  the channel stream (NIP-34 flavored), which is how "the agent/human shipped
  something" becomes visible in chat.
- **Client sync = git.** The Swift client clones/pulls the repos of the member's
  channels into the encrypted vault, and pushes local commits when online. Conflicts
  are ordinary git merges surfaced in the client UI (server never force-resolves).
- Large/binary media (voice memos, screenshots, exported artifacts) go to the
  Blossom-style blob store, referenced from events by hash — keeping channel repos
  lean and syncs fast.

## 8. Artifacts, viewer, comments

- Artifacts (HTML pages, reports, generated docs) are files in the channel repo,
  produced by threads; an `artifact published` event announces them in the stream.
- The client's artifact viewer renders HTML in a sandboxed WKWebView (strict CSP, no
  network). Selection uses injected JS to compute robust anchors (W3C
  Web-Annotation-style: text quote + position fallback).
- **Comments are durable signed events** (47xxx kind) referencing
  `(channel, path, git blob hash, anchor)` — so a comment survives and can be
  re-anchored or shown as "on an older version" after the file changes.
- **Regenerate-with-AI**: a comment/selection can be escalated to a work thread —
  the anchor + quoted fragment becomes the prompt context, the thread's diff comes
  back as a proposal in the channel.
- Agents keep self-inspection: the MCP preview toolkit drives a headless Chromium on
  the server (replacing T3's desktop-webview automation), so an agent can screenshot
  and verify the artifact it just produced.

## 9. Model plane: gateway, metering, native harness

This is Silent Mesh's own identity beyond the fork (D16–D18).

### Model gateway

A server subsystem exposing OpenAI- and Anthropic-compatible endpoints internally,
fronting three backend classes:

1. **Local models** — served from the 2× RTX 4060 8 GB GPUs (16 GB VRAM total) by a
   local inference server (llama.cpp server / vLLM / Ollama — stack chosen by
   spike). Realistic capacity: ~7–14B-class models at Q4–Q8, or ~24B with aggressive
   quantization and partial CPU offload; embedding and rerank models fit trivially.
2. **Remote inference provider** — one provider abstraction (OpenRouter/Together/
   Fireworks/direct — chosen later); the API key lives only in the server secret
   store; clients and agents never hold it.
3. **Vendor APIs** — Anthropic/OpenAI/xAI traffic from the vendor harnesses, proxied
   through the gateway via each CLI's base-URL override where the auth mode allows
   it (API-key auth proxies cleanly; subscription/OAuth auth may not — see the
   fallback below).

**Per-user token metering**: every request through the gateway is attributed to
`(user, agent, channel, thread, model, backend)` with prompt/completion token
counts, persisted and projected into usage summaries the owner can query (CLI and
client admin screens); per-user budgets/limits are owner-settable. Where a vendor
harness cannot be proxied (subscription auth), metering falls back to the
harness-reported usage T3 already surfaces — attributed the same way, flagged as
self-reported.

**Airgapped channels (v1)**: a channel policy flag restricting its agents to
local-backend models only. With it set, no file content or prompt ever leaves the
server — satisfying D18 from launch.

### Native Silent Mesh harness

Silent Mesh's own agent loop — a fourth driver behind the existing provider SPI, so
orchestration/threads/approvals/checkpoints treat it like any other agent:

- Built on Effect (`effect/unstable/ai`), speaking only to the model gateway — so a
  harness agent can run on a local model, the remote provider, or a vendor API by
  configuration, and is metered like everything else.
- Tool layer reuses what exists: workspace FS + search, git/worktrees, checkpoints,
  the MCP toolkit (including the headless preview browser).
- **Per-user customization (D17)**: each member owns one or more agent profiles —
  persona/system prompt, default model route, tool allowlist, temperature/limits —
  bounded by owner policy (a user cannot grant their agent tools or channels the
  owner hasn't allowed). Profiles are the user's own config, versioned like
  everything else.
- Harness instances are Bot members with their own keypairs (§6), tagged
  operated-for their user.

V1 harness scope is deliberately tight: one solid agent loop with the existing tool
set and per-user profiles — not a plugin marketplace.

## 10. Swift macOS client (and the iOS path)

SwiftUI app, **macOS 14+** (D19), structured as shared Swift packages so the iOS
client reuses everything below the view layer:

- **`MeshProtocol`** — NIP-01/10/42/98 client, kind codecs, subscription management
  (libsecp256k1 for Schnorr).
- **`MeshVault`** — encrypted storage. The vault is an APFS encrypted sparse bundle
  (or file-level AES-GCM store; decided by a spike) mounted/unlocked only while the
  app is unlocked. Note the honest constraint: the Secure Enclave only does P-256,
  so the secp256k1 identity key cannot live *inside* it — instead the vault/master
  key is SE-resident, and the Nostr key + all data are encrypted under it, with
  Keychain access control (`.biometryCurrentSet` + PIN fallback) gating unlock. App
  lock = LocalAuthentication (Touch ID / Watch / password on macOS; Face ID on iOS
  later).
- **`MeshSync`** — libgit2-based clone/pull/push of channel repos into the vault,
  plus the signed-event offline outbox.
- **`MeshIntelligence`** — bundled open models (D19): whisper.cpp for voice-to-text,
  a llama.cpp/MLX-served small model for offline summarization and translation.
  Weights are fetched on first run (from the owner's server blob store, not a
  third party) and stored in the vault; the model lineup is upgradable
  independently of app releases. All of it runs fully offline. This stack also
  ports to Linux clients if those ever happen.
- **UI**: Slack-like sidebar (channels → unread/mention badges), channel view
  (stream + threads), thread view (T3's turn/approval/diff semantics), file browser,
  artifact viewer with selection/comment/regenerate, sync & conflict UI, member/ACL
  admin, and usage/metering dashboards for the owner.

Since the web console is removed (D10), the **admin CLI is the fallback surface**
(headless server management, recovery, backups) and the Swift app carries the
owner-facing admin UI.

## 11. Privacy posture — and its two controlled egresses

No third-party service is in the loop: no Clerk, no Cloudflare, no telemetry, no
update pings. Data exists in exactly two places: the Linux server (owner-managed
disk; LUKS recommended) and client vaults (encrypted, biometric-gated).

Exactly two egress paths exist, both owner-controlled and both metered through the
gateway:

1. **Vendor harness APIs** (Anthropic / OpenAI / xAI) — active only in channels
   where the owner admits those Bot members.
2. **The remote inference provider** — active only for agent profiles routed to it;
   key held server-side.

Channels flagged **airgapped** use neither: their agents run exclusively on the
server's local GPUs, so nothing leaves the owner's infrastructure — available from
v1 (D18).
