require("@nomicfoundation/hardhat-toolbox");
require("@nomiclabs/hardhat-web3");
const task = require("hardhat/config").task;
require("dotenv").config();

const importToml = require("import-toml");
const foundryConfig = importToml.sync("foundry.toml");

const baseConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      forking: {
        url: `https://mainnet.gateway.tenderly.co`,
        blockNumber: 18364580,
      },
      // set this here because it is the limit of the bor testchain
      // and we can only set this once for all hardhat tests
      blockGasLimit: 20000000,
      allowUnlimitedContractSize: true,
      accounts: {
        mnemonic:
          "clock radar mass judge dismiss just intact mind resemble fringe diary casino",
      },
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.5.17",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  paths: {
    sources: "./contracts",
    cache: "./cache_hardhat",
    tests: "./test",
  },
};

const networks = () => {
  if (process.env.ENV === "dev") {
    return {
      ...baseConfig.networks,
      sepolia: {
        url: "https://sepolia.gateway.tenderly.co",
        accounts: {
          mnemonic: process.env.MNEMONIC_DEV,
        },
      },
    };
  } else if (process.env.ENV === "prod") {
    return {
      ...baseConfig.networks,
      mainnet: {
        url: "https://mainnet.gateway.tenderly.co",
        accounts: [process.env.PK_MAINNET],
      },
    };
  } else if (process.env.LOCAL_NETWORK) {
    console.log("using local hardhat network");
    return {
      hardhat: {
        blockGasLimit: 20000000,
        allowUnlimitedContractSize: true,
        accounts: {
          mnemonic:
            "clock radar mass judge dismiss just intact mind resemble fringe diary casino",
        },
      },
    };
  }
  return baseConfig.networks;
};

const config = {
  ...baseConfig,
  networks: networks(),
  etherscan: !process.env.ETHERSCAN_TOKEN
    ? {}
    : { apiKey: process.env.ETHERSCAN_TOKEN },
};

task("accounts", "Prints the list of accounts", async (_, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(await account.address);
  }
});

module.exports = config;
