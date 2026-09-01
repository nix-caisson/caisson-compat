# SPDX-License-Identifier: MIT
{

  description = "Pinned-world tests and compatibility surface for the caisson family";

  inputs = {

    # caisson-core is public; caisson is still private, so its input
    # keeps the SSH URL until it publishes.
    caisson-core.url = "github:nix-caisson/caisson-core";
    caisson.url = "git+ssh://git@github.com/nix-caisson/caisson";
    caisson.inputs.caisson-core.follows = "caisson-core";

    nixpkgs-lib.url = "github:nix-community/nixpkgs.lib";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    colmena.url = "github:zhaofengli/colmena";
    colmena.inputs.nixpkgs.follows = "nixpkgs";
    terranix.url = "github:terranix/terranix";
    terranix.inputs.nixpkgs.follows = "nixpkgs";
    system-manager.url = "github:numtide/system-manager";
    system-manager.inputs.nixpkgs.follows = "nixpkgs";

  };

  outputs =
    inputs@{ self, ... }:
    {
      lib.caisson-compat.tests = import ./tests { inherit inputs; };
    };

}
