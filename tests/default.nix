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
      entries.nixpkgs
      entries.nixos
      entries.home-manager
      entries.colmena
      entries.terranix
      entries.system-manager
    ];
  };

  expectedCaissonNames = [
    "callConsumerFlake"
    "colmena"
    "eval-weight"
    "home-manager"
    "importApply"
    "mkFlake"
    "mkFlakeModule"
    "mkLib"
    "mkLibOverlay"
    "mkMemoizedDerivationRead"
    "mkModule"
    "modules"
    "nixos"
    "nixpkgs"
    "partitionExtraInputs"
    "system-manager"
    "terranix"
    "types"
  ];

  pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };

  minimalNixosBase =
    { ... }:
    {
      boot.loader.grub.enable = false;
      fileSystems."/" = {
        device = "none";
        fsType = "tmpfs";
      };
      system.stateVersion = "25.05";
    };

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
      builtins.all (ns: composed.lib.caisson ? ${ns}) [
        "nixpkgs"
        "nixos"
        "home-manager"
        "colmena"
        "terranix"
        "system-manager"
      ];

    minimalNixosSystemEvaluates =
      let
        system = composed.lib.caisson.nixos.mkSystemMinimal {
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
        meta = composed.lib.caisson.home-manager.mkSourceMeta {
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
      throws (composed.lib.caisson.colmena.mkColmenaHive { ecosystemSrc = { }; })
      && throws (composed.lib.caisson.terranix.mkTerranixConfiguration { ecosystemSrc = { }; })
      && throws (composed.lib.caisson.system-manager.mkSystemConfig { ecosystemSrc = { }; });

    homeConfigurationEvaluatesEndToEnd =
      let
        home = composed.lib.caisson.home-manager.mkHomeConfiguration {
          ecosystemSrc = inputs.home-manager;
          pkgSets.pkgs = pkgs;
          configModule =
            { ... }:
            {
              home.username = "probe";
              home.homeDirectory = "/home/probe";
              home.stateVersion = "25.05";
            };
        };
        meta = home.config.caisson-home-manager.sourceMeta;
      in
      builtins.isString home.activationPackage.drvPath
      && home.config.home.username == "probe"
      && meta.schemaVersion == 3
      && meta.homeManagerOutPath == builtins.toString inputs.home-manager
      && meta.nixpkgsOutPath == builtins.toString pkgs.path;

    nixosAdapterUpstreamModeEvaluatesEndToEnd =
      let
        system = composed.lib.caisson.nixos.mkSystem {
          ecosystemSrc = inputs.nixpkgs;
          pkgSets.pkgs = pkgs;
          configModule =
            { ... }:
            {
              imports = [
                minimalNixosBase
                (composed.lib.caisson.home-manager.mkNixosAdapter {
                  ecosystemSrc = inputs.home-manager;
                  hostName = "compat-probe";
                  users.probe.configModule =
                    { ... }:
                    {
                      home.stateVersion = "25.05";
                    };
                })
              ];
              users.users.probe = {
                isNormalUser = true;
                home = "/home/probe";
              };
            };
        };
        # fromJSON refuses context-carrying strings; the marker file
        # embeds store paths as ordinary references, which is correct.
        marker = builtins.fromJSON (
          builtins.unsafeDiscardStringContext
            system.config.environment.etc."caisson-home-manager/source.json".text
        );
      in
      builtins.isString system.config.system.build.toplevel.drvPath
      && system.config.home-manager.users.probe.home.stateVersion == "25.05"
      && marker.hostName == "compat-probe"
      && marker.schemaVersion == 3;

    nixosAdapterUserServiceModeEvaluatesEndToEnd =
      let
        system = composed.lib.caisson.nixos.mkSystem {
          ecosystemSrc = inputs.nixpkgs;
          pkgSets.pkgs = pkgs;
          configModule =
            { ... }:
            {
              imports = [
                minimalNixosBase
                (composed.lib.caisson.home-manager.mkNixosAdapter {
                  ecosystemSrc = inputs.home-manager;
                  activationMode = "user-service";
                  hostName = "compat-probe-homed";
                  users.probe.configModule =
                    { ... }:
                    {
                      home.username = "probe";
                      home.homeDirectory = "/home/probe";
                      home.stateVersion = "25.05";
                    };
                })
              ];
            };
        };
      in
      builtins.isString system.config.caisson-home-manager.hostedActivations.probe.drvPath
      && system.config.systemd.user.services.home-manager.unitConfig.ConditionUser == "probe"
      && builtins.isString system.config.system.build.toplevel.drvPath;

    colmenaHiveEvaluatesEndToEnd =
      let
        hive = composed.lib.caisson.colmena.mkColmenaHive {
          ecosystemSrc = inputs.colmena;
          meta.nixpkgs = pkgs;
          probe-node =
            { ... }:
            {
              imports = [ minimalNixosBase ];
              deployment.targetHost = "probe";
            };
        };
      in
      builtins.isString hive.nodes.probe-node.config.system.build.toplevel.drvPath;

    terranixConfigurationEvaluatesEndToEnd =
      let
        terraform = composed.lib.caisson.terranix.mkTerranixConfiguration {
          ecosystemSrc = inputs.terranix;
          system = "x86_64-linux";
          modules = [ { config.terraform.required_version = ">= 1.0"; } ];
        };
      in
      builtins.isString terraform.drvPath;

    systemManagerConfigEvaluatesEndToEnd =
      let
        config = composed.lib.caisson.system-manager.mkSystemConfig {
          ecosystemSrc = inputs.system-manager;
          modules = [
            {
              config = {
                nixpkgs.hostPlatform = "x86_64-linux";
                system-manager.allowAnyDistro = true;
              };
            }
          ];
        };
      in
      builtins.isString config.drvPath || builtins.isString (config.build.toplevel.drvPath or null);

    nixpkgsHelpersWorkOnRealPkgs =
      let
        cn = composed.lib.caisson.nixpkgs;
        scoped = cn.mkScope pkgs (callPackage: { probe = callPackage ({ hello }: hello) { }; });
        withPackages = pkgs.extend (
          (cn.mkPackagesOverlay (callPackage: { probe = callPackage ({ hello }: hello) { }; }))
            "compatScope"
        );
        withPolyfill = pkgs.extend (
          (cn.mkPolyfillOverlay (final: prev: { compatPolyfillProbe = prev.hello; })) "unused"
        );
      in
      scoped.probe.pname == "hello"
      && withPackages.compatScope.probe.pname == "hello"
      && withPolyfill.compatPolyfillProbe.pname == "hello";

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
