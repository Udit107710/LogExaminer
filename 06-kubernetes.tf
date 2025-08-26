############################################
# Phase 2: Kubernetes/Helm Resources
############################################

# External Secrets Operator - Manages secrets from AWS Secrets Manager
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = var.eso_namespace
  create_namespace = true
  version          = "0.19.2"

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_secrets.arn
  }

  depends_on = [module.eks]
}

# NOTE: SecretStore and ExternalSecret resources will be created in a subsequent deployment
# after the External Secrets Operator CRDs are installed

# Hive namespace
resource "kubernetes_namespace" "hive" {
  metadata {
    name = var.hive_namespace
  }
}

# Temporary manual secret for Hive Metastore DB (will be replaced by External Secrets later)
resource "kubernetes_secret" "hms_db_secret" {
  metadata {
    name      = "hms-db-secret"
    namespace = var.hive_namespace
  }

  data = {
    username = "hiveuser"
    password = "HiveUser123!@#Strong"
    jdbc_url = "jdbc:mysql://${aws_db_instance.hive.address}:3306/${var.db_name}?useSSL=true&amp;requireSSL=true&amp;useUnicode=true&amp;characterEncoding=UTF-8"
  }

  depends_on = [kubernetes_namespace.hive]
}

# Hive Metastore ServiceAccount with IRSA
resource "kubernetes_service_account" "hive_metastore" {
  metadata {
    name      = "hive-metastore"
    namespace = var.hive_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.spark_apps.arn
    }
  }
  depends_on = [kubernetes_namespace.hive]
}

# Hadoop core-site for Hive Metastore
resource "kubernetes_config_map" "hadoop_core_site_hive" {
  metadata {
    name      = "hadoop-core-site"
    namespace = var.hive_namespace
  }

  data = {
    "core-site.xml" = <<-EOT
      <?xml version="1.0"?>
      <configuration>
        <property>
          <name>fs.s3a.aws.credentials.provider</name>
          <value>com.amazonaws.auth.WebIdentityTokenCredentialsProvider</value>
        </property>
        <property>
          <name>fs.s3a.impl</name>
          <value>org.apache.hadoop.fs.s3a.S3AFileSystem</value>
        </property>
        <property>
          <name>fs.s3a.path.style.access</name>
          <value>false</value>
        </property>
        <property>
          <name>fs.s3a.block.size</name>
          <value>134217728</value>
        </property>
        <property>
          <name>fs.s3a.connection.timeout</name>
          <value>60000</value>
        </property>
        <property>
          <name>fs.s3a.socket.timeout</name>
          <value>60000</value>
        </property>
        <property>
          <name>fs.s3a.connection.establish.timeout</name>
          <value>60000</value>
        </property>
        <property>
          <name>fs.s3a.socket.send.buffer</name>
          <value>8192</value>
        </property>
        <property>
          <name>fs.s3a.socket.recv.buffer</name>
          <value>8192</value>
        </property>
      </configuration>
    EOT
  }

  depends_on = [kubernetes_namespace.hive]
}

