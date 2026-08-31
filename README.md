# caisson-compat

The churn quarantine of the caisson family. caisson-compat pins
concrete versions of everything: [caisson](https://github.com/nix-caisson/caisson),
[caisson-core](https://github.com/nix-caisson/caisson-core), and the
upstream world (nixpkgs' lib). Its pins are ordinary flake inputs,
overridable with standard `follows`, and advancing them routinely is
this repository's job, so its commit history is expected to churn.

Two audiences use it:

- **Consumers outside the caisson ecosystem** depend on caisson-compat
  when they want the caisson family with current, standard-overridable
  upstream pins.
- **The stable repositories test through it.** caisson and
  caisson-core carry no churning pins of their own; their CI fetches
  this repository and runs the suite with the local working tree
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

The suite composes caisson's seven integrations and its tooling
through the caisson-core composition calculus against the pinned
world, and exercises the calculus's guarantees (dedup, replacement,
polyfills, the keyless tail) over the real entries plus integration
behavior: both framework namespaces' shapes, a minimal NixOS system
evaluated through `caisson.nixos` against the pinned nixpkgs,
`caisson.home-manager` source-metadata provenance, the integrations'
ecosystemSrc validation, layered ecosystem-source resolution from a
declared `ecosystems.nixpkgs`, overlay-borne module contribution, and
the manifest an mkLib composition carries.

## CI and the private phase

The workflow runs on push, pull request, a weekly schedule, and
manual dispatch. The scheduled run is the family's drift detector: it
advances every pin, reruns the suite, and lands the advance when
green. While the caisson repositories are private, every job needs
the `CAISSON_CI_SSH_KEY` repository secret, an SSH private key whose
account can read the nix-caisson repositories; without it the jobs
skip with a notice. Creating and rotating that key is an owner
action (add the public half as an account SSH key or fine-grained
deploy credential; delete it to revoke). At publication the secret
becomes unnecessary and the gate steps can go. The same secret gates
the non-blocking `compat-suite` jobs in caisson and caisson-core,
which fetch this repository at HEAD and run the suite with the local
working tree overriding the corresponding pin.

## License

MIT. See [LICENSE](LICENSE).

caisson-compat is an independent project, not affiliated with or
endorsed by the NixOS Foundation. Nix and NixOS are trademarks of the
NixOS Foundation.
