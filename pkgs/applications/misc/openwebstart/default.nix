{ stdenv, lib, fetchurl, makeDesktopItem, makeWrapper, writeText
, dpkg, openjdk11, adoptopenjdk-icedtea-web
, gtk3, gdk-pixbuf, gsettings-desktop-schemas, hicolor-icon-theme
}:
let
  inherit (lib) escapeShellArgs replaceStrings;

  # Needs a non-headless version with JavaFX
  java = openjdk11;

  # Don't forget to check for changes to the varfile
  # See: https://openwebstart.com/configuration/
  version = "1.1.7";
  deb-version = replaceStrings ["."] ["_"] version;
  name = "OpenWebStart_linux_${deb-version}.deb";

  sha256 = "15msf4akz11j4vjidccm07icp03vllpj05xv5qaa1ij4fl9nw6zl";

  itw-settings = makeDesktopItem {
    type = "Application";
    name = "OpenWebStart Settings";
    desktopName = "itw-settings";
    exec = "itw-settings";
    icon = "openwebstart";
  };

  openwebstart = makeDesktopItem {
    type = "Application";
    name = "OpenWebStart";
    desktopName = "openwebstart";
    exec = "openwebstart";
    icon = "openwebstart";
    # Settings copied from debian postinst script
    mimeType = "application/x-java-jnlp-file";
  };

  # Extracted from deb postinst
  mime-info = writeText "jlnp.xml" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
            <mime-type type="application/x-java-jnlp-file">
                    <icon name="application-x-java-jnlp-file"/>
            </mime-type>
    </mime-info>
  '';
in
stdenv.mkDerivation rec {
  pname = "openwebstart";
  inherit version;

  # We only care about the Jar contained in the deb and the icons
  src = fetchurl rec {
    inherit name sha256;
    url = "https://github.com/karakun/OpenWebStart/releases/download/v${version}/${name}";
  };

  sourcesRoot = ".";
  unpackCmd = ''
    dpkg-deb -x "$src" .
  '';

  dontBuild = true;
  dontConfigure = true;
  dontStrip = true;

  nativeBuildInputs = [ dpkg makeWrapper ];

  buildInputs = [ adoptopenjdk-icedtea-web java hicolor-icon-theme gdk-pixbuf ];

  # Allow overriding the varfile
  varfile = ./response.varfile;

  installPhase = let
    # The install4j splashscreen and launcher filename may change. Must be manually retrieved from either ./javaws or ./itw-settings within the deb
    wrap = exec: launch: install4j-launcher: ''
      makeWrapper ${java}/bin/java $out/bin/${exec} \
        --prefix XDG_DATA_DIRS : "$XDG_ICON_DIRS:${gtk3.out}/share:${gsettings-desktop-schemas}/share:${hicolor-icon-theme}/share:$out/share:$GSETTINGS_SCHEMAS_PATH" \
        --add-flags "-Dawt.useSystemAAFontSettings=lcd -splash:$out/share/${pname}/.install4j/s_1g4la53.png" \
        --add-flags "-cp $out/share/${pname}/.install4j/i4jruntime.jar:$out/share/${pname}/.install4j/${install4j-launcher}.jar:$out/share/${pname}/${pname}.jar" \
        --add-flags ${launch}
    '';
    # Different every release of OpenWebStart. found in deb within the exec line of the file `itw-settings` and `javaws` respectively
    itw-settings-i4j-launcher = "launcher6799353e";
    openwebstart-i4j-launcher = "launcher12cc4282";
  in ''
    # Copy JAR
    mkdir -pv $out/bin $out/share/${pname}
    cp -v OpenWebStart/openwebstart.jar $out/share/${pname}/${pname}.jar
    cp -vr OpenWebStart/.install4j $out/share/${pname}

    # Copy OpenWebStart varfile
    ln -sv ${varfile} $out/share/${pname}/response.varfile
    ln -sv ${varfile} $out/share/${pname}/.install4j/response.varfile

    # Extract icons
    ${java}/bin/jar xf $out/share/${pname}/${pname}.jar com/openwebstart/app/icon
    for size in 32 64 128 256 512; do
      mkdir -pv $out/share/icons/hicolor/''${size}x''${size}/apps
      install -Dm444 com/openwebstart/app/icon/default-icon-''${size}.png $out/share/icons/hicolor/''${size}x''${size}/apps/openwebstart.png
    done

    mkdir -pv $out/share/applications
    ln -sv ${itw-settings}/share/applications/* $out/share/applications/
    ln -sv ${openwebstart}/share/applications/* $out/share/applications/

    mkdir -pv $out/share/mime/packages
    ln -sv ${mime-info} $out/share/mime/packages/jlnp.xml

    ${wrap "itw-settings" "install4j.com.openwebstart.launcher.ControlPanelLauncher" itw-settings-i4j-launcher}
    ${wrap "openwebstart" "install4j.com.openwebstart.launcher.OpenWebStartLauncher" openwebstart-i4j-launcher}
  '';

  meta = with stdenv.lib; {
    homepage = "https://github.com/karakun/OpenWebStart";
    description = "Implementation of Java Web Start";
    longDescription = ''
      OpenWebStart offers a user-friendly installer to use Web Start / JNLP
      functionality with future Java versions without depending on a specific
      Java vendor or distribution.
      The first goal of the project is to target Java 8 LTS versions while
      support for Java 11 LTS will come in near future.
    '';
    maintainers = [ maintainers.nberbiche ];
    license = licenses.gpl2Classpath;
    # Officially supported platforms
    platforms = [ "x86_64-linux" "x86_64-windows" "x86_64-darwin" ]
                ++ [ "i686-linux" "i686-windows" ];
  };
}
