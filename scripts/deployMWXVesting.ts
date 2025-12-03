import { ethers, run, upgrades } from "hardhat";
import readline from "readline/promises";
import { stdin as input, stdout as output } from "process";
import { getValidatedTokenAddress, getTokenDecimals } from "./helper/deployment.helper";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  const rl = readline.createInterface({ input, output });

  // Get and validate Vesting Token address
  const vestingToken = await getValidatedTokenAddress(rl, "Vesting Token");
  const vestingTokenDecimals = await getTokenDecimals(vestingToken);
  console.log(`📊 Vesting Token decimals: ${vestingTokenDecimals}\n`);

  // Get owner and schedule manager
  let owner = await rl.question("Enter the contract owner address (default is deployer): ");
  if (!owner || owner === "") owner = deployer.address;
  let scheduleManager = await rl.question("Enter the schedule manager address (default is owner): ");
  if (!scheduleManager || scheduleManager === "") scheduleManager = owner;

  // Get max batch params
  const maxBatchForCreateVestingSchedule = Number(
    await rl.question("Enter max batch for create vesting schedule (default 50): ") || "50"
  );
  const maxBatchForRelease = Number(
    await rl.question("Enter max batch for release (default 50): ") || "50"
  );

  // Get default vesting params
  console.log("\nEnter default vesting parameters:");
  const startTimestampDays = Number(
    await rl.question("  Start in how many days from now? (default: 1): ") || "1"
  );
  const cliffDurationDays = Number(
    await rl.question("  Cliff duration (days, e.g. 0 for none): ") || "0"
  );
  const vestingDurationDays = Number(
    await rl.question("  Vesting duration (days, e.g. 365 for 1 year): ") || "365"
  );
  const releaseIntervalDays = Number(
    await rl.question("  Release interval (days, e.g. 30): ") || "30"
  );
  rl.close();

  // Convert days to seconds
  const now = Math.floor(Date.now() / 1000);
  const startTimestamp = now + startTimestampDays * 86400;
  const cliffDuration = cliffDurationDays * 86400;
  const vestingDuration = vestingDurationDays * 86400;

  const defaultParams = {
    startTimestamp,
    cliffDuration,
    vestingDuration,
    releaseIntervalDays,
  };

  console.log(`\n📋 Deployment Summary:`);
  console.log(`   Vesting Token: ${vestingToken} (${vestingTokenDecimals} decimals)`);
  console.log(`   Owner: ${owner}`);
  console.log(`   Schedule Manager: ${scheduleManager}`);
  console.log(`   Max Batch (Create): ${maxBatchForCreateVestingSchedule}`);
  console.log(`   Max Batch (Release): ${maxBatchForRelease}`);
  console.log(`   Default Vesting Params:`);
  console.log(`     Start Timestamp: ${startTimestamp} (${startTimestampDays} days from now, ${new Date(startTimestamp * 1000).toISOString()})`);
  console.log(`     Cliff Duration: ${cliffDuration} seconds (${cliffDurationDays} days)`);
  console.log(`     Vesting Duration: ${vestingDuration} seconds (${vestingDurationDays} days)`);
  console.log(`     Release Interval: ${releaseIntervalDays} days`);

  // Deploy MWXVesting
  console.log("Deploying MWXVesting...");
  const MWXVesting = await ethers.getContractFactory("MWXVesting");
  const mwxVesting = await upgrades.deployProxy(MWXVesting, [
    owner,
    scheduleManager,
    maxBatchForCreateVestingSchedule,
    maxBatchForRelease,
    defaultParams,
  ]);
  await mwxVesting.waitForDeployment();
  const vestingAddress = await mwxVesting.getAddress();
  console.log("MWXVesting deployed to:", vestingAddress);

  console.log("\n=== Deployment Summary ===");
  console.log("Vesting Token:", vestingToken);
  console.log("MWXVesting:", vestingAddress);
  console.log("Owner:", owner);
  console.log("Schedule Manager:", scheduleManager);
  console.log("Start Timestamp:", new Date(startTimestamp * 1000).toISOString());
  console.log("Cliff Duration (s):", cliffDuration, `(${cliffDurationDays} days)`);
  console.log("Vesting Duration (s):", vestingDuration, `(${vestingDurationDays} days)`);
  console.log("Release Interval (days):", releaseIntervalDays);

  await run("verify:verify", {
    address: vestingAddress,
    constructorArguments: [],
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
