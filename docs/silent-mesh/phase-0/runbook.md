# Phase 0 Runbook — Fork setup and slim-down

Executable steps for Phase 0 (roadmap.md). Steps 1–2 happen on GitHub; the rest
on the Linux server that will run Silent Mesh. Items marked ✋ need a human;
everything else can be driven by an agent session on the server.

## 1. ✋ Create the fork

Fork `block/buzz` to your account (web UI, or `gh repo fork block/buzz`).
Recommended: rename the fork repo to `silent-mesh` (repo name doesn't affect
upstream mergeability — remotes track URLs). Leave GitHub Actions disabled on
the fork (the default) — upstream's 12 workflows should not run on our infra;
our own slim CI comes later.

## 2. ✋ Grant access

Add the fork to whatever agent sessions will work on it (for Claude Code
remote sessions: the fork must be in the session's repository scope).

## 3. Clone and branch (on the server)

```bash
git clone git@github.com:<you>/silent-mesh.git && cd silent-mesh
git remote add upstream https://github.com/block/buzz.git
git fetch upstream --tags
git checkout -b silent-mesh upstream/main   # or the latest v0.5.x tag
git push -u origin silent-mesh
```

`silent-mesh` is the long-lived integration branch; `main` stays a clean
mirror of upstream (never commit to it) so diffs against upstream are always
one command away.

## 4. Apply the bootstrap overlay

From a checkout of this planning repo:

```bash
docs/silent-mesh/phase-0/bootstrap/apply.sh /path/to/silent-mesh
cd /path/to/silent-mesh
git add -A && git commit -m "silent-mesh: bootstrap overlay (plan docs, FORK.md, deploy profile)"
git push
```

This copies in: `FORK.md` (fork discipline), `docs/silent-mesh/architecture.md`
+ `roadmap.md` (the plan, which becomes canonical in the fork from this moment),
and `deploy/silent-mesh/` (single-host profile).

## 5. Toolchain + build sanity

Buzz pins its toolchain via Hermit in `bin/`:

```bash
source bin/activate-hermit          # cargo, just, node, pnpm, etc.
just bootstrap                      # per CONTRIBUTING.md; installs system deps guidance
cargo build -p buzz-relay -p buzz-cli -p buzz-acp   # backend only — do NOT build desktop/mobile/web
```

Per D35/D36 the client trees stay in-tree and unbuilt. Never run the
client-inclusive `just ci` target; the backend subset is our surface.

## 6. Deploy the single-host stack

```bash
cd deploy/silent-mesh
cp .env.example .env                # then fill in the secrets it demands
docker compose -f ../compose/compose.yml -f compose.silent-mesh.yml up -d --build
```

The override binds the relay to `SM_VPN_BIND_ADDR` (your Tailscale/WireGuard
interface IP) instead of 0.0.0.0, builds the relay image from the fork's own
source, and skips any public-TLS layer (`compose.caddy.yml` is deliberately
unused — D11: nothing faces the internet). Run migrations on first boot per
`deploy/compose/README.md` (`buzz-admin migrate`, or `BUZZ_AUTO_MIGRATE=true`
for the first start only).

Verify: `curl http://<vpn-ip>:3000/_readiness` from a VPN-connected machine —
and confirm the port is NOT reachable from any non-VPN network.

## 7. Community bootstrap

Single-community mode (one host = one implicit community). Enroll the owner
and verify invites end-to-end with `buzz-cli` (`cargo run -p buzz-cli -- --help`
for the current command set — `users`, `channels`, `messages`, `agents` are the
relevant families; exact invite flow to be verified against the deployed
version, since upstream's invite side-effect handler was listed as deferred —
if it still is, wiring it becomes the first `silent-mesh` branch commit, per
roadmap Phase 0).

Exit check: two members (owner + one invited) exchange kind-9 messages in a
members-only channel; a third keypair without membership is denied.

## 8. Agent baseline

Configure `buzz-acp` for the D15 lineup and verify each spawns and answers an
@mention in a test channel:

- `claude-code-acp` (Claude Code must be installed + authenticated on the server)
- `codex-acp` (Codex CLI installed + authenticated)
- Grok CLI via the BYOH generic runtime (`crates/buzz-acp/src/config.rs` —
  BYOH agent command + args)

Note the current upstream behavior while testing: agent permission requests
are auto-approved (`buzz-acp` selects `allow_once`). This is the known gap
that Phase 1 (governance) closes — do not put anything sensitive in test
channels until then.

## 9. Upstream tracking cadence

```bash
git fetch upstream
git checkout silent-mesh && git merge upstream/main   # merge, not rebase: the branch is shared
# resolve, run: cargo test -p buzz-relay && integration subset, then push
```

Biweekly, or on any upstream release. FORK.md documents the full discipline.

## 10. Phase 0 exit checklist

- [ ] Fork exists; `silent-mesh` branch pushed; `main` mirrors upstream
- [ ] Bootstrap overlay committed (FORK.md, plan docs, deploy profile)
- [ ] Backend crates build on the server toolchain (no client builds)
- [ ] Stack up on the VPN interface; `/_readiness` green; unreachable off-VPN
- [ ] Owner enrolled; invite flow verified; non-member denied
- [ ] claude-code, codex, and Grok(BYOH) agents each answer an @mention
- [ ] One upstream merge executed end-to-end with tests green
