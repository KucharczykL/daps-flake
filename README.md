# DAPS Nix Flake

This repository provides a standalone, fully self-contained Nix flake for **DAPS (Document Autothing Platform Suite)**. 

It is designed to cleanly build, package, and install DAPS from unmodified upstream sources within Nix's isolated, offline build sandbox, while resolving standard stylesheet and schema path dependencies dynamically at compile time and runtime.

---

## Usage

### 1. Using the Devshell Only

You can load and enter the DAPS development environment—which includes all runtime dependencies such as standard DocBook schemas/DTDs, Java/FOP, Jing/Trang, and Asciidoctor—without installing DAPS permanently on your system.

#### Locally (cloned repository)
```bash
nix develop
```

#### Directly from Remote Git
```bash
nix develop git+https://git.kucharczyk.xyz/lukas/daps-flake
```

Once inside the shell, you will have access to `daps`, `xmlcatalog`, `xsltproc`, `xmllint`, `fop`, and all required tools pre-configured with a dynamically populated XML catalog pointing to the store-installed schemas.

---

### 2. Adding to a Flake-using Nix Configuration

To integrate the DAPS package into your own system configuration or a home-manager setup using Nix flakes, add this repository to your flake inputs:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    daps-flake = {
      url = "git+https://git.kucharczyk.xyz/lukas/daps-flake"; # Replace with actual repository URL
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, daps-flake, ... }:
    let
      system = "x86_64-linux"; # Adjust to your target system
      pkgs = import nixpkgs { inherit system; };
    in
    {
      # 1. Reference the package directly
      environment.systemPackages = [
        daps-flake.packages.${system}.daps
      ];

      # 2. Or apply it via an overlay in nixpkgs
      nixpkgs.overlays = [
        (final: prev: {
          daps = daps-flake.packages.${system}.daps;
        })
      ];
    };
}
```

---

## Package Targets

* `packages.<system>.daps`: The compiled DAPS authoring and publishing tool.
* `packages.<system>.geekodoc`: Custom SUSE styling schema compiled into XML RelaxNG.
* `packages.<system>.suse-xsl-stylesheets`: Custom SUSE XSL stylesheet transformations.
* `devShells.<system>.default`: Comprehensive documentation authoring shell environment.

For deep-dive technical insights regarding the sandbox solutions and design patterns employed to support unmodified upstream code compilation, please see [NIX.md](./NIX.md).
