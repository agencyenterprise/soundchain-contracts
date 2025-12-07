import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-solhint";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import dotenv from "dotenv";
import "hardhat-contract-sizer";
import "hardhat-gas-reporter";
import "hardhat-abi-exporter";

import { HardhatUserConfig } from "hardhat/config";
import "solidity-coverage";

dotenv.config();

const {
  PRIVATE_KEY,
  ETHERSCAN_API_KEY,
  POLYGONSCAN_API_KEY,
  BASESCAN_API_KEY,
  ARBISCAN_API_KEY,
} = process.env;

// Default to a dummy key if not set (for compilation only)
const accounts = PRIVATE_KEY ? [`0x${PRIVATE_KEY}`] : [];

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.10",
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
  abiExporter: {
    path: "./abi",
    runOnCompile: true,
    clear: true,
    spacing: 2,
  },
  networks: {
    // ============ Testnets ============
    mumbai: {
      url: "https://polygon-mumbai.g.alchemy.com/v2/PTbEov9b9XjfTgmiT9nuDM80Wl98Qg3t",
      accounts,
      gasPrice: 8000000000,
    },
    amoy: {
      url: "https://rpc-amoy.polygon.technology",
      accounts,
      chainId: 80002,
    },
    zetachain_testnet: {
      url: "https://zetachain-athens-evm.blockpi.network/v1/rpc/public",
      accounts,
      chainId: 7001,
      gasPrice: 20000000000,
    },
    sepolia: {
      url: "https://rpc.sepolia.org",
      accounts,
      chainId: 11155111,
    },

    // ============ Mainnets ============
    polygon: {
      url: "https://polygon-mainnet.g.alchemy.com/v2/JRptRNLZzr65CeN9PyapuBIFbFMu7CtM",
      accounts,
      chainId: 137,
    },
    ethereum: {
      url: "https://eth.llamarpc.com",
      accounts,
      chainId: 1,
    },
    zetachain: {
      url: "https://zetachain-evm.blockpi.network/v1/rpc/public",
      accounts,
      chainId: 7000,
      gasPrice: 20000000000,
    },
    arbitrum: {
      url: "https://arb1.arbitrum.io/rpc",
      accounts,
      chainId: 42161,
    },
    optimism: {
      url: "https://mainnet.optimism.io",
      accounts,
      chainId: 10,
    },
    base: {
      url: "https://mainnet.base.org",
      accounts,
      chainId: 8453,
    },
    avalanche: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      accounts,
      chainId: 43114,
    },
    blast: {
      url: "https://rpc.blast.io",
      accounts,
      chainId: 81457,
    },
  },
  etherscan: {
    apiKey: {
      mainnet: ETHERSCAN_API_KEY || "",
      polygon: POLYGONSCAN_API_KEY || ETHERSCAN_API_KEY || "",
      polygonMumbai: POLYGONSCAN_API_KEY || ETHERSCAN_API_KEY || "",
      arbitrumOne: ARBISCAN_API_KEY || "",
      base: BASESCAN_API_KEY || "",
    },
  },
};

export default config;
