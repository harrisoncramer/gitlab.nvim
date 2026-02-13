{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, flake-utils, nixpkgs }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
        gitlab-nvim-server = pkgs.buildGoModule {
          pname = "gitlab.nvim-server";
          version = "git";
          src = ./.;
          vendorHash = "sha256-OLAKTdzqynBDHqWV5RzIpfc3xZDm6uYyLD4rxbh0DMg=";
          postInstall = ''
            cp -r ${./cmd/config} $out/bin/config
            mv $out/bin/cmd $out/bin/gitlab.nvim
          '';
        };
        gitlab-nvim = pkgs.vimUtils.buildVimPlugin {
          name = "gitlab.nvim";
          src = ./.;
          doCheck = false;
        };
      in
      rec {
        formatter = pkgs.nixpkgs-fmt;
        packages.gitlab-nvim-server = gitlab-nvim-server;
        packages.gitlab-nvim = gitlab-nvim;
        packages.default = packages.gitlab-nvim;
        devShell = pkgs.mkShell {
          packages = with pkgs; [
            git
            go
            go-tools
            golangci-lint
            luajitPackages.busted
            luajitPackages.luacheck
            luajitPackages.luarocks
            neovim
            stylua
          ];
        };
      }
    );
}
