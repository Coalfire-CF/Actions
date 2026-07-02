# Fixture: INVALID — floating ref (no ?ref= at all).
# The source-pin gate MUST flag this file.
module "kms" {
  source = "github.com/Coalfire-CF/terraform-aws-kms"

  name = "example"
}
