import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const CustomERC20Module = buildModule("CustomERC20Module", (m) => {
  const customErc20 = m.contract("CustomERC20", ["Token A", "TKA"], {});

  return { darkPoolFactory: customErc20 };
});

export default CustomERC20Module;
