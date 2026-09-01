# SPDX-License-Identifier: MIT
{

  description = "Pinned-world tests and compatibility surface for the caisson family";

  inputs = {

    # caisson's own core pin is hidden (not an input), so there is
    # nothing to follow; the suite composes with this caisson-core
    # directly where it cares.
    caisson-core.url = "github:nix-caisson/caisson-core";
    caisson.url = "github:nix-caisson/caisson";

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
