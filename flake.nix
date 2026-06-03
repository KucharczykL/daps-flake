{
  description = "Document Autothing Platform Suite (DAPS) - A tool for publishing DocBook XML and AsciiDoc";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    daps-src = {
      url = "github:openSUSE/daps/5d56233294fea56df93869c19956a3422eaef848";
      flake = false;
    };
    suse-xsl = {
      url = "github:openSUSE/suse-xsl";
      flake = false;
    };
    geekodoc-src = {
      url = "github:openSUSE/geekodoc";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, daps-src, suse-xsl, geekodoc-src }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          lxml
        ]);

        suse-xsl-stylesheets = pkgs.stdenv.mkDerivation {
          pname = "suse-xsl-stylesheets";
          version = "2.95.36";
          src = suse-xsl;
          nativeBuildInputs = [ pkgs.sassc pkgs.libxml2 pkgs.perl pkgs.gnutar ];
          buildInputs = [ pkgs.bash ];
          
          postPatch = ''
            patchShebangs bin/
            substituteInPlace Makefile \
              --replace 'SHELL         := /bin/bash' 'SHELL         := ${pkgs.bash}/bin/bash'
          '';

          makeFlags = [
            "SHELL=${pkgs.bash}/bin/bash"
          ];

          installPhase = ''
            mkdir -p $out/share
            make install DESTDIR=$out PREFIX=/share SHELL=${pkgs.bash}/bin/bash XSL_INST_PATH=$out/share/xml/docbook/stylesheet/
          '';
        };

        geekodoc = pkgs.stdenv.mkDerivation {
          pname = "geekodoc";
          version = "2.0";
          src = geekodoc-src;
          nativeBuildInputs = [
            pkgs.util-linux
            pkgs.jing-trang
            pkgs.python3Packages.rnginline
            pkgs.libxml2
            pkgs.bash
          ];
          buildInputs = [ pkgs.bash ];

          postPatch = ''
            patchShebangs build.sh tests/run-tests.sh
            substituteInPlace build.sh \
              --replace 'source /etc/os-release || exit_on_error "File /etc/os-release not found"' 'echo "Bypassing os-release check"'
          '';

          buildPhase = ''
            ./build.sh
          '';

          installPhase = ''
            mkdir -p $out/share/xml/geekodoc
            cp -r build/geekodoc/rng $out/share/xml/geekodoc/
            mkdir -p $out/etc/xml/catalog.d
            sed 's_uri="../geekodoc/_uri="_g' catalog.d/geekodoc.xml > $out/etc/xml/catalog.d/geekodoc.xml
            # Update the xml:base in catalog.d/geekodoc.xml
            substituteInPlace $out/etc/xml/catalog.d/geekodoc.xml \
              --replace '<group id="geekodoc">' '<group id="geekodoc" xml:base="file://'"$out"'/share/xml/geekodoc/rng/">'
          '';
        };

        makeDaps = {
          withPdf ? true,
          withEpub ? true,
          withGraphics ? true,
          withAsciidoc ? true,
          withDiagrams ? true,
        }@args:
        let
          runtimeDeps = with pkgs; [
            bash
            coreutils
            gnused
            gnugrep
            gnumake
            libxml2
            libxslt
            jing-trang
            poppler-utils
            imagemagick
            optipng
            xmlstarlet
            w3m
            zip
            util-linux
            which
            pythonEnv
          ]
          ++ pkgs.lib.optional withAsciidoc asciidoctor
          ++ pkgs.lib.optional withPdf fop
          ++ pkgs.lib.optional withDiagrams ditaa
          ++ pkgs.lib.optional withEpub epubcheck
          ++ pkgs.lib.optional withGraphics inkscape;
        in
        pkgs.stdenv.mkDerivation rec {
          pname = "daps";
          version = "4.0.beta1";

          src = daps-src;

          nativeBuildInputs = with pkgs; [
            autoconf
            automake
            libtool
            makeWrapper
            pkg-config
          ] ++ runtimeDeps;

          buildInputs = with pkgs; [
            pythonEnv
            libxml2
            libxslt
            docbook_xml_dtd_412
            docbook_xml_dtd_42
            docbook_xml_dtd_43
            docbook_xml_dtd_44
            docbook_xml_dtd_45
            docbook_xsl
            docbook_xsl_ns
            docbook5
            suse-xsl-stylesheets
            geekodoc
          ] ++ runtimeDeps;

          postPatch = ''
            # Use our synthetic catalog as the main XML catalog file
            substituteInPlace etc/config.in \
              --replace 'XML_MAIN_CATALOG="/etc/xml/catalog"' 'XML_MAIN_CATALOG="@root_catalog@"'

            # Allow configure to accept root_catalog from environment
            substituteInPlace configure.ac \
              --replace 'root_catalog="/etc/xml/catalog"' 'root_catalog="''${root_catalog:-/etc/xml/catalog}"'

            # Remove hardcoded FHS paths to make, xsltproc, and xmlcatalog
            substituteInPlace lib/daps_functions \
              --replace 'MAKE_BIN="/usr/bin/make"' 'MAKE_BIN="make"' \
              --replace 'MAKE_BIN="/usr/bin/remake"' 'MAKE_BIN="remake"'
            substituteInPlace libexec/daps-xslt \
              --replace 'XSLTPROC="/usr/bin/xsltproc"' 'XSLTPROC="xsltproc"' \
              --replace 'SAXON="/usr/bin/saxon"' 'SAXON="saxon"'
            substituteInPlace libexec/xml_cat_resolver \
              --replace '_XMLCATALOG=/usr/bin/xmlcatalog' '_XMLCATALOG=xmlcatalog'
            substituteInPlace etc/config.in \
              --replace 'XSLTPROCESSOR="/usr/bin/xsltproc"' 'XSLTPROCESSOR="xsltproc"'

            # Remove hardcoded FHS paths to xmlstarlet and bash in makefiles
            substituteInPlace make/common_variables.mk \
              --replace '/usr/bin/xmlstarlet' 'xmlstarlet' \
              --replace '/usr/bin/xml' 'xml' \
              --replace 'SHELL := /bin/bash' 'SHELL := bash'

            # Fix hardcoded autoconf paths in Makefile.am and Makefile.in to support standard DESTDIR / sysconfdir overriding
            for file in Makefile.am Makefile.in; do
              substituteInPlace $file \
                --replace 'dapsconfdir    = @sysconfdir@/daps' 'dapsconfdir    = $(sysconfdir)/daps' \
                --replace 'catalogdir     = @sysconfdir@/xml/catalog.d' 'catalogdir     = $(sysconfdir)/xml/catalog.d' \
                --replace 'emacssitedir   = @datadir@/emacs/site-lisp' 'emacssitedir   = $(datadir)/emacs/site-lisp' \
                --replace 'bashcompletiondir =@datadir@/bash-completion/completions' 'bashcompletiondir =$(datadir)/bash-completion/completions' \
                --replace 'bashcompletiondir = @datadir@/bash-completion/completions' 'bashcompletiondir =$(datadir)/bash-completion/completions' \
                --replace 'htmldocdir     = @docdir@/html' 'htmldocdir     = $(docdir)/html'
            done

            # Bypass path validation during Nix builds to prevent failing on non-existent absolute paths
            substituteInPlace bin/daps.in \
              --replace '-d $MYPATH || -f $MYPATH' '-d $MYPATH || -f $MYPATH || -n "$NIX_BUILD_TOP"'

            # Inject path translation code into bin/daps.in to redirect absolute FHS paths to Nix store
            substituteInPlace bin/daps.in \
              --replace 'MYPATH=''${MYPATH%/}' 'MYPATH=''${MYPATH%/}

    # Rewrite /usr/share/xml/docbook/stylesheet/ to the Nix store path of suse-xsl-stylesheets
    if [[ $MYPATH =~ ^/usr/share/xml/docbook/stylesheet/(.*) ]]; then
        local RELPATH="''${BASH_REMATCH[1]}"
        if [[ -d "${suse-xsl-stylesheets}/share/xml/docbook/stylesheet/$RELPATH" ]]; then
            MYPATH="${suse-xsl-stylesheets}/share/xml/docbook/stylesheet/$RELPATH"
        fi
    fi

    # Rewrite /usr/share/xml/geekodoc/ to the Nix store path of geekodoc
    if [[ $MYPATH =~ ^/usr/share/xml/geekodoc/(.*) ]]; then
        local RELPATH="''${BASH_REMATCH[1]}"
        if [[ -e "${geekodoc}/share/xml/geekodoc/$RELPATH" ]]; then
            MYPATH="${geekodoc}/share/xml/geekodoc/$RELPATH"
        fi
    fi'

            # Make all template files executable
            chmod +x bin/*.in etc/*.in libexec/* autobuild/*.in
            patchShebangs bin/ etc/ libexec/ autobuild/

            # Force all python scripts to use our pythonEnv containing lxml (run AFTER patchShebangs!)
            find libexec python-scripts -type f \( -name "*.py" -o -name "daps-xmlwellformed" \) \
              -exec sed -i "s|#!/usr/bin/env python3|#!${pythonEnv}/bin/python3|g; s|#!/usr/bin/python3|#!${pythonEnv}/bin/python3|g; s|#!/usr/bin/env python|#!${pythonEnv}/bin/python3|g; s|#!/nix/store/.*/bin/python[0-9.]*|#!${pythonEnv}/bin/python3|g" {} +

            # Patch Makefiles to ensure copied/symlinked static assets from the Nix store are made writable.
            # This prevents permission denied errors on cleanups (e.g. make clean / rm -rf).
            substituteInPlace make/html.mk \
              --replace '  ifneq "$(HTML_CSS)" "none"
	$(HTML_GRAPH_COMMAND) $(HTML_CSS) $(HTML_DIR)/static/css/
  endif
endif' '  ifneq "$(HTML_CSS)" "none"
	$(HTML_GRAPH_COMMAND) $(HTML_CSS) $(HTML_DIR)/static/css/
  endif
endif
	chmod -R +w $(HTML_DIR)/static || true'

            substituteInPlace make/webhelp.mk \
              --replace '  ifneq "$(HTML_CSS)" "none"
	$(HTML_GRAPH_COMMAND) $(HTML_CSS) $(WEBHELP_DIR)/static/css/
  endif
endif' '  ifneq "$(HTML_CSS)" "none"
	$(HTML_GRAPH_COMMAND) $(HTML_CSS) $(WEBHELP_DIR)/static/css/
  endif
endif
	chmod -R +w $(WEBHELP_DIR)/static || true'

            substituteInPlace make/epub.mk \
              --replace '	cp -rs --remove-destination $(STYLEIMG)/* $(EPUB_STATIC)
  ifneq "$(strip $(EPUB_CSS))" ""
	cp -s --remove-destination $(EPUB_CSS) $(EPUB_OEBPS)
  endif' '	cp -rs --remove-destination $(STYLEIMG)/* $(EPUB_STATIC)
  ifneq "$(strip $(EPUB_CSS))" ""
	cp -s --remove-destination $(EPUB_CSS) $(EPUB_OEBPS)
  endif
	chmod -R +w $(EPUB_TMPDIR) || true'
          '';

          preConfigure = ''
            # Create a build-time wrapper for xmlcatalog to filter out "No entry for" stdout messages
            mkdir -p $TMPDIR/bin
            cat <<EOF > $TMPDIR/bin/xmlcatalog
            #!${pkgs.bash}/bin/bash
            out=\$(${pkgs.libxml2}/bin/xmlcatalog "\$@")
            status=\$?
            echo "\$out" | grep -v "^No entry for" || true
            exit \$status
            EOF
            chmod +x $TMPDIR/bin/xmlcatalog
            export PATH=$TMPDIR/bin:$PATH

            # Generate a synthetic root catalog file containing references to all buildInputs catalogs
            echo "XML_CATALOG_FILES inside build is: $XML_CATALOG_FILES"
            mkdir -p build/xml
            export root_catalog="$PWD/build/xml/catalog.xml"
            echo "<?xml version=\"1.0\"?>" > "$root_catalog"
            echo "<!DOCTYPE catalog PUBLIC \"-//OASIS//DTD XML Catalogs V1.0//EN\" \"http://www.oasis-open.org/committees/entity/release/1.0/catalog.dtd\">" >> "$root_catalog"
            echo "<catalog xmlns=\"urn:oasis:names:tc:entity:xmlns:xml:catalog\">" >> "$root_catalog"
            for cat in $XML_CATALOG_FILES; do
              echo "  <nextCatalog catalog=\"$cat\"/>" >> "$root_catalog"
            done
            # Add build-time explicit local redirects for standard DocBook 4.5 DTD and DocBook 5.0 schemas to bypass missing SYSTEM mapping in standard nixpkgs catalogs
            echo "  <rewriteSystem systemIdStartString=\"http://www.docbook.org/xml/4.5/\" rewritePrefix=\"file://${pkgs.docbook_xml_dtd_45}/xml/dtd/docbook/\"/>" >> "$root_catalog"
            echo "  <rewriteURI uriStartString=\"http://www.docbook.org/xml/4.5/\" rewritePrefix=\"file://${pkgs.docbook_xml_dtd_45}/xml/dtd/docbook/\"/>" >> "$root_catalog"
            echo "  <rewriteSystem systemIdStartString=\"http://docbook.org/xml/4.5/\" rewritePrefix=\"file://${pkgs.docbook_xml_dtd_45}/xml/dtd/docbook/\"/>" >> "$root_catalog"
            echo "  <rewriteURI uriStartString=\"http://docbook.org/xml/4.5/\" rewritePrefix=\"file://${pkgs.docbook_xml_dtd_45}/xml/dtd/docbook/\"/>" >> "$root_catalog"
            echo "  <rewriteSystem systemIdStartString=\"http://www.oasis-open.org/docbook/xml/4.5/\" rewritePrefix=\"file://${pkgs.docbook_xml_dtd_45}/xml/dtd/docbook/\"/>" >> "$root_catalog"
            echo "  <rewriteURI uriStartString=\"http://www.oasis-open.org/docbook/xml/4.5/\" rewritePrefix=\"file://${pkgs.docbook_xml_dtd_45}/xml/dtd/docbook/\"/>" >> "$root_catalog"
            echo "  <rewriteSystem systemIdStartString=\"http://docbook.org/xml/5.0/rng/\" rewritePrefix=\"file://${pkgs.docbook5}/share/xml/docbook-5.0/rng/\"/>" >> "$root_catalog"
            echo "  <rewriteURI uriStartString=\"http://docbook.org/xml/5.0/rng/\" rewritePrefix=\"file://${pkgs.docbook5}/share/xml/docbook-5.0/rng/\"/>" >> "$root_catalog"
            echo "  <rewriteSystem systemIdStartString=\"http://www.oasis-open.org/docbook/xml/5.0/rng/\" rewritePrefix=\"file://${pkgs.docbook5}/share/xml/docbook-5.0/rng/\"/>" >> "$root_catalog"
            echo "  <rewriteURI uriStartString=\"http://docbook.org/xml/5.0/rng/\" rewritePrefix=\"file://${pkgs.docbook5}/share/xml/docbook-5.0/rng/\"/>" >> "$root_catalog"
            echo "  <rewriteSystem systemIdStartString=\"http://docbook.org/xml/5.1/rng/\" rewritePrefix=\"file://${pkgs.docbook5}/share/xml/docbook-5.0/rng/\"/>" >> "$root_catalog"
            echo "  <rewriteURI uriStartString=\"http://docbook.org/xml/5.1/rng/\" rewritePrefix=\"file://${pkgs.docbook5}/share/xml/docbook-5.0/rng/\"/>" >> "$root_catalog"
            echo "  <rewriteSystem systemIdStartString=\"http://www.oasis-open.org/docbook/xml/5.1/rng/\" rewritePrefix=\"file://${pkgs.docbook5}/share/xml/docbook-5.0/rng/\"/>" >> "$root_catalog"
            echo "  <rewriteURI uriStartString=\"http://www.oasis-open.org/docbook/xml/5.1/rng/\" rewritePrefix=\"file://${pkgs.docbook5}/share/xml/docbook-5.0/rng/\"/>" >> "$root_catalog"
            echo "</catalog>" >> "$root_catalog"

            # Point the build config to the build-time synthetic catalog
            substituteInPlace etc/config.in --replace '@root_catalog@' "$root_catalog"

            # Remove etc/config symlink if it exists to prevent self-truncation when pre-generating config
            rm -f etc/config

            # Pre-generate etc/config so it exists when the manuals are built during make
            sed -e "s|@sysconfdir@|/etc|g" \
                -e "s|@bindir@|/usr/bin|g" \
                -e "s|@pkgdatadir@|$PWD|g" \
                -e "s|@datadir@|/usr/share|g" \
                -e "s|@prefix@|/usr|g" \
                -e "s|@db5version@|5.0|g" \
                -e "s|@PACKAGE_VERSION@|4.0.beta1|g" \
                etc/config.in > etc/config
            ls -lh etc/config || true

            echo "Querying XML catalog for docbook-xsl-ns URI..."
            xmlcatalog "$root_catalog" "http://docbook.sourceforge.net/release/xsl-ns/current/"

            # Generate the configure script
            bash ./autogen.sh
          '';

          preBuild = ''
            export PATH=$TMPDIR/bin:$PATH
          '';

          configureFlags = [
            "--disable-edit-rootcatalog"
            "--sysconfdir=/etc"
          ];

          installFlags = [
            "sysconfdir=\$(out)/etc"
          ];

          postInstall = ''
            # Generate the final runtime synthetic XML catalog in the Nix store
            mkdir -p $out/share/xml
            local cat_file="$out/share/xml/catalog.xml"
            echo "<?xml version=\"1.0\"?>" > "$cat_file"
            echo "<!DOCTYPE catalog PUBLIC \"-//OASIS//DTD XML Catalogs V1.0//EN\" \"http://www.oasis-open.org/committees/entity/release/1.0/catalog.dtd\">" >> "$cat_file"
            echo "<catalog xmlns=\"urn:oasis:names:tc:entity:xmlns:xml:catalog\">" >> "$cat_file"
            for cat in $XML_CATALOG_FILES; do
              echo "  <nextCatalog catalog=\"$cat\"/>" >> "$cat_file"
            done
            # Delegate to DAPS's own private catalog file for its custom stylesheets and schemas
            echo "  <nextCatalog catalog=\"$out/etc/xml/catalog.d/daps.xml\"/>" >> "$cat_file"
            echo "</catalog>" >> "$cat_file"

            # Create a runtime wrapper for xmlcatalog to filter out "No entry for" stdout messages
            mkdir -p $out/libexec
            cat <<EOF > $out/libexec/xmlcatalog
            #!${pkgs.bash}/bin/bash
            out=\$(${pkgs.libxml2}/bin/xmlcatalog "\$@")
            status=\$?
            echo "\$out" | grep -v "^No entry for" || true
            exit \$status
            EOF
            chmod +x $out/libexec/xmlcatalog

            # Point the installed DAPS config to our runtime synthetic catalog
            substituteInPlace $out/etc/daps/config \
              --replace "$root_catalog" "$cat_file"

            # Point the installed DAPS private catalog base to our Nix store share directory
            # and add rewrite rules to redirect absolute /usr/share/daps/daps-xslt/, stylesheet, and geekodoc paths to the Nix store
            substituteInPlace $out/etc/xml/catalog.d/daps.xml \
              --replace "file:///usr/share/daps/daps-xslt/" "file://$out/share/daps/daps-xslt/" \
              --replace "</catalog>" "  <rewriteSystem systemIdStartString=\"/usr/share/daps/daps-xslt/\" rewritePrefix=\"file://$out/share/daps/daps-xslt/\"/>\n  <rewriteURI uriStartString=\"/usr/share/daps/daps-xslt/\" rewritePrefix=\"file://$out/share/daps/daps-xslt/\"/>\n  <rewriteSystem systemIdStartString=\"file:///usr/share/daps/daps-xslt/\" rewritePrefix=\"file://$out/share/daps/daps-xslt/\"/>\n  <rewriteURI uriStartString=\"file:///usr/share/daps/daps-xslt/\" rewritePrefix=\"file://$out/share/daps/daps-xslt/\"/>\n  <rewriteSystem systemIdStartString=\"/usr/share/xml/docbook/stylesheet/\" rewritePrefix=\"file://${suse-xsl-stylesheets}/share/xml/docbook/stylesheet/\"/>\n  <rewriteURI uriStartString=\"/usr/share/xml/docbook/stylesheet/\" rewritePrefix=\"file://${suse-xsl-stylesheets}/share/xml/docbook/stylesheet/\"/>\n  <rewriteSystem systemIdStartString=\"/usr/share/xml/geekodoc/\" rewritePrefix=\"file://${geekodoc}/share/xml/geekodoc/\"/>\n  <rewriteURI uriStartString=\"/usr/share/xml/geekodoc/\" rewritePrefix=\"file://${geekodoc}/share/xml/geekodoc/\"/>\n  <rewriteSystem systemIdStartString=\"file:///usr/share/xml/geekodoc/\" rewritePrefix=\"file://${geekodoc}/share/xml/geekodoc/\"/>\n  <rewriteURI uriStartString=\"file:///usr/share/xml/geekodoc/\" rewritePrefix=\"file://${geekodoc}/share/xml/geekodoc/\"/>\n  <rewriteSystem systemIdStartString=\"http://docbook.org/xml/5.0/rng/docbookxi.rng\" rewritePrefix=\"file://${geekodoc}/share/xml/geekodoc/rng/2_5.2/geekodoc-v2-flat.rng\"/>\n  <rewriteURI uriStartString=\"http://docbook.org/xml/5.0/rng/docbookxi.rng\" rewritePrefix=\"file://${geekodoc}/share/xml/geekodoc/rng/2_5.2/geekodoc-v2-flat.rng\"/>\n  <rewriteSystem systemIdStartString=\"http://docbook.org/xml/5.0/rng/docbookxi.rnc\" rewritePrefix=\"file://${geekodoc}/share/xml/geekodoc/rng/2_5.2/geekodoc-v2-flat.rnc\"/>\n  <rewriteURI uriStartString=\"http://docbook.org/xml/5.0/rng/docbookxi.rnc\" rewritePrefix=\"file://${geekodoc}/share/xml/geekodoc/rng/2_5.2/geekodoc-v2-flat.rnc\"/>\n  <rewriteSystem systemIdStartString=\"http://docbook.org/xml/5.0/rng/docbook.rng\" rewritePrefix=\"file://${geekodoc}/share/xml/geekodoc/rng/2_5.2/geekodoc-v2-flat.rng\"/>\n  <rewriteURI uriStartString=\"http://docbook.org/xml/5.0/rng/docbook.rng\" rewritePrefix=\"file://${geekodoc}/share/xml/geekodoc/rng/2_5.2/geekodoc-v2-flat.rng\"/>\n  <rewriteSystem systemIdStartString=\"http://docbook.org/xml/5.0/rng/docbook.rnc\" rewritePrefix=\"file://${geekodoc}/share/xml/geekodoc/rng/2_5.2/geekodoc-v2-flat.rnc\"/>\n  <rewriteURI uriStartString=\"http://docbook.org/xml/5.0/rng/docbook.rnc\" rewritePrefix=\"file://${geekodoc}/share/xml/geekodoc/rng/2_5.2/geekodoc-v2-flat.rnc\"/>\n  <rewriteSystem systemIdStartString=\"http://docbook.org/xml/5.1/rng/docbookxi.rng\" rewritePrefix=\"file://${geekodoc}/share/xml/geekodoc/rng/2_5.2/geekodoc-v2-flat.rng\"/>\n  <rewriteURI uriStartString=\"http://docbook.org/xml/5.1/rng/docbookxi.rng\" rewritePrefix=\"file://${geekodoc}/share/xml/geekodoc/rng/2_5.2/geekodoc-v2-flat.rng\"/>\n  <rewriteSystem systemIdStartString=\"http://docbook.org/xml/5.1/rng/docbookxi.rnc\" rewritePrefix=\"file://${geekodoc}/share/xml/geekodoc/rng/2_5.2/geekodoc-v2-flat.rnc\"/>\n  <rewriteURI uriStartString=\"http://docbook.org/xml/5.1/rng/docbookxi.rnc\" rewritePrefix=\"file://${geekodoc}/share/xml/geekodoc/rng/2_5.2/geekodoc-v2-flat.rnc\"/>\n  <rewriteSystem systemIdStartString=\"http://docbook.org/xml/5.1/rng/docbook.rng\" rewritePrefix=\"file://${geekodoc}/share/xml/geekodoc/rng/2_5.2/geekodoc-v2-flat.rng\"/>\n  <rewriteURI uriStartString=\"http://docbook.org/xml/5.1/rng/docbook.rng\" rewritePrefix=\"file://${geekodoc}/share/xml/geekodoc/rng/2_5.2/geekodoc-v2-flat.rng\"/>\n  <rewriteSystem systemIdStartString=\"http://docbook.org/xml/5.1/rng/docbook.rnc\" rewritePrefix=\"file://${geekodoc}/share/xml/geekodoc/rng/2_5.2/geekodoc-v2-flat.rnc\"/>\n  <rewriteURI uriStartString=\"http://docbook.org/xml/5.1/rng/docbook.rnc\" rewritePrefix=\"file://${geekodoc}/share/xml/geekodoc/rng/2_5.2/geekodoc-v2-flat.rnc\"/>\n</catalog>"

            # Wrap all installed binaries so they have runtime dependencies in PATH and the correct XML catalog
            for prog in $out/bin/*; do
              if [ -f "$prog" ] && [ -x "$prog" ]; then
                wrapProgram "$prog" \
                  --prefix PATH : $out/libexec:$out/bin:${pkgs.lib.makeBinPath runtimeDeps} \
                  --set XML_MAIN_CATALOG "$cat_file" \
                  --set XML_CATALOG_FILES "$cat_file"
              fi
            done
          '';

          passthru = {
            inherit runtimeDeps;
          };

          meta = with pkgs.lib; {
            description = "DocBook Authoring and Publishing Suite (DAPS)";
            homepage = "https://github.com/openSUSE/daps";
            license = licenses.gpl2Only;
            platforms = platforms.linux;
          };
        };

      in
      {
        packages.suse-xsl-stylesheets = suse-xsl-stylesheets;
        packages.geekodoc = geekodoc;
        packages.daps = pkgs.lib.makeOverridable makeDaps {};
        packages.default = self.packages.${system}.daps;

        apps.daps = flake-utils.lib.mkApp {
          drv = self.packages.${system}.daps;
        };
        apps.default = self.apps.${system}.daps;

        devShells.default = pkgs.mkShell {
          buildInputs = self.packages.${system}.daps.runtimeDeps ++ (with pkgs; [
            autoconf
            automake
            libtool
            pkg-config
          ]);

          shellHook = ''
            # Generate local development synthetic XML catalog
            mkdir -p .dev-catalog
            export root_catalog="$PWD/.dev-catalog/catalog.xml"
            echo "<?xml version=\"1.0\"?>" > "$root_catalog"
            echo "<!DOCTYPE catalog PUBLIC \"-//OASIS//DTD XML Catalogs V1.0//EN\" \"http://www.oasis-open.org/committees/entity/release/1.0/catalog.dtd\">" >> "$root_catalog"
            echo "<catalog xmlns=\"urn:oasis:names:tc:entity:xmlns:xml:catalog\">" >> "$root_catalog"
            for cat in $XML_CATALOG_FILES; do
              echo "  <nextCatalog catalog=\"$cat\"/>" >> "$root_catalog"
            done
            echo "</catalog>" >> "$root_catalog"

            export XML_CATALOG_FILES="$root_catalog $XML_CATALOG_FILES"
            echo "DAPS Dev Shell loaded! Synthetic catalog created at: $root_catalog"
          '';
        };
      }
    );
}