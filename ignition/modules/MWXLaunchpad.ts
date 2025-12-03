// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const _mwxtLaunchpadFutureId = "mwxtLaunchpadFutureId";

const MWXLaunchpadModule = buildModule("MWXLaunchpadModule", (m) => {
  const owner = m.getAccount(0);

  const usdt = m.getParameter("usdt");
  const usdc = m.getParameter("usdc");
  const initialOwner = m.getParameter("initialOwner");
  const adminVerifier = m.getParameter("adminVerifier");
  const destinationAddress = m.getParameter("destinationAddress");
  const decimalTokenSold = m.getParameter("decimalTokenSold");

  const startTime = m.getParameter("startTime"); // timestamp in seconds
  const endTime = m.getParameter("endTime"); // timestamp in seconds
  const tokenPrice = m.getParameter("tokenPrice"); // decimals 18
  const totalAllocation = m.getParameter("totalAllocation"); // decimals of token sold
  const softCap = m.getParameter("softCap"); // decimals of token payment token
  const hardCap = m.getParameter("hardCap"); // decimals of token payment token
  const minimumPurchase = m.getParameter("minimumPurchase"); // decimals of token payment token

  const implementation = m.contract("MWXLaunchpad", [], { id: _mwxtLaunchpadFutureId });

  const initialize = m.encodeFunctionCall(implementation, "initialize", [
    usdt,
    usdc,
    initialOwner,
    adminVerifier,
    destinationAddress,
    decimalTokenSold,
  ]);

  const proxy = m.contract("UUPSUpgradeableProxy", [implementation, initialize], {
    from: owner,
  });
  const mwxLaunchpad = m.contractAt("MWXLaunchpad", proxy);

  m.call(mwxLaunchpad, "configureSale", [
    startTime,
    endTime,
    tokenPrice,
    totalAllocation,
    softCap,
    hardCap,
    minimumPurchase,
    decimalTokenSold,
  ], {
    from: owner,
  });

  return { mwxLaunchpad, proxy, implementation };
});

export default MWXLaunchpadModule;
