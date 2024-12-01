provider "aws" {
  region = "us-east-1"
}

# Create VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.16.0"

  name                 = "demo-vpc"
  cidr                 = "10.0.0.0/16"
  azs                  = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_support   = true
  enable_dns_hostnames = true
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_security_group" "eks_control_plane_sg" {
  name        = "eks-control-plane-sg"
  description = "Security Group for EKS Control Plane"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "eks_worker_sg" {
  name        = "eks-worker-sg"
  description = "Security Group for EKS Worker Nodes"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create EKS Cluster
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "20.30.1"

  cluster_name    = "demo-eks-cluster"
  cluster_version = "1.31"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  cluster_security_group_id = aws_security_group.eks_control_plane_sg.id

  # Enable Control Plane Logging
  cluster_enabled_log_types = ["api", "audit", "authenticator"]

  # Config Endpoint
  cluster_endpoint_private_access = false
  cluster_endpoint_public_access  = true

  # Worker Nodes
  eks_managed_node_groups = {
    workers = {
      desired_capacity = 1
      max_capacity     = 3
      min_capacity     = 1

      instance_types = ["t3.medium"]
      key_name       = "my-key"
      security_groups  = [aws_security_group.eks_worker_sg.id]

    }
  }

  tags = {
    Environment = "production"
    Project     = "kube-prometheus-postgres"
  }
}

# Fetch EKS Cluster details
data "aws_eks_cluster" "demo" {
  name = module.eks.cluster_name
  depends_on = [module.eks]
}

# Fetch the EKS cluster authentication token
data "aws_eks_cluster_auth" "demo" {
  name = module.eks.cluster_name
  depends_on = [module.eks]
}

# Config K8s provider
provider "kubernetes" {
  host                   = data.aws_eks_cluster.demo.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.demo.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.demo.token
}

# Config Helm Provider
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.demo.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.demo.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.demo.token
  }
}

# Deploy kube-prometheus-stack
resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  chart      = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  namespace  = "monitoring"

  create_namespace = true

  version = "66.3.0"

  values = [
    <<EOF
    grafana:
    persistence:
        enabled: true
    database:
        type: postgres
        host: postgres.monitoring.svc.cluster.local
        user: grafana-demo
        password: admin123
        database: grafana
    EOF
  ]
}

# Deploy PostgreSQL
resource "helm_release" "postgres" {
  name       = "postgres"
  chart      = "postgresql"
  repository = "https://charts.bitnami.com/bitnami"
  namespace  = "monitoring"

  create_namespace = false

  values = [
    <<EOF
    global:
    postgresql:
        auth:
        database: grafana
        username: grafana-demo
        password: admin123
    EOF
  ]
}

# Expose Grafana through Ingress
resource "kubernetes_ingress" "grafana_ingress" {
  metadata {
    name      = "grafana-ingress"
    namespace = "monitoring"
    annotations = {
      "kubernetes.io/ingress.class" = "nginx"
    }
  }

  spec {
    rule {
      host = "thnhng.site"
      http {
        path {
          path = "/"
          backend {
            service_name = "kube-prometheus-stack-grafana"
            service_port = 80
          }
        }
      }
    }
  }
}
