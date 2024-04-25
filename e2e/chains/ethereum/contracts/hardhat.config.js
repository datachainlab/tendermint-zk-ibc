require("@nomicfoundation/hardhat-toolbox");

const mnemonic =
  "math razor capable expose worth grape metal sunset metal sudden usage scheme";

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    },
  },
  networks: {
    local: {
      url: "http://127.0.0.1:8545",
      accounts: {
        mnemonic: mnemonic,
      },
      chainId: 2018,
    }
  }
}
