# Nix Support for DAPS (Document Autothing Platform Suite)

This repository contains a standalone, self-contained Nix flake for **DAPS**, designed to build, package, and run successfully using **unmodified upstream sources** (targeting standard branches/commits of `openSUSE/daps`, `openSUSE/suse-xsl`, and `openSUSE/geekodoc` on GitHub).

All required FHS path translations, build-time configurations, and sandboxing workarounds are handled dynamically at compile time via `postPatch`, `preConfigure`, and `installFlags` within the Nix flake derivation itself.

---

## Architectural Challenges & Solutions

Building unmodified upstream DAPS within the offline, read-only Nix build sandbox presented several unique architectural challenges. Below is a detailed map of how these were resolved.

### 1. Hardcoded FHS Toolchains in Makefiles
* **Challenge**: The clean upstream DAPS make template (`make/common_variables.mk`) hardcodes FHS paths to standard utilities like `xmlstarlet` (`/usr/bin/xmlstarlet`) and `bash` (`/bin/bash`). Because these paths do not exist in the Nix sandbox, `make` fails silently during `ROOTID` resolution, resulting in empty root elements and causing the build to throw fatal errors (`ROOTID "book.daps.user" does not exist!`).
* **Solution**: In the `postPatch` phase, we run `substituteInPlace` to replace these hardcoded `/usr/bin/` paths with standard PATH-resolved executable names (`xmlstarlet`, `xml`, `bash`).

### 2. Autoconf Install Directories Overrides
* **Challenge**: Upstream DAPS hardcodes autoconf placeholders like `@sysconfdir@` and `@datadir@` directly into installation path definitions inside `Makefile.am` and `Makefile.in` (e.g. `dapsconfdir = @sysconfdir@/daps` and `catalogdir = @sysconfdir@/xml/catalog.d`). This hardcoding causes `make install` to ignore standard Nix `sysconfdir` overrides, attempting to write files to host paths like `/etc/daps` and `/etc/xml/catalog.d`, which results in *Permission Denied* errors during `installPhase`.
* **Solution**: In the `postPatch` phase, we dynamically replace the FHS autoconf placeholders in both `Makefile.am` and `Makefile.in` with standard Makefile variable references (`$(sysconfdir)`, `$(datadir)`), allowing Nix to safely route these directories into the local package store path.

### 3. Bash Redirection Symlink Gotcha
* **Challenge**: In unmodified upstream DAPS, `etc/config` is a relative symbolic link pointing to `config.in`. In the `preConfigure` hook, the shell command `sed ... etc/config.in > etc/config` followed the symlink, opening `etc/config.in` for writing. Because both the input and output streams pointed to the same physical file, the shell truncated `etc/config.in` to 0 bytes before execution. This created an empty config, which resulted in stylesheet URIs resolving as `""` (empty strings) and crashing the build during manual compilation.
* **Solution**: We explicitly run `rm -f etc/config` inside `preConfigure` prior to generating the config, destroying the symlink and allowing `sed` to create `etc/config` as a pristine, independent, fully populated real file.

### 4. Dynamic Path Translation in `bin/daps.in`
* **Challenge**: Upstream DAPS has no awareness of the Nix store and relies on absolute system paths (like `/usr/share/xml/docbook/stylesheet/` and `/usr/share/xml/geekodoc/`) to locate stylesheets and schemas at runtime. Because these paths do not physically exist on NixOS or inside the sandbox, runtime validation and directory checks fail.
* **Solution**: We patch `bin/daps.in` dynamically during `postPatch` by injecting a path-rewriting shell block right after `MYPATH=${MYPATH%/}`. This block intercepts any incoming absolute `/usr/share/xml/` paths and translates them on-the-fly to their corresponding Nix store output directories (`${suse-xsl-stylesheets}` and `${geekodoc}`).

### 5. Build-Time Offline XML Catalog Resolution
* **Challenge**: Standard XML catalogs in nixpkgs (such as `docbook5` and `docbook_xml_dtd_45`) lack `SYSTEM` identifier mappings for schemas and DTDs, only mapping them via `URI` entries. Because DAPS queries catalogs via `SYSTEM` IDs, standard resolution fails offline, triggering network fallbacks to web URLs (like `http://www.docbook.org/xml/4.5/docbookx.dtd`) which fail inside the network-isolated Nix sandbox.
* **Solution**: We configure explicit, build-time `rewriteSystem` and `rewriteURI` redirect rules in the build-time catalog (`root_catalog`) pointing standard DocBook 4.5 DTD and DocBook 5.0/5.1 schemas directly to local store paths. We also wrap the `xmlcatalog` binary to filter out "No entry for" stdout lines and exit cleanly on URI matches. This allows DAPS to successfully compile and validate its own user manuals offline during `nix build`.

---

## Usage Instructions

### 1. Build the Package
To compile and package DAPS from clean upstream sources:
```bash
nix build .#daps --out-link ./result
```

### 2. Run the Developer Shell
To load the DAPS development environment with all required run-time dependencies (including Java/FOP, Jing, Schemas, etc.):
```bash
nix develop
```

### 3. Validate Documents
To test the newly built binary on local documents (such as SLES release notes), run the compiled binary inside the devShell:
```bash
nix develop -c bash -c "cd /home/lukas/work/git/release-notes-github && /home/lukas/git/daps-flake/result/bin/daps -d DC-releasenotes_sles_16.0 validate"
```
