# caisson-compat

The churn quarantine of the caisson family. caisson-compat pins
concrete versions of everything: [caisson](https://github.com/nix-caisson/caisson),
[caisson-core](https://github.com/nix-caisson/caisson-core), and the
upstream world (nixpkgs and the integrated ecosystems). Its pins are
ordinary flake inputs,
overridable with standard `follows`, and advancing them routinely is
this repository's job, so its commit history is expected to churn.

It is a churn shield. caisson declares only the three small trees its
own evaluation composes with (caisson-core, nixpkgs' lib, flake-parts)
and caisson-core declares nothing; the ecosystems the integrations
wrap (nixpkgs, home-manager, colmena, terranix, system-manager) are
pinned here and nowhere else in the family, so their routine advances
land in this repository's history and the stable repositories' histories
stay about the code. The stable repositories test through it: their CI
fetches this repository and runs the suite with the local working tree
overriding the corresponding input:

  ```sh
  nix eval .#lib.caisson-compat.tests.summary \
    --override-input caisson "path:$PWD"
  ```

A routine pin advance that fails against the current stable
repositories is the family's drift detector: it signals an upstream
evaluation-shape change that caisson must absorb.

## Tests

```sh
./run-tests.sh
```

The suite composes caisson's integrations and its tooling
through caisson-core's `compose` against the pinned
world, and exercises the composition guarantees (dedup, replacement,
polyfills, the keyless tail) over the real entries plus integration
behavior: both framework namespaces' shapes, a minimal NixOS system
evaluated through `caisson.nixos` against the pinned nixpkgs,
`caisson.home-manager` source-metadata provenance, the integrations'
ecosystemSrc validation, layered ecosystem-source resolution from a
declared `defaultEcosystemSrc.nixpkgs`, a flake-parts evaluation over
the flake-parts this repository declares, overlay-borne module
contribution, and the manifest an mkLib composition carries.

## CI

The workflow runs on push, pull request, a weekly schedule, and
manual dispatch. The scheduled run is the family's drift detector: it
advances every pin, reruns the suite, and lands the advance when
green. caisson and caisson-core carry non-blocking `compat-suite`
jobs that fetch this repository at HEAD and run the suite with the
local working tree overriding the corresponding pin.

## License

MIT. See [LICENSE](LICENSE).

Despite the org name, caisson-compat is an independent project, not
affiliated with or endorsed by the NixOS Foundation. Nix and NixOS
are trademarks of the NixOS Foundation.
