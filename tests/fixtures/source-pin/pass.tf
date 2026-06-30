# Fixture: VALID — Coalfire-CF source pinned to a release tag (vX.Y.Z).
# The source-pin gate MUST NOT flag this file.
module "ec2" {
  source = "github.com/Coalfire-CF/terraform-aws-ec2?ref=v2.2.6"

  name = "example"
}
