import { ethers, upgrades, run } from "hardhat";
import readline from "readline/promises";
import { stdin as input, stdout as output } from "process";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  const rl = readline.createInterface({ input, output });

  const tokenName = await rl.question("Enter the token name (default is MWX Token): ");
  const tokenSymbol = await rl.question("Enter the token symbol (default is MWXT): ");
  let tokenTotalSupply = await rl.question("Enter the token total supply (default is 1000000000): ");
  if (!tokenTotalSupply || tokenTotalSupply == "") {
    tokenTotalSupply = "1000000000";
  }
  let tokenOwner = await rl.question("Enter the token owner (default is deployer): ");
  if (!tokenOwner || tokenOwner == "") {
    tokenOwner = deployer.address;
  }

  // Deploy MWXT token
  console.log("Deploying MWXT token...");
  const MWXT = await ethers.getContractFactory("MWXT");
  const mwxt = await upgrades.deployProxy(MWXT, [
    tokenName,
    tokenSymbol, 
    tokenTotalSupply, // 1 billion tokens
    tokenOwner
  ]);
  await mwxt.waitForDeployment();
  console.log("MWXT deployed to:", await mwxt.getAddress());

  console.log("\n=== Deployment Summary ===");
  console.log("MWXT Token:", await mwxt.getAddress());
  console.log("Token Name:", tokenName);
  console.log("Token Symbol:", tokenSymbol);
  console.log("Token Total Supply:", tokenTotalSupply);
  console.log("Token Owner:", tokenOwner);
  console.log("Token Decimals:", await mwxt.decimals());

  await run("verify:verify", {
    address: await mwxt.getAddress(),
    constructorArguments: [
      tokenName,
      tokenSymbol, 
      tokenTotalSupply, // 1 billion tokens
      tokenOwner
    ]
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 