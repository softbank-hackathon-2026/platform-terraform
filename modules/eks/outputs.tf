output "cluster_name" {
  description = "EKS 클러스터 이름입니다."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "EKS 클러스터 ARN입니다."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Kubernetes API 엔드포인트입니다."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Kubernetes API CA 인증서의 Base64 데이터입니다."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_oidc_issuer_url" {
  description = "EKS 클러스터의 OIDC issuer URL입니다. IAM OIDC Provider 생성 여부와 관계없이 제공됩니다."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "cluster_primary_security_group_id" {
  description = "EKS가 생성한 기본 클러스터 Security Group ID입니다."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "node_group_names" {
  description = "논리 키별 관리형 노드 그룹 이름입니다."
  value = {
    for key, group in aws_eks_node_group.this : key => group.node_group_name
  }
}

output "node_group_arns" {
  description = "논리 키별 관리형 노드 그룹 ARN입니다."
  value = {
    for key, group in aws_eks_node_group.this : key => group.arn
  }
}

output "oidc_provider_arn" {
  description = "IRSA용 IAM OIDC Provider ARN입니다. 생성하지 않으면 null입니다."
  value       = try(aws_iam_openid_connect_provider.this[0].arn, null)
}
