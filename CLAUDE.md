# pipeline-raw-go-cam

The Jenkins pipeline that produces a **"live" view of GO-CAM data
products** — a rolling snapshot of production Noctua curation, republished
as GPAD / low-level JSON / API indexes / gocam-py YAML for internal and
downstream use. Marked `[EXPERIMENTAL]` in the README by origin, but it now
has a **real downstream consumer** (the GOEx load reads the unified GPAD),
so treat breakage as production-impacting.

This is a **sibling of `pipeline-from-goa`** and shares its Jenkins/skyhook/S3
world, but it is a different animal: a *rolling live product*, not a
release pipeline. Do **not** blindly port `pipeline-from-goa` conventions —
see "How this differs from pipeline-from-goa" below.

## What it does (data flow)

One Jenkins job, one branch (`main`), almost all of it **inline in the
`Jenkinsfile`** (two scripts under `scripts/`, both fetched from this
branch at run time; no `justfile`, no `docs/`). Three build parts:

1. **Minerva generations** (runs on the Jenkins agent in a Python venv;
   `minerva-cli` staged onto skyhook and rsync'd back):
   - Pull GO-CAM TTL from `s3://go-data-product-live-go-cam/ttl` into
     `models/`, then `scripts/select-latest-ttl-export.py` drops every TTL
     not written by the latest export (see Data provenance) and fails the
     run if that export looks partial (under 90% of `ttl/`).
   - `minerva-cli --import-owl-models` → `blazegraph.jnl`.
   - `--lego-to-gpad-sparql` → per-model GPAD (`legacy/gpad/*.gpad`), then
     `unify-gpads.pl` (fetched from go-site) → `unified.gpad.gz`.
   - `--dump-owl-json` (using a **remote reacto-neo ontojournal** pulled
     from `skyhook.berkeleybop.org`) → low-level JSON.
   - `gen-model-meta.py` (fetched from go-site) → `provider-to-model.json`
     plus API index files (`taxon`, `contributor`, `providedBy`, `source`,
     `evidence`, `entity`).
2. **Produce gocam-py YAML** (runs in the pinned docker image
   `geneontology/dev-base:ea32b54c…_2023-08-28…`):
   - Pull low-level JSON back down, run go-site's
     `minerva_to_gocam_yaml_converter.py` → gocam-py YAML.
3. **GO-CAM reports** (`scripts/gocam-reports.sh` in `ubuntu:noble`,
   fetched from this branch at run time so Restart From Stage picks up
   script fixes; gocam-py from `TARGET_GOCAM_PY_BRANCH`):
   - gocam-py pipeline steps 1–5 on this run's `jsonout/`, then
     `generate_log_summary.py` → `summary-html/` + `summary.xlsx`, the same
     reports `pipeline-from-goa` publishes per release.
   - Wrapped in `catchError(buildResult: 'UNSTABLE')`: the live products
     are already uploaded, so a report failure does not fail the build.
   - Refuses to install a gocam-py `uv.lock` that pins any file uploaded
     in the last 7 days.

**Everything is written back into `s3://go-data-product-live-go-cam/`**,
fronted by CloudFront `E2291OLR508FRR` at `live-go-cam.geneontology.io`.
Product layout under that bucket:

- `ttl/` — **input**, not produced here (see Data provenance).
- `product/gpad/unified.gpad.gz` and `product/gpad/model/*.gpad`
- `product/json/low-level/*.json`
- `product/json/provider-to-model.json` and `product/json/api-index/*.json`
- `product/yaml/go-cam/*.yaml`
- `product/reports/go-cam/summary-html/` (entry
  `go-cam_pipeline_report.html`; no directory index on this CDN) and
  `product/reports/go-cam/summary.xlsx` — written with `aws s3 sync
  --delete` confined to that prefix, `Cache-Control: max-age=3600`

Known downstream consumers (search before renaming any of the above):

- **GOEx load** reads `product/gpad/unified.gpad.gz` (issue #11 — a bad
  `assigned_by` there blocked the GOEx load, i.e. this is load-bearing).
- Not consumers any more (checked 2026-11-02): go-fastapi (v0.5.0 reads
  `current.geneontology.org/go-cams/index-json/`) and the GO-CAM Browser
  (reads `release.geneontology.org/<date>/products/go-cam-search/`). No
  other org repo reads the bucket, and neither the bucket nor CloudFront
  logs requests, so runtime readers outside the org are unknown.

### Bucket lifecycle (since 2026-11-02)

Versioning is on. Current objects expire **30 days after their last
write**; replaced or expired versions are kept **90 days**. This removes
stale files only because **every run, and every export, rewrites every
current object** (`aws s3 cp --recursive`). Never switch either writer to
a copy that skips unchanged files (`aws s3 sync` of files that are not
regenerated each run) — unchanged current files would then expire. The
reports stage's `sync` is safe: every file it uploads is regenerated. Recovery of anything removed
or overwritten in the last 90 days: `aws s3api list-object-versions` plus a
copy of the prior version. Record: `geneontology/operations`
`events/live-go-cam-lifecycle-2026-11-02.md`.

### Schedule (and the upstream it depends on)

- This job: `cron('0 21 * * 1,3,5')` — **MWF 9pm Pacific** (04:00Z),
  builds appear as `#NNN` at ~04:00Z on Tue/Thu/Sat.
- Its TTL input is produced **one hour earlier** by a cron **outside this
  repo** (see next section). The 9pm start deliberately trails the 8pm
  export. See commit `0308464` / issue #11 for work on not having to wait
  on that ordering.

## Data provenance — where the input TTL comes from

The `s3://go-data-product-live-go-cam/ttl` input is **not** produced by this
pipeline and is **not** grabbed from `geneontology/noctua-models` at run
time. It is exported from the **production Noctua host** by a cronjob owned
by user **`bbop` on `toaster.lbl.gov`**:

```
0 20 * * 1,3,5  aws s3 cp /home/swdev/local/src/git/noctua-models/models/ \
    s3://go-data-product-live-go-cam/ttl --recursive --exclude "*" --include "*.ttl"
```

That is: a working checkout of `noctua-models/models/` on `toaster`, synced
to S3 MWF at 8pm Pacific (issue #1, "Periodically export TTL models from
production noctua to S3"). **This is out of scope for this repo** but is the
reason the "live" product reflects current production Noctua state. If the
live products look stale or wrong at the source, suspect that cron / the
`toaster` checkout first, before this pipeline.

That `cp` never deletes, so `ttl/` also holds models since removed from
`noctua-models` until the 30-day expiry above (702 Reactome models retired
on 2026-07-02 sat there for four months and were republished every run).
`select-latest-ttl-export.py` therefore imports only the objects written
within 3 hours of the newest one. On 2026-11-02 the latest export was
byte-identical (S3 ETag vs git blob MD5) to `noctua-models` master at
export time.

Because this is a *live view of production Noctua*, this pipeline
**intentionally reads from a serving bucket** (`live-go-cam`) — the strict
"never read pipeline inputs from a serving endpoint" reproducibility rule
that governs `pipeline-from-goa` does **not** apply here. The bucket *is*
the hand-off point between the production-Noctua export and this pipeline.

**Accepted interim exception (shared with pipeline-from-goa):** the
`--dump-owl-json` step needs a reacto-**neo** ontojournal and pulls a remote
NEO (`blazegraph-go-lego-reacto-neo.jnl.gz` from `skyhook.berkeleybop.org`).
NEO isn't produced in-pipeline yet — flagged, on the roadmap, not a blocker.

## How this differs from pipeline-from-goa (read before porting habits)

`pipeline-from-goa`'s `CLAUDE.md` has a lot of hard-won process. Most of it
does **not** transfer, because this repo is structured differently:

- **Almost everything is inline in the `Jenkinsfile`.** The exceptions
  are `scripts/gocam-reports.sh` (the GO-CAM reports stage), which follows
  `pipeline-from-goa`'s pattern: fetched at run time, `su jenkins -c`
  inside the container, `shellcheck` before pushing, and fixable through
  Restart From Stage; and `scripts/select-latest-ttl-export.py`
  (stdlib only), also fetched at run time. For every other stage a bug fix means editing the
  `Jenkinsfile` (slow path — see CI below). Externalizing the rest is a
  project, not an assumption.
- **No release / "bless" / Zenodo / snapshot→release lifecycle.** This
  publishes a single rolling live product. The env block in the
  `Jenkinsfile` inherits a large amount of **vestigial** configuration from
  the `geneontology/pipeline` template (release emails, `ZENODO_*`,
  `AWS_CLOUDFRONT_*`, `TARGET_BUCKET='go-data-TBD'`, `GOLR_*`, the
  `watchdog()` guard, the `success`/`changed`/`failure` email logic that
  references non-existent branches like `release`/`snapshot-post-fail`).
  Most of it is `null`/dummy and not wired up. Don't assume an env var does
  something just because it's declared — grep the stages for actual use.
- **No `docs/`, no `justfile`.** If you add durable operator docs, this is
  where a `docs/` dir would start.

## Jenkins CI

- **Host:** `build.geneontology.io` (the GO Jenkins; agent runs on
  `fryer.lbl.gov` as user `jenkins`). Skyhook writes go to
  `skyhook.geneontology.io` (also `fryer`).
- **Job path:** `https://build.geneontology.io/job/pipeline-raw-go-cam/job/main/`.
  (Note: some `emailext` bodies in the `Jenkinsfile` have **wrong** paths —
  `pipeline-pipeline-raw-go-cam` and `job/geneontology/job/…`. The real
  path is the one above; fix the emails if you touch that block.)
- **API token** is in `~/.netrc` for `machine build.geneontology.io login
  sjcarbon`. If missing/expired, ask the user to regenerate via Jenkins:
  username (top right) → Security → API Token → Add new Token.
- **curl gotcha:** the API's `tree=jobs[name]` syntax trips curl's URL
  globbing — pass `-g`. A default UA can hit a Cloudflare 403; send a
  browser `-A`.

### Downloading console logs

Console logs are **huge** (build #270 was ~93 MB / 380k lines). Never curl
`consoleText` straight into a tool buffer. Instead:

1. `curl -n -g -s -A "Mozilla/5.0" -o /tmp/build-NNN.log \
   "https://build.geneontology.io/job/pipeline-raw-go-cam/job/main/NNN/consoleText"`
2. Analyze locally (`tail`, `grep`), then clean up.

Note: the per-model `ERROR … Inconsistent ontology: …` / `gocam with that
iri already exists, skipping` lines from `minerva-cli` are **expected
noise**, not the build failure. Find the real failure at the tail.

### Iteration model (slow path only)

Since the pipeline is inline in the `Jenkinsfile`, essentially every fix is
a **Jenkinsfile change**, which Restart-from-Stage **cannot** pick up (it
pins the original build's Jenkinsfile + SCM revision). The workflow is:

1. Edit the `Jenkinsfile` carefully. A full run takes **hours**, so a typo
   is expensive.
2. `git commit && git push`.
3. In the Jenkins multibranch UI → **"Scan Repository Now"** so it discovers
   the new commit; a fresh build runs from the first stage.

Before pushing a `Jenkinsfile` change: read the diff; verify any new repo
URLs / credential IDs / S3 paths actually exist; sanity-check `{`/`}`
balance. You **cannot** pre-validate syntax — the declarative-linter
endpoint is behind Cloudflare's WAF. To scaffold a stage you don't want to
run yet, **comment it out** (`/* … */`) rather than gating it live.

### Credentials used by the Jenkinsfile

- `skyhook-private-key` (file) + `skyhook-machine-private` (string) — SSH to
  skyhook for staging `minerva-cli` and (via `initialize()`) the sshfs mount.
- `aws_go_access_key` + `aws_go_secret_key` (string) — S3 read/write of
  `go-data-product-live-go-cam`.

### Skyhook usage

`initialize()` sshfs-mounts skyhook's `/home/skyhook` at `$WORKSPACE/mnt`,
`rm -r -f`s the `$JOB_NAME` tree (skyhook **self-cleans** between runs), and
`mkdir -p`s a product skeleton. Skyhook here is mostly a **staging area for
the `minerva-cli` build artifacts** (`bin/`), not the final product store —
final products go to **S3**, unlike `pipeline-from-goa` whose canonical tree
lives on skyhook. Much of the `initialize()` skeleton is inherited and
larger than what this pipeline actually writes.

## Issue and commit hygiene

Every commit references a GitHub issue; issues live under a project. The
chain is `commit → issue → project`.

- Commits: end the first line with `; for geneontology/pipeline-raw-go-cam#NN`
  (or the relevant repo, e.g. `; for geneontology/go-fastapi#137` when the
  work is really about a consumer). Pick the issue by **story fit**, walk up
  the hierarchy of generality if there's no exact match, and **ask** rather
  than stretch.
- If no issue exists for the work, create one first.

**Which project (drifts over time — confirm, don't assume).** Projects are
temporally bound; this repo is not. Different work here will land in
different projects. As of **2026-07**, ongoing pipeline-maintenance work
(outages, upstream/data-source issues, product tweaks) belongs to
**`geneontology/project-management#20` — "Ongoing data QC and pipeline
maintenance"** (org project **#162**; PI Chris, PO Pascale, TL Seth). If it
isn't obvious from context or recent issues which project is current,
**confirm with the user before assigning.**

## Renaming public-facing paths

Before renaming anything under
`live-go-cam.geneontology.io/` (i.e. any key in
`s3://go-data-product-live-go-cam/product/…`), search the org for consumers:

    gh search code 'PATH org:geneontology' --limit 100

The unified GPAD path is consumed by the GOEx load (above); other readers
may exist outside the org, unlogged. If any repo hardcodes the
URL, the rename needs cross-repo coordination (open + assign an issue, pin
behind a cutover), not a unilateral change. If the audit is clean, land it.

## Posting under the user's identity

Anything posted via a CLI that authenticates as the user (`gh issue
comment`, PR reviews, etc.) must carry the agency-disclosure trailer per the
global `~/.claude/CLAUDE.md` rule — this is a `geneontology/*` work repo, so
it also applies to fresh issue/PR **bodies**, not just comments.
