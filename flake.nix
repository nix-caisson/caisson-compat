# SPDX-License-Identifier: MIT
{

  description = "Pinned-world tests and compatibility surface for the caisson family";

  inputs = {

    # While the caisson repositories are private, the sibling inputs use
    # SSH URLs; they switch to github: references at publication.
    caisson-core.url = "git+ssh://git@github.com/nix-caisson/caisson-core";
    caisson.url = "git+ssh://git@github.com/nix-caisson/caisson";

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
