# Required Docker Images for IBM POWER Installation

```text
|----|------------------------|----------------------------|------------------------------------------------------------------------------|-----------------------------|
| No | Image                  |Registry                    | Repository                                                                   |   Tag                       |
|----|------------------------|----------------------------|------------------------------------------------------------------------------|-----------------------------|
| 1  | Elasticsearch          | artifact-public.instana.io | self-hosted-images/3rd-party/datastore/elasticsearch                         | 8.19.13_v0.40.0             |
| 2  | Elasticsearch Operator | artifact-public.instana.io | self-hosted-images/3rd-party/operator/elasticsearch                          | 3.0.0_v0.26.0               |
| 3  | Kafka                  | artifact-public.instana.io | self-hosted-images/3rd-party/datastore/kafka                                 | 0.51.0-kafka-4.1.1_v0.32.0  |
| 4  | Strimzi                | artifact-public.instana.io | self-hosted-images/3rd-party/operator/strimzi                                | 0.51.0_v0.32.0              |
| 5  | Postgres Operator      | artifact-public.instana.io | self-hosted-images/3rd-party/operator/cloudnative-pg                         | v1.29.0_v0.33.0             |
| 5  | Postgres               | artifact-public.instana.io | self-hosted-images/3rd-party/datastore/cnpg-containers                       | 15_v0.37.0                  |
| 5  | Aggregrator            | artifact-public.instana.io | beeinstana/aggregator                                                        | v1.164.3-release            |
| 5  | Monoconfig             | artifact-public.instana.io | beeinstana/monconfig                                                         | v2.46.0                     |
| 5  | Ingestor               | artifact-public.instana.io | beeinstana/ingestor                                                          | v1.164.3-release            |
| 5  | Beeinstana Operator    | artifact-public.instana.io | beeinstana/operator                                                          | v1.101.0                    |
| 4  | Cassandra              | artifact-public.instana.io | self-hosted-images/3rd-party/datastore/cassandra                             | 4.1.8_v0.32.0               |
| 4  | k8ssandra-client       | artifact-public.instana.io | self-hosted-images/3rd-party/datastore/k8ssandra-client                      | 0.8.9_v0.32.0               |
| 4  | System Logger          | artifact-public.instana.io | self-hosted-images/3rd-party/datastore/system-logger                         | 1.26.0_v0.18.0              |
| 5  | Cassandra Operator     | artifact-public.instana.io | self-hosted-images/3rd-party/operator/cass-operator                          | 1.26.0_v0.39.0              |
| 4  | Clickhouse             | artifact-public.instana.io | clickhouse-openssl                                                           | 25.8.13.1-1-lts-ibm         |
| 5  | Clickhouse Operator    | artifact-public.instana.io | clickhouse-operator                                                          | v1.2.0                      |
|----|------------------------|----------------------------|------------------------------------------------------------------------------|-----------------------------|
```

- The basic configuration is consistent across all architectures. Below is a sample configuration for defining images in custom_values.yaml.
- For a detailed explanation of the file structure, refer to the README.md.
- The instana_values.yaml file contains the default configuration values. If you need custom values, create a custom_values.yaml.
- Any image definitions added in custom_values.yaml will override the default image values.
- If custom_values.yaml is not provided, the deployment will use the values from instana_values.yaml.
- The registry and repository are consistent across all datastore and operator images, with the exception of the Elasticsearch datastore, which uses a different repository path.
- Therefore, only the tags need to be added or updated in the configuration; the remaining fields can be omitted if the repository stays unchanged.

## Datastores Configuration

### Beeinstana

```text
aggregator:
  image:
    tag: <tag>
    name: <repository>
config:
  image:
    tag: <tag>
    name: <repository>
ingestor:
  image:
    tag: <tag>
    name: <repository>
```

#### Beeinstana Operator

```text
image:
  tag: <tag>
  repository: <repository>
```

#### Cassandra Operator

```text
image:
  tag: <tag>
  repository: <repository>
imageConfig:
  systemLogger: <regisry>/<repository>:<tag>
  k8ssandraClient: <registry>/<repository>:<tag>
appVersion: <cassandra_version>
```

#### Cassandra

```text
image:
  tag: "<tag>"
version: <cassandra_version>
```

#### Elastic Operator

```text
image:
  tag: "<tag>"
  repository: "<registry>/<repository>"
```

#### Elastic

```text
image:
  tag: "<tag>"
  repository: <repository>
  registry: <registry>
imagePullSecrets:
  - name: "instana-registry"
version: <es_version>

```

#### Clickhouse Operator

```text
operator:
  image:
    tag: <tag>
    repository: <registry>/<repository>
```

#### Clickhouse

```text

image:
  tag: "<tag>"
  repository: "clickhouse"

```

#### Kafka Operator

Use operator image for image , topicOperator and userOperator

```text
image:
  tag: <tag>
  registry: <registry>
  repository: <repository>
topicOperator:
  image:
    tag: <tag>
    registry: <registry>
    repository: <repository>
userOperator:
  image:
    tag: <tag>
    registry: <registry>
    repository: <repository>

```

#### Kafka

```text
image:
  tag: "<tag>"
  registry: "<registry>"
  repository: "<repository>"
```

#### Postgres Operator

```text
image:
  tag: <tag>
  repository: "<registry>/<repository>"
```

#### Postgres

```text
image:
  tag: "<tag>"
  registry: "<registry>"
  repository: "<repository>"
```

#### Elasticsearch configuration for OCP

Update the `deploy/values/elasticsearch/instana-values-ocp.yaml` file to set `xpack.ml.enabled: false`

```text
      node.store.allow_mmap: false
      xpack.ml.enabled: false
      search.max_buckets: 300000
```
