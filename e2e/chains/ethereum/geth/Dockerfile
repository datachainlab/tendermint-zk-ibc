FROM ethereum/client-go:v1.13.14

ARG CHAIN_ID

ADD geth.password /root/geth.password
ADD genesis.json  /root/genesis.json
ADD privatekey  /root/privatekey
ADD run.sh  /run.sh

RUN /usr/local/bin/geth --nousb --datadir /root/.ethereum init /root/genesis.json

RUN /usr/local/bin/geth --nousb account import --password /root/geth.password /root/privatekey

EXPOSE 8545

ENTRYPOINT ["/run.sh"]
CMD ["--verbosity", "5", "--vmdebug"]