# Hive Metastore ConfigMap
resource "kubernetes_config_map" "hive_metastore_config" {
  metadata {
    name      = "hive-metastore-config"
    namespace = var.hive_namespace
  }

  data = {
    "hive-site.xml" = <<-EOT
      <?xml version="1.0" encoding="UTF-8" standalone="no"?>
      <?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
      <configuration>
        <property>
          <name>javax.jdo.option.ConnectionDriverName</name>
          <value>com.mysql.cj.jdbc.Driver</value>
        </property>
        <property>
          <name>javax.jdo.option.ConnectionURL</name>
          <value>jdbc:mysql://${aws_db_instance.hive.address}:3306/${var.db_name}?useSSL=true&amp;requireSSL=true&amp;useUnicode=true&amp;characterEncoding=UTF-8</value>
        </property>
        <property>
          <name>javax.jdo.option.ConnectionUserName</name>
          <value>hiveuser</value>
        </property>
        <property>
          <name>javax.jdo.option.ConnectionPassword</name>
          <value>HiveUser123!@#Strong</value>
        </property>
        <property>
          <name>hive.metastore.warehouse.dir</name>
          <value>s3a://${local.iceberg_bucket}/warehouse/</value>
        </property>
        <property>
          <name>hive.metastore.schema.verification</name>
          <value>false</value>
        </property>
        <property>
          <name>hive.metastore.port</name>
          <value>9083</value>
        </property>
        <property>
          <name>fs.s3a.aws.credentials.provider</name>
          <value>com.amazonaws.auth.WebIdentityTokenCredentialsProvider</value>
        </property>
        <property>
          <name>fs.s3a.impl</name>
          <value>org.apache.hadoop.fs.s3a.S3AFileSystem</value>
        </property>
        <property>
          <name>fs.s3a.connection.timeout</name>
          <value>60000</value>
        </property>
        <property>
          <name>fs.s3a.socket.timeout</name>
          <value>60000</value>
        </property>
        <property>
          <name>fs.s3a.connection.establish.timeout</name>
          <value>60000</value>
        </property>
        <property>
          <name>fs.s3a.socket.send.buffer</name>
          <value>8192</value>
        </property>
        <property>
          <name>fs.s3a.socket.recv.buffer</name>
          <value>8192</value>
        </property>
        <property>
          <name>fs.s3a.multipart.size</name>
          <value>104857600</value>
        </property>
        <property>
          <name>fs.s3a.connection.maximum</name>
          <value>15</value>
        </property>
        <property>
          <name>fs.s3a.threads.max</name>
          <value>10</value>
        </property>
        <property>
          <name>fs.s3a.threads.core</name>
          <value>5</value>
        </property>
        <property>
          <name>fs.s3a.threads.keepalivetime</name>
          <value>60000</value>
        </property>
        <property>
          <name>fs.s3a.retry.limit</name>
          <value>3</value>
        </property>
        <property>
          <name>fs.s3a.retry.interval</name>
          <value>500</value>
        </property>
        <property>
          <name>fs.s3a.connection.ssl.enabled</name>
          <value>true</value>
        </property>
        <property>
          <name>fs.s3a.request.timeout</name>
          <value>60000</value>
        </property>
        <property>
          <name>fs.s3a.connection.ttl</name>
          <value>86400000</value>
        </property>
        <property>
          <name>fs.s3a.multipart.purge.age</name>
          <value>86400000</value>
        </property>
        <property>
          <name>datanucleus.autoCreateSchema</name>
          <value>false</value>
        </property>
        <property>
          <name>datanucleus.fixedDatastore</name>
          <value>true</value>
        </property>
        <property>
          <name>datanucleus.autoCreateTables</name>
          <value>false</value>
        </property>
        <property>
          <name>hive.metastore.authorization.storage.checks</name>
          <value>false</value>
        </property>
        <property>
          <name>hive.security.authorization.enabled</name>
          <value>false</value>
        </property>
        <property>
          <name>hive.security.metastore.authorization.manager</name>
          <value>org.apache.hadoop.hive.ql.security.authorization.DefaultHiveMetastoreAuthorizationProvider</value>
        </property>
        <property>
          <name>hive.support.concurrency</name>
          <value>false</value>
        </property>
        <property>
          <name>hive.txn.manager</name>
          <value>org.apache.hadoop.hive.ql.lockmgr.DummyTxnManager</value>
        </property>
        <property>
          <name>hive.compactor.initiator.on</name>
          <value>false</value>
        </property>
        <property>
          <name>hive.compactor.cleaner.on</name>
          <value>false</value>
        </property>
        <property>
          <name>hive.enforce.bucketing</name>
          <value>false</value>
        </property>
        <property>
          <name>hive.enforce.sorting</name>
          <value>false</value>
        </property>
      </configuration>
    EOT
  }

  depends_on = [kubernetes_namespace.hive]
}

