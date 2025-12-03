import { ethers, run, upgrades } from "hardhat";
import readline from "readline/promises";
import { stdin as input, stdout as output } from "process";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying MWXDisperse contract with the account:", deployer.address);

  const rl = readline.createInterface({ input, output });

  // Get owner address
  let owner = await rl.question("Enter the contract owner address (default is deployer): ");
  if (!owner || owner === "") owner = deployer.address;

  // Get treasury address
  let treasuryAddress = await rl.question("Enter the treasury address: ");
  while (!treasuryAddress || treasuryAddress === "") {
    console.log("❌ Treasury address is required!");
    treasuryAddress = await rl.question("Enter the treasury address: ");
  }

  // Validate treasury address
  if (!ethers.isAddress(treasuryAddress)) {
    throw new Error("Invalid treasury address format");
  }

  // Get percentage configuration (in basis points - 10000 = 100%)
  console.log("\n📊 Percentage Configuration (in basis points - 10000 = 100%):");
  console.log("Example: 1000 = 10%, 5000 = 50%, 10000 = 100%");
  
  const treasuryPercentage = Number(
    await rl.question("Enter treasury percentage (basis points, default 10%): ") || "10"
  ) * 100;
  
  const recipientPercentage = Number(
    await rl.question("Enter recipient percentage (basis points, default 85%): ") || "85"
  ) * 100;
  
  const burnPercentage = Number(
    await rl.question("Enter burn percentage (basis points, default 5%): ") || "5"
  ) * 100;

  // Validate percentages sum to 100%
  const totalPercentage = treasuryPercentage + recipientPercentage + burnPercentage;
  if (totalPercentage !== 10000) {
    throw new Error(`Invalid percentages: ${treasuryPercentage / 100} + ${recipientPercentage / 100} + ${burnPercentage / 100} = ${totalPercentage / 100}. Must equal 100% (10000 in basis points)`);
  }

  // Get max recipients per transaction
  const maxRecipientsPerTx = Number(
    await rl.question("Enter max recipients per transaction (default 50): ") || "50"
  );

  if (maxRecipientsPerTx === 0) {
    throw new Error("Max recipients per transaction must be greater than 0");
  }

  rl.close();

  console.log(`\n📋 Deployment Summary:`);
  console.log(`   Owner: ${owner}`);
  console.log(`   Treasury Address: ${treasuryAddress}`);
  console.log(`   Treasury Percentage: ${treasuryPercentage / 100}% (${treasuryPercentage} in basis points)`);
  console.log(`   Recipient Percentage: ${recipientPercentage / 100}% (${recipientPercentage} in basis points)`);
  console.log(`   Burn Percentage: ${burnPercentage / 100}% (${burnPercentage} in basis points)`);
  console.log(`   Max Recipients Per Tx: ${maxRecipientsPerTx}`);

  // Deploy MWXDisperse
  console.log("\n🚀 Deploying MWXDisperse...");
  const MWXDisperse = await ethers.getContractFactory("MWXDisperse");
  const mwxDisperse = await upgrades.deployProxy(MWXDisperse, [
    owner,
    treasuryAddress,
    treasuryPercentage,
    recipientPercentage,
    burnPercentage,
    maxRecipientsPerTx
  ]);
  await mwxDisperse.waitForDeployment();
  const disperseAddress = await mwxDisperse.getAddress();
  console.log("✅ MWXDisperse deployed to:", disperseAddress);

  // Verify the deployment
  console.log("\n🔍 Verifying contract on Etherscan...");
  try {
    await run("verify:verify", {
      address: disperseAddress,
      constructorArguments: [],
    });
    console.log("✅ Contract verified successfully!");
  } catch (error: any) {
    console.log("⚠️  Verification failed:", error.message);
  }

  console.log("\n=== Deployment Summary ===");
  console.log("MWXDisperse:", disperseAddress);
  console.log("Owner:", owner);
  console.log("Treasury Address:", treasuryAddress);
  console.log("Treasury Percentage:", `${treasuryPercentage / 100}% (${treasuryPercentage} in basis points)`);
  console.log("Recipient Percentage:", `${recipientPercentage / 100}% (${recipientPercentage} in basis points)`);
  console.log("Burn Percentage:", `${burnPercentage / 100}% (${burnPercentage} in basis points)`);
  console.log("Max Recipients Per Tx:", maxRecipientsPerTx);
  console.log("\n💡 Next Steps:");
  console.log("1. Test the contract with small amounts first");
  console.log("2. Configure any additional settings via the owner functions");
  console.log("3. Monitor the contract for any issues");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 