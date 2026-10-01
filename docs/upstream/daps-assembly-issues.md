# Upstream DAPS issues found while building doc-modular

Found while building DocBook 5.2 assemblies from `doc-modular` with DAPS
4.0.beta15/16. The packaging-side problems are fixed in this flake (see
`NIX.md`, sections 9–11). What remains belongs to `openSUSE/daps`.

## 1. `assemble.xsl` depends on unreleased DocBook XSL

`daps-xslt/assembly/assemble.xsl` imports
`http://docbook.sourceforge.net/release/xsl-ns/current/assembly/assemble.xsl`
and applies templates in `mode="ref.content.nodes"`. Upstream DocBook XSL
defines that mode only on `docbook/xslt10-stylesheets` master. No release
has it, including 1.79.2, the latest one.

With a 1.79.2 install, XSLT's built-in rules strip every element. Every
assembly then fails with:

```text
ERROR: @href = '../concepts/....xml' has no content or is unresolved.
```

Any distribution that packages the 1.79.2 release hits this. This flake
overlays `assembly/assemble.xsl` and `effectivity.xsl` from master commit
`efd6265`.

**Proposed fix:** define the `ref.content.nodes` templates in DAPS's own
`assemble.xsl`, so it works on top of 1.79.2. At minimum, document that
DAPS needs a post-1.79.2 snapshot.

## 2. No command-line override for `ASSEMBLY_RNG_URI`

`--schema` sets `DOCBOOK5_RNG_URI`, and `recover_cmdl_values` in
`bin/daps.in` restores it after config files are read. There is no
counterpart for `ASSEMBLY_RNG_URI`, so it can only be set in a config file.
`--param` does not help: it passes XSLT parameters, not DAPS config keys.

**Proposed fix:** add an option such as `--assembly-schema` and restore its
value in `recover_cmdl_values`.

## 3. Wrong key in the `ASSEMBLY_RNG_URI` example (`etc/config.in`)

The commented examples under `## Key: ASSEMBLY_RNG_URI` use the wrong key:

```bash
#DOCBOOK5_RNG_URI="http://docbook.org/xml/5.1/rng/assembly.rng"
#DOCBOOK5_RNG_URI="http://docbook.org/xml/5.2/rng/assembly.rng"
```

They should read `ASSEMBLY_RNG_URI=`.

## 4. `fop-daps.xml` hardcodes font paths

`etc/fop/fop-daps.xml` loads the Poppins family (a workaround for
FOP-3045) and the Noto CJK fonts by absolute path, all under
`/usr/share/fonts/truetype/`. It also adds that directory to the font
search path.

Distributions that store fonts somewhere else get a
`FileNotFoundException` as soon as a document uses one of these fonts, for
example an SVG that uses Poppins. Debian is one case: it uses
per-family subdirectories under `/usr/share/fonts/truetype/`.

**Proposed fix:** have `configure` substitute a font directory, or
document that the file must be adapted for each distribution.
