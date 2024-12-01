output "kubeconfig" {
  description = "Kubeconfig connect to cluster"
  value       = <<KUBECONFIG
                apiVersion: v1
                clusters:
                - cluster:
                    server: ${data.aws_eks_cluster.demo.endpoint}
                    certificate-authority-data: ${base64decode(data.aws_eks_cluster.demo.certificate_authority[0].data)}
                name: ${data.aws_eks_cluster.demo.name}
                contexts:
                - context:
                    cluster: ${data.aws_eks_cluster.demo.name}
                    user: eks-user
                name: ${data.aws_eks_cluster.demo.name}-context
                current-context: ${data.aws_eks_cluster.demo.name}-context
                kind: Config
                users:
                - name: eks-user
                user:
                    token: ${data.aws_eks_cluster_auth.demo.token}
                KUBECONFIG
  sensitive   = true
}

output "grafana_ingress_url" {
  description = "Grafana Ingress URL"
  value       = "http://mthnhng.site"
}
