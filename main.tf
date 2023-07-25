terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.9.0"
    }
  }
}

module "s3_oidc_provider" {
  source = "./modules/s3-oidc-provider"

  name = "sa-signer"

  jwks_json = file("jwks.json")
}


module "iam_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.28.0"

  create_role = true

  role_name = "sa-signer-test-role"

  provider_urls = [
    module.s3_oidc_provider.issuer_url,
  ]

  oidc_subjects_with_wildcards = [
    "system:serviceaccount:default:*",
  ]

  oidc_fully_qualified_audiences = [
    module.s3_oidc_provider.audience
  ]

  number_of_role_policy_arns = 1

  role_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
  ]
}

resource "local_file" "start_sh" {
  filename        = "out/start.sh"
  content         = <<EOF
#!/bin/bash
set -ex

mkdir -p $HOME/.minikube/files/var/lib/minikube/certs
cp -r ./out/certs/* $HOME/.minikube/files/var/lib/minikube/certs

# Start new minikube
minikube start \
--extra-config=apiserver.service-account-key-file=/var/lib/minikube/certs/sa-signer-pkcs8.pub \
--extra-config=apiserver.service-account-signing-key-file=/var/lib/minikube/certs/sa-signer.key \
--extra-config=apiserver.api-audiences=https://kubernetes.default.svc.cluster.local,${module.s3_oidc_provider.audience} \
--extra-config=apiserver.service-account-issuer=https://${module.s3_oidc_provider.issuer_url}

echo "Wait for cluster to be up"
sleep 5


helm repo add jkroepke https://jkroepke.github.io/helm-charts/
helm repo add jetstack https://charts.jetstack.io
helm repo update



echo "Installing cert-manager"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.0/cert-manager.crds.yaml
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.12.0 

echo "Installing eks-pod-identity-webhook"
helm install amazon-eks-pod-identity-webhook jkroepke/amazon-eks-pod-identity-webhook --namespace kube-system --set config.tokenAudience=${module.s3_oidc_provider.audience}

EOF
  file_permission = "0755"

}

resource "local_file" "pod_yaml" {
  filename = "out/pod.yaml"
  content  = <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sa-signer-test
  namespace: default
  annotations:
    eks.amazonaws.com/role-arn: ${module.iam_role.iam_role_arn}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sa-signer-test
spec:
  selector:
    matchLabels:
      app: sa-signer-test
  template:
    metadata:
      labels:
        app: sa-signer-test
    spec:
      serviceAccountName: sa-signer-test
      containers:
      - name: sa-signer-test
        image: amazon/aws-cli:latest
        command: ["/bin/sh", "-c", "--"]
        args: ["while true; do sleep 30; done;"]
EOF
}
