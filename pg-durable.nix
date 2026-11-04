# Upstream's PG18 amd64 release, relinked to the Nix runtime libraries.
# No Debian maintainer scripts run, and no demo server configuration is copied.
{ lib, stdenv, fetchurl, dpkg, autoPatchelfHook, openssl, zlib, zstd, postgresql }:

stdenv.mkDerivation (finalAttrs: {
  pname = "pg_durable";
  version = "0.2.9";

  src = fetchurl {
    url = "https://github.com/microsoft/pg_durable/releases/download/v${finalAttrs.version}/pg-durable-postgresql-18_${finalAttrs.version}-1_amd64.deb";
    # Verified against the release's SHA256SUMS.
    sha256 = "a60c5892c808ad41969c3a5f60f8b085d5417036b62b9c934bfbb9633938b3d7";
  };

  nativeBuildInputs = [ dpkg autoPatchelfHook ];
  buildInputs = [ openssl zlib zstd stdenv.cc.cc.lib ];
  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x "$src" .
    runHook postUnpack
  '';
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib $out/share/postgresql/extension
    cp usr/lib/postgresql/18/lib/pg_durable.so $out/lib/
    cp usr/share/postgresql/18/extension/* $out/share/postgresql/extension/
    runHook postInstall
  '';

  passthru = { inherit postgresql; };
  meta = {
    description = "Durable SQL workflows inside PostgreSQL";
    homepage = "https://microsoft.github.io/pg_durable/";
    license = lib.licenses.postgresql;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
