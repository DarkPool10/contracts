import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const DarkPoolFactoryModule = buildModule("DarkPoolFactoryModuleD", (m) => {
  const darkPoolFactory = m.contract("DarkPoolFactory", [], {});

  return { darkPoolFactory };
});

export default DarkPoolFactoryModule;
