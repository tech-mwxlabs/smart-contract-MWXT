import { parseUnits } from "ethers";
import { ethers, upgrades } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // Deploy MWXT token
  console.log("Deploying MWXT token...");
  const MWXT = await ethers.getContractFactory("MWXT");
  const mwxt = await upgrades.deployProxy(MWXT, [
    "MWX Token",
    "MWXT", 
    1000000000, // 1 billion tokens
    deployer.address
  ]);
  await mwxt.waitForDeployment();
  console.log("MWXT deployed to:", await mwxt.getAddress());

  // Deploy Mock USDT and USDC for testing
  console.log("Deploying Mock USDT...");
  const MockERC20 = await ethers.getContractFactory("MockERC20");
  const mockUsdt = await MockERC20.deploy("Tether USD", "USDT", 1000000);
  await mockUsdt.waitForDeployment();
  console.log("Mock USDT deployed to:", await mockUsdt.getAddress());

  console.log("Deploying Mock USDC...");
  const mockUsdc = await MockERC20.deploy("USD Coin", "USDC", 1000000);
  await mockUsdc.waitForDeployment();
  console.log("Mock USDC deployed to:", await mockUsdc.getAddress());

  // Deploy MWXLaunchpad
  console.log("Deploying MWXLaunchpad...");
  const MWXLaunchpad = await ethers.getContractFactory("MWXLaunchpad");
  const mwxLaunchpad = await upgrades.deployProxy(MWXLaunchpad, [
    await mockUsdt.getAddress(),
    await mockUsdc.getAddress(),
    deployer.address, // owner
    deployer.address, // adminVerifier
    deployer.address, // destinationAddress
    18 // decimalTokenSold
  ]);
  await mwxLaunchpad.waitForDeployment();
  console.log("MWXLaunchpad deployed to:", await mwxLaunchpad.getAddress());

  // Configure the sale
  console.log("Configuring sale...");
  const currentTime = Math.floor(Date.now() / 1000);
  const startTime = currentTime + 60; // Start in 1 minute
  const endTime = startTime + (30 * 24 * 3600); // End in 30 days

  await mwxLaunchpad.configureSale(
    startTime,
    endTime,
    parseUnits("0.25", 18), // $0.25 per token (6 decimals)
    parseUnits("100000000", 18), // 100M tokens allocation
    parseUnits("1000000", 6), // $1M soft cap
    parseUnits("100000000", 6), // $100M hard cap
    parseUnits("100", 6), // $100 minimum purchase
    18 // decimalTokenSold
  );
  console.log("Sale configured successfully!");

  console.log("\n=== Deployment Summary ===");
  console.log("MWXT Token:", await mwxt.getAddress());
  console.log("Mock USDT:", await mockUsdt.getAddress());
  console.log("Mock USDC:", await mockUsdc.getAddress());
  console.log("MWXLaunchpad:", await mwxLaunchpad.getAddress());
  console.log("Sale Start Time:", new Date(startTime * 1000).toISOString());
  console.log("Sale End Time:", new Date(endTime * 1000).toISOString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 