{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
    gomod2nix = {
      url = "github:nix-community/gomod2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, flake-utils, nixpkgs, gomod2nix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ gomod2nix.overlays.default ];
        };
        gitlab-nvim-server = pkgs.buildGoApplication {
          pname = "gitlab.nvim-server";
          version = "git";
          src = ./.;
          modules = ./gomod2nix.toml;
          subPackages = [ "cmd" ];
          postInstall = ''
            mv $out/bin/cmd $out/bin/gitlab.nvim
          '';
        };
        gitlab-nvim = pkgs.vimUtils.buildVimPlugin {
          name = "gitlab.nvim";
          src = ./.;
          doCheck = false;
        };
      in
      {
        formatter = pkgs.nixpkgs-fmt;
        packages.gitlab-nvim-server = gitlab-nvim-server;
        packages.gitlab-nvim = gitlab-nvim;
        packages.default = gitlab-nvim;
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            git
            go
            go-tools
            gomod2nix
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
