# Changelog

## [0.7.0](https://github.com/Coalfire-CF/Actions/compare/v0.6.0...v0.7.0) (2026-07-02)


### Features

* add reusable Terratest workflow with multi-cloud OIDC ([a2477d4](https://github.com/Coalfire-CF/Actions/commit/a2477d44fe20feb72ab20a42c74a93c105b93a29))
* add Terraform source-pin gate (F04) ([8da3502](https://github.com/Coalfire-CF/Actions/commit/8da350245eaf2ceee17fe5a412064084ac766627))
* **opa:** add org-opa advisory policy-as-code runner (F08/ADR-0003) ([33d6c8f](https://github.com/Coalfire-CF/Actions/commit/33d6c8f2ce2e241596eac96c3b90ea1ce2e34fca))
* **source-pin:** adopt SHA-preferred semantics + strict input; wire tests into CI ([a94aad9](https://github.com/Coalfire-CF/Actions/commit/a94aad9b74f34a2efef1eca3e12297ad161db311))
* **uses-pin:** add workflow uses: pin gate (SHA-preferred, advisory) ([a2abef8](https://github.com/Coalfire-CF/Actions/commit/a2abef810ac6536d3b4a8145889fb39be0fb7aec))
* v0.7.0 consolidated gates + root-cause fixes ([#129](https://github.com/Coalfire-CF/Actions/issues/129), [#130](https://github.com/Coalfire-CF/Actions/issues/130)) ([598c71c](https://github.com/Coalfire-CF/Actions/commit/598c71ca4c6034a6cd0517a4d29f56c5d08e585e))
* **version-band:** add org-terraform-version-band gate + band mirror ([243c734](https://github.com/Coalfire-CF/Actions/commit/243c734a2fce81df10f16f861a3a1c7c6fc6b32c))


### Bug Fixes

* **ci:** self-PR script fallback for pin gates + MD029 in ORG_OPA ([276c3d5](https://github.com/Coalfire-CF/Actions/commit/276c3d5e6f44bc24aab76f53b6791693385ba21d))
* **org-release-clean:** restore NIST control breadcrumbs; annotate terratest ([43cbeb3](https://github.com/Coalfire-CF/Actions/commit/43cbeb3c0000735077232f092d8b569ffffc4316))
* **release:** type org-release secrets interface + fix caller contract (F42/N1) ([10c4cd6](https://github.com/Coalfire-CF/Actions/commit/10c4cd6b56fd0cd8c1fe4bf8c2025dc47266fde3))
* remove deprecated org-azure-deploy workflow (F39, D2) ([cab4f8d](https://github.com/Coalfire-CF/Actions/commit/cab4f8de3033a6b6f3e6c5a1356668e379353406))
* remove org-checkov-release.yml straggler ([#130](https://github.com/Coalfire-CF/Actions/issues/130)) ([739bdc5](https://github.com/Coalfire-CF/Actions/commit/739bdc57019d44016aeb9bea9a9f01b6e8481777))
* **terraform:** fail-closed version validation in resolve (F36) ([31c6c2a](https://github.com/Coalfire-CF/Actions/commit/31c6c2aaa076398f385295551a02616309ac1dd7))
* **terraform:** hermetic TF-version resolution via baked default (F36, Plan B) ([3cc48bd](https://github.com/Coalfire-CF/Actions/commit/3cc48bd82545274409921db21d860f2997c90529))
* **terratest:** declare SLACK_BOT_TOKEN secret and fail-closed version resolution ([fffcab4](https://github.com/Coalfire-CF/Actions/commit/fffcab450ab0cf05f258c1784c162cdd22490ba3))
* **terratest:** harden input validation and shell safety ([7842d90](https://github.com/Coalfire-CF/Actions/commit/7842d90df75c62b549b811e6536de8dc5d595ca9))
* **terratest:** honest pass/fail state and informative reporting ([b3254d4](https://github.com/Coalfire-CF/Actions/commit/b3254d4dd73f5f510881fd4b98719d7d0233b007))
* **terratest:** honor working_directory and add job hardening ([a5e447e](https://github.com/Coalfire-CF/Actions/commit/a5e447e38b7edef818c185fa1a62cfbb12bc3f92))
* **terratest:** pin notify-failure to the local sibling workflow ref ([33c9772](https://github.com/Coalfire-CF/Actions/commit/33c977254d7fb24081c79a49744a5ef2c27dc9de))
* **terratest:** quote $GITHUB_OUTPUT in check-app-secrets step ([bfaad5c](https://github.com/Coalfire-CF/Actions/commit/bfaad5c92ba4177978028bb9ef69c7c98cf523c5))
* **terratest:** resolve TF version from baked literal, not raw main fetch (Plan B) ([42c779a](https://github.com/Coalfire-CF/Actions/commit/42c779a8c0c8ad8cb5df00a37aef4bf8214b1254))
* **workflows:** declare forwarded SLACK_BOT_TOKEN secret (N3) ([4a3a208](https://github.com/Coalfire-CF/Actions/commit/4a3a208765d850279391664bdf1f50a1fe68f51d))
* **workflows:** pin internal sibling calls to local ./ refs (N2/D3) ([ceb0c16](https://github.com/Coalfire-CF/Actions/commit/ceb0c1606e0969d2b25f240344ec2c9ee30aa3b5))


### Documentation

* add new-gate rows + ORG_SOURCE_PIN/ORG_VERSION_BAND one-pagers ([0dd87d7](https://github.com/Coalfire-CF/Actions/commit/0dd87d787862342785dfbe2f7be67b7e211829fd))
* **terratest:** fix OIDC trust policies for PR mode, lint to zero, add notes ([d9c8ebf](https://github.com/Coalfire-CF/Actions/commit/d9c8ebf2aac735457b2fa5b683c347bd4133a7ca))

## [0.6.0](https://github.com/Coalfire-CF/Actions/compare/v0.5.1...v0.6.0) (2026-07-01)


### Features

* add cosign signing to release clean pipeline ([60e3f48](https://github.com/Coalfire-CF/Actions/commit/60e3f48c3a14428e92ce2b7e8407df4983f2d960))
* add cosign signing to release clean pipeline ([6e1639c](https://github.com/Coalfire-CF/Actions/commit/6e1639c0930c446eed8db84f6f40aaa438ec290f))
* auto merge dependabot ([9145ca7](https://github.com/Coalfire-CF/Actions/commit/9145ca7f5772e190eca1ccbdbf7551f29219e7b0))
* auto merge dependabot ([3dfdaa6](https://github.com/Coalfire-CF/Actions/commit/3dfdaa6e97fdf8b37a5ead855e250f2efa97e940))
* convert dependabot auto-merge to use Bedrock Converse ([24412dd](https://github.com/Coalfire-CF/Actions/commit/24412ddf1097157d32cda58241fc50bdeb52ef32))
* two-tier S3 cache and repo-scoped applicability analysis ([be018f1](https://github.com/Coalfire-CF/Actions/commit/be018f14020cf8b95c834b23a663ce62c1a5b62b))


### Bug Fixes

* dependabot restriction ([222e26d](https://github.com/Coalfire-CF/Actions/commit/222e26d8e9da13a557218956cc2d5649843b7f6f))
* dependabot restriction ([d7f5867](https://github.com/Coalfire-CF/Actions/commit/d7f58672717884218550d116940200a83b942764))
* harden Bedrock response parsing in breaking change check ([6476a64](https://github.com/Coalfire-CF/Actions/commit/6476a641253d1b9780ff1a89923bd07ab5d374dd))
* include full step context in GitHub Actions usage analysis ([e5da858](https://github.com/Coalfire-CF/Actions/commit/e5da858bc429ff515fb00a6f616ae4f5e8640592))
* restore org-checkov-release.yml for backward compatibility ([4cdeda8](https://github.com/Coalfire-CF/Actions/commit/4cdeda8188182d43cd5622c3eb5cb8d80c2b18bc))
* restore org-checkov-release.yml for backward compatibility ([ef89945](https://github.com/Coalfire-CF/Actions/commit/ef8994570449c3e3868494e8d87479ba8efecb4d))


### Miscellaneous

* bump terraform version to 1.15.3 ([555ffc9](https://github.com/Coalfire-CF/Actions/commit/555ffc9193c89d56a5c795d9bde5175ce23a9c66))
* bump terraform version to 1.15.3 ([e9cacd0](https://github.com/Coalfire-CF/Actions/commit/e9cacd06b61ad5dd1fc5e47b1167420dfab5ed52))
* bump terraform version to 1.15.7 ([807a6b5](https://github.com/Coalfire-CF/Actions/commit/807a6b5f387e40cbe22aaa8488de2759fd8113f0))
* bump terraform version to 1.15.7 ([ebddbbf](https://github.com/Coalfire-CF/Actions/commit/ebddbbfefebdd48ac3cebba381bd9839d35fc4bf))
* **deps:** bump actions/checkout from 6 to 7 ([a98715c](https://github.com/Coalfire-CF/Actions/commit/a98715cd3322a66856b814aafe6836006b832faa))
* **deps:** bump actions/checkout from 6 to 7 ([6198ebd](https://github.com/Coalfire-CF/Actions/commit/6198ebdfe746466b92befe57dd9d0f58f7e5c0d8))
* **deps:** bump actions/create-github-app-token from 1.12.0 to 3.0.0 ([df5f494](https://github.com/Coalfire-CF/Actions/commit/df5f4941a1718081c1815df3fbf01798a9a3cffb))
* **deps:** bump actions/create-github-app-token from 1.12.0 to 3.0.0 ([37c8514](https://github.com/Coalfire-CF/Actions/commit/37c8514005e3c6a9464e6b1c6f3b2d376f6008cc))
* **deps:** bump actions/create-github-app-token from 3.1.1 to 3.2.0 ([c98ecb8](https://github.com/Coalfire-CF/Actions/commit/c98ecb8c8d7a7b16d8d2ab04d3539b10eebc7bfa))
* **deps:** bump actions/create-github-app-token from 3.1.1 to 3.2.0 ([a20f547](https://github.com/Coalfire-CF/Actions/commit/a20f547418c1bc1694f726d0dc874b036edcfea1))
* **deps:** bump actions/github-script from 8.0.0 to 9.0.0 ([8c79386](https://github.com/Coalfire-CF/Actions/commit/8c7938612c95a320126683b5d87fdc6af7a26523))
* **deps:** bump actions/github-script from 8.0.0 to 9.0.0 ([5e68a38](https://github.com/Coalfire-CF/Actions/commit/5e68a3807a8b4019562b221005155923540dc77f))
* **deps:** bump actions/setup-node from 4.4.0 to 6.3.0 ([546ef76](https://github.com/Coalfire-CF/Actions/commit/546ef766441e23335aa0f98f9e2a9519bf2269ff))
* **deps:** bump actions/setup-node from 4.4.0 to 6.3.0 ([137096a](https://github.com/Coalfire-CF/Actions/commit/137096a81c1ab15a55dc288c3e88146021b51cde))
* **deps:** bump actions/setup-node from 6.3.0 to 6.4.0 ([37cd50c](https://github.com/Coalfire-CF/Actions/commit/37cd50c30bbab67aff5ee5c92ebce485678f3df0))
* **deps:** bump actions/setup-node from 6.3.0 to 6.4.0 ([f298f60](https://github.com/Coalfire-CF/Actions/commit/f298f6000942e668eff61bceeea72e0dca4f91b8))
* **deps:** bump actions/setup-python from 6.2.0 to 6.3.0 ([43dc86f](https://github.com/Coalfire-CF/Actions/commit/43dc86f880b347c6221363e945ba9bdce0831dca))
* **deps:** bump actions/setup-python from 6.2.0 to 6.3.0 ([064c8a7](https://github.com/Coalfire-CF/Actions/commit/064c8a70cb335078dc03f5fb6af78b4dd6013abc))
* **deps:** bump actions/upload-artifact from 7.0.0 to 7.0.1 ([5976cc5](https://github.com/Coalfire-CF/Actions/commit/5976cc5d9a25c527b1569d3441248a88e7b4a585))
* **deps:** bump actions/upload-artifact from 7.0.0 to 7.0.1 ([e461ec5](https://github.com/Coalfire-CF/Actions/commit/e461ec508fa3cf518c2e8580f7e963ab6fb7748b))
* **deps:** bump aquasecurity/trivy-action from 0.35.0 to 0.36.0 ([2911b4a](https://github.com/Coalfire-CF/Actions/commit/2911b4aef757904379f66102f5cf66d2cee36b8f))
* **deps:** bump aquasecurity/trivy-action from 0.35.0 to 0.36.0 ([4578438](https://github.com/Coalfire-CF/Actions/commit/457843838b2cf0c6adc23ef76043018a1f84f00a))
* **deps:** bump aws-actions/configure-aws-credentials ([b73cc3b](https://github.com/Coalfire-CF/Actions/commit/b73cc3bd5ef245ba7352dd392d4033bbb534a8f4))
* **deps:** bump aws-actions/configure-aws-credentials ([1f98e44](https://github.com/Coalfire-CF/Actions/commit/1f98e4471425c3e7a507f4b591f60d7e0fcf8e8e))
* **deps:** bump aws-actions/configure-aws-credentials ([1ee65b1](https://github.com/Coalfire-CF/Actions/commit/1ee65b1500006a68c34716de87c2063fba73a345))
* **deps:** bump aws-actions/configure-aws-credentials ([9290937](https://github.com/Coalfire-CF/Actions/commit/929093779c81df080bf0d649ded7d6db6cbde873))
* **deps:** bump aws-actions/configure-aws-credentials from 4.3.1 to 6.1.0 ([92807c2](https://github.com/Coalfire-CF/Actions/commit/92807c2861d7132f28dfe5013ac0cea95ff0985b))
* **deps:** bump aws-actions/configure-aws-credentials from 6.1.0 to 6.1.1 ([1e16e5b](https://github.com/Coalfire-CF/Actions/commit/1e16e5bdb8f0d13e485cb113b6c59c0e3de53b88))
* **deps:** bump aws-actions/configure-aws-credentials from 6.1.1 to 6.2.1 ([139c556](https://github.com/Coalfire-CF/Actions/commit/139c55678a58ae34fb356faa120fb58bc2d00596))
* **deps:** bump aws-actions/configure-aws-credentials from ff717079ee2060e4bcee96c4779b553acc87447c to 7474bc4690e29a8392af63c5b98e7449536d5c3a ([e6380a0](https://github.com/Coalfire-CF/Actions/commit/e6380a03642aab5c14e5605b70827b341ccb441a))
* **deps:** bump dependabot/fetch-metadata from 3.0.0 to 3.1.0 ([f378746](https://github.com/Coalfire-CF/Actions/commit/f378746afdb6751bce19b2679813a55fd40e22ea))
* **deps:** bump dependabot/fetch-metadata from 3.0.0 to 3.1.0 ([f93a63e](https://github.com/Coalfire-CF/Actions/commit/f93a63e91b99d67a5e1d296bea14b581c42bc21d))
* **deps:** bump googleapis/release-please-action from 4.4.0 to 5.0.0 ([e794cdb](https://github.com/Coalfire-CF/Actions/commit/e794cdb3a0909ade901dcc150111d1fcc93b137e))
* **deps:** bump googleapis/release-please-action from 4.4.0 to 5.0.0 ([85fdfb9](https://github.com/Coalfire-CF/Actions/commit/85fdfb9c47e2faedbb9525a0a101390ef470c2fb))
* **deps:** bump hashicorp/setup-terraform from 4.0.0 to 4.0.1 ([5d1fce9](https://github.com/Coalfire-CF/Actions/commit/5d1fce9fb857d22f41b54cc776b1cea57f64cd7e))
* **deps:** bump hashicorp/setup-terraform from 4.0.0 to 4.0.1 ([fead13d](https://github.com/Coalfire-CF/Actions/commit/fead13de775f5acc52dec43f9af931245eef9b11))
* **deps:** bump sigstore/cosign-installer from 4.1.1 to 4.1.2 ([31581a7](https://github.com/Coalfire-CF/Actions/commit/31581a73ca75bd46607bb5749ae1e840b6a937d2))
* **deps:** bump sigstore/cosign-installer from 4.1.1 to 4.1.2 ([a4f0c0e](https://github.com/Coalfire-CF/Actions/commit/a4f0c0e4c944bc54893b49158c72d935d163a07a))
* remove test-cosign workflow ([7555e24](https://github.com/Coalfire-CF/Actions/commit/7555e249c64db64dd6d574587ca41857cc7f0b8c))
* remove test-cosign workflow after validation ([7d9ebe2](https://github.com/Coalfire-CF/Actions/commit/7d9ebe2a330843dc3100e08ff5cb23f995ec55b7))

## [0.5.1](https://github.com/Coalfire-CF/Actions/compare/v0.5.0...v0.5.1) (2026-04-01)


### Bug Fixes

* add github app for release ([56412b8](https://github.com/Coalfire-CF/Actions/commit/56412b872dd4dbcea55fac2a2bf252425ce83c2e))
* release app from token ([baef6f8](https://github.com/Coalfire-CF/Actions/commit/baef6f8e633f9b47dbcb2d8d5c776708216ddfc4))

## [0.5.0](https://github.com/Coalfire-CF/Actions/compare/v0.4.1...v0.5.0) (2026-04-01)


### Features

* all dependabot refresh ([5aaa40e](https://github.com/Coalfire-CF/Actions/commit/5aaa40e141e93e8ad6f60b075b592b3df9a9d963))
* init terraform plan and apply actions ([2179f01](https://github.com/Coalfire-CF/Actions/commit/2179f016f3a77b1b6173e9962cff2c36c143fac7))
* init terraform plan and apply actions ([d83c586](https://github.com/Coalfire-CF/Actions/commit/d83c586159f1452d6583b38def891e9d7aa2d088))


### Bug Fixes

* add claude files to be purged ([a430b2c](https://github.com/Coalfire-CF/Actions/commit/a430b2cbd2eb670f915ff2adb59e56406a7e79da))
* add claude files to be purged ([11906d5](https://github.com/Coalfire-CF/Actions/commit/11906d5b295c61d965fd9caa48d58a681f38247b))
* create inline markdownlint config and enable pipefail ([66db752](https://github.com/Coalfire-CF/Actions/commit/66db7522d319248709ee9a41360e947be964b9de))
* disable MD024 and MD060 for terraform-docs compatibility ([3006491](https://github.com/Coalfire-CF/Actions/commit/30064910f0a10f90a489245316d238b6064e060e))
* fixing some markdown read errors ([5097e8e](https://github.com/Coalfire-CF/Actions/commit/5097e8e72c2f66f0a947e93f88b1dbfcc644e973))
* harden workflow security and pin third-party actions to SHAs ([b9e22b8](https://github.com/Coalfire-CF/Actions/commit/b9e22b828a5a3820846421e5f27bd7a156c48024))
* keeping input but is deprecated, will be removed in future versions ([0bb85cf](https://github.com/Coalfire-CF/Actions/commit/0bb85cf0e6d4fad938000d25c4a1bb02a274b995))
* remove checkov ([f4ac0b9](https://github.com/Coalfire-CF/Actions/commit/f4ac0b9c5aaf9d0019a157c4618e23d19efe5dc9))
* remove checkov ([76fd82e](https://github.com/Coalfire-CF/Actions/commit/76fd82efc3b65dd64cfb6977a4b93dc1982ecf88))
* truncate release highlights to stay within Slack block text limit ([a1f54bf](https://github.com/Coalfire-CF/Actions/commit/a1f54bfee5e2415710c7d6b3b6e3fcbb47f9f48c))
* use fetch-depth 0 in markdown lint to enable diff against origin/main ([471f332](https://github.com/Coalfire-CF/Actions/commit/471f33290126a4db3e2e661167ed71c7c73960c7))
* use npx with pinned version for markdown lint in reusable workflow ([0fccd87](https://github.com/Coalfire-CF/Actions/commit/0fccd873bb8be31f59f6ee31c4f6cc4c42597e54))


### Miscellaneous

* bump terraform version to 1.14.8 ([1f2431f](https://github.com/Coalfire-CF/Actions/commit/1f2431f630d9135914e5541926355128c99b28fc))
* bump terraform version to 1.14.8 ([8d154d4](https://github.com/Coalfire-CF/Actions/commit/8d154d41a3279b46b634708702bb18ec6e85328d))
* **deps:** bump actions/create-github-app-token from 2 to 3 ([c7ce8ba](https://github.com/Coalfire-CF/Actions/commit/c7ce8bae7f09c4f643647873696fbafab5b309f4))
* **deps:** bump actions/create-github-app-token from 2 to 3 ([0c8fe7b](https://github.com/Coalfire-CF/Actions/commit/0c8fe7b12ca9eb3e89564705269fba990740b903))


### Documentation

* update README and docs for security hardening changes ([e9f63d1](https://github.com/Coalfire-CF/Actions/commit/e9f63d19c99da9905881017d66ddfe1c973aebf9))

## [0.4.1](https://github.com/Coalfire-CF/Actions/compare/v0.4.0...v0.4.1) (2026-03-16)


### Documentation

* add Slack notification setup and usage guide ([7e22dbe](https://github.com/Coalfire-CF/Actions/commit/7e22dbecbca706205ca3cd80ff37b51d8c8d0ac9))
* add Slack notification setup and usage guide ([584dd84](https://github.com/Coalfire-CF/Actions/commit/584dd8495e4d7d078323cc270b233328a510c9c2))

## [0.4.0](https://github.com/Coalfire-CF/Actions/compare/v0.3.2...v0.4.0) (2026-03-16)


### Features

* add optional slack failure notifications to all reusable workflows ([782da28](https://github.com/Coalfire-CF/Actions/commit/782da28ef7f6e22049dd7dc334d1191038e2bddf))
* add Slack channel notifications to reusable workflows ([be68807](https://github.com/Coalfire-CF/Actions/commit/be688079505fe9ca7a13f5bc28a5373354be8db7))
* adding org slack notify ([0a9f18e](https://github.com/Coalfire-CF/Actions/commit/0a9f18e4bb3f7b887d919870694ade0fdaf8cf78))


### Bug Fixes

* clean up release highlights for Slack formatting ([d373649](https://github.com/Coalfire-CF/Actions/commit/d3736497b93b282241a960e745a29ba4a1eda08d))
* convert markdown headers to Slack bold and strip commit hashes ([8ed0dde](https://github.com/Coalfire-CF/Actions/commit/8ed0ddea54ec34459e806b31a7b7444c6b6c08aa))
* use jq for JSON payload construction to handle multiline release bodies ([49172f4](https://github.com/Coalfire-CF/Actions/commit/49172f43dc828c9eb98580f85f1575c24b3d3888))

## [0.3.2](https://github.com/Coalfire-CF/Actions/compare/v0.3.1...v0.3.2) (2026-03-10)


### Bug Fixes

* allow individual repos to ignore as needed ([5880e68](https://github.com/Coalfire-CF/Actions/commit/5880e68f364ee2346daf27a877fa0c8230db1fb7))
* allow individual repos to ignore as needed ([dfc9224](https://github.com/Coalfire-CF/Actions/commit/dfc922485a655081fe467c0e9355660146b7792c))
* remove infracost ([2929b93](https://github.com/Coalfire-CF/Actions/commit/2929b93ddf90fb348192b46361487b66caad06d6))
* remove infracost ([29f6de5](https://github.com/Coalfire-CF/Actions/commit/29f6de5bfd2527dfd17ea6ee8a9e36a57c62c203))


### Miscellaneous

* bumping to latest ([8390d63](https://github.com/Coalfire-CF/Actions/commit/8390d63cde26e477544ee24af5c047b98ded5710))
* bumping to latest ([5408cf2](https://github.com/Coalfire-CF/Actions/commit/5408cf244508bc0612034e4fd9f38b1aab954b6e))
* **deps:** bump actions/upload-artifact from 6 to 7 ([f35b43d](https://github.com/Coalfire-CF/Actions/commit/f35b43d315cf85ebef3b74b2506939e2377d905f))
* **deps:** bump actions/upload-artifact from 6 to 7 ([262a12c](https://github.com/Coalfire-CF/Actions/commit/262a12c05f66952f8ac853298ce25dedd7259bc7))
* **deps:** bump aquasecurity/trivy-action from 0.34.0 to 0.35.0 ([d3503d3](https://github.com/Coalfire-CF/Actions/commit/d3503d38db25da95b4bcf357d75d3c67c86f0c41))
* **deps:** bump aquasecurity/trivy-action from 0.34.0 to 0.35.0 ([5bc7054](https://github.com/Coalfire-CF/Actions/commit/5bc70544696954c0d33962a4dfcf2243c570d58d))
* **deps:** bump hashicorp/setup-terraform from 3 to 4 ([c27068e](https://github.com/Coalfire-CF/Actions/commit/c27068e411cd4168ad8ee689eda234c7b0dbad10))
* **deps:** bump hashicorp/setup-terraform from 3 to 4 ([97257d0](https://github.com/Coalfire-CF/Actions/commit/97257d0b3e18a1fbcf6695e400b1edc428e47fe7))

## [0.3.1](https://github.com/Coalfire-CF/Actions/compare/v0.3.0...v0.3.1) (2026-02-17)


### Bug Fixes

* infracost comment feature ([b9ea2ed](https://github.com/Coalfire-CF/Actions/commit/b9ea2ed15e942d50b719a087c5ce74a0c412ffd5))
* infracost comment feature ([e462f8c](https://github.com/Coalfire-CF/Actions/commit/e462f8c808af6cd6f6a541b1e7aa03195a673446))

## [0.3.0](https://github.com/Coalfire-CF/Actions/compare/v0.2.4...v0.3.0) (2026-02-16)


### Features

* gitleaks init ([14a540a](https://github.com/Coalfire-CF/Actions/commit/14a540a5063b94fe8199be9e0064a95e4c948f3c))
* init gitleaks ([41e32ed](https://github.com/Coalfire-CF/Actions/commit/41e32ed90e4107fb020e89cde1d76b0772c11211))
* testing release cleaner ([ba47b44](https://github.com/Coalfire-CF/Actions/commit/ba47b44c9fd4f98c9317eb4d2fd4ba5393263224))


### Bug Fixes

* deleting git too soon ([d9ee35d](https://github.com/Coalfire-CF/Actions/commit/d9ee35d9cc9e1283a21de1d00eefebb4e8dc8cee))
* need to correct branch for testing ([ca1ce23](https://github.com/Coalfire-CF/Actions/commit/ca1ce23085d543ac18d1297310c4b770ca8c5738))


### Miscellaneous

* cleanup after testing ([8ef606e](https://github.com/Coalfire-CF/Actions/commit/8ef606e32528f50300f087da3a22c04f65cd554c))
* **deps:** bump aquasecurity/trivy-action from 0.33.1 to 0.34.0 ([026a03c](https://github.com/Coalfire-CF/Actions/commit/026a03ccf7dc601c86eedb399e380f523a7fefa9))
* **deps:** bump aquasecurity/trivy-action from 0.33.1 to 0.34.0 ([7cbbb15](https://github.com/Coalfire-CF/Actions/commit/7cbbb15ce38c43a9245347df6572b4644a0a79e1))

## [0.2.4](https://github.com/Coalfire-CF/Actions/compare/v0.2.3...v0.2.4) (2026-01-31)


### Bug Fixes

* branch tagging ([e685a2b](https://github.com/Coalfire-CF/Actions/commit/e685a2b598a6758140bc27497c52ba583a03b294))
* branch tagging ([f691317](https://github.com/Coalfire-CF/Actions/commit/f6913174f8e89b08db5ff1fa1267ad0e47c2d8e8))

## [0.2.3](https://github.com/Coalfire-CF/Actions/compare/v0.2.2...v0.2.3) (2026-01-31)


### Bug Fixes

* add outputs to workflow ([f08ac31](https://github.com/Coalfire-CF/Actions/commit/f08ac31236aeb187ebe6c750c1cca2d91ec53307))
* add outputs to workflow ([0c37104](https://github.com/Coalfire-CF/Actions/commit/0c371041858c2f7a9909992d88f3491e1370b7de))


### Miscellaneous

* **deps:** bump actions/github-script from 7 to 8 ([e79b893](https://github.com/Coalfire-CF/Actions/commit/e79b893f53c3aed6a15af8538822bd9c79ab576c))
* **deps:** bump actions/github-script from 7 to 8 ([7d7e1b7](https://github.com/Coalfire-CF/Actions/commit/7d7e1b74d386c8da4323fa38a1511cb0676c370c))
* **deps:** bump infracost/actions from 1 to 3 ([64e295e](https://github.com/Coalfire-CF/Actions/commit/64e295e74898683ec9d0773cdad143a86d74d80c))
* **deps:** bump infracost/actions from 1 to 3 ([240b4eb](https://github.com/Coalfire-CF/Actions/commit/240b4eb5e672d4859839c26ae649e5656d77e68a))

## [0.2.2](https://github.com/Coalfire-CF/Actions/compare/v0.2.1...v0.2.2) (2026-01-28)


### Bug Fixes

* add org creds ([1ac8f3d](https://github.com/Coalfire-CF/Actions/commit/1ac8f3d96ce0c30116a14701886038390ae8b481))
* add org creds ([f2798af](https://github.com/Coalfire-CF/Actions/commit/f2798affbc1c9abf98feff6b9eb7d26167670472))
* renaming local release, also was behind could be the issue. ([5412066](https://github.com/Coalfire-CF/Actions/commit/5412066dd2365708b0651f155231b435b695c900))
* renaming local release, also was behind could be the issue. ([c3d9360](https://github.com/Coalfire-CF/Actions/commit/c3d93608364b616961c1192d5b5fbbe3bb7b325b))


### Miscellaneous

* **deps:** bump actions/setup-python from 6.1.0 to 6.2.0 ([cdabc23](https://github.com/Coalfire-CF/Actions/commit/cdabc233d9a8157846f12e5a622e2968db9fa746))
* **deps:** bump actions/setup-python from 6.1.0 to 6.2.0 ([70f4486](https://github.com/Coalfire-CF/Actions/commit/70f44865fdea04d90da2407a73f3fdcae6bf0240))

## [0.2.1](https://github.com/Coalfire-CF/Actions/compare/v0.2.0...v0.2.1) (2026-01-16)


### Bug Fixes

* skip github release creation temporarily to unblock release-please ([4a28c61](https://github.com/Coalfire-CF/Actions/commit/4a28c61ae0ee008029be78909dfecc0791689c83))
* splitting local and reusable release process ([a3ddaed](https://github.com/Coalfire-CF/Actions/commit/a3ddaedd64655287ed5f8112254257180494bf3f))
* splitting local and reusable release process ([24ac2af](https://github.com/Coalfire-CF/Actions/commit/24ac2af662d8ea4602bcdc7e29d05d5eab1b77f3))
* testing new release fix ([b978089](https://github.com/Coalfire-CF/Actions/commit/b978089f0759cd94275a7d5ec1722d2326d1b637))
* testing new release fix ([d3b272d](https://github.com/Coalfire-CF/Actions/commit/d3b272da334287bcb9729ab3feb9856e9ac0d463))
* updating pinned branch to main for temp workaround. ([4819e1c](https://github.com/Coalfire-CF/Actions/commit/4819e1c3160c90bbfdd538c4eaa9c875930d3869))
* updating pinned branch to main for temp workaround. ([36f11df](https://github.com/Coalfire-CF/Actions/commit/36f11dfe11e66e160c9e1982e9697ec822b6dd7f))


### Miscellaneous

* trigger release-please after fixing v0.2.0 tag ([895a4b7](https://github.com/Coalfire-CF/Actions/commit/895a4b7945d78e30a932c975c55e8a2b08670191))
* trigger release-please after updating PR label ([e1225f7](https://github.com/Coalfire-CF/Actions/commit/e1225f75c26d99c33170f657a0ca3b5419fbd5fc))
* trigger release-please to create new PR ([e7357fb](https://github.com/Coalfire-CF/Actions/commit/e7357fb61d5ab3718839683e0c8f5842a6b39ce1))

## [0.2.0](https://github.com/Coalfire-CF/Actions/compare/v0.1.1...v0.2.0) (2026-01-07)


### Features

* add jira integration ([4cedcbb](https://github.com/Coalfire-CF/Actions/commit/4cedcbbd22e901cd344bb698e122cccd8e0647ec))

## [0.1.1](https://github.com/Coalfire-CF/Actions/compare/v0.1.0...v0.1.1) (2026-01-06)


### Miscellaneous

* **deps:** bump actions/checkout from 5 to 6 ([8f9bf7c](https://github.com/Coalfire-CF/Actions/commit/8f9bf7c1583e2e430eb18b63c68de4e8eda0d177))
* **deps:** bump actions/checkout from 5 to 6 ([86693b9](https://github.com/Coalfire-CF/Actions/commit/86693b95d94bd1ca10c588c952d223b1668f852f))
* **deps:** bump actions/create-github-app-token from 1 to 2 ([3087278](https://github.com/Coalfire-CF/Actions/commit/308727810f805e706936a9b9918cbb372da853ad))
* **deps:** bump actions/create-github-app-token from 1 to 2 ([7b235ba](https://github.com/Coalfire-CF/Actions/commit/7b235ba636248705addb1b0d891cdc20e41b0ab6))
* **deps:** bump actions/setup-python from 6.0.0 to 6.1.0 ([387642e](https://github.com/Coalfire-CF/Actions/commit/387642eab769f76bd907b5cf74210778d2d14514))
* **deps:** bump actions/setup-python from 6.0.0 to 6.1.0 ([000abaa](https://github.com/Coalfire-CF/Actions/commit/000abaa2b1a9b40f28a20c2183f2dfc9ec87c47a))
* **deps:** bump googleapis/release-please-action from 4.3.0 to 4.4.0 ([10cf66f](https://github.com/Coalfire-CF/Actions/commit/10cf66f0ef1fae5f140132c3e0b92faed0cf2f07))
* **deps:** bump googleapis/release-please-action from 4.3.0 to 4.4.0 ([9b8560b](https://github.com/Coalfire-CF/Actions/commit/9b8560b03c26221cd3357314091b21830dfef5c8))

## [0.1.0](https://github.com/Coalfire-CF/Actions/compare/v0.0.20...v0.1.0) (2025-09-29)


### Features

* add dependsbot update action, updates to dependabot.yml, update codeowner ([8347989](https://github.com/Coalfire-CF/Actions/commit/83479898fc42e6d016d17fe06e4dacd4b352b9c0))
* change release and dependency update process ([0a377a5](https://github.com/Coalfire-CF/Actions/commit/0a377a5c6791df46c40831723c425f642efcdbd5))
* dependabot release please update ([8e4b1a3](https://github.com/Coalfire-CF/Actions/commit/8e4b1a310624c63d378537785117fbffe04d4704))
* dependabot updater workflow ([d9a3ec6](https://github.com/Coalfire-CF/Actions/commit/d9a3ec67e8f1cac78d69f366669acce80452c16d))


### Bug Fixes

* action flops on no tf files ([703c3c8](https://github.com/Coalfire-CF/Actions/commit/703c3c81a847eb5626abaed1affe1ebd9ffc6468))
* adding ignore step ([ee843a9](https://github.com/Coalfire-CF/Actions/commit/ee843a97c94efd76661e165455f4b26ace9d3d20))
* don't need to update ([d6d4377](https://github.com/Coalfire-CF/Actions/commit/d6d437703764a7d177da64002d753b0d1f2561c9))
* eh going to have to embed I believe ([df29e10](https://github.com/Coalfire-CF/Actions/commit/df29e10ca4f4ebe365407e4a0c21a398b353b3cb))
* eh trying new approach, mapfil still prints empty ([9d71eab](https://github.com/Coalfire-CF/Actions/commit/9d71eab683143f9938033e1ffc4588e5aadbe312))
* final test on just branch. ([5df5cbb](https://github.com/Coalfire-CF/Actions/commit/5df5cbb67f2cba4a5ce8c08f7a87c953e27c590b))
* i think I have the submodule issue worked out ([5b7b60d](https://github.com/Coalfire-CF/Actions/commit/5b7b60dac88c85dbdcb0a5b2520bfaae4556c3b4))
* remove unneeded script ([62af43d](https://github.com/Coalfire-CF/Actions/commit/62af43dc8e21596a99ee61fa6e68ae55880eb3b3))
* removing old tree readme for new ([8af3eff](https://github.com/Coalfire-CF/Actions/commit/8af3eff50e05c1fcef840fc50781f29512867316))
* removing update part. Should be good now ([3d84c8c](https://github.com/Coalfire-CF/Actions/commit/3d84c8c156994416652a1e4f83adceea73f21215))
* shouldn't have dev it the other way to begin with ([dcb9528](https://github.com/Coalfire-CF/Actions/commit/dcb9528ca44ffdcebce2acc5351f06658b4145a1))
* still testing ([5cf1598](https://github.com/Coalfire-CF/Actions/commit/5cf1598cb1070121cd2aa110d7f37e90b793724a))
* still testing downstream ([2e6b717](https://github.com/Coalfire-CF/Actions/commit/2e6b717bcd1fc60df0bb6e732a198d77e274d4ba))
* still testing if it ignores ([667d2b1](https://github.com/Coalfire-CF/Actions/commit/667d2b147dcdef43d4e510941fe52508d58f4caf))
* still testing, re-broke it ([7505dc4](https://github.com/Coalfire-CF/Actions/commit/7505dc44f5b0fafb3d91da78444f59812695a100))
* still wip ([45f0833](https://github.com/Coalfire-CF/Actions/commit/45f0833bc5d4f0abaead3fb714d8ceec62288a3a))
* testing dependabot update workflow ([b8ee4ad](https://github.com/Coalfire-CF/Actions/commit/b8ee4ade1614941fdb3df921bda015cd2b82eded))
* testing different clone locaiton for scriopt ([e90bbb6](https://github.com/Coalfire-CF/Actions/commit/e90bbb6f3b2eb37ab4d3b428e460ea27e7e84762))
* testing how to pass in repo name ([de8137a](https://github.com/Coalfire-CF/Actions/commit/de8137aab4486d05704e1c5a60fc8b47bd30213b))
* testing permission fix ([f0a0863](https://github.com/Coalfire-CF/Actions/commit/f0a08633c2b5bf2f71972b936931a046b19ccf80))
* testing permission fix ([a446059](https://github.com/Coalfire-CF/Actions/commit/a44605974dbb4453a916d71adc73ab9cb9193972))
* testing the swapping the mapfile ([b040da6](https://github.com/Coalfire-CF/Actions/commit/b040da66970cebbb69350f1c288c4a3ae0e13792))
* typo ([d2328c1](https://github.com/Coalfire-CF/Actions/commit/d2328c115b7d3f141d1d8bc42ad9e823548f55dd))


### Miscellaneous

* remove unneeded script ([a2f048c](https://github.com/Coalfire-CF/Actions/commit/a2f048cec48a2bc280b20fcfb768439e91eb516d))
* update readme to account for slight change in release process ([250594b](https://github.com/Coalfire-CF/Actions/commit/250594b0d0036c807d6a39197e02c5fff640539d))
