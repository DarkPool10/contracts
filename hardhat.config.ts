import { HardhatUserConfig } from "hardhat/config";
import "ten-hardhat-plugin";
import "@openzeppelin/hardhat-upgrades";
import "@nomicfoundation/hardhat-toolbox";
import "dotenv/config";

const privateKey = process.env.PRIVATE_KEY;
if (!privateKey) {
  throw new Error("PRIVATE_KEY environment variable not set");
}

const config: HardhatUserConfig = {
  solidity: "0.8.20",
  networks: {
    hardhat: {
      // Configuration for the Hardhat Network
    },
    ten: {
      url: "https://testnet.ten.xyz/v1/?token=66228CF94036FAA00B76859D9EE109F80AC591E1",
      chainId: 443,
      accounts: [privateKey],
    },
  },
};

export default config;
