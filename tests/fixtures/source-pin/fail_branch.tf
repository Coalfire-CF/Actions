# Fixture: INVALID — branch ref (?ref=module), not a release tag.
# The source-pin gate MUST flag this file.
module "vnet" {
  source = "github.com/Coalfire-CF/ACE-Azure-Vnet?ref=module"

  name = "example"
}
