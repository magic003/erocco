-module(erocco_main).
-export([main/1]).

main(Args) -> erocco:generate_documentation(Args).
