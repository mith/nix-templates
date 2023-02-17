{
  description = "A collection of Nix flake templates";

  outputs = {self}: {
    templates = {
      bevy = {
        path = ./bevy;
        description = "A template for a Bevy game. Includes Cargo.toml and basic main.rs";
      };
      bevy-web = {
        path = ./bevy-web;
        description = "A template for a Bevy game with webassembly target configured. Includes Cargo.toml and basic main.rs";
      };
    };
  };
}
