{
  description = "A terminal based spreadsheet editor and calculator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in {
      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in {
          default = pkgs.stdenv.mkDerivation {
            pname = "spreadsheet";
            version = "0.1.0";

            src = ./.;

            nativeBuildInputs = [ pkgs.odin ];

            buildPhase = ''
              runHook preBuild
              odin build . -out:spreadsheet
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p $out/bin
              cp spreadsheet $out/bin/
              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "A terminal based spreadsheet editor and calculator";
              homepage = "https://github.com/dagis/spreadsheet";
              license = licenses.gpl3Plus;
              platforms = platforms.unix;
              mainProgram = "spreadsheet";
            };
          };
        });

      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              odin
              ols
            ];
          };
        });
    };
}