# Hive Metastore Deployment
resource "kubernetes_deployment" "hive_metastore" {
  metadata {
    name      = "hive-metastore"
    namespace = var.hive_namespace
  }

  spec {
    replicas = var.hive_metastore_replicas

    selector {
      match_labels = {
        app = "hive-metastore"
      }
    }

    template {
      metadata {
        labels = {
          app = "hive-metastore"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.hive_metastore.metadata[0].name

        init_container {
          name  = "schema-init"
          image = var.hive_metastore_image
          image_pull_policy = "Always"
          command = ["/bin/bash", "-c"]
          args = [
            "/usr/local/bin/init-schema.sh"
          ]
          env {
            name  = "PATH"
            value = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/hive/bin:/opt/hadoop/bin"
          }
          env {
            name  = "JAVA_HOME"
            value = "/usr/local/openjdk-8"
          }
          env {
            name  = "HADOOP_HOME"
            value = "/opt/hadoop"
          }
          env {
            name  = "HIVE_HOME"
            value = "/opt/hive"
          }
          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = "hms-db-secret"
                key  = "password"
              }
            }
          }
          env {
            name = "JDBC_URL"
            value_from {
              secret_key_ref {
                name = "hms-db-secret"
                key  = "jdbc_url"
              }
            }
          }
          env {
            name  = "JAVAX_JDO_OPTION_CONNECTIONURL"
            value = "$(JDBC_URL)"
          }
          env {
            name  = "JAVAX_JDO_OPTION_CONNECTIONPASSWORD"
            value = "$(DB_PASSWORD)"
          }
          env {
            name  = "AWS_STS_REGIONAL_ENDPOINTS"
            value = "regional"
          }
          env {
            name  = "AWS_DEFAULT_REGION"
            value = var.aws_region
          }
          env {
            name  = "AWS_REGION"
            value = var.aws_region
          }
          env {
            name  = "AWS_ROLE_ARN"
            value = aws_iam_role.spark_apps.arn
          }
          env {
            name  = "AWS_WEB_IDENTITY_TOKEN_FILE"
            value = "/var/run/secrets/eks.amazonaws.com/serviceaccount/token"
          }
          volume_mount {
            name       = "hive-config"
            mount_path = "/opt/hive/conf"
          }
        }

        container {
          name  = "hive-metastore"
          image = var.hive_metastore_image
          image_pull_policy = "Always"
          command = ["/entrypoint.sh", "start-metastore"]

          port {
            container_port = 9083
          }

          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = "hms-db-secret"
                key  = "password"
              }
            }
          }
          env {
            name = "JDBC_URL"
            value_from {
              secret_key_ref {
                name = "hms-db-secret"
                key  = "jdbc_url"
              }
            }
          }
          env {
            name  = "JAVAX_JDO_OPTION_CONNECTIONURL"
            value = "$(JDBC_URL)"
          }
          env {
            name  = "JAVAX_JDO_OPTION_CONNECTIONPASSWORD"
            value = "$(DB_PASSWORD)"
          }
          env {
            name  = "AWS_STS_REGIONAL_ENDPOINTS"
            value = "regional"
          }
          env {
            name  = "AWS_DEFAULT_REGION"
            value = var.aws_region
          }
          env {
            name  = "AWS_REGION"
            value = var.aws_region
          }
          env {
            name  = "AWS_ROLE_ARN"
            value = aws_iam_role.spark_apps.arn
          }
          env {
            name  = "AWS_WEB_IDENTITY_TOKEN_FILE"
            value = "/var/run/secrets/eks.amazonaws.com/serviceaccount/token"
          }

          volume_mount {
            name       = "hive-config"
            mount_path = "/opt/hive/conf"
          }
          volume_mount {
            name       = "hadoop-core-site"
            mount_path = "/opt/hadoop/etc/hadoop/core-site.xml"
            sub_path   = "core-site.xml"
          }

          readiness_probe {
            tcp_socket {
              port = 9083
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          liveness_probe {
            tcp_socket {
              port = 9083
            }
            initial_delay_seconds = 60
            period_seconds        = 30
          }
        }

        volume {
          name = "hive-config"
          config_map {
            name = kubernetes_config_map.hive_metastore_config.metadata[0].name
          }
        }
        volume {
          name = "hadoop-core-site"
          config_map {
            name = kubernetes_config_map.hadoop_core_site_hive.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [kubernetes_secret.hms_db_secret]
}

# Hive Metastore Service
resource "kubernetes_service" "hive_metastore" {
  metadata {
    name      = "hive-metastore"
    namespace = var.hive_namespace
  }

  spec {
    selector = {
      app = "hive-metastore"
    }

    port {
      port        = 9083
      target_port = 9083
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_deployment.hive_metastore]
}

# Spark namespace
resource "kubernetes_namespace" "spark" {
  metadata {
    name = var.spark_namespace
  }
}

# Spark Apps ServiceAccount with IRSA
resource "kubernetes_service_account" "spark_apps" {
  metadata {
    name      = "spark-apps"
    namespace = var.spark_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.spark_apps.arn
    }
  }
  depends_on = [kubernetes_namespace.spark]
}

# Spark Operator
resource "helm_release" "spark_operator" {
  name             = "spark-operator"
  repository       = "https://kubeflow.github.io/spark-operator"
  chart            = "spark-operator"
  namespace        = var.spark_namespace
  create_namespace = false
  version          = "2.3.0"

  set {
    name  = "image.registry"
    value = "docker.io"
  }

  set {
    name  = "image.repository"
    value = "kubeflow/spark-operator"
  }

  set {
    name  = "image.tag"
    value = "2.1.1"
  }

  set {
    name  = "webhook.enable"
    value = "true"
  }

  # Configure to watch spark namespace instead of default
  set {
    name  = "operator.watchedNamespaces"
    value = var.spark_namespace
  }

  # Removed nodeSelector to allow scheduling on single node
  # set {
  #   name  = "nodeSelector.role"
  #   value = "system"
  # }

  depends_on = [kubernetes_namespace.spark, kubernetes_cluster_role_binding.spark_operator_controller_full_permissions]
}

# Additional ClusterRoleBinding to grant full spark-operator permissions to controller
resource "kubernetes_cluster_role_binding" "spark_operator_controller_full_permissions" {
  metadata {
    name = "spark-operator-controller-full-permissions"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "spark-operator"  # Use the full permissions cluster role
  }

  subject {
    kind      = "ServiceAccount"
    name      = "spark-operator-controller"
    namespace = var.spark_namespace
  }

  depends_on = [kubernetes_namespace.spark]
}

# Additional Role and RoleBinding for spark operator to manage services in spark namespace
resource "kubernetes_role" "spark_operator_services" {
  metadata {
    name      = "spark-operator-services"
    namespace = var.spark_namespace
  }

  rule {
    api_groups = [""]
    resources  = ["services"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  
  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  depends_on = [kubernetes_namespace.spark]
}

resource "kubernetes_role_binding" "spark_operator_services" {
  metadata {
    name      = "spark-operator-services"
    namespace = var.spark_namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.spark_operator_services.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "spark-operator-controller"
    namespace = var.spark_namespace
  }

  depends_on = [kubernetes_role.spark_operator_services]
}

# ClickHouse namespace
resource "kubernetes_namespace" "clickhouse" {
  metadata {
    name = var.clickhouse_namespace
  }
}

# ClickHouse ServiceAccount with IRSA
resource "kubernetes_service_account" "clickhouse" {
  metadata {
    name      = "clickhouse"
    namespace = var.clickhouse_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.clickhouse.arn
    }
  }
  depends_on = [kubernetes_namespace.clickhouse]
}

# ClickHouse Operator
resource "helm_release" "clickhouse_operator" {
  name             = "clickhouse-operator"
  repository       = "https://docs.altinity.com/clickhouse-operator"
  chart            = "altinity-clickhouse-operator"
  namespace        = var.clickhouse_namespace
  create_namespace = false
  version          = "0.25.3"

  # Removed nodeSelector to allow scheduling on single node
  # set {
  #   name  = "operator.nodeSelector.role"
  #   value = "system"
  # }

  depends_on = [kubernetes_namespace.clickhouse]
}

# NOTE: ClickHouseInstallation resource will be created in a subsequent deployment
# after the ClickHouse Operator CRDs are installed

# Cluster Autoscaler
# ClusterRole for Cluster Autoscaler
resource "kubernetes_cluster_role" "cluster_autoscaler" {
  metadata {
    name = "cluster-autoscaler"
  }

  rule {
    api_groups = [""]
    resources  = ["events", "endpoints"]
    verbs      = ["create", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/eviction"]
    verbs      = ["create"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/status"]
    verbs      = ["update"]
  }

  rule {
    api_groups = [""]
    resources  = ["endpoints"]
    resource_names = ["cluster-autoscaler"]
    verbs      = ["get", "update"]
  }

  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["watch", "list", "get", "update"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "services", "replicationcontrollers", "persistentvolumeclaims", "persistentvolumes"]
    verbs      = ["watch", "list", "get"]
  }

  rule {
    api_groups = ["extensions"]
    resources  = ["replicasets", "daemonsets"]
    verbs      = ["watch", "list", "get"]
  }

  rule {
    api_groups = ["policy"]
    resources  = ["poddisruptionbudgets"]
    verbs      = ["watch", "list"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["statefulsets", "replicasets", "daemonsets"]
    verbs      = ["watch", "list", "get"]
  }

  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses", "csinodes", "csidrivers", "csistoragecapacities"]
    verbs      = ["watch", "list", "get"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["watch", "list", "get"]
  }

  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    verbs      = ["create"]
  }

  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    resource_names = ["cluster-autoscaler"]
    verbs      = ["get", "update"]
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get", "create", "update", "patch"]
  }
}

# ClusterRoleBinding for Cluster Autoscaler
resource "kubernetes_cluster_role_binding" "cluster_autoscaler" {
  metadata {
    name = "cluster-autoscaler"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.cluster_autoscaler.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "cluster-autoscaler"
    namespace = "kube-system"
  }
}

resource "kubernetes_service_account" "cluster_autoscaler" {
  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.cluster_autoscaler.arn
    }
  }
}

resource "kubernetes_deployment" "cluster_autoscaler" {
  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"
    labels = {
      app = "cluster-autoscaler"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "cluster-autoscaler"
      }
    }

    template {
      metadata {
        labels = {
          app = "cluster-autoscaler"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.cluster_autoscaler.metadata[0].name

        # Removed nodeSelector to allow scheduling on single node
        # node_selector = {
        #   role = "system"
        # }

        container {
          name  = "cluster-autoscaler"
          image = "registry.k8s.io/autoscaling/cluster-autoscaler:v1.32.2"

          command = [
            "./cluster-autoscaler",
            "--v=4",
            "--stderrthreshold=info",
            "--cloud-provider=aws",
            "--skip-nodes-with-local-storage=false",
            "--expander=least-waste",
            "--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/${module.eks.cluster_name}",
            "--balance-similar-node-groups",
            "--skip-nodes-with-system-pods=false"
          ]

          resources {
            limits = {
              cpu    = "200m"
              memory = "1Gi"
            }
            requests = {
              cpu    = "100m"
              memory = "512Mi"
            }
          }

          env {
            name  = "AWS_REGION"
            value = var.aws_region
          }
        }
      }
    }
  }

  depends_on = [kubernetes_service_account.cluster_autoscaler]
}

