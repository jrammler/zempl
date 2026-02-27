{
    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
        flake-utils.url = "github:numtide/flake-utils";
        zig-overlay = {
            url = "github:mitchellh/zig-overlay";
            inputs.nixpkgs.follows = "nixpkgs";
        };
    };

    outputs = { self, nixpkgs, flake-utils, zig-overlay }:
        flake-utils.lib.eachDefaultSystem (system:
            let
                pkgs = nixpkgs.legacyPackages.${system};
            in
            {
                devShells.default = pkgs.mkShell {
                    buildInputs = with pkgs; [
                        zig-overlay.packages.${system}."0.15.2"
                        zls_0_15
                    ];
                };
            }
        );
}
