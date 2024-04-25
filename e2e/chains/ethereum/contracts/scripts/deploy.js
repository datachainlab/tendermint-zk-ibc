
const stepVerifierDigest = "0x09bf185e9e478bac323981a844afe484dcd73823f6a34f5adb8cffe6c4436111";
const skipVerifierDigest = "0x286fd609266936f71d552671b7553f1a0e59c7cf296112996bded1ca3bafa4a4";
const revisionNumber = 0;

async function deploy(deployer, contractName, args = []) {
  const factory = await hre.ethers.getContractFactory(contractName);
  const contract = await factory.connect(deployer).deploy(...args);
  await contract.waitForDeployment();
  return contract;
}

async function deployIBC(deployer) {
  const logicNames = [
    "IBCClient",
    "IBCConnectionSelfStateNoValidation",
    "IBCChannelHandshake",
    "IBCChannelPacketSendRecv",
    "IBCChannelPacketTimeout"
  ];
  const logics = [];
  for (const name of logicNames) {
    const logic = await deploy(deployer, name);
    logics.push(logic);
  }
  return deploy(deployer, "OwnableIBCHandler", logics.map(l => l.target));
}

async function main() {
  // This is just a convenience check
  if (network.name === "hardhat") {
    console.warn(
      "You are trying to deploy a contract to the Hardhat Network, which" +
        "gets automatically created and destroyed every time. Use the Hardhat" +
        " option '--network localhost'"
    );
  }

  let tendermintZKLightClient;
  if (process.env.TM_ZK_PS === "groth16") {
    tendermintZKLightClient = "TendermintZKLightClientGroth16";
  } else if (process.env.TM_ZK_PS === "groth16-commitment") {
    tendermintZKLightClient = "TendermintZKLightClientGroth16Commitment";
  } else if (process.env.TM_ZK_PS === "mock") {
    tendermintZKLightClient = "TendermintZKLightClientMock";
  } else {
    throw new Error("Unknown env value `TM_ZK_PS`:" + process.env.TM_ZK_PS);
  }
  console.log("Using TendermintZKLightClient:", tendermintZKLightClient);

  // ethers is available in the global scope
  const [deployer] = await hre.ethers.getSigners();
  console.log(
    "Deploying the contracts with the account:",
    await deployer.getAddress()
  );
  console.log("Account balance:", (await hre.ethers.provider.getBalance(deployer.getAddress())).toString());

  const ibcHandler = await deployIBC(deployer);
  console.log("IBCHandler address:", ibcHandler.target);

  const tendermintZKProtoMarshaler = await deploy(deployer, "TendermintZKLightClientProtoMarshaler");
  console.log("TendermintZKLightClientProtoMarshaler address:", tendermintZKProtoMarshaler.target);
  const factory = await hre.ethers.getContractFactory(tendermintZKLightClient, {
    libraries: {
      TendermintZKLightClientProtoMarshaler: tendermintZKProtoMarshaler.target
    }
  });
  const tendermintZKClient = await factory.connect(deployer).deploy(ibcHandler.target, stepVerifierDigest, skipVerifierDigest, revisionNumber);
  await tendermintZKClient.waitForDeployment();
  console.log("TendermintZKLightClient address:", tendermintZKClient.target);

  const erc20token = await deploy(deployer, "ERC20Token", ["simple", "simple", 1000000]);
  console.log("ERC20Token address:", erc20token.target);

  const ics20bank = await deploy(deployer, "ICS20Bank");
  console.log("ICS20Bank address:", ics20bank.target);

  const ics20transferbank = await deploy(deployer, "ICS20TransferBank", [ibcHandler.target, ics20bank.target]);
  console.log("ICS20TransferBank address:", ics20transferbank.target);

  await ibcHandler.bindPort("transfer", ics20transferbank.target);
  await ibcHandler.registerClient("tendermint-zk", tendermintZKClient.target);
  await ics20bank.setOperator(ics20transferbank.target);

}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}
