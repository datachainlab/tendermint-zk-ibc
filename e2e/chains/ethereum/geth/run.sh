#!/bin/sh

/usr/local/bin/geth --password /root/geth.password \
  --unlock "0" --syncmode full --gcmode archive \
  --authrpc.vhosts "*" --authrpc.addr "0.0.0.0" --http --http.addr "0.0.0.0" --http.port 8545 --http.api web3,eth,net,personal,miner,txpool,debug --http.corsdomain '*' \
  --ws --ws.api eth,net,web3,personal,txpool --ws.addr "0.0.0.0" --ws.port 8546 --ws.origins '*' \
  --datadir /root/.ethereum --nodiscover \
  --mine --miner.gasprice "0" --miner.etherbase "0xa89f47c6b463f74d87572b058427da0a13ec5425" \
  --allow-insecure-unlock --nousb \
  $@
