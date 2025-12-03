import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-verify";
import "@nomicfoundation/hardhat-ignition-ethers";
import "@openzeppelin/hardhat-upgrades";
import { config as DotEnvConfig }from "dotenv";

DotEnvConfig();

const config = {
  solidity: {
    version: "0.8.28",
    settings: {
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 200,
      },
    }
  },
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545"
    },
    base_mainnet: {
      url: `${process.env.BASE_RPC_MAINNET}`,
      accounts: [`${process.env.BASE_MAINNET_PRIVATE_KEY}`]
    },
    base_testnet: {
      url: `${process.env.BASE_RPC_TESTNET}`,
      accounts: [`${process.env.BASE_TESTNET_PRIVATE_KEY}`]
    }
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: {
      base_mainnet: process.env.BASE_API_KEY,
      base_testnet: process.env.BASE_API_KEY,
    },
    customChains: [
      {
        network: 'base_mainnet',
        chainId: 8453,
        urls: {
          apiURL: "https://api.basescan.org/api",
          browserURL: "https://basescan.org"
        }
      },
      {
        network: 'base_testnet',
        chainId: 84532,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia.basescan.org"
        }
      }
    ]
  }
};

export default config;
