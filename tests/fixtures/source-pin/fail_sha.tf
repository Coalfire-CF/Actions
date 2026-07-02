# Fixture: INVALID (FAIL) — bare 40-hex commit SHA WITHOUT an adjacent
# `# vX.Y.Z` release comment (unauditable). The gate MUST flag this file
# (::error under strict, ::warning under advisory).
module "vpc" {
  source = "github.com/Coalfire-CF/terraform-aws-vpc-nfw?ref=a1b2c3d4e5f60718293a4b5c6d7e8f9001122334"

  name = "example"
}
