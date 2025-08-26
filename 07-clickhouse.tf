# ClickHouse Installation for Iceberg Integration
resource "kubernetes_manifest" "clickhouse_installation" {
  manifest = {
    apiVersion = "clickhouse.altinity.com/v1"
    kind       = "ClickHouseInstallation"
    metadata = {
      name      = "data-platform-clickhouse"
      namespace = var.clickhouse_namespace
    }
    spec = {
      defaults = {
        templates = {
          podTemplate  = "pod-template"
          serviceTemplate = "svc-template"
        }
      }
      
      configuration = {
        users = {
          "default/password" = "clickhouse123"
          "default/networks/ip" = ["::/0"]
          "analytics/password" = "analytics123"
          "analytics/networks/ip" = ["::/0"]
        }
        
        profiles = {
          "default/max_memory_usage" = "1000000000"
          "default/use_uncompressed_cache" = "0"
          "default/load_balancing" = "random"
        }
        
        settings = {
          "logger/level" = "information"
          "logger/console" = "1"
          "max_connections" = "4096"
          "keep_alive_timeout" = "3"
          "max_concurrent_queries" = "100"
          "uncompressed_cache_size" = "8589934592"
          "mark_cache_size" = "5368709120"
        }
        
        files = {
          "config.d/storage.xml" = <<-EOT
            <clickhouse>
              <storage_configuration>
                <disks>
                  <s3>
                    <type>s3</type>
                    <endpoint>${format("https://s3.%s.amazonaws.com/%s/", var.aws_region, local.iceberg_bucket)}</endpoint>
                    <use_environment_credentials>true</use_environment_credentials>
                    <region>${var.aws_region}</region>
                  </s3>
                </disks>
                <policies>
                  <s3_main>
                    <volumes>
                      <main>
                        <disk>s3</disk>
                      </main>
                    </volumes>
                  </s3_main>
                </policies>
              </storage_configuration>
            </clickhouse>
          EOT
          
          "config.d/s3.xml" = <<-EOT
            <clickhouse>
              <s3>
                <region>${var.aws_region}</region>
                <use_environment_credentials>true</use_environment_credentials>
              </s3>
            </clickhouse>
          EOT
        }
        
        clusters = [{
          name = "data-platform"
          layout = {
            shardsCount   = 1
            replicasCount = 1
          }
        }]
      }
      
      templates = {
        podTemplates = [{
          name = "pod-template"
          spec = {
            containers = [{
              name  = "clickhouse"
              image = "clickhouse/clickhouse-server:23.8"
              
              volumeMounts = [{
                name      = "clickhouse-storage"
                mountPath = "/var/lib/clickhouse"
              }]
              
              env = [{
                name  = "AWS_REGION"
                value = var.aws_region
              }, {
                name  = "AWS_ROLE_ARN"
                value = aws_iam_role.clickhouse.arn
              }, {
                name = "AWS_WEB_IDENTITY_TOKEN_FILE"
                value = "/var/run/secrets/eks.amazonaws.com/serviceaccount/token"
              }]
              
              resources = {
                requests = {
                  memory = "1Gi"
                  cpu    = "500m"
                }
                limits = {
                  memory = "2Gi"
                  cpu    = "1"
                }
              }
            }]
            
            serviceAccountName = kubernetes_service_account.clickhouse.metadata[0].name
            
            volumes = [{
              name = "clickhouse-storage"
              emptyDir = {}
            }]
          }
        }]
        
        serviceTemplates = [{
          name = "svc-template"
          spec = {
            ports = [{
              name = "http"
              port = 8123
            }, {
              name = "tcp"
              port = 9000
            }]
            type = "ClusterIP"
          }
        }]
      }
      
    }
  }
  
  depends_on = [
    helm_release.clickhouse_operator,
    kubernetes_service_account.clickhouse
  ]
}

# ClickHouse Service for external access
resource "kubernetes_service" "clickhouse_external" {
  metadata {
    name      = "clickhouse-external"
    namespace = var.clickhouse_namespace
  }
  
  spec {
    selector = {
      "clickhouse.altinity.com/cluster" = "data-platform"
    }
    
    port {
      name        = "http"
      port        = 8123
      target_port = 8123
      protocol    = "TCP"
    }
    
    port {
      name        = "tcp"
      port        = 9000
      target_port = 9000
      protocol    = "TCP"
    }
    
    type = "ClusterIP"
  }
  
  depends_on = [kubernetes_manifest.clickhouse_installation]
}
