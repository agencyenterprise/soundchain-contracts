// require("dotenv").config();
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-etherscan";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "@nomiclabs/hardhat-solhint";
import "hardhat-contract-sizer";
import "@openzeppelin/hardhat-upgrades";

// const PRIVATE_KEY = process.env.PRIVATE_KEY;

export const solidity = {
  version: "0.8.2",
  settings: {
    optimizer: {
      enabled: true,
      runs: 200,
    },
  },
};

export const gasReporter = {
  currency: "USD",
  enabled: false,
  gasPrice: 50,
};

export const paths = {
  tests: "./test",
};

export const networks = {
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
};

export const etherscan = {
  apiKey: "46DD6NK19R2AZQQIJIY1FXR85HKM2XSNBE",
};
