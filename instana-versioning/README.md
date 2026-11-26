# update-version.sh

Automates version resolution and configuration generation for an Instana self-hosted deployment, given a target `INSTANA_VERSION`.

## Prerequisites

- `bash` 4+
- `curl`
- `yq` v4 (mikefarah/yq)
- `tar`
- Linux amd64 or arm64

## Usage

```bash
./update-version.sh -k <download_key> [-v <instana_version>] [-e]
```

| Flag | Required | Description |
|------|----------|-------------|
| `-k` | Yes | Download key for `artifact-public.instana.io` |
| `-v` | No | Target Instana version, e.g. `3.321.1325-0`. Defaults to the latest entry in `custom-edition-releases.yaml` |
| `-e` | No | Also generate `artifacts-amd64-<instana_version>.env`. Disabled by default |

Both `-k` and `-v` can also be supplied via environment variables `DOWNLOAD_KEY` and `INSTANA_VERSION`. CLI flags take precedence.

## Execution Steps

```
[1/10]  Download custom-edition-releases.yaml
[2/10]  Download standard-edition-releases.yaml
[3/10]  Resolve INSTANA_OPERATOR_CHART_VERSION  (custom-edition-releases.yaml)
[4/10]  Resolve STANCTL_VERSION                 (standard-edition-releases.yaml)
[5/10]  Download stanctl binary
[6/10]  Download dependencies-<stanctl_version>.yaml
[7/10]  Run stanctl versions list-images  →  <instana_version>.images.txt
[8/10]  Generate versions_<instana_version>.sh
[9/10]  Generate values-<instana_version>/        (skipped if values/ not present)
[10/10] Generate artifacts-amd64-<instana_version>.env  (only with -e)
```

## Output Files

| File | Description |
|------|-------------|
| `tmp/` | Working directory for downloaded intermediate files |
| `versions_<instana_version>.sh` | Helm chart versions for all components |
| `values-<instana_version>/` | Copy of `values/` with image tags updated |
| `<instana_version>.images.txt` | Full image list produced by `stanctl` |
| `artifacts-amd64-<instana_version>.env` | Artifact download env vars (`-e` only) |

---

## Version Resolution Logic

### Step 3 — INSTANA_OPERATOR_CHART_VERSION

Source: `custom-edition-releases.yaml`

Each release entry contains a `minSupported`/`maxSupported` range and an optional `supported` list.
The script selects every entry where `INSTANA_VERSION` appears in the `supported` list **or** falls within the `minSupported`–`maxSupported` range, then takes the **last (latest)** match.

```
INSTANA_VERSION  →  custom-edition-releases.yaml  →  INSTANA_OPERATOR_CHART_VERSION
e.g. 3.321.1325-0                                     e.g. 1.11.1
```

### Step 4 — STANCTL_VERSION

Source: `standard-edition-releases.yaml`

Same matching logic applied to `INSTANA_OPERATOR_CHART_VERSION`.

```
INSTANA_OPERATOR_CHART_VERSION  →  standard-edition-releases.yaml  →  STANCTL_VERSION
e.g. 1.11.1                                                             e.g. 1.15.0
```

---

## Mapping Tables

All values in Steps 8–10 are read from `dependencies-<stanctl_version>.yaml` unless noted otherwise.

### versions_\<instana_version\>.sh

