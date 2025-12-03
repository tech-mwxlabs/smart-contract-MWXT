// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const _mwxtFutureId = "mwxtFutureId";

const MWXTModule = buildModule("MWXTModule", (m) => {
  const owner = m.getAccount(0);

  const name = m.getParameter("name");
  const symbol = m.getParameter("symbol");
  const initialSupply = m.getParameter("initialSupply");
  const initialOwner = m.getParameter("initialOwner");

  const implementation = m.contract("MWXT", [], { id: _mwxtFutureId });

  const initialize = m.encodeFunctionCall(implementation, "initialize", [
    name,
    symbol,
    initialSupply,
    initialOwner,
  ]);

  const proxy = m.contract("UUPSUpgradeableProxy", [implementation, initialize], {
    from: owner,
  });
  const mwxt = m.contractAt("MWXT", proxy);

  return { mwxt, proxy, implementation };
});

export default MWXTModule;