# Example Spark Application (conditional)
resource "kubernetes_manifest" "example_spark_app" {
  count = var.deploy_example_spark_app ? 1 : 0

  manifest = {
    apiVersion = "sparkoperator.k8s.io/v1beta2"
    kind       = "SparkApplication"
    metadata = {
      name      = "spark-iceberg-example"
      namespace = var.spark_namespace
    }
    spec = {
      type                = "Scala"
      mode                = "cluster"
      image               = var.spark_image
      imagePullPolicy     = "IfNotPresent"
      mainApplicationFile = "local:///opt/spark/examples/jars/spark-examples_2.12-3.5.1.jar"
      mainClass           = "org.apache.spark.examples.SparkPi"
      sparkVersion        = "3.5.1"

      deps = {
        packages = [var.spark_jars_packages]
      }

      driver = {
        cores         = 1
        memory        = "1024m"
        labels = {
          version = "3.5.1"
        }
        serviceAccount = kubernetes_service_account.spark_apps.metadata[0].name
        env = [
          {
            name  = "SPARK_DRIVER_BIND_ADDRESS"
            value = "0.0.0.0"
          }
        ]
      }

      executor = {
        cores      = 1
        instances  = var.spark_executor_instances
        memory     = "1024m"
        labels = {
          version = "3.5.1"
        }
        # Commented out nodeSelector since we don't have executor nodes yet
        # nodeSelector = {
        #   role = "executors"
        # }
      }

      restartPolicy = {
        type = "Never"
      }
    }
  }

  depends_on = [helm_release.spark_operator, kubernetes_service_account.spark_apps]
}

