# aiu-shell-history package definition
#
# This file will be similar to the package definition in nixpkgs:
#     https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/at/atuin/package.nix
#
# Helpful documentation: https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/rust.section.md
{
  lib,
  stdenv,
  installShellFiles,
  rustPlatform,
  libiconv,
}:
rustPlatform.buildRustPackage {
  name = "aiu-shell-history";

  src = lib.cleanSource ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
    # Allow dependencies to be fetched from git and avoid having to set the outputHashes manually
    allowBuiltinFetchGit = true;
  };

  nativeBuildInputs = [installShellFiles];

  buildInputs = lib.optionals stdenv.isDarwin [libiconv];

  postInstall = ''
    installShellCompletion --cmd aiu-shell-history \
      --bash <($out/bin/aiu-shell-history gen-completions -s bash) \
      --fish <($out/bin/aiu-shell-history gen-completions -s fish) \
      --zsh <($out/bin/aiu-shell-history gen-completions -s zsh)
  '';

  doCheck = false;

  meta = with lib; {
    description = "Replacement for a shell history which records additional commands context with optional encrypted synchronization between machines";
    homepage = "https://github.com/atuinsh/atuin";
    license = licenses.mit;
    mainProgram = "aiu-shell-history";
  };
}