| Variable | Source key | Field |
|----------|-----------|-------|
| `INSTANA_REGISTRY_CHART_VERSION` | — | Fixed value `1.0.0` |
| `INSTANA_OPERATOR_CHART_VERSION` | — | Resolved in Step 3 |
| `INSTANA_CORE_CHART_VERSION` | `instana-core` | `chart-version` |
| `INSTANA_UNIT_CHART_VERSION` | `instana-unit` | `chart-version` |
| `CERT_MANAGER_VERSION` | `cert-manager` | `chart-version` |
| `KAFKA_OPERATOR_CHART_VERSION` | `strimzi-kafka-operator` | `chart-version` |
| `KAFKA_INSTANCE_CHART_VERSION` | `instana-kafka` | `chart-version` |
| `ES_OPERATOR_CHART_VERSION` | `eck-operator` | `chart-version` |
| `ES_INSTANCE_CHART_VERSION` | `instana-elasticsearch` | `chart-version` |
| `POSTGRES_OPERATOR_CHART_VERSION` | `cloudnative-pg` | `chart-version` |
| `POSTGRES_INSTANCE_CHART_VERSION` | `instana-postgres` | `chart-version` |
| `CASSANDRA_OPERATOR_CHART_VERSION` | `cass-operator` | `chart-version` |
| `CASSANDRA_OPERATOR_SYSTEMLOGGER_IMAGE_TAG` | `cass-operator` | `images[system-logger].tag` |
| `CASSANDRA_OPERATOR_K8SSANDRACLIENT_IMAGE_TAG` | `cass-operator` | `images[k8ssandra-client].tag` |
| `CASSANDRA_INSTANCE_CHART_VERSION` | `instana-cassandra` | `chart-version` |
| `CLICKHOUSE_OPERATOR_CHART_VERSION` | `ibm-clickhouse-operator` | `chart-version` |
| `CLICKHOUSE_INSTANCE_CHART_VERSION` | `instana-clickhouse` | `chart-version` |
| `BEEINSTANA_OPERATOR_CHART_VERSION` | `beeinstana-operator` | `chart-version` |
| `BEEINSTANA_INSTANCE_CHART_VERSION` | `instana-beeinstana` | `chart-version` |

### values-\<instana_version\>/ — updated fields

| Component directory | YAML field | Source key | Image repository match |
|--------------------|-----------|-----------|----------------------|
| `core/` | `.imageConfig.tag` | — | `INSTANA_VERSION` (direct) |
| `beeinstana-operator/` | `.image.tag` | `beeinstana-operator` | `beeinstana/operator` |
| `beeinstana/` | `.version` | `instana-beeinstana` | `vendor-version` |
| `beeinstana/` | `.aggregator.image.tag` | `instana-beeinstana` | `beeinstana/aggregator` |
| `beeinstana/` | `.config.image.tag` | `instana-beeinstana` | `beeinstana/monconfig` |
| `beeinstana/` | `.ingestor.image.tag` | `instana-beeinstana` | `beeinstana/ingestor` |
| `cassandra/` | `.image.tag` | `instana-cassandra` | `datastore/cassandra` |
| `cassandra/` | `.version` | `instana-cassandra` | `vendor-version` |
| `cassandra-operator/` | `.image.tag` | `cass-operator` | `operator/cass-operator` |
| `cassandra-operator/` | `.appVersion` | `cass-operator` | first segment of operator tag, e.g. `1.26.0_v0.34.0` → `1.26.0` |
| `clickhouse/` | `.image.tag` | `instana-clickhouse` | `clickhouse` |
| `clickhouse-operator/` | `.operator.image.tag` | `ibm-clickhouse-operator` | `clickhouse-operator` |
| `elasticsearch/` | `.image.tag` | `instana-elasticsearch` | `datastore/elasticsearch` |
| `elasticsearch/` | `.version` | `instana-elasticsearch` | `vendor-version` |
| `elasticsearch-operator/` | `.image.tag` | `eck-operator` | `operator/elasticsearch` |
| `kafka/` | `.image.tag` | `instana-kafka` | `datastore/kafka` |
| `kafka/` | `.version` | `instana-kafka` | `vendor-version` |
| `kafka-operator/` | `.image.tag` | `strimzi-kafka-operator` | `operator/strimzi` |
| `kafka-operator/` | `.topicOperator.image.tag` | `strimzi-kafka-operator` | `operator/strimzi` |
| `kafka-operator/` | `.userOperator.image.tag` | `strimzi-kafka-operator` | `operator/strimzi` |
| `postgres/` | `.image.tag` | `instana-postgres` | `cnpg-containers` |
| `postgres-operator/` | `.image.tag` | `cloudnative-pg` | `operator/cloudnative-pg` |

> **Note:** `cert-manager/`, `unit/`, `instana-operator/` are copied as-is — no image tag updates.

### artifacts-amd64-\<instana_version\>.env (with `-e`)

