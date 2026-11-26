#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# Usage
# ──────────────────────────────────────────────
usage() {
  echo "Usage: $0 -k <download_key> [-v <instana_version>] [-e]"
  echo ""
  echo "  -k  Download key for artifact-public.instana.io (required)"
  echo "  -v  Instana version, e.g. 3.321.1325-0 (optional, defaults to latest in custom-edition-releases.yaml)"
  echo "  -e  Generate artifacts-amd64-<instana_version>.env (optional, disabled by default)"
  exit 1
}

# ──────────────────────────────────────────────
# Parse arguments (flags override env vars)
# ──────────────────────────────────────────────
INSTANA_VERSION="${INSTANA_VERSION:-}"
DOWNLOAD_KEY="${DOWNLOAD_KEY:-}"
GEN_ARTIFACTS_ENV=false

while getopts ":k:v:e" opt; do
  case "${opt}" in
    k) DOWNLOAD_KEY="${OPTARG}" ;;
    v) INSTANA_VERSION="${OPTARG}" ;;
    e) GEN_ARTIFACTS_ENV=true ;;
    *) usage ;;
  esac
done

if [[ -z "${DOWNLOAD_KEY}" ]]; then
  echo "Error: DOWNLOAD_KEY is not set. Provide it via -k <key> or the DOWNLOAD_KEY environment variable." >&2
  usage
fi

BASE_URL="https://artifact-public.instana.io/artifactory/rel-generic-instana-virtual/versioning"
CUSTOM_YAML_URL="${BASE_URL}/custom-edition-releases.yaml"
STANDARD_YAML_URL="${BASE_URL}/standard-edition-releases.yaml"

# WORKDIR="$(mktemp -d)"
# trap 'rm -rf "${WORKDIR}"' EXIT

WORKDIR="$(dirname "$0")/tmp"
mkdir -p "${WORKDIR}"


CUSTOM_YAML="${WORKDIR}/custom-edition-releases.yaml"
STANDARD_YAML="${WORKDIR}/standard-edition-releases.yaml"

# ──────────────────────────────────────────────
# Step 1 & 2: Download versioning yaml files
# ──────────────────────────────────────────────
echo "[1/8] Downloading custom-edition-releases.yaml ..."
curl -fsSL -u "_:${DOWNLOAD_KEY}" -o "${CUSTOM_YAML}" "${CUSTOM_YAML_URL}"

echo "[2/8] Downloading standard-edition-releases.yaml ..."
curl -fsSL -u "_:${DOWNLOAD_KEY}" -o "${STANDARD_YAML}" "${STANDARD_YAML_URL}"

# If INSTANA_VERSION not specified, use the latest supported version from custom-edition-releases.yaml
if [[ -z "${INSTANA_VERSION}" ]]; then
  INSTANA_VERSION=$(yq '.releases[-1].supported[-1] // .releases[-1].maxSupported' "${CUSTOM_YAML}")
  echo "    INSTANA_VERSION not specified, using latest: ${INSTANA_VERSION}"
fi

