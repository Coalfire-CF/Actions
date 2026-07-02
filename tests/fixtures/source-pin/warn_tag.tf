# Fixture: TRANSITIONAL (WARN) — pinned to a release tag vX.Y.Z. Allowed during
# the RFC-0008 advisory window but mutable; the gate MUST emit a ::warning and
# MUST NOT count it as a fail-class finding (never fails the job).
module "kms" {
  source = "github.com/Coalfire-CF/terraform-aws-kms?ref=v0.0.6"

  name = "example"
}
