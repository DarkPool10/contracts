import { HardhatUserConfig } from "hardhat/config";
import "ten-hardhat-plugin";
import "@openzeppelin/hardhat-upgrades";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  solidity: "0.8.10",
  networks: {
    hardhat: {
      // Configuration for the Hardhat Network
    },
    ten: {
      url: "https://testnet.ten.xyz/v1/",
      chainId: 443,
      // accounts: ["your-private-key"],
    },
  },
};

export default config;
