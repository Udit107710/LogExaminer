# LogExaminer - AWS Data Platform Architecture

```mermaid
graph TB
    %% External Access
    User[👤 User/Developer] 
    Internet[🌐 Internet]
    
    %% AWS Account Boundary
    subgraph AWS["☁️ AWS Account (us-east-1/us-east-2)"]
        
        %% VPC and Networking
        subgraph VPC["🏗️ VPC - data-platform"]
            
            %% Public Subnets
            subgraph PubSub["📡 Public Subnets"]
                IGW[Internet Gateway]
                NAT[NAT Gateway<br/>Optional]
            end
            
            %% Private Subnets
            subgraph PrivSub["🔒 Private Subnets"]
                
                %% EKS Cluster
                subgraph EKS["⚙️ EKS Cluster v1.33"]
                    
                    %% System Node Group
                    subgraph SysNodes["🖥️ System Node Group<br/>(On-Demand, label: role=system)"]
                        CoreDNS[CoreDNS]
                        KubeProxy[kube-proxy]
                        VPCCNI[vpc-cni]
                        EBSCSI[ebs-csi]
                        CA[Cluster Autoscaler]
                    end
                    
                    %% Executor Node Group
                    subgraph ExecNodes["⚡ Executor Node Group<br/>(Spot, label: role=executors)"]
                        SparkExec1[Spark Executors]
                        SparkExec2[Spark Executors]
                    end
                    
                    %% Spark Namespace
                    subgraph SparkNS["🔥 Spark Namespace"]
                        SparkOp[Spark Operator<br/>gcr.io/spark-operator/spark-operator]
                        SparkApps[Spark Applications<br/>apache/spark:3.5.1]
                        SparkAppsSA[spark-apps ServiceAccount<br/>IRSA]
                    end
                    
                    %% ClickHouse Namespace
                    subgraph CHNS["📊 ClickHouse Namespace"]
                        CH[ClickHouse<br/>Port: 8123/9000]
                        CHSA[clickhouse ServiceAccount<br/>IRSA]
                    end
                    
                    %% Hive Namespace
                    subgraph HiveNS["🏪 Hive Namespace"]
                        HMS[Hive Metastore<br/>apache/hive:3.1.3<br/>Port: 9083]
                    end
                    
                    %% External Secrets Namespace
                    subgraph ExtSecNS["🔐 external-secrets Namespace"]
                        ExtSec[External Secrets Operator]
                        ExtSecSA[external-secrets ServiceAccount<br/>IRSA]
                    end
                    
                    %% Kube System
                    subgraph KubeSys["⚙️ kube-system"]
                        CÁSA[cluster-autoscaler ServiceAccount<br/>IRSA]
                    end
                end
                
                %% RDS
                subgraph RDS["🗄️ RDS PostgreSQL"]
                    RDSDB[(Hive Metastore DB<br/>Port: 5432<br/>Multi-AZ Optional)]
                end
            end
        end
        
        %% VPC Endpoints
        subgraph VPCEndpoints["🔗 VPC Endpoints"]
            S3GW[S3 Gateway Endpoint]
            SecretsVPCE[Secrets Manager<br/>Interface Endpoint]
            ECRVPCE[ECR API/DKR<br/>Interface Endpoints]
            STSVPCE[STS Interface<br/>Endpoint]
        end
        
        %% S3 Storage
        subgraph S3["🪣 S3 Storage"]
            RawBucket[📥 Raw Data Bucket<br/>Versioning: On<br/>SSE: AES256<br/>Lifecycle: 30d → IA]
            IcebergBucket[🧊 Iceberg Data Bucket<br/>Versioning: On<br/>SSE: AES256<br/>Parquet Format]
        end
        
        %% ECR
        subgraph ECR["📦 ECR Repositories"]
            SparkECR[data-platform/spark<br/>apache/spark:3.5.1]
            HiveECR[data-platform/hive<br/>apache/hive:3.1.3]
            SparkOpECR[data-platform/spark-operator<br/>gcr.io/spark-operator/...]
        end
        
        %% AWS Services
        subgraph AWSServices["☁️ AWS Services"]
            SM[🔐 AWS Secrets Manager<br/>HMS Connection Details<br/>(user, password, host, port)]
            IAM[👥 AWS IAM<br/>IRSA Roles & Policies]
            ASG[📈 Auto Scaling Groups<br/>EKS Node Groups]
            EC2[💻 EC2 Instances<br/>EKS Worker Nodes]
        end
    end
    
    %% External Container Registries
    subgraph ExtReg["📦 External Registries"]
        DockerHub[🐳 Docker Hub<br/>apache/spark<br/>apache/hive]
        GCR[📦 GCR<br/>spark-operator]
    end
    
    %% Local Development
    subgraph Local["💻 Local Development"]
        Terraform[🏗️ Terraform<br/>Infrastructure as Code]
        kubectl[⚙️ kubectl<br/>Kubernetes Management]
        Docker[🐳 Docker<br/>Image Operations]
        Scripts[📜 Helper Scripts<br/>mirror_to_ecr.sh<br/>ch_port_forward.sh]
    end
    
    %% Connections
    User --> Internet
    Internet --> IGW
    IGW --> NAT
    Internet --> User
    
    %% VPC Endpoints connections
    EKS -.-> S3GW
    EKS -.-> SecretsVPCE
    EKS -.-> ECRVPCE
    EKS -.-> STSVPCE
    
    %% Data flow
    SparkApps --> RawBucket
    SparkApps --> IcebergBucket
    CH --> RawBucket
    CH --> IcebergBucket
    HMS --> RDSDB
    SparkApps --> HMS
    
    %% IRSA connections
    SparkAppsSA -.-> IAM
    CHSA -.-> IAM
    ExtSecSA -.-> IAM
    CÁSA -.-> IAM
    
    %% Secrets
    ExtSec --> SM
    HMS -.-> SM
    
    %% Image pulling
    SparkOp --> SparkOpECR
    SparkApps --> SparkECR
    HMS --> HiveECR
    
    %% Local operations
    Terraform --> AWS
    kubectl --> EKS
    Docker --> ECR
    Scripts --> ECR
    Scripts --> EKS
    
    %% Image mirroring
    DockerHub -.-> ECR
    GCR -.-> ECR
    
    %% Port forwarding (dashed for optional)
    User -.-> CH
    User -.-> HMS
    
    %% Security Groups (implied)
    RDSDB -.-> EKS
    
    %% Styling
    classDef awsService fill:#FF9900,stroke:#232F3E,stroke-width:2px,color:#FFFFFF
    classDef k8sResource fill:#326CE5,stroke:#FFFFFF,stroke-width:2px,color:#FFFFFF
    classDef storage fill:#3F8EFC,stroke:#FFFFFF,stroke-width:2px,color:#FFFFFF
    classDef security fill:#FF4B4B,stroke:#FFFFFF,stroke-width:2px,color:#FFFFFF
    classDef local fill:#2ECC40,stroke:#FFFFFF,stroke-width:2px,color:#FFFFFF
    
    class AWS,RDS,S3,ECR,SM,IAM,ASG,EC2,VPCEndpoints awsService
    class EKS,SparkOp,SparkApps,CH,HMS,ExtSec,CoreDNS,KubeProxy,VPCCNI,EBSCSI,CA k8sResource
    class RawBucket,IcebergBucket,RDSDB storage
    class SparkAppsSA,CHSA,ExtSecSA,CÁSA security
    class Terraform,kubectl,Docker,Scripts,Local local
```

