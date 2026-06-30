# Fixture: INVALID — bare commit SHA ref, not a release tag.
# The source-pin gate MUST flag this file.
module "vpc" {
  source = "github.com/Coalfire-CF/terraform-aws-vpc-nfw?ref=a1b2c3d4e5f60718293a4b5c6d7e8f9001122334"

  name = "example"
}
