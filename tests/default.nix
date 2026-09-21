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

  # caisson's integrations as the keyed entries a registry holds: the
  # overlays caisson exports, registered by mkLib and read back from
  # the manifest, each keyed by its registry name and importing the
  # published nixpkgs-lib entry. The suite composes them with
  # caisson-core's `compose` directly, the way mkLib does, so the
  # composition guarantees are probed on the real entries.
  registered =
    (inputs.caisson.lib.caisson-core.mkLib {
      inputs = { };
      defaultEcosystemSrc.nixpkgs-lib = inputs.nixpkgs-lib;
      libOverlays = _mkLibOverlay: inputs.caisson.libOverlays;
    }).caisson-core.libManifest.libOverlays;

  composed = compose {
    entries = [
      registered.caisson-core
      registered.flake-parts
      registered.tooling
      registered.nixpkgs
      registered.nixos
      registered.nixos-minimal
      registered.home-manager
      registered.colmena
      registered.terranix
      registered.system-manager
      registered.structural
    ];
  };

  # The integrations plus the pkgs-dependent tooling live under
  # `caisson`; the machinery lives under `caisson-core`.
  expectedCaissonNames = [
    "colmena"
    "eval-weight"
    "flake-parts"
    "home-manager"
    "mkMemoizedDerivationRead"
    "nixos"
    "nixos-minimal"
    "nixpkgs"
    "structural"
    "system-manager"
    "terranix"
  ];

  expectedCoreNames = [
    "callConsumerFlake"
    "callFlake"
    "classes"
    "compose"
    "configs"
    "evalManifest"
    "importApply"
    "libManifest"
    "mkLib"
    "mkLibOverlay"
    "mkLibOverlays"
    "mkModule"
    "mkModules"
    "mkNixpkgsLibEntry"
    "modules"
    "partitionExtraInputs"
    "pkgsManifest"
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

  # The colmena probes compose with declared ecosystems: a node's
  # `ecosystemSrc` is colmena's, and nixpkgs resolves from the
  # declaration, as it does in a consumer flake.
  hiveLib = inputs.caisson.lib.caisson-core.mkLib {
    inputs = { };
    projects = {
      caisson = inputs.caisson;
    };
    defaultEcosystemSrc = {
      inherit (inputs) nixpkgs colmena;
    };
  };

  results = {

    composesTheCaissonLibrary =
      builtins.attrNames composed.lib.caisson == expectedCaissonNames
      && builtins.attrNames composed.lib.caisson-core == expectedCoreNames
      &&
        composed.meta.order == [
          "caisson-core"
          "nixpkgs-lib"
          "flake-parts"
          "tooling"
          "nixpkgs"
          "nixos"
          "nixos-minimal"
          "home-manager"
          "colmena"
          "terranix"
          "system-manager"
          "structural"
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
          imports = [ registered.nixpkgs-lib ];
          overlay = _final: prev: {
            compatProbe = prev.compatProbe or (x: "probe-${prev.concatStringsSep "-" x}");
          };
        };
        r = compose {
          entries = [
            registered.caisson-core
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
          key = "nixpkgs-lib";
          imports = [ ];
          overlay = _final: _prev: { stubMarker = true; };
        };
        r = compose {
          entries = [
            registered.caisson-core
            registered.flake-parts
            stub
          ];
        };
      in
      r.lib.stubMarker or false
      && !(r.lib ? evalModules)
      &&
        r.meta.order == [
          "caisson-core"
          "nixpkgs-lib"
          "flake-parts"
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
            registered.caisson-core
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
      "nixos-minimal"
      "home-manager"
      "colmena"
      "terranix"
      "system-manager"
    ];

    minimalNixosSystemEvaluates =
      let
        system = composed.lib.caisson.nixos-minimal.mkConfiguration {
          ecosystemSrc = inputs.nixpkgs;
          pkgSets.pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
          # The minimal evaluator carries no nixpkgs module, so the
          # package set arrives as the `pkgs` module argument.
          configModule =
            { lib, pkgs, ... }:
            {
              options.probePkgs = lib.mkOption { type = lib.types.raw; };
              config.probePkgs = pkgs;
            };
        };
      in
      system.config.probePkgs ? hello;

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
      throws (composed.lib.caisson.colmena.mkConfiguration {
        ecosystemSrc = { };
        configModule = { };
      })
      && throws (composed.lib.caisson.terranix.mkConfiguration {
        ecosystemSrc = { };
        configModule = { };
      })
      && throws (composed.lib.caisson.system-manager.mkConfiguration {
        ecosystemSrc = { };
        configModule = { };
      });

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
    # A node is checked when it is read, so the probe forces one.
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
        }).nodes.plain
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
        }).nodes.bad;

    # Node names colmena's flat hive reserved (meta, defaults, network)
    # are ordinary names here. A node is an evaluated NixOS
    # configuration, so its module takes its host name from its own
    # definitions rather than from a `name` argument.
    colmenaNodesAreNamedFreely =
      let
        hive = hiveLib.caisson.colmena.mkConfiguration {
          configModule =
            { mkNixosConfiguration, ... }:
            {
              nodes = builtins.mapAttrs (
                hostName: peer:
                mkNixosConfiguration {
                  pkgSets.pkgs = pkgs;
                  configModule =
                    { ... }:
                    {
                      imports = [ minimalNixosBase ];
                      networking.hostName = hostName;
                      deployment.targetHost = peer;
                      deployment.tags = [ peer ];
                    };
                }
              ) {
                meta = "defaults";
                defaults = "network";
                network = "meta";
              };
            };
        };
      in
      builtins.attrNames hive.deploymentConfig == [ "defaults" "meta" "network" ]
      && hive.deploymentConfig.meta.targetHost == "defaults"
      && hive.nodes.network.config.networking.hostName == "network"
      && builtins.attrNames (hive.evalSelected [ "meta" ]) == [ "meta" ];

    # Names colmena's `--on` filter cannot express are refused at hive
    # evaluation.
    colmenaRefusesUnaddressableNames =
      let
        refused =
          nodeName:
          !(builtins.tryEval
            (hiveLib.caisson.colmena.mkConfiguration {
              configModule =
                { mkNixosConfiguration, ... }:
                {
                  nodes.${nodeName} = mkNixosConfiguration {
                    pkgSets.pkgs = pkgs;
                    configModule = minimalNixosBase;
                  };
                };
            }).nodes.${nodeName}
          ).success;
      in
      refused "a,b" && refused "@tagged" && refused "";

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
      && refused (composed.lib.caisson.nixos-minimal.mkConfiguration {
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
        minimal = composed.lib.caisson.nixos-minimal.mkConfigurationWithEcosystemArgs {
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
          defaultEcosystemSrc.nixpkgs-lib = inputs.nixpkgs-lib;
          libOverlays = _mkLibOverlay: {
            nixos = inputs.caisson.libOverlays.nixos;
            nixos-minimal = inputs.caisson.libOverlays.nixos-minimal;
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
        system = contributingLib.caisson.nixos-minimal.mkConfiguration {
          ecosystemSrc = inputs.nixpkgs;
          pkgSets.pkgs = pkgs;
          configModule =
            { lib, ... }:
            {
              options.nixpkgs.pkgs = lib.mkOption { type = lib.types.raw; };
            };
          # Selected by name: the default default is the entries named
          # `default`, and this one is not.
          moduleImports = modules: [ modules.compat-probe ];
        };
      in
      system.config.compatProbe;

    manifestTravelsWithMkLibCompositions =
      let
        composedWithMkLib = inputs.caisson.lib.caisson-core.mkLib {
          inputs = { };
          defaultEcosystemSrc.nixpkgs-lib = inputs.nixpkgs-lib;
          libOverlays = _mkLibOverlay: {
            flake-parts = inputs.caisson.libOverlays.flake-parts;
          };
        };
        manifest = composedWithMkLib.caisson-core.libManifest;
      in
      builtins.attrNames manifest == [
        "configs"
        "defaultEcosystemSrc"
        "inputs"
        "libOverlays"
        "modules"
        "projects"
        "systems"
      ]
      && manifest.systems == null
      && composedWithMkLib.caisson-core.pkgsManifest == null
      && composedWithMkLib.caisson-core.evalManifest == null
      && builtins.attrNames manifest.libOverlays == [
        "caisson-core"
        "flake-parts"
        "nixpkgs-lib"
      ]
      && composedWithMkLib.caisson.flake-parts ? mkConfiguration;

    # A tree declares its platforms once, on mkLib; the flake-parts
    # integration reads them from the manifest, so a flake module that
    # names no `systems` still enumerates them.
    systemsDeclaredOnMkLibReachFlakeParts =
      let
        composedWithSystems = inputs.caisson.lib.caisson-core.mkLib {
          inputs = { };
          defaultEcosystemSrc.nixpkgs-lib = inputs.nixpkgs-lib;
          defaultEcosystemSrc.flake-parts = inputs.flake-parts;
          systems = [
            "x86_64-linux"
            "aarch64-linux"
          ];
          libOverlays = _mkLibOverlay: {
            flake-parts = inputs.caisson.libOverlays.flake-parts;
          };
        };
        outputs = composedWithSystems.caisson.flake-parts.mkConfiguration {
          configModule = {
            perSystem =
              { system, ... }:
              {
                legacyPackages.probeSystem = system;
              };
          };
        };
      in
      builtins.attrNames outputs.legacyPackages == [
        "aarch64-linux"
        "x86_64-linux"
      ]
      && outputs.legacyPackages.x86_64-linux.probeSystem == "x86_64-linux";

    projectConsumptionComposesCaissonWhole =
      let
        composedFromProject = inputs.caisson.lib.caisson-core.mkLib {
          inputs = { };
          defaultEcosystemSrc.nixpkgs-lib = inputs.nixpkgs-lib;
          projects = {
            caisson = inputs.caisson;
          };
        };
        system = composedFromProject.caisson.nixos-minimal.mkConfiguration {
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
          defaultEcosystemSrc.nixpkgs = inputs.nixpkgs;
          libOverlays = _mkLibOverlay: {
            nixos = inputs.caisson.libOverlays.nixos;
            nixos-minimal = inputs.caisson.libOverlays.nixos-minimal;
          };
        };
        system = composedWithDeclaration.caisson.nixos-minimal.mkConfiguration {
          pkgSets.pkgs = pkgs;
          configModule =
            { lib, pkgs, ... }:
            {
              options.probePkgs = lib.mkOption { type = lib.types.raw; };
              config.probePkgs = pkgs;
            };
        };
      in
      system.config.probePkgs ? hello;

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

    # The structural integration: a top over the empty class returns
    # the selected registries with the manifest beside them, and the
    # same selectors under flake-parts export the same registries.
    structuralTopMatchesFlakeParts =
      let
        composedWithBoth = inputs.caisson.lib.caisson-core.mkLib {
          inputs = { };
          defaultEcosystemSrc.nixpkgs-lib = inputs.nixpkgs-lib;
          defaultEcosystemSrc.flake-parts = inputs.flake-parts;
          systems = [ "x86_64-linux" ];
          libOverlays = _mkLibOverlay: {
            structural = inputs.caisson.libOverlays.structural;
            flake-parts = inputs.caisson.libOverlays.flake-parts;
          };
        };
        selectors = {
          caisson.libOverlays.exported = overlays: { inherit (overlays) structural; };
        };
        top = composedWithBoth.caisson.structural.mkTopConfiguration {
          configModule = selectors;
        };
        flake = composedWithBoth.caisson.flake-parts.mkConfiguration {
          configModule = selectors;
        };
      in
      builtins.attrNames top.libOverlays == [ "structural" ]
      && builtins.attrNames flake.libOverlays == [ "structural" ]
      && top.caisson.manifest ? modules
      && top.lib == { };

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
