require("dotenv").config();
const HDWalletProvider = require("@truffle/hdwallet-provider");

module.exports = {
  compilers: {
    solc: {
      version: "0.7.5",
      settings: {
        optimizer: {
          enabled: true,
          runs: 10000,
        },
      },
    },
  },
  networks: {
    development: {
      host: "localhost",
      port: 8545,
      network_id: "*",
    },
    mainnet: {
      provider() {
        const { MNEMONIC, INFURA_API_KEY } = process.env;
        if (!MNEMONIC || !INFURA_API_KEY) {
          console.error(
            "Environment variables MNEMONIC and INFURA_API_KEY are required"
          );
          process.exit(1);
        }
        return new HDWalletProvider(
          MNEMONIC,
          `https://mainnet.infura.io/v3/${INFURA_API_KEY}`
        );
      },
      network_id: 1,
    },
    kovan: {
      provider() {
        const { MNEMONIC, INFURA_API_KEY } = process.env;
        if (!MNEMONIC || !INFURA_API_KEY) {
          console.error(
            "Environment variables MNEMONIC and INFURA_API_KEY are required"
          );
          process.exit(1);
        }
        return new HDWalletProvider(
          MNEMONIC,
          `wss://kovan.infura.io/ws/v3/${INFURA_API_KEY}`
        );
      },
      network_id: 42,
      gasPrice: 2000000000, // 10 gwei (default: 20 gwei)
    },
  },
  mocha: {
    timeout: 2000000,
    reporter: "Spec",
  },
  plugins: ["solidity-coverage"],
};
