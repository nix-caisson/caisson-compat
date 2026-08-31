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

The suite composes caisson's library and its six integrations through
the caisson-core composition calculus against the pinned world, and
exercises the calculus's guarantees (dedup, replacement, polyfills,
the keyless tail) over the real entries plus integration behavior:
a minimal NixOS system evaluated through `caisson-nixos` against the
pinned nixpkgs, `caisson-home-manager` source-metadata provenance,
and the integrations' ecosystemSrc validation.

While the caisson repositories are private, the sibling inputs use SSH
URLs and cross-repository fetches need credentials that GitHub's
default workflow token does not have, so the suite runs locally and
push-triggered CI is enabled at publication (the workflow currently
runs on manual dispatch).

## License

MIT. See [LICENSE](LICENSE).

caisson-compat is an independent project, not affiliated with or
endorsed by the NixOS Foundation. Nix and NixOS are trademarks of the
NixOS Foundation.
