# Fixture: VALID (PASS) — SHA-preferred pin: 40-hex commit SHA + adjacent
# `# vX.Y.Z` release comment (RFC-0008). The source-pin gate MUST NOT flag it.
module "ec2" {
  source = "github.com/Coalfire-CF/terraform-aws-ec2?ref=4f1e8d2c9b0a7654321fedcba9876543210abcd0" # v2.2.6

  name = "example"
}
