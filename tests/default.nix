# SPDX-License-Identifier: MIT
#
# The pinned-world suite: exercises the caisson family against
# concrete pinned versions of itself and the upstream world.  Run
# locally with ./run-tests.sh, or from a sibling repository with its
# working tree overriding the corresponding input, e.g.
#
#   nix eval .#lib.caisson-compat.tests.summary \
#     --override-input caisson "path:$PWD"
#
{ inputs }:

let

  core = inputs.caisson-core.lib.caisson-core;
  inherit (core) compose resolve;

  entries = inputs.caisson.lib.composition.entriesFor {
    ecosystemSrc = "${inputs.nixpkgs-lib}/lib";
  };

  composed = compose {
    entries = [
      entries.caisson-nixpkgs
      entries.caisson-nixos
      entries.caisson-home-manager
      entries.caisson-colmena
      entries.caisson-terranix
      entries.caisson-system-manager
    ];
  };

  expectedCaissonNames = [
    "callConsumerFlake"
    "eval-weight"
    "importApply"
    "mkFlake"
    "mkFlakeModule"
    "mkLib"
    "mkLibOverlay"
    "mkMemoizedDerivationRead"
    "mkModule"
    "modules"
    "partitionExtraInputs"
    "types"
  ];

  results = {

    composesTheCaissonLibrary =
      builtins.attrNames composed.lib.caisson == expectedCaissonNames
      && composed.meta.order == [
        "caisson.nixpkgs-lib"
        "caisson.lib"
        "caisson.nixpkgs"
        "caisson.nixos"
        "caisson.home-manager"
        "caisson.colmena"
        "caisson.terranix"
        "caisson.system-manager"
      ];

    baseLibraryBehaves =
      composed.lib.concatStringsSep "," [ "a" "b" ] == "a,b"
      && composed.lib ? evalModules
      && composed.lib ? mkOption;

    flakePartsLibReexported = composed.lib ? flake-parts;

    polyfillOverTheRealBase =
      let
        polyfill = {
          key = "compat.polyfill";
          imports = [ entries.base ];
          overlay = _final: prev: {
            compatProbe = prev.compatProbe or (x: "probe-${prev.concatStringsSep "-" x}");
          };
        };
        r = compose { entries = [ entries.caisson-lib polyfill ]; };
      in
      r.lib.compatProbe [ "a" "b" ] == "probe-a-b" && r.lib ? caisson;

    baseReplacementLastWins =
      let
        stub = {
          key = "caisson.nixpkgs-lib";
          imports = [ ];
          overlay = _final: _prev: { stubMarker = true; };
        };
        r = compose { entries = [ entries.caisson-lib stub ]; };
      in
      r.lib.stubMarker or false
      && !(r.lib ? evalModules)
      && r.meta.order == [
        "caisson.nixpkgs-lib"
        "caisson.lib"
      ];

    keylessPatchSeesComposedWorld =
      let
        anon = {
          key = null;
          imports = [ ];
          overlay = _final: prev: { sawCaisson = prev.caisson ? mkLib; };
        };
        r = compose { entries = [ anon entries.caisson-lib ]; };
      in
      r.lib.sawCaisson;

    resolverFindsRealInput =
      resolve {
        name = "nixpkgs-lib";
        inputs = { inherit (inputs) nixpkgs-lib; };
      } == inputs.nixpkgs-lib;

    integrationNamespacesPresent =
      builtins.all (ns: composed.lib ? ${ns}) [
        "caisson-nixpkgs"
        "caisson-nixos"
        "caisson-home-manager"
        "caisson-colmena"
        "caisson-terranix"
        "caisson-system-manager"
      ];

    minimalNixosSystemEvaluates =
      let
        system = composed.lib.caisson-nixos.mkSystemMinimal {
          ecosystemSrc = inputs.nixpkgs;
          pkgSets.pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
          configModule =
            { lib, ... }:
            {
              options.nixpkgs.pkgs = lib.mkOption { type = lib.types.raw; };
            };
        };
      in
      system.config.nixpkgs.pkgs ? hello;

    sourceMetaProvenanceIsCompositional =
      let
        meta = composed.lib.caisson-home-manager.mkSourceMeta {
          profileName = "compat";
          homeManagerOutPath = "/probe-hm";
          nixpkgsOutPath = "/probe-np";
        };
      in
      meta.schemaVersion == 3
      && meta.homeManagerOutPath == "/probe-hm"
      && meta ? fingerprint;

    ecosystemSrcValidationThrows =
      let
        throws =
          expr: !(builtins.tryEval (builtins.deepSeq expr true)).success;
      in
      throws (composed.lib.caisson-colmena.mkColmenaHive { ecosystemSrc = { }; })
      && throws (composed.lib.caisson-terranix.mkTerranixConfiguration { ecosystemSrc = { }; })
      && throws (composed.lib.caisson-system-manager.mkSystemConfig { ecosystemSrc = { }; });

  };

  failures = builtins.filter (n: results.${n} != true) (builtins.attrNames results);

in
{
  inherit results failures;
  ok = failures == [ ];
  summary =
    if failures == [ ] then
      "ok: ${toString (builtins.length (builtins.attrNames results))} tests passed"
    else
      throw "caisson-compat tests failed: ${builtins.concatStringsSep ", " failures}";
}
