variable "name" {
  type    = string
  default = "sa-signer"
}

variable "create_file" {
  type    = bool
  default = true
}

variable "out_directory" {
  type    = string
  default = "out/certs"

}

resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "local_sensitive_file" "private_key" {
  count    = var.create_file ? 1 : 0
  content  = tls_private_key.this.private_key_pem
  filename = "${var.out_directory}/${var.name}.key"
}

resource "local_sensitive_file" "public_key" {
  count    = var.create_file ? 1 : 0
  content  = tls_private_key.this.public_key_pem
  filename = "${var.out_directory}/${var.name}-pkcs8.pub"
}

resource "local_file" "public_key_pem" {
  count    = var.create_file ? 1 : 0
  content  = tls_private_key.this.public_key_openssh
  filename = "${var.out_directory}/${var.name}.key.pub"
}

resource "local_file" "jwks_json" {
  count    = var.create_file ? 1 : 0
  content  = local.jwks_json
  filename = "${var.out_directory}/jwks.json"
}

data "external" "kid" {
  program = ["bash", "${path.module}/get-kid.sh"]

  query = {
    private_key = tls_private_key.this.private_key_pem
  }
}

data "jwks_from_key" "with_kid" {
  key = tls_private_key.this.private_key_pem
  kid = data.external.kid.result.kid
}

locals {
  decoded_jwk = jsondecode(data.jwks_from_key.with_kid.jwks)
  jwks_json = jsonencode({
    "keys" = [
      {
        use = "sig"
        kty = local.decoded_jwk.kty
        kid = lookup(local.decoded_jwk, "kid", "")
        alg = "RS256"
        n   = local.decoded_jwk.n
        e   = local.decoded_jwk.e
      },
      {
        use = "sig"
        kty = local.decoded_jwk.kty
        kid = ""
        alg = "RS256"
        n   = local.decoded_jwk.n
        e   = local.decoded_jwk.e
      }
    ]
  })
}

output "jwks_json_file_location" {
  value = var.create_file ? local_file.jwks_json[0].filename : null
}

output "private_key_file_location" {
  value = var.create_file ? local_sensitive_file.private_key[0].filename : null
}

output "public_key_file_location" {
  value = var.create_file ? local_sensitive_file.public_key[0].filename : null
}

output "public_key_pem_file_location" {
  value = var.create_file ? local_file.public_key_pem[0].filename : null
}

output "jwks_json" {
  value = local.jwks_json
}
