require("@nomicfoundation/hardhat-toolbox");
require("@openzeppelin/hardhat-upgrades");
require("dotenv").config();

const accounts = process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [];
module.exports = {
  solidity: {
    version: "0.8.28",
    settings: { optimizer: { enabled: true, runs: 200 }, viaIR: true }
  },
  networks: {
    hardhat: {},
    polygonAmoy: {
      url: process.env.POLYGON_AMOY_RPC_URL || "",
      chainId: 80002,
      accounts
    },
    polygon: {
      url: process.env.POLYGON_RPC_URL || "",
      chainId: 137,
      accounts
    }
  },
  etherscan: { apiKey: { polygonAmoy: process.env.POLYGONSCAN_API_KEY || "", polygon: process.env.POLYGONSCAN_API_KEY || "" } }
};
