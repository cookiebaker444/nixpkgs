{ lib
, buildGoModule
, fetchFromGitHub
}:

buildGoModule rec {
  pname = "carbonapi";
  version = "0.15.6";

  src = fetchFromGitHub {
    owner = "go-graphite";
    repo = pname;
    rev = "v${version}";
    sha256 = "184p8l8kh9jhcqv1cp46mnwa4pfzf1gixzfnfg7dz587c1yafz2i";
  };

  vendorSha256 = "1x661npgfbmjqrv0vhd86wnb3kfgm971qw2w16whn4z9hdi51g9w";

  subPackages = [ "cmd/carbonapi" ];

  meta = with lib; {
    description = "Implementation of graphite API (graphite-web) in golang";
    homepage = "https://github.com/go-graphite/carbonapi";
    license = licenses.bsd2;
    maintainers = with maintainers; [ jsoo1 ];
  };
}