# Spark ConfigMaps
resource "kubernetes_config_map" "hadoop_core_site" {
  metadata {
    name      = "hadoop-core-site"
    namespace = var.spark_namespace
  }

  data = {
    "core-site.xml" = <<-EOT
      <?xml version="1.0"?>
      <configuration>
        <property>
          <name>fs.s3a.aws.credentials.provider</name>
          <value>com.amazonaws.auth.WebIdentityTokenCredentialsProvider</value>
        </property>
        <property>
          <name>fs.s3a.impl</name>
          <value>org.apache.hadoop.fs.s3a.S3AFileSystem</value>
        </property>
        <property>
          <name>fs.s3a.path.style.access</name>
          <value>false</value>
        </property>
        <property>
          <name>fs.s3a.block.size</name>
          <value>134217728</value>
        </property>
        <property>
          <name>fs.s3a.connection.timeout</name>
          <value>60000</value>
        </property>
        <property>
          <name>fs.s3a.socket.timeout</name>
          <value>60000</value>
        </property>
        <property>
          <name>fs.s3a.connection.establish.timeout</name>
          <value>60000</value>
        </property>
        <property>
          <name>fs.s3a.socket.send.buffer</name>
          <value>8192</value>
        </property>
        <property>
          <name>fs.s3a.socket.recv.buffer</name>
          <value>8192</value>
        </property>
      </configuration>
    EOT
  }

  depends_on = [kubernetes_namespace.spark]
}

resource "kubernetes_config_map" "spark_hive_site" {
  metadata {
    name      = "spark-hive-site"
    namespace = var.spark_namespace
  }

  data = {
    "hive-site.xml" = <<-EOT
      <?xml version="1.0"?>
      <configuration>
        <property>
          <name>javax.jdo.option.ConnectionDriverName</name>
          <value>com.mysql.cj.jdbc.Driver</value>
        </property>
        <property>
          <name>javax.jdo.option.ConnectionURL</name>
          <value>jdbc:mysql://${aws_db_instance.hive.address}:3306/${var.db_name}?useSSL=true&amp;requireSSL=true&amp;useUnicode=true&amp;characterEncoding=UTF-8</value>
        </property>
        <property>
          <name>javax.jdo.option.ConnectionUserName</name>
          <value>hiveuser</value>
        </property>
        <property>
          <name>javax.jdo.option.ConnectionPassword</name>
          <value>HiveUser123!@#Strong</value>
        </property>
        <property>
          <name>hive.metastore.warehouse.dir</name>
          <value>s3a://${local.iceberg_bucket}/warehouse/</value>
        </property>
        <property>
          <name>hive.metastore.uris</name>
          <value>thrift://hive-metastore.hive.svc.cluster.local:9083</value>
        </property>
      </configuration>
    EOT
  }

  depends_on = [kubernetes_namespace.spark]
}

