// require("dotenv").config();
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-truffle5");
require("@nomiclabs/hardhat-etherscan");
require("hardhat-gas-reporter");
require("solidity-coverage");
require("@nomiclabs/hardhat-solhint");
require("hardhat-contract-sizer");
require("@openzeppelin/hardhat-upgrades");

// const PRIVATE_KEY = process.env.PRIVATE_KEY;

module.exports = {
  solidity: {
    version: "0.8.2",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  gasReporter: {
    currency: "USD",
    enabled: false,
    gasPrice: 50,
  },
  paths: {
    tests: "./test",
  },
  networks: {
    hardhat: {
      blockGasLimit: 20000000,
    },
    mumbai: {
      url:
        "https://polygon-mumbai.g.alchemy.com/v2/q5_h_8LI6tg6eVk234iKqKm6H4JGS-Zy",
    },
    polygon: {
      url:
        "https://polygon-mainnet.g.alchemy.com/v2/JRptRNLZzr65CeN9PyapuBIFbFMu7CtM",
      gasMultiplier: 2,
    },
  },
  etherscan: {
    apiKey: "46DD6NK19R2AZQQIJIY1FXR85HKM2XSNBE",
  },
};