## Architecture Components

### 🏗️ **Infrastructure Layer (Terraform)**
- **VPC**: Custom VPC with public/private subnets
- **NAT Gateway**: Optional for private subnet internet access
- **VPC Endpoints**: Cost optimization for S3, Secrets Manager, ECR, STS

### ⚙️ **Compute Layer (EKS)**
- **EKS Cluster**: Kubernetes v1.33 with IRSA enabled
- **System Node Group**: On-demand instances for system workloads
- **Executor Node Group**: Spot instances for Spark executors
- **Add-ons**: CoreDNS, kube-proxy, vpc-cni, ebs-csi-driver

### 🔥 **Data Processing Layer**
- **Apache Spark**: Big data processing (v3.5.1)
- **Spark Operator**: Kubernetes-native Spark job management
- **Hive Metastore**: Metadata catalog (v3.1.3)
- **ClickHouse**: Analytics database with Iceberg integration

### 🪣 **Storage Layer**
- **Raw Data Bucket**: Landing zone for raw data files
- **Iceberg Bucket**: Structured data in Apache Iceberg format
- **RDS PostgreSQL**: Hive Metastore backend database

### 🔐 **Security & Access**
- **IRSA**: IAM Roles for Service Accounts
- **AWS Secrets Manager**: Database credentials and configuration
- **Security Groups**: Network-level access control
- **Bucket Policies**: S3 access restrictions

### 📦 **Container Management**
- **ECR Repositories**: Private container registry
- **Image Mirroring**: Automated sync from public registries
- **Multi-architecture**: Support for different container platforms

## 🚀 **Deployment Phases**

### Phase 1: Infrastructure (Current)
- AWS cloud resources provisioning
- Networking and security setup
- Container image preparation

### Phase 2: Kubernetes Resources (Future)
- Helm charts deployment
- Application configuration
- Monitoring and logging setup

## 🔧 **Operational Features**
- **Port Forwarding**: Local access to ClickHouse and Hive Metastore
- **Auto Scaling**: Dynamic node scaling based on workload
- **Cost Optimization**: Spot instances and VPC endpoints
- **Multi-AZ**: Optional high availability setup
