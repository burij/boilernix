{ pkgs ? import
    (fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-25.11")
    { config = { }; overlays = [ ]; }
}:

let


	shell = pkgs.mkShell {
		packages = with pkgs; [
		  	# pandoc
			(lua5_4.withPackages(ps: with ps; [
				inspect
			]))
		];

		shellHook = ''
			alias run='lua main.lua'
		'';
	};


in

{
  inherit shell;
}