# ──────────────────────────────────────────────
# Step 3: custom-edition-releases.yaml → INSTANA_OPERATOR_CHART_VERSION
# Match against the supported list first, fall back to min/maxSupported range.
# Take the last (latest) match.
# ──────────────────────────────────────────────
echo "[3/8] Looking up operator chart version for ${INSTANA_VERSION} in custom-edition-releases.yaml ..."
INSTANA_OPERATOR_CHART_VERSION=$(
  TARGET="${INSTANA_VERSION}" yq '
    .releases[] | select(
      (.supported // [] | contains([strenv(TARGET)]))
      or (.minSupported <= strenv(TARGET) and .maxSupported >= strenv(TARGET))
    ) | .version
  ' "${CUSTOM_YAML}" | tail -1
)

if [[ -z "${INSTANA_OPERATOR_CHART_VERSION}" ]]; then
  echo "Error: no release found for ${INSTANA_VERSION} in custom-edition-releases.yaml" >&2
  exit 1
fi

# ──────────────────────────────────────────────
# Step 4: standard-edition-releases.yaml → STANCTL_VERSION
# ──────────────────────────────────────────────
echo "[4/8] Looking up stanctl version for ${INSTANA_OPERATOR_CHART_VERSION} in standard-edition-releases.yaml ..."
STANCTL_VERSION=$(
  TARGET="${INSTANA_OPERATOR_CHART_VERSION}" yq '
    .releases[] | select(
      (.supported // [] | contains([strenv(TARGET)]))
      or (.minSupported <= strenv(TARGET) and .maxSupported >= strenv(TARGET))
    ) | .version
  ' "${STANDARD_YAML}" | tail -1
)

if [[ -z "${STANCTL_VERSION}" ]]; then
  echo "Error: no release found for ${INSTANA_OPERATOR_CHART_VERSION} in standard-edition-releases.yaml" >&2
  exit 1
fi

# ──────────────────────────────────────────────
# Step 5: Download stanctl
# ──────────────────────────────────────────────
ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64)        ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "Error: unsupported architecture ${ARCH}, only linux amd64/arm64 is supported" >&2; exit 1 ;;
esac

STANCTL_FILE="stanctl-linux_${ARCH}-${STANCTL_VERSION}.tar.gz"
STANCTL_URL="https://artifact-public.instana.io/artifactory/rel-generic-instana-virtual/stanctl/${STANCTL_FILE}"
STANCTL_DIR="${WORKDIR}/stanctl"

echo ""
echo "[5/8] Downloading stanctl ${STANCTL_VERSION} ..."
curl -fsSL -u "_:${DOWNLOAD_KEY}" -o "${WORKDIR}/${STANCTL_FILE}" "${STANCTL_URL}"

# ──────────────────────────────────────────────
# Step 6: Download dependencies yaml
# ──────────────────────────────────────────────
DEPS_FILE="dependencies-${STANCTL_VERSION}.yaml"
DEPS_URL="https://artifact-public.instana.io/artifactory/rel-generic-instana-virtual/dependencies/${DEPS_FILE}"
DEPS_YAML="${WORKDIR}/${DEPS_FILE}"

echo ""
echo "[6/8] Downloading ${DEPS_FILE} ..."
curl -fsSL -u "_:${DOWNLOAD_KEY}" -o "${DEPS_YAML}" "${DEPS_URL}"

# ──────────────────────────────────────────────
# Step 7: Extract and list images
# ──────────────────────────────────────────────
echo "[7/8] Extracting stanctl and fetching image list ..."
mkdir -p "${STANCTL_DIR}"
tar -xzf "${WORKDIR}/${STANCTL_FILE}" -C "${STANCTL_DIR}"

IMAGES_FILE="${WORKDIR}/${INSTANA_VERSION}.images.txt"
"${STANCTL_DIR}/stanctl" versions list-images \
  --registry-url https://artifact-public.instana.io/artifactory/rel-generic-instana-virtual \
  --registry-user "_" \
  --download-key "${DOWNLOAD_KEY}" \
  --instana-version "${INSTANA_VERSION}" \
  > "${IMAGES_FILE}"

# ──────────────────────────────────────────────
# Step 8: Generate updated-versions.sh
# ──────────────────────────────────────────────
echo "[8/9] Generating updated-versions.sh ..."

# Helper: get chart-version from dependencies yaml by top-level key
dep_chart() { yq ".[\"$1\"].chart-version" "${DEPS_YAML}"; }

# Helper: get image tag from dependencies yaml by key + repository substring
dep_tag() {
  local key="$1" repo_substr="$2"
  yq ".[\"${key}\"].images[] | select(.repository | contains(\"${repo_substr}\")) | .tag" "${DEPS_YAML}"
}

UPDATED_VERSIONS_FILE="versions_${INSTANA_VERSION}.sh"
cat > "${UPDATED_VERSIONS_FILE}" << EOF
# (c) Copyright IBM Corp. 2025
# Auto-generated for INSTANA_VERSION=${INSTANA_VERSION}

# instana registry
INSTANA_REGISTRY_CHART_VERSION=1.0.0

# instana operator
INSTANA_OPERATOR_CHART_VERSION=${INSTANA_OPERATOR_CHART_VERSION}

# core
INSTANA_CORE_CHART_VERSION=$(dep_chart instana-core)

# unit
INSTANA_UNIT_CHART_VERSION=$(dep_chart instana-unit)

# cert-manager
CERT_MANAGER_VERSION=$(dep_chart cert-manager)

# kafka
KAFKA_OPERATOR_CHART_VERSION=$(dep_chart strimzi-kafka-operator)
KAFKA_INSTANCE_CHART_VERSION=$(dep_chart instana-kafka)

# elasticsearch
ES_OPERATOR_CHART_VERSION=$(dep_chart eck-operator)
ES_INSTANCE_CHART_VERSION=$(dep_chart instana-elasticsearch)

# postgres
POSTGRES_OPERATOR_CHART_VERSION=$(dep_chart cloudnative-pg)
POSTGRES_INSTANCE_CHART_VERSION=$(dep_chart instana-postgres)

# cassandra
CASSANDRA_OPERATOR_CHART_VERSION=$(dep_chart cass-operator)
CASSANDRA_OPERATOR_SYSTEMLOGGER_IMAGE_TAG=$(dep_tag cass-operator system-logger)
CASSANDRA_OPERATOR_K8SSANDRACLIENT_IMAGE_TAG=$(dep_tag cass-operator k8ssandra-client)
CASSANDRA_INSTANCE_CHART_VERSION=$(dep_chart instana-cassandra)

# clickhouse
CLICKHOUSE_OPERATOR_CHART_VERSION=$(dep_chart ibm-clickhouse-operator)
CLICKHOUSE_INSTANCE_CHART_VERSION=$(dep_chart instana-clickhouse)

# beeinstana
BEEINSTANA_OPERATOR_CHART_VERSION=$(dep_chart beeinstana-operator)
BEEINSTANA_INSTANCE_CHART_VERSION=$(dep_chart instana-beeinstana)
EOF

# ──────────────────────────────────────────────
# Step 9: Generate values-${INSTANA_VERSION}/ with updated image tags
# ──────────────────────────────────────────────
echo "[9/10] Generating values-${INSTANA_VERSION}/ ..."

SCRIPT_DIR="$(dirname "$0")"
VALUES_SRC="${SCRIPT_DIR}/values"
VALUES_DST="${SCRIPT_DIR}/values-${INSTANA_VERSION}"

# Copy entire values/ tree as baseline (skip if source does not exist)
if [[ ! -d "${VALUES_SRC}" ]]; then
  echo "Warning: ${VALUES_SRC} not found, skipping values directory update."
  VALUES_DST=""
else
  cp -r "${VALUES_SRC}" "${VALUES_DST}"
fi

# Helper: update a single yaml field in-place (no-op if VALUES_DST is unset)
yq_set() {
  local file="$1" path="$2" value="$3"
  [[ -z "${VALUES_DST}" ]] && return 0
  yq -i "${path} = \"${value}\"" "${file}"
}

# beeinstana-operator: image.tag
yq_set "${VALUES_DST}/beeinstana-operator/instana-values.yaml" \
  ".image.tag" \
  "$(dep_tag beeinstana-operator beeinstana/operator)"

# beeinstana: version + three image tags
yq_set "${VALUES_DST}/beeinstana/instana-values.yaml" \
  ".version" \
  "$(yq '."instana-beeinstana"."vendor-version"' "${DEPS_YAML}")"
yq_set "${VALUES_DST}/beeinstana/instana-values.yaml" \
  ".aggregator.image.tag" \
  "$(dep_tag instana-beeinstana beeinstana/aggregator)"
yq_set "${VALUES_DST}/beeinstana/instana-values.yaml" \
  ".config.image.tag" \
  "$(dep_tag instana-beeinstana beeinstana/monconfig)"
yq_set "${VALUES_DST}/beeinstana/instana-values.yaml" \
  ".ingestor.image.tag" \
  "$(dep_tag instana-beeinstana beeinstana/ingestor)"

# cassandra: image.tag + version (vendor-version)
yq_set "${VALUES_DST}/cassandra/instana-values.yaml" \
  ".image.tag" \
  "$(dep_tag instana-cassandra datastore/cassandra)"
yq_set "${VALUES_DST}/cassandra/instana-values.yaml" \
  ".version" \
  "$(yq '."instana-cassandra"."vendor-version"' "${DEPS_YAML}")"

# cassandra-operator: image.tag + appVersion (first segment of the operator tag)
CASS_OPERATOR_TAG="$(dep_tag cass-operator operator/cass-operator)"
CASS_OPERATOR_APP_VERSION="${CASS_OPERATOR_TAG%%_*}"
yq_set "${VALUES_DST}/cassandra-operator/instana-values.yaml" ".image.tag"    "${CASS_OPERATOR_TAG}"
yq_set "${VALUES_DST}/cassandra-operator/instana-values.yaml" ".appVersion"   "${CASS_OPERATOR_APP_VERSION}"

# clickhouse: image.tag
yq_set "${VALUES_DST}/clickhouse/instana-values.yaml" \
  ".image.tag" \
  "$(dep_tag instana-clickhouse clickhouse)"

# clickhouse-operator: operator.image.tag
yq_set "${VALUES_DST}/clickhouse-operator/instana-values.yaml" \
  ".operator.image.tag" \
  "$(dep_tag ibm-clickhouse-operator clickhouse-operator)"

# elasticsearch: image.tag + version (vendor-version)
yq_set "${VALUES_DST}/elasticsearch/instana-values.yaml" \
  ".image.tag" \
  "$(dep_tag instana-elasticsearch datastore/elasticsearch)"
yq_set "${VALUES_DST}/elasticsearch/instana-values.yaml" \
  ".version" \
  "$(yq '."instana-elasticsearch"."vendor-version"' "${DEPS_YAML}")"

# elasticsearch-operator: image.tag
yq_set "${VALUES_DST}/elasticsearch-operator/instana-values.yaml" \
  ".image.tag" \
  "$(dep_tag eck-operator operator/elasticsearch)"

# kafka: image.tag + version (vendor-version)
KAFKA_VENDOR_VERSION="$(yq '."instana-kafka"."vendor-version"' "${DEPS_YAML}")"
yq_set "${VALUES_DST}/kafka/instana-values.yaml" ".image.tag" "$(dep_tag instana-kafka datastore/kafka)"
yq_set "${VALUES_DST}/kafka/instana-values.yaml" ".version"   "${KAFKA_VENDOR_VERSION}"

# kafka-operator: three image tags (all same strimzi tag)
STRIMZI_TAG="$(dep_tag strimzi-kafka-operator operator/strimzi)"
yq_set "${VALUES_DST}/kafka-operator/instana-values.yaml" ".image.tag"               "${STRIMZI_TAG}"
yq_set "${VALUES_DST}/kafka-operator/instana-values.yaml" ".topicOperator.image.tag"  "${STRIMZI_TAG}"
yq_set "${VALUES_DST}/kafka-operator/instana-values.yaml" ".userOperator.image.tag"   "${STRIMZI_TAG}"

# postgres: image.tag
yq_set "${VALUES_DST}/postgres/instana-values.yaml" \
  ".image.tag" \
  "$(dep_tag instana-postgres cnpg-containers)"

# postgres-operator: image.tag
yq_set "${VALUES_DST}/postgres-operator/instana-values.yaml" \
  ".image.tag" \
  "$(dep_tag cloudnative-pg operator/cloudnative-pg)"

# core: add/update imageConfig.tag with INSTANA_VERSION
yq_set "${VALUES_DST}/core/instana-values.yaml" \
  ".imageConfig.tag" \
  "${INSTANA_VERSION}"

# ──────────────────────────────────────────────
# Step 10 (optional): Generate artifacts-amd64-${INSTANA_VERSION}.env
# ──────────────────────────────────────────────
ARTIFACTS_ENV_FILE=""
if ${GEN_ARTIFACTS_ENV}; then
  ARTIFACTS_ENV_FILE="${SCRIPT_DIR}/artifacts-amd64-${INSTANA_VERSION}.env"
  echo "[10/10] Generating $(basename "${ARTIFACTS_ENV_FILE}") ..."

  # cert-manager chart version has a leading 'v', strip it for the helm chart version number
  CERT_CHART_VER="$(dep_chart cert-manager)"
  CERT_HELM_VER="${CERT_CHART_VER#v}"

  CASSANDRA_SERVER_TAG="$(dep_tag instana-cassandra datastore/cassandra)"
  CASSANDRA_SERVER_VERSION="$(yq '."instana-cassandra"."vendor-version"' "${DEPS_YAML}")"
  BEEINSTANA_VERSION="$(yq '."instana-beeinstana"."vendor-version"' "${DEPS_YAML}")"

  cat > "${ARTIFACTS_ENV_FILE}" << EOF
### Used variables defined in credentials.env

### Versions
INSTANA_CORE_IMAGE_TAG=${INSTANA_VERSION}
INSTANA_CORE_ENVOY_IMAGE_TAG=$(dep_tag instana-core k8s/envoy)
INSTANA_OPERATOR_IMAGE_TAG=${INSTANA_OPERATOR_CHART_VERSION}


## kubectl plugin
KUBECTL_INSTANA_PLUGIN_URL=https://artifact-public.instana.io/artifactory/rel-generic-instana-virtual/infrastructure/kubectl
KUBECTL_INSTANA_PLUGIN=instana-kubectl-plugin-linux_amd64-\${INSTANA_OPERATOR_IMAGE_TAG}.tar.gz


## nfs-client
NFS_CLIENT_HELM_CHART_VERSION=4.0.18

### Certification manager
CERT_MANAGER_HELM_CHART_VERSION=${CERT_HELM_VER}
CERT_MANAGER_HELM_CHART=cert-manager-v\${CERT_MANAGER_HELM_CHART_VERSION}.tgz
CERT_MANAGER_IMAGE_REPOSITORY=jetstack

## Kafka
KAFKA_HELM_CHART_VERSION=$(dep_chart strimzi-kafka-operator)
KAFKA_HELM_CHART=strimzi-kafka-operator-\${KAFKA_HELM_CHART_VERSION}.tgz
KAFKA_IMAGE_REGISTRY=\${INSTANA_IMAGE_REGISTRY}
KAFKA_OPERATOR_IMAGE_REPOSITORY=\${INSTANA_DATASTORE_OPERATOR_IMAGE_REPOSITORY}
KAFKA_OPERATOR_IMAGE_NAME=strimzi
KAFKA_OPERATOR_IMAGE_TAG=$(dep_tag strimzi-kafka-operator operator/strimzi)
KAFKA_VERSION=${KAFKA_VENDOR_VERSION}
KAFKA_IMAGE_REPOSITORY=\${INSTANA_DATASTORE_IMAGE_REPOSITORY}
KAFKA_IMAGE_NAME=kafka
KAFKA_IMAGE_TAG=$(dep_tag instana-kafka datastore/kafka)

## Elasticsearch
ELASTIC_HELM_CHART_VERSION=$(dep_chart eck-operator)
ELASTIC_HELM_CHART=eck-operator-\${ELASTIC_HELM_CHART_VERSION}.tgz
ELASTIC_OPERATOR_IMAGE_NAME=\${INSTANA_IMAGE_REGISTRY}/\${INSTANA_DATASTORE_OPERATOR_IMAGE_REPOSITORY}/elasticsearch
ELASTIC_OPERATOR_IMAGE_TAG=$(dep_tag eck-operator operator/elasticsearch)
ELASTIC_VERSION=$(yq '."instana-elasticsearch"."vendor-version"' "${DEPS_YAML}")
ELASTIC_IMAGE_TAG=$(dep_tag instana-elasticsearch datastore/elasticsearch)
ELASTIC_IMAGE_NAME=\${INSTANA_IMAGE_REGISTRY}/\${INSTANA_DATASTORE_IMAGE_REPOSITORY}/elasticsearch:\${ELASTIC_IMAGE_TAG}


## Postgres
POSTGRES_HELM_CHART_VERSION=$(dep_chart cloudnative-pg)
POSTGRES_HELM_CHART=cloudnative-pg-\${POSTGRES_HELM_CHART_VERSION}.tgz
POSTGRES_OPERATOR_IMAGE_NAME=\${INSTANA_IMAGE_REGISTRY}/\${INSTANA_DATASTORE_OPERATOR_IMAGE_REPOSITORY}/cloudnative-pg
POSTGRES_OPERATOR_IMAGE_TAG=$(dep_tag cloudnative-pg operator/cloudnative-pg)
POSTGRES_IMAGE_NAME=\${INSTANA_IMAGE_REGISTRY}/\${INSTANA_DATASTORE_IMAGE_REPOSITORY}/cnpg-containers
POSTGRES_IMAGE_TAG=$(dep_tag instana-postgres cnpg-containers)

## Cassandra
CASSANDRA_HELM_CHART_VERSION=$(dep_chart cass-operator)
CASSANDRA_HELM_CHART=cass-operator-\${CASSANDRA_HELM_CHART_VERSION}.tgz
CASSANDRA_IMAGE_REGISTRY=\${INSTANA_IMAGE_REGISTRY}
CASSANDRA_OPERATOR_IMAGE_NAME=\${INSTANA_DATASTORE_OPERATOR_IMAGE_REPOSITORY}/cass-operator
CASSANDRA_OPERATOR_IMAGE_TAG=${CASS_OPERATOR_TAG}
CASSANDRA_OPERATOR_APP_VERSION=${CASS_OPERATOR_APP_VERSION}
CASSANDRA_IMAGE_REPOSITORY=\${INSTANA_DATASTORE_IMAGE_REPOSITORY}
CASSANDRA_SERVER_VERSION=${CASSANDRA_SERVER_VERSION}
CASSANDRA_SYSTEMLOGGER_IMAGE_TAG=$(dep_tag cass-operator system-logger)
CASSANDRA_SYSTEMLOGGER_IMAGE_NAME=\${INSTANA_IMAGE_REGISTRY}/\${INSTANA_DATASTORE_IMAGE_REPOSITORY}/system-logger:\${CASSANDRA_SYSTEMLOGGER_IMAGE_TAG}
CASSANDRA_K8SSANDRACLIENT_IMAGE_TAG=$(dep_tag cass-operator k8ssandra-client)
CASSANDRA_K8SSANDRACLIENT_IMAGE_NAME=\${INSTANA_IMAGE_REGISTRY}/\${INSTANA_DATASTORE_IMAGE_REPOSITORY}/k8ssandra-client:\${CASSANDRA_K8SSANDRACLIENT_IMAGE_TAG}
CASSANDRA_SERVER_IMAGE_TAG=${CASSANDRA_SERVER_TAG}
CASSANDRA_SERVER_IMAGE_NAME=\${INSTANA_IMAGE_REGISTRY}/\${INSTANA_DATASTORE_IMAGE_REPOSITORY}/cassandra:\${CASSANDRA_SERVER_IMAGE_TAG}

## Clickhouse
CLICKHOUSE_HELM_CHART_VERSION=$(dep_chart ibm-clickhouse-operator)
CLICKHOUSE_HELM_CHART=ibm-clickhouse-operator-\${CLICKHOUSE_HELM_CHART_VERSION}.tgz
CLICKHOUSE_OPERATOR_IMAGE_NAME=\${INSTANA_IMAGE_REGISTRY}/clickhouse-operator
CLICKHOUSE_OPERATOR_IMAGE_TAG=$(dep_tag ibm-clickhouse-operator clickhouse-operator)
CLICKHOUSE_IMAGE_TAG=$(dep_tag instana-clickhouse clickhouse)
CLICKHOUSE_IMAGE_NAME=\${INSTANA_IMAGE_REGISTRY}/clickhouse:\${CLICKHOUSE_IMAGE_TAG}


## Beeinstana
BEEINSTANA_HELM_CHART_VERSION=$(dep_chart beeinstana-operator)
BEEINSTANA_HELM_CHART=beeinstana-operator-\${BEEINSTANA_HELM_CHART_VERSION}.tgz
BEEINSTANA_OPERATOR_IMAGE_NAME=beeinstana/operator
BEEINSTANA_OPERATOR_IMAGE_TAG=$(dep_tag beeinstana-operator beeinstana/operator)
BEEINSTANA_VERSION=${BEEINSTANA_VERSION}
BEEINSTANA_AGGREGATOR_IMAGE_NAME=beeinstana/aggregator
BEEINSTANA_AGGREGATOR_IMAGE_TAG=$(dep_tag instana-beeinstana beeinstana/aggregator)
BEEINSTANA_MONCONFIG_IMAGE_NAME=beeinstana/monconfig
BEEINSTANA_MONCONFIG_IMAGE_TAG=$(dep_tag instana-beeinstana beeinstana/monconfig)
BEEINSTANA_INGESTOR_IMAGE_NAME=beeinstana/ingestor
BEEINSTANA_INGESTOR_IMAGE_TAG=$(dep_tag instana-beeinstana beeinstana/ingestor)
EOF
fi

echo ""
echo "Done."
echo "  INSTANA_VERSION                = ${INSTANA_VERSION}"
echo "  INSTANA_OPERATOR_CHART_VERSION = ${INSTANA_OPERATOR_CHART_VERSION}"
echo "  STANCTL_VERSION                = ${STANCTL_VERSION}"
echo "  Image list saved to:           ${IMAGES_FILE}"
echo "  Updated versions saved to:     ${UPDATED_VERSIONS_FILE}"
[[ -n "${VALUES_DST}" ]] && echo "  Updated values saved to:       ${VALUES_DST}/"
if ${GEN_ARTIFACTS_ENV}; then
  echo "  Artifacts env saved to:        ${ARTIFACTS_ENV_FILE}"
fi