# Spark Log Ingestion Job - Updated for Spark 3.5.1 compatibility
resource "kubernetes_manifest" "spark_ingest_job" {
  count = var.deploy_spark_jobs ? 1 : 0
  
  field_manager {
    force_conflicts = true
  }
  
  manifest = {
    apiVersion = "sparkoperator.k8s.io/v1beta2"
    kind       = "SparkApplication"
    metadata = {
      name      = "ingest-logs-spark351-prod"
      namespace = "spark"
      labels = {
        app       = "log-ingestion"
        version   = "spark-3.5.1"
        component = "data-pipeline"
      }
    }
    spec = {
      type                = "Python"
      mode                = "cluster"
      image               = "503233514096.dkr.ecr.us-east-1.amazonaws.com/log-ingest-spark:v14-spark351"
      imagePullPolicy     = "Always"
      mainApplicationFile = "local:///opt/jobs/ingest_logs_to_iceberg.py"
      sparkVersion        = "3.5.1"
      restartPolicy = {
        type = "Never"
      }
      # No explicit deps needed - JARs are baked into the image
      sparkConf = {
        # Iceberg Spark Extensions
        "spark.sql.extensions"                                      = "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions"
        
        # Iceberg Catalog Configuration (Hive-based, NO Hadoop catalog)
        "spark.sql.catalog.iceberg"                                 = "org.apache.iceberg.spark.SparkCatalog"
        "spark.sql.catalog.iceberg.type"                           = "hive"
        "spark.sql.catalog.iceberg.uri"                            = "thrift://hive-metastore.hive.svc.cluster.local:9083"
        "spark.sql.catalog.iceberg.warehouse"                      = "s3a://${local.iceberg_bucket}/warehouse/"
        
        # S3A Configuration for AWS
        "spark.hadoop.fs.s3a.impl"                                 = "org.apache.hadoop.fs.s3a.S3AFileSystem"
        "spark.hadoop.fs.s3a.aws.credentials.provider"            = "com.amazonaws.auth.WebIdentityTokenCredentialsProvider"
        "spark.hadoop.fs.s3a.path.style.access"                   = "false"
        "spark.hadoop.fs.s3a.connection.timeout"                  = "60000"
        "spark.hadoop.fs.s3a.socket.timeout"                      = "60000"
        "spark.hadoop.fs.s3a.connection.establish.timeout"        = "60000"
        "spark.hadoop.fs.s3a.multipart.size"                      = "104857600"
        "spark.hadoop.fs.s3a.connection.maximum"                  = "15"
        "spark.hadoop.fs.s3a.threads.max"                         = "10"
        "spark.hadoop.fs.s3a.threads.core"                        = "5"
        "spark.hadoop.fs.s3a.threads.keepalivetime"               = "60000"
        
        # Performance optimizations for Spark 3.5.1
        "spark.serializer"                                          = "org.apache.spark.serializer.KryoSerializer"
        "spark.sql.adaptive.enabled"                               = "true"
        "spark.sql.adaptive.coalescePartitions.enabled"           = "true"
        "spark.sql.adaptive.skewJoin.enabled"                     = "true"
        "spark.sql.adaptive.localShuffleReader.enabled"           = "true"
        "spark.dynamicAllocation.enabled"                          = "false"
        
        # Kubernetes authentication
        "spark.kubernetes.authenticate.driver.serviceAccountName"  = "spark-apps"
        "spark.kubernetes.authenticate.executor.serviceAccountName" = "spark-apps"
        
        # Iceberg lock manager (NoLock to avoid conflicts)
        "spark.sql.catalog.iceberg.lock-impl"                      = "org.apache.iceberg.util.NoLockManager"
        
        # Memory and storage optimizations
        "spark.sql.files.maxPartitionBytes"                        = "134217728"
        "spark.sql.adaptive.maxShuffledHashJoinLocalMapThreshold"  = "67108864"
        
        # EventLog fully disabled by explicitly setting directory to local path
        "spark.eventLog.enabled"                                    = "false"
        "spark.eventLog.dir"                                        = "file:///tmp/spark-events"
        "spark.history.fs.logDirectory"                             = "file:///tmp/spark-events"
      }
      arguments = [
        "--raw-prefix", "s3a://${local.raw_bucket}/logs/",
        "--warehouse", "s3a://${local.iceberg_bucket}/warehouse/",
        "--hms-uri", "thrift://hive-metastore.hive.svc.cluster.local:9083",
        "--db", "analytics",
        "--table", "logs"
      ]
      driver = {
        cores         = 1
        coreLimit     = "1200m"
        memory        = "2g"
        memoryOverhead = "512m"
        labels = {
          version   = "3.5.1"
          component = "log-ingestion"
        }
        serviceAccount = kubernetes_service_account.spark_apps.metadata[0].name
        env = [
          {
            name  = "AWS_REGION"
            value = var.aws_region
          },
          {
            name  = "HIVE_METASTORE_URIS"
            value = "thrift://hive-metastore.hive.svc.cluster.local:9083"
          },
          {
            name  = "SPARK_USER"
            value = "spark"
          }
        ]
        volumeMounts = [
          {
            name      = "hadoop-core-site"
            mountPath = "/opt/spark/conf/core-site.xml"
            subPath   = "core-site.xml"
          },
          {
            name      = "spark-hive-site"
            mountPath = "/opt/spark/conf/hive-site.xml"
            subPath   = "hive-site.xml"
          }
        ]
      }
      executor = {
        cores         = 1
        coreLimit     = "1200m"
        instances     = 2
        memory        = "2g"
        memoryOverhead = "512m"
        labels = {
          version   = "3.5.1"
          component = "log-ingestion"
        }
        serviceAccount = kubernetes_service_account.spark_apps.metadata[0].name
        env = [
          {
            name  = "AWS_REGION"
            value = var.aws_region
          },
          {
            name  = "HIVE_METASTORE_URIS"
            value = "thrift://hive-metastore.hive.svc.cluster.local:9083"
          },
          {
            name  = "SPARK_USER"
            value = "spark"
          }
        ]
        volumeMounts = [
          {
            name      = "hadoop-core-site"
            mountPath = "/opt/spark/conf/core-site.xml"
            subPath   = "core-site.xml"
          },
          {
            name      = "spark-hive-site"
            mountPath = "/opt/spark/conf/hive-site.xml"
            subPath   = "hive-site.xml"
          }
        ]
      }
      volumes = [
        {
          name = "hadoop-core-site"
          configMap = {
            name = kubernetes_config_map.hadoop_core_site.metadata[0].name
          }
        },
        {
          name = "spark-hive-site"
          configMap = {
            name = kubernetes_config_map.spark_hive_site.metadata[0].name
          }
        }
      ]
    }
  }

  depends_on = [
    helm_release.spark_operator,
    kubernetes_service_account.spark_apps,
    kubernetes_config_map.hadoop_core_site,
    kubernetes_config_map.spark_hive_site,
    kubernetes_service.hive_metastore
  ]
}

