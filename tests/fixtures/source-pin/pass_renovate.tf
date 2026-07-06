# Fixture: VALID (PASS) — the exact line shape the Renovate preset
# (renovate/terraform-ref-pins.json5) produces after a bump: full git:: form
# with .git suffix + //subdir, 40-hex SHA, adjacent `# vX.Y.Z` comment.
# The source-pin gate MUST NOT flag it (proves Renovate output is gate-clean
# by construction — grade-A plan item #18).
module "vpc" {
  source = "git::https://github.com/Coalfire-CF/terraform-aws-vpc-nfw.git//modules/vpc?ref=aabbccddeeff00112233445566778899aabbccdd" # v3.1.4

  name = "example"
}
