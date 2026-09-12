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
      entries.flake-parts
      entries.tooling
      entries.nixpkgs
      entries.nixos
      entries.home-manager
      entries.colmena
      entries.terranix
      entries.system-manager
    ];
  };

  # The seven integrations plus the pkgs-dependent tooling live under
  # `caisson`; the machinery lives under `caisson-core`.
  expectedCaissonNames = [
    "colmena"
    "eval-weight"
    "flake-parts"
    "home-manager"
    "mkMemoizedDerivationRead"
    "nixos"
    "nixpkgs"
    "system-manager"
    "terranix"
  ];

  expectedCoreNames = [
    "callConsumerFlake"
    "compose"
    "importApply"
    "mkLib"
    "mkLibOverlay"
    "mkModule"
    "modules"
    "partitionExtraInputs"
    "resolve"
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
      && builtins.attrNames composed.lib.caisson-core == expectedCoreNames
      &&
        composed.meta.order == [
          "caisson.nixpkgs-lib"
          "caisson.lib"
          "caisson.flake-parts"
          "caisson.tooling"
          "caisson.nixpkgs"
          "caisson.nixos"
          "caisson.home-manager"
          "caisson.colmena"
          "caisson.terranix"
          "caisson.system-manager"
        ];

    baseLibraryBehaves =
      composed.lib.concatStringsSep "," [
        "a"
        "b"
      ] == "a,b"
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
        r = compose {
          entries = [
            entries.caisson-lib
            polyfill
          ];
        };
      in
      r.lib.compatProbe [
        "a"
        "b"
      ] == "probe-a-b"
      && r.lib ? caisson-core;

    baseReplacementLastWins =
      let
        stub = {
          key = "caisson.nixpkgs-lib";
          imports = [ ];
          overlay = _final: _prev: { stubMarker = true; };
        };
        r = compose {
          entries = [
            entries.caisson-lib
            stub
          ];
        };
      in
      r.lib.stubMarker or false
      && !(r.lib ? evalModules)
      &&
        r.meta.order == [
          "caisson.nixpkgs-lib"
          "caisson.lib"
        ];

    keylessPatchSeesComposedWorld =
      let
        anon = {
          key = null;
          imports = [ ];
          overlay = _final: prev: { sawCaisson = prev.caisson-core ? mkLib; };
        };
        r = compose {
          entries = [
            anon
            entries.caisson-lib
          ];
        };
      in
      r.lib.sawCaisson;

    resolverFindsRealInput =
      resolve {
        name = "nixpkgs-lib";
        inputs = { inherit (inputs) nixpkgs-lib; };
      } == inputs.nixpkgs-lib;

    integrationNamespacesPresent = builtins.all (ns: composed.lib.caisson ? ${ns}) [
      "nixpkgs"
      "nixos"
      "home-manager"
      "colmena"
      "terranix"
      "system-manager"
    ];

    minimalNixosSystemEvaluates =
      let
        system = composed.lib.caisson.nixos.mkConfigurationMinimal {
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
      meta.schemaVersion == 3 && meta.homeManagerOutPath == "/probe-hm" && meta ? fingerprint;

    ecosystemSrcValidationThrows =
      let
        throws = expr: !(builtins.tryEval (builtins.deepSeq expr true)).success;
      in
      throws (composed.lib.caisson.colmena.mkConfiguration { ecosystemSrc = { }; })
      && throws (composed.lib.caisson.terranix.mkConfiguration { ecosystemSrc = { }; })
      && throws (composed.lib.caisson.system-manager.mkConfiguration { ecosystemSrc = { }; });

    homeConfigurationEvaluatesEndToEnd =
      let
        home = composed.lib.caisson.home-manager.mkConfiguration {
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
        system = composed.lib.caisson.nixos.mkConfiguration {
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
        system = composed.lib.caisson.nixos.mkConfiguration {
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

    # The colmena probes compose with declared ecosystems: a node's
    # `ecosystemSrc` is colmena's, and nixpkgs resolves from the
    # declaration, as it does in a consumer flake.
    hiveLib = inputs.caisson.lib.caisson-core.mkLib {
      inputs = { };
      projects = {
        caisson = inputs.caisson;
      };
      ecosystems = {
        inherit (inputs) nixpkgs colmena;
      };
    };

    colmenaHiveEvaluatesEndToEnd =
      let
        hive = hiveLib.caisson.colmena.mkConfiguration {
          pkgSets.pkgs = pkgs;
          configModule =
            { mkNixosConfiguration, ... }:
            {
              meta.allowApplyAll = false;
              nodes.probe-node = mkNixosConfiguration {
                pkgSets.pkgs = pkgs;
                configModule = {
                  imports = [ minimalNixosBase ];
                  networking.hostName = "probe";
                  deployment.targetHost = "probe";
                };
              };
            };
        };
        node = hive.nodes.probe-node;
      in
      hive.__schema == (inputs.colmena.lib.makeHive { }).__schema
      && hive.toplevel.probe-node.drvPath == node.config.system.build.toplevel.drvPath
      && hive.deploymentConfig.probe-node.targetHost == "probe"
      && hive.metaConfig.allowApplyAll == false
      && builtins.attrNames (hive.evalSelectedDrvPaths [ "probe-node" ]) == [ "probe-node" ];

    # A node is the NixOS configuration nixos.mkConfiguration builds from
    # the same module, with colmena's deployment options declared: the
    # extra modules leave the system untouched. The node's ecosystem
    # source is nixpkgs, explicit here.
    colmenaNodesAreNixosConfigurations =
      let
        hostModule = {
          imports = [ minimalNixosBase ];
          networking.hostName = "probe";
        };
        hive = hiveLib.caisson.colmena.mkConfiguration {
          configModule =
            { mkNixosConfiguration, ... }:
            {
              nodes.probe = mkNixosConfiguration {
                ecosystemSrc = inputs.nixpkgs;
                pkgSets.pkgs = pkgs;
                configModule = hostModule;
              };
            };
        };
        node = hive.nodes.probe;
        system = hiveLib.caisson.nixos.mkConfiguration {
          ecosystemSrc = inputs.nixpkgs;
          pkgSets.pkgs = pkgs;
          configModule = hostModule;
        };
      in
      node.config.system.build.toplevel.drvPath == system.config.system.build.toplevel.drvPath
      && node.options ? deployment
      && node.pkgs.hello.drvPath == pkgs.hello.drvPath;

    # A hive refuses a node that is not a colmena node, and the node
    # constructor refuses `deployment` as an argument.
    colmenaRefusesPlainNixosNodes =
      let
        refused = f: !(builtins.tryEval f).success;
      in
      refused
        (hiveLib.caisson.colmena.mkConfiguration {
          configModule.nodes.plain = hiveLib.caisson.nixos.mkConfiguration {
            pkgSets.pkgs = pkgs;
            configModule = minimalNixosBase;
          };
        }).toplevel
      && refused
        (hiveLib.caisson.colmena.mkConfiguration {
          configModule =
            { mkNixosConfiguration, ... }:
            {
              nodes.bad = mkNixosConfiguration {
                pkgSets.pkgs = pkgs;
                configModule = { };
                deployment.targetHost = "x";
              };
            };
        }).toplevel;

    terranixConfigurationEvaluatesEndToEnd =
      let
        terraform = composed.lib.caisson.terranix.mkConfiguration {
          ecosystemSrc = inputs.terranix;
          pkgSets.pkgs = pkgs;
          configModule = {
            config.terraform.required_version = ">= 1.0";
          };
        };
      in
      builtins.isString terraform.drvPath;

    systemManagerConfigEvaluatesEndToEnd =
      let
        config = composed.lib.caisson.system-manager.mkConfiguration {
          ecosystemSrc = inputs.system-manager;
          pkgSets.pkgs = pkgs;
          configModule = {
            config.system-manager.allowAnyDistro = true;
          };
        };
      in
      builtins.isString config.drvPath || builtins.isString (config.build.toplevel.drvPath or null);

    # The closed entry points refuse evaluator arguments; the
    # ecosystem-args twins take them in `ecosystemArgs`, applied last.
    evaluatorArgumentsAreRefused =
      let
        refused = f: !(builtins.tryEval f).success;
      in
      refused (composed.lib.caisson.nixos.mkConfiguration {
        ecosystemSrc = inputs.nixpkgs;
        pkgSets.pkgs = pkgs;
        configModule = { };
        pkgs = pkgs;
      })
      && refused (composed.lib.caisson.nixos.mkConfigurationMinimal {
        ecosystemSrc = inputs.nixpkgs;
        pkgSets.pkgs = pkgs;
        configModule = { };
        extraModules = [ ];
      })
      && refused (composed.lib.caisson.home-manager.mkConfiguration {
        ecosystemSrc = inputs.home-manager;
        pkgSets.pkgs = pkgs;
        configModule = { };
        extraSpecialArgs = { };
      })
      && refused (composed.lib.caisson.colmena.mkConfiguration {
        ecosystemSrc = inputs.colmena;
        configModule = { };
        nodes = { };
      })

      && refused (composed.lib.caisson.terranix.mkConfiguration {
        ecosystemSrc = inputs.terranix;
        pkgSets.pkgs = pkgs;
        configModule = { };
        extraArgs = { };
      })
      && refused (composed.lib.caisson.system-manager.mkConfiguration {
        ecosystemSrc = inputs.system-manager;
        pkgSets.pkgs = pkgs;
        configModule = { };
        overlays = [ ];
      })
      && refused (composed.lib.caisson.flake-parts.mkConfiguration {
        configModule = { };
        moduleLocation = "x";
      });

    ecosystemArgsTwinsReachTheEvaluator =
      let
        minimal = composed.lib.caisson.nixos.mkConfigurationMinimalWithEcosystemArgs {
          ecosystemSrc = inputs.nixpkgs;
          pkgSets.pkgs = pkgs;
          configModule =
            { lib, ... }:
            {
              options.probe = lib.mkOption { type = lib.types.raw; };
              config.probe = "minimal";
            };
          ecosystemArgs.prefix = [ "probe-prefix" ];
        };
        terraform = composed.lib.caisson.terranix.mkConfigurationWithEcosystemArgs {
          ecosystemSrc = inputs.terranix;
          configModule = {
            config.terraform.required_version = ">= 1.0";
          };
          ecosystemArgs = {
            inherit pkgs;
            strip_nulls = false;
          };
        };
        home = composed.lib.caisson.home-manager.mkConfigurationWithEcosystemArgs {
          ecosystemSrc = inputs.home-manager;
          pkgSets.pkgs = pkgs;
          configModule = {
            home.username = "probe";
            home.homeDirectory = "/home/probe";
            home.stateVersion = "24.05";
          };
          ecosystemArgs.check = false;
        };
      in
      minimal.config.probe == "minimal"
      && builtins.isString terraform.drvPath
      && builtins.isString home.activationPackage.drvPath;

    overlayBorneModulesReachAdapters =
      let
        contributingLib = inputs.caisson.lib.caisson-core.mkLib {
          inputs = { };
          libOverlays = _mkLibOverlay: {
            nixos = inputs.caisson.libOverlays.nixos;
            contrib = inputs.caisson.lib.caisson-core.mkLibOverlay (
              {
                mkModule,
                contributeModules,
                ...
              }:
              {
                imports = [ ];
                overlay =
                  _final: prev:
                  contributeModules prev {
                    nixos.compat-probe = mkModule "nixos" (
                      { ... }:
                      { lib, ... }:
                      {
                        options.compatProbe = lib.mkOption {
                          type = lib.types.bool;
                          default = true;
                        };
                      }
                    );
                  };
              }
            );
          };
        };
        system = contributingLib.caisson.nixos.mkConfigurationMinimal {
          ecosystemSrc = inputs.nixpkgs;
          pkgSets.pkgs = pkgs;
          configModule =
            { lib, ... }:
            {
              options.nixpkgs.pkgs = lib.mkOption { type = lib.types.raw; };
            };
        };
      in
      system.config.compatProbe;

    manifestTravelsWithMkLibCompositions =
      let
        composedWithMkLib = inputs.caisson.lib.caisson-core.mkLib {
          inputs = { };
          libOverlays = _mkLibOverlay: {
            flake-parts = inputs.caisson.libOverlays.flake-parts;
          };
        };
        manifest = composedWithMkLib.caisson-core.manifest;
      in
      builtins.attrNames manifest == [
        "ecosystems"
        "inputs"
        "libOverlays"
        "modules"
        "projects"
      ]
      && builtins.attrNames manifest.libOverlays == [ "flake-parts" ]
      && composedWithMkLib.caisson.flake-parts ? mkConfiguration;

    projectConsumptionComposesCaissonWhole =
      let
        composedFromProject = inputs.caisson.lib.caisson-core.mkLib {
          inputs = { };
          projects = {
            caisson = inputs.caisson;
          };
        };
        system = composedFromProject.caisson.nixos.mkConfigurationMinimal {
          ecosystemSrc = inputs.nixpkgs;
          pkgSets.pkgs = pkgs;
          configModule =
            { pkgs, lib, ... }:
            {
              options.probe = lib.mkOption { type = lib.types.raw; };
              config.probe = pkgs ? hello;
            };
        };
      in
      composedFromProject.caisson.flake-parts ? mkConfiguration
      && composedFromProject.caisson-core.modules.flake ? "caisson/default"
      && system.config.probe;

    declaredEcosystemServesAdapters =
      let
        composedWithDeclaration = inputs.caisson.lib.caisson-core.mkLib {
          inputs = { };
          ecosystems.nixpkgs = inputs.nixpkgs;
          libOverlays = _mkLibOverlay: {
            nixos = inputs.caisson.libOverlays.nixos;
          };
        };
        system = composedWithDeclaration.caisson.nixos.mkConfigurationMinimal {
          pkgSets.pkgs = pkgs;
          configModule =
            { lib, ... }:
            {
              options.nixpkgs.pkgs = lib.mkOption { type = lib.types.raw; };
            };
        };
      in
      system.config.nixpkgs.pkgs ? hello;

    nixpkgsHelpersWorkOnRealPkgs =
      let
        cn = composed.lib.caisson.nixpkgs;
        scoped = cn.mkScope pkgs (callPackage: {
          probe = callPackage ({ hello }: hello) { };
        });
        withPackages = pkgs.extend (
          (cn.mkPackagesOverlay (callPackage: {
            probe = callPackage ({ hello }: hello) { };
          }))
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
