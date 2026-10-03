{ lib, cfg }:
let
  onHost = builtins.elem cfg.llmHost [
    "127.0.0.1"
    "localhost"
  ];
  ipv6 = lib.hasInfix ":" cfg.llmHost;
  address = if onHost then "127.0.0.1" else cfg.llmHost;
  isAddress = ipv6 || builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+" address != null;
  port = toString cfg.llmPort;
in
{
  baseUrl = "http://${
    if onHost then
      "10.0.2.2"
    else if ipv6 then
      "[${cfg.llmHost}]"
    else
      cfg.llmHost
  }:${port}/v1";

  nftablesRule = lib.optionalString isAddress "${if ipv6 then "ip6" else "ip"} daddr ${address} tcp dport ${port} accept";
}
