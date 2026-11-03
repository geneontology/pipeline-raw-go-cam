#!/bin/bash
#
# GO-CAM reports stage: gocam-py's summary reports for the live models.
#
# Runs inside ubuntu:noble with /workspace mounted from the Jenkins
# workspace. Same gocam-py step sequence as pipeline-from-goa's
# scripts/gocam-processing.sh, but only the reports are kept. The upload
# is done by the Jenkinsfile on the agent, so no AWS credentials enter
# the container.
#
# Required env vars:
#   JENKINS_UID, JENKINS_GID
#   TARGET_GO_SITE_BRANCH
#   START_DATE, BRANCH_NAME
#
# Required mounts:
#   /workspace -- Jenkins workspace, with gocam-py checked out at
#                 /workspace/gocam-py and this run's --dump-owl-json
#                 output at /workspace/json-noctua-models/jsonout
#
# Output:
#   /workspace/gocam-reports/summary-html/ (entry: go-cam_pipeline_report.html)
#   /workspace/gocam-reports/summary.xlsx

set -euo pipefail

# This run's dump, not s3://.../product/json/low-level/: that prefix is
# written with a non-deleting `aws s3 cp`, so it also holds models the
# current run no longer produces.
MODELS_DIR='/workspace/json-noctua-models/jsonout'
OUT_DIR='/workspace/gocam-reports'
WORK='/tmp/gocam-work'
# Same ontology host as the GPAD step's go-lego.owl.
ONTOLOGY_BASE='https://ontology-build.geneontology.org'

# WARNING: MEGAHACK -- the Jenkins host's docker network DNS is broken.
echo 'nameserver 8.8.8.8' > /etc/resolv.conf
echo 'search lbl.gov' >> /etc/resolv.conf

# archive.ubuntu.com is intermittently unreachable from the Jenkins host.
apt_install_retry() {
    local _i
    for _i in 1 2 3; do
        if DEBIAN_FRONTEND=noninteractive apt-get -y install "$@"; then
            return 0
        fi
        echo "apt-get install attempt ${_i} failed; sleeping 30s before retry"
        sleep 30
        DEBIAN_FRONTEND=noninteractive apt-get update || true
    done
    return 1
}

DEBIAN_FRONTEND=noninteractive apt-get update
apt_install_retry python3 python3-pip python3-venv git wget graphviz libgraphviz-dev

# pip has no release-age cooldown, so uv is pinned by version and hash.
echo 'uv==0.13.5 --hash=sha256:fa8d26e08e34c29c0c4e820cf3181757086d547240b4f4d31ff1d8bd810ca946' > /tmp/uv-requirements.txt
pip3 install --break-system-packages --require-hashes -r /tmp/uv-requirements.txt

# -o and numeric chowns: the image's own ubuntu user and group may
# already hold these IDs, in which case no group named jenkins exists.
groupadd -g "$JENKINS_GID" jenkins || true
useradd -o -u "$JENKINS_UID" -g "$JENKINS_GID" -m -s /bin/bash jenkins
chown -R "$JENKINS_UID:$JENKINS_GID" /workspace/gocam-py
chown "$JENKINS_UID:$JENKINS_GID" /tmp
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
chown "$JENKINS_UID:$JENKINS_GID" "$OUT_DIR"

# Tracking gocam-py's branch means installing whatever its uv.lock pins;
# refuse a lock holding any file uploaded in the last 7 days.
python3 - <<'EOF'
import datetime, re, sys
cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=7)
lock = open('/workspace/gocam-py/uv.lock').read()
young = [t for t in re.findall(r'upload-time = "([^"]+)"', lock)
         if datetime.datetime.fromisoformat(t) > cutoff]
if young:
    sys.exit(f"gocam-py uv.lock pins {len(young)} file(s) uploaded within 7 days "
             f"(newest {max(young)}); refusing to install")
EOF