| Variable | Source key | Field | Notes |
|----------|-----------|-------|-------|
| `INSTANA_CORE_IMAGE_TAG` | — | `INSTANA_VERSION` | direct |
| `INSTANA_CORE_ENVOY_IMAGE_TAG` | `instana-core` | `images[k8s/envoy].tag` | |
| `INSTANA_OPERATOR_IMAGE_TAG` | — | `INSTANA_OPERATOR_CHART_VERSION` | direct |
| `CERT_MANAGER_HELM_CHART_VERSION` | `cert-manager` | `chart-version` | leading `v` stripped |
| `KAFKA_HELM_CHART_VERSION` | `strimzi-kafka-operator` | `chart-version` | |
| `KAFKA_OPERATOR_IMAGE_TAG` | `strimzi-kafka-operator` | `images[operator/strimzi].tag` | |
| `KAFKA_VERSION` | `instana-kafka` | `vendor-version` | |
| `KAFKA_IMAGE_TAG` | `instana-kafka` | `images[datastore/kafka].tag` | |
| `ELASTIC_HELM_CHART_VERSION` | `eck-operator` | `chart-version` | |
| `ELASTIC_OPERATOR_IMAGE_TAG` | `eck-operator` | `images[operator/elasticsearch].tag` | |
| `ELASTIC_VERSION` | `instana-elasticsearch` | `vendor-version` | |
| `ELASTIC_IMAGE_TAG` | `instana-elasticsearch` | `images[datastore/elasticsearch].tag` | |
| `POSTGRES_HELM_CHART_VERSION` | `cloudnative-pg` | `chart-version` | |
| `POSTGRES_OPERATOR_IMAGE_TAG` | `cloudnative-pg` | `images[operator/cloudnative-pg].tag` | |
| `POSTGRES_IMAGE_TAG` | `instana-postgres` | `images[cnpg-containers].tag` | |
| `CASSANDRA_HELM_CHART_VERSION` | `cass-operator` | `chart-version` | |
| `CASSANDRA_OPERATOR_IMAGE_TAG` | `cass-operator` | `images[operator/cass-operator].tag` | |
| `CASSANDRA_OPERATOR_APP_VERSION` | `cass-operator` | `images[operator/cass-operator].tag` | first segment before `_` |
| `CASSANDRA_SERVER_VERSION` | `instana-cassandra` | `vendor-version` | |
| `CASSANDRA_SYSTEMLOGGER_IMAGE_TAG` | `cass-operator` | `images[system-logger].tag` | |
| `CASSANDRA_K8SSANDRACLIENT_IMAGE_TAG` | `cass-operator` | `images[k8ssandra-client].tag` | |
| `CASSANDRA_SERVER_IMAGE_TAG` | `instana-cassandra` | `images[datastore/cassandra].tag` | |
| `CLICKHOUSE_HELM_CHART_VERSION` | `ibm-clickhouse-operator` | `chart-version` | |
| `CLICKHOUSE_OPERATOR_IMAGE_TAG` | `ibm-clickhouse-operator` | `images[clickhouse-operator].tag` | |
| `CLICKHOUSE_IMAGE_TAG` | `instana-clickhouse` | `images[clickhouse].tag` | |
| `BEEINSTANA_HELM_CHART_VERSION` | `beeinstana-operator` | `chart-version` | |
| `BEEINSTANA_OPERATOR_IMAGE_TAG` | `beeinstana-operator` | `images[beeinstana/operator].tag` | |
| `BEEINSTANA_VERSION` | `instana-beeinstana` | `vendor-version` | |
| `BEEINSTANA_AGGREGATOR_IMAGE_TAG` | `instana-beeinstana` | `images[beeinstana/aggregator].tag` | |
| `BEEINSTANA_MONCONFIG_IMAGE_TAG` | `instana-beeinstana` | `images[beeinstana/monconfig].tag` | |
| `BEEINSTANA_INGESTOR_IMAGE_TAG` | `instana-beeinstana` | `images[beeinstana/ingestor].tag` | |
| `NFS_CLIENT_HELM_CHART_VERSION` | — | Fixed value `4.0.18` | not in dependencies yaml |
