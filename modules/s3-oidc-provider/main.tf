terraform {
  required_providers {
    jwks = {
      source  = "cirrus-platform/jwks"
      version = "0.1.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "5.9.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.1.0"
    }
  }
}

variable "name" {
  type    = string
  default = "sa-signer"
}

variable "jwks_json" {
  type = string
}

variable "audience" {
  type    = string
  default = "sts.amazonaws.com"

}

data "aws_caller_identity" "this" {}
data "aws_region" "current" {}
resource "random_string" "postfix" {
  length  = 8
  special = false
  upper   = false
}

module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "3.14.1"

  bucket                   = "${var.name}-${data.aws_caller_identity.this.account_id}-${data.aws_region.current.name}-${random_string.postfix.result}"
  control_object_ownership = true
  object_ownership         = "BucketOwnerPreferred"
  acl                      = "private"
  block_public_acls        = false
  block_public_policy      = false
  ignore_public_acls       = false
  restrict_public_buckets  = false
}

locals {
  discovery_json = jsonencode({
    issuer                 = "https://${module.s3_bucket.s3_bucket_bucket_regional_domain_name}"
    jwks_uri               = "https://${module.s3_bucket.s3_bucket_bucket_regional_domain_name}/jwks.json"
    authorization_endpoint = "urn:kubernetes:programmatic_authorization",
    response_types_supported = [
      "id_token"
    ],
    subject_types_supported = [
      "public"
    ],
    id_token_signing_alg_values_supported = [
      "RS256"
    ],
    claims_supported = [
      "sub",
      "iss"
    ]

  })
}

resource "aws_s3_object" "jwks_json" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "jwks.json"
  content      = var.jwks_json
  etag         = md5(var.jwks_json)
  acl          = "public-read"
  content_type = "application/json"
  depends_on   = [module.s3_bucket]
}

resource "aws_s3_object" "oidc_configuration" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = ".well-known/openid-configuration"
  content      = local.discovery_json
  etag         = md5(local.discovery_json)
  acl          = "public-read"
  content_type = "application/json"
  depends_on   = [module.s3_bucket]
}

data "tls_certificate" "this" {
  url = "https://${module.s3_bucket.s3_bucket_bucket_regional_domain_name}"
}

resource "aws_iam_openid_connect_provider" "this" {
  url = "https://${module.s3_bucket.s3_bucket_bucket_regional_domain_name}"
  client_id_list = [
    var.audience
  ]
  thumbprint_list = [
    data.tls_certificate.this.certificates[0].sha1_fingerprint,
  ]
}

output "issuer_url" {
  value = module.s3_bucket.s3_bucket_bucket_regional_domain_name
}

output "audience" {
  value = var.audience

}