su jenkins -c 'git config --global --add safe.directory /workspace/gocam-py'
su jenkins -c 'cd /workspace/gocam-py && uv sync --frozen --all-extras'

su jenkins -c "
    mkdir -p \
        $WORK/01-gocam-models \
        $WORK/02-true-gocams \
        $WORK/02-pseudo-gocams \
        $WORK/03-indexed-true-gocams \
        $WORK/04-index-files \
        $WORK/05-browser-search-docs \
        $WORK/logs \
        $WORK/ontology \
        $WORK/metadata
"
su jenkins -c "wget -q -O $WORK/ontology/go.obo $ONTOLOGY_BASE/go.obo"
su jenkins -c "wget -q -O $WORK/metadata/users.yaml https://raw.githubusercontent.com/geneontology/go-site/${TARGET_GO_SITE_BRANCH}/metadata/users.yaml"
su jenkins -c "wget -q -O $WORK/metadata/groups.yaml https://raw.githubusercontent.com/geneontology/go-site/${TARGET_GO_SITE_BRANCH}/metadata/groups.yaml"

# Steps 1-5 only produce the logs the summary reads; their model and
# index outputs are discarded with the container.
su jenkins -c "
    cd /workspace/gocam-py && \
    uv run python pipeline/convert_minerva_models_to_gocam_models.py \
        --input-dir $MODELS_DIR \
        --output-dir $WORK/01-gocam-models \
        --log-file $WORK/logs/01-convert.jsonl \
        --verbose
"
su jenkins -c "
    cd /workspace/gocam-py && \
    uv run python pipeline/filter_true_gocam_models.py \
        --input-dir $WORK/01-gocam-models \
        --output-dir $WORK/02-true-gocams \
        --pseudo-gocam-output-dir $WORK/02-pseudo-gocams \
        --log-file $WORK/logs/02-filter.jsonl \
        --verbose
"
# NCBITaxon is not a GO product; it auto-downloads from OBO Foundry.
su jenkins -c "
    cd /workspace/gocam-py && \
    uv run python pipeline/add_query_index_to_models.py \
        --input-dir $WORK/02-true-gocams \
        --output-dir $WORK/03-indexed-true-gocams \
        --log-file $WORK/logs/03-index.jsonl \
        --go-adapter-descriptor pronto:$WORK/ontology/go.obo \
        --goc-groups-yaml $WORK/metadata/groups.yaml \
        --verbose
"
su jenkins -c "
    cd /workspace/gocam-py && \
    uv run python pipeline/generate_index_files.py \
        --input-dir $WORK/03-indexed-true-gocams \
        --output-dir $WORK/04-index-files \
        --log-file $WORK/logs/04-index-files.jsonl \
        --verbose
"
su jenkins -c "
    cd /workspace/gocam-py && \
    uv run python pipeline/generate_go_cam_browser_search_docs.py \
        --input-dir $WORK/03-indexed-true-gocams \
        --output $WORK/05-browser-search-docs/go-cam-browser-search-docs.json \
        --log-file $WORK/logs/05-browser-search.jsonl \
        --verbose
"

su jenkins -c "
    cd /workspace/gocam-py && \
    uv run python pipeline/generate_log_summary.py \
        --logs-dir $WORK/logs \
        --excel-output $OUT_DIR/summary.xlsx \
        --html-output-dir $OUT_DIR/summary-html \
        --html-index-filename go-cam_pipeline_report.html \
        --goc-users-yaml $WORK/metadata/users.yaml \
        --goc-groups-yaml $WORK/metadata/groups.yaml \
        --metadata 'Run date=${START_DATE}' \
        --metadata 'Pipeline name=pipeline-raw-go-cam' \
        --metadata 'Pipeline branch=${BRANCH_NAME}' \
        --verbose
"

chown -R "$JENKINS_UID:$JENKINS_GID" /workspace/gocam-py "$OUT_DIR" || true
