import { parseUnits } from "ethers";
import { ethers, run, upgrades } from "hardhat";
import readline from "readline/promises";
import { stdin as input, stdout as output } from "process";
import { getValidatedTokenAddress, getTokenDecimals } from "./helper/deployment.helper";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  const rl = readline.createInterface({ input, output });

  // Get and validate USDT address
  const usdt = await getValidatedTokenAddress(rl, "USDT");
  const usdtDecimals = await getTokenDecimals(usdt);
  console.log(`📊 USDT decimals: ${usdtDecimals}\n`);

  // Get and validate USDC address
  const usdc = await getValidatedTokenAddress(rl, "USDC");
  const usdcDecimals = await getTokenDecimals(usdc);
  console.log(`📊 USDC decimals: ${usdcDecimals}\n`);

  const adminVerifier = await rl.question("Enter the admin verifier address: ");
  const destinationAddress = await rl.question("Enter the destination address: ");
  const decimalTokenSold = await rl.question("Enter the decimal of token sold: ");
  let initialOwner = await rl.question("Enter the initial owner (default is deployer): ");
  if (!initialOwner || initialOwner == "") {
    initialOwner = deployer.address;
  }
  let startTime = Number(await rl.question("Enter the start time (epoch time in seconds. eg. 1729190400): "));
  const currentTime = Math.floor(Date.now() / 1000);
  if (!startTime || startTime == undefined) {
    startTime = currentTime + 120; // Start in 2 minutes
  }

  let endTime = Number(await rl.question("Enter the end time (epoch time in seconds. eg. 1729190400): "));
  if (!endTime || endTime == undefined) {
    endTime = startTime + (30 * 24 * 3600); // End in 30 days
  }

  const tokenPrice = parseUnits(await rl.question("Enter the token price (eg. 0.06): "), 18);
  const totalAllocation = parseUnits(await rl.question("Enter the total allocation (eg. 100000000): "), 18);

  // Use appropriate decimals for soft cap and hard cap based on payment tokens
  console.log(`\n💡 Note: Using ${usdtDecimals} decimals for soft cap and hard cap (based on USDT/USDC decimals auto convert)`);
  const softCap = parseUnits(await rl.question("Enter the soft cap (eg. 1000000): "), usdtDecimals);
  const hardCap = parseUnits(await rl.question("Enter the hard cap (eg. 1500000): "), usdtDecimals);
  const minimumPurchase = parseUnits(await rl.question("Enter the minimum purchase (eg. 50000): "), usdtDecimals);
  rl.close();

  console.log(`\n📋 Deployment Summary:`);
  console.log(`   USDT: ${usdt} (${usdtDecimals} decimals)`);
  console.log(`   USDC: ${usdc} (${usdcDecimals} decimals)`);
  console.log(`   Initial Owner: ${initialOwner}`);
  console.log(`   Admin Verifier: ${adminVerifier}`);
  console.log(`   Destination: ${destinationAddress}`);
  console.log(`   Token Sold Decimals: ${decimalTokenSold}`);
  console.log(`   Start Time: ${startTime}`);
  console.log(`   End Time: ${endTime}`);
  console.log(`   Token Price: ${tokenPrice.toString()}`);
  console.log(`   Total Allocation: ${totalAllocation.toString()}`);
  console.log(`   Soft Cap: ${softCap.toString()}`);
  console.log(`   Hard Cap: ${hardCap.toString()}`);
  console.log(`   Minimum Purchase: ${minimumPurchase.toString()}\n`);

  // Deploy MWXLaunchpad
  console.log("Deploying MWXLaunchpad...");
  const MWXLaunchpad = await ethers.getContractFactory("MWXLaunchpad");
  const mwxLaunchpad = await upgrades.deployProxy(MWXLaunchpad, [
    usdt,
    usdc,
    initialOwner,
    adminVerifier,
    destinationAddress,
    decimalTokenSold
  ]);
  await mwxLaunchpad.waitForDeployment();
  console.log("MWXLaunchpad deployed to:", await mwxLaunchpad.getAddress());

  // Configure the sale
  console.log("Configuring sale...")

  await mwxLaunchpad.configureSale(
    startTime,
    endTime,
    tokenPrice,
    totalAllocation,
    softCap,
    hardCap,
    minimumPurchase,
    decimalTokenSold
  );
  console.log("Sale configured successfully!");

  console.log("\n=== Deployment Summary ===");
  console.log("Mock USDT:", usdt);
  console.log("Mock USDC:", usdc);
  console.log("MWXLaunchpad:", await mwxLaunchpad.getAddress());
  console.log("Sale Start Time:", new Date(startTime * 1000).toISOString());
  console.log("Sale End Time:", new Date(endTime * 1000).toISOString());

  await run("verify:verify", {
    address: await mwxLaunchpad.getAddress(),
    constructorArguments: []
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 