# Spark Aggregation Job - Updated for Spark 3.5.1 compatibility
resource "kubernetes_manifest" "spark_aggregate_job" {
  count = var.deploy_spark_jobs ? 1 : 0
  
  field_manager {
    force_conflicts = true
  }
  
  manifest = {
    apiVersion = "sparkoperator.k8s.io/v1beta2"
    kind       = "SparkApplication"
    metadata = {
      name      = "aggregate-logs-spark351-prod"
      namespace = "spark"
      labels = {
        app       = "log-aggregation"
        version   = "spark-3.5.1"
        component = "data-pipeline"
      }
    }
    spec = {
      type                = "Python"
      mode                = "cluster"
      image               = "503233514096.dkr.ecr.us-east-1.amazonaws.com/spark-aggregate:v1"
      imagePullPolicy     = "Always"
      mainApplicationFile = "local:///opt/jobs/logs_aggregation_prod.py"
      sparkVersion        = "3.5.1"
      restartPolicy = {
        type = "Never"
      }
      # No explicit deps needed - JARs are baked into the image
      sparkConf = {
        # Iceberg Spark Extensions
        "spark.sql.extensions"                                      = "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions"
        
        # Iceberg Catalog Configuration (Hive-based, NO Hadoop catalog)
        "spark.sql.catalog.iceberg"                                 = "org.apache.iceberg.spark.SparkCatalog"
        "spark.sql.catalog.iceberg.type"                           = "hive"
        "spark.sql.catalog.iceberg.uri"                            = "thrift://hive-metastore.hive.svc.cluster.local:9083"
        "spark.sql.catalog.iceberg.warehouse"                      = "s3a://${local.iceberg_bucket}/warehouse/"
        
        # S3A Configuration for AWS
        "spark.hadoop.fs.s3a.impl"                                 = "org.apache.hadoop.fs.s3a.S3AFileSystem"
        "spark.hadoop.fs.s3a.aws.credentials.provider"            = "com.amazonaws.auth.WebIdentityTokenCredentialsProvider"
        "spark.hadoop.fs.s3a.path.style.access"                   = "false"
        "spark.hadoop.fs.s3a.connection.timeout"                  = "60000"
        "spark.hadoop.fs.s3a.socket.timeout"                      = "60000"
        "spark.hadoop.fs.s3a.connection.establish.timeout"        = "60000"
        "spark.hadoop.fs.s3a.multipart.size"                      = "104857600"
        "spark.hadoop.fs.s3a.connection.maximum"                  = "15"
        "spark.hadoop.fs.s3a.threads.max"                         = "10"
        "spark.hadoop.fs.s3a.threads.core"                        = "5"
        "spark.hadoop.fs.s3a.threads.keepalivetime"               = "60000"
        
        # Performance optimizations for Spark 3.5.1
        "spark.serializer"                                          = "org.apache.spark.serializer.KryoSerializer"
        "spark.sql.adaptive.enabled"                               = "true"
        "spark.sql.adaptive.coalescePartitions.enabled"           = "true"
        "spark.sql.adaptive.skewJoin.enabled"                     = "true"
        "spark.sql.adaptive.localShuffleReader.enabled"           = "true"
        "spark.dynamicAllocation.enabled"                          = "false"
        
        # Kubernetes authentication
        "spark.kubernetes.authenticate.driver.serviceAccountName"  = "spark-apps"
        "spark.kubernetes.authenticate.executor.serviceAccountName" = "spark-apps"
        
        # Iceberg lock manager (NoLock to avoid conflicts)
        "spark.sql.catalog.iceberg.lock-impl"                      = "org.apache.iceberg.util.NoLockManager"
        
        # Memory and storage optimizations
        "spark.sql.files.maxPartitionBytes"                        = "134217728"
        "spark.sql.adaptive.maxShuffledHashJoinLocalMapThreshold"  = "67108864"
        
        # EventLog fully disabled by explicitly setting directory to local path
        "spark.eventLog.enabled"                                    = "false"
        "spark.eventLog.dir"                                        = "file:///tmp/spark-events"
        "spark.history.fs.logDirectory"                             = "file:///tmp/spark-events"
      }
      arguments = [
        "--sql-file", "/opt/jobs/sql/aggregate_topn.sql",
        "--warehouse", "s3a://${local.iceberg_bucket}/warehouse/",
        "--hms-uri", "thrift://hive-metastore.hive.svc.cluster.local:9083"
      ]
      driver = {
        cores         = 1
        coreLimit     = "1200m"
        memory        = "2g"
        memoryOverhead = "512m"
        labels = {
          version   = "3.5.1"
          component = "log-aggregation"
        }
        serviceAccount = kubernetes_service_account.spark_apps.metadata[0].name
        env = [
          {
            name  = "AWS_REGION"
            value = var.aws_region
          },
          {
            name  = "HIVE_METASTORE_URIS"
            value = "thrift://hive-metastore.hive.svc.cluster.local:9083"
          },
          {
            name  = "SPARK_USER"
            value = "spark"
          }
        ]
        volumeMounts = [
          {
            name      = "hadoop-core-site"
            mountPath = "/opt/spark/conf/core-site.xml"
            subPath   = "core-site.xml"
          },
          {
            name      = "spark-hive-site"
            mountPath = "/opt/spark/conf/hive-site.xml"
            subPath   = "hive-site.xml"
          }
        ]
      }
      executor = {
        cores         = 1
        coreLimit     = "1200m"
        instances     = 2
        memory        = "2g"
        memoryOverhead = "512m"
        labels = {
          version   = "3.5.1"
          component = "log-aggregation"
        }
        serviceAccount = kubernetes_service_account.spark_apps.metadata[0].name
        env = [
          {
            name  = "AWS_REGION"
            value = var.aws_region
          },
          {
            name  = "HIVE_METASTORE_URIS"
            value = "thrift://hive-metastore.hive.svc.cluster.local:9083"
          },
          {
            name  = "SPARK_USER"
            value = "spark"
          }
        ]
        volumeMounts = [
          {
            name      = "hadoop-core-site"
            mountPath = "/opt/spark/conf/core-site.xml"
            subPath   = "core-site.xml"
          },
          {
            name      = "spark-hive-site"
            mountPath = "/opt/spark/conf/hive-site.xml"
            subPath   = "hive-site.xml"
          }
        ]
      }
      volumes = [
        {
          name = "hadoop-core-site"
          configMap = {
            name = kubernetes_config_map.hadoop_core_site.metadata[0].name
          }
        },
        {
          name = "spark-hive-site"
          configMap = {
            name = kubernetes_config_map.spark_hive_site.metadata[0].name
          }
        }
      ]
    }
  }

  depends_on = [
    helm_release.spark_operator,
    kubernetes_service_account.spark_apps,
    kubernetes_config_map.hadoop_core_site,
    kubernetes_config_map.spark_hive_site,
    kubernetes_service.hive_metastore
  ]
}

# Locals for bucket names (used in configurations)
locals {
  raw_bucket     = var.s3_raw_bucket_name != null ? var.s3_raw_bucket_name : aws_s3_bucket.raw.bucket
  iceberg_bucket = var.s3_iceberg_bucket_name != null ? var.s3_iceberg_bucket_name : aws_s3_bucket.iceberg.bucket
}
