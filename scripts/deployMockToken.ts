import { ethers, upgrades, run } from "hardhat";
import readline from "readline/promises";
import { stdin as input, stdout as output } from "process";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  const rl = readline.createInterface({ input, output });

  const tokenName = await rl.question("Enter the token name (default is Mock Token): ");
  const tokenSymbol = await rl.question("Enter the token symbol (default is MTK): ");
  let tokenTotalSupply = await rl.question("Enter the token total supply (default is 1000000000): ");
  if (!tokenTotalSupply || tokenTotalSupply == "") {
    tokenTotalSupply = "1000000000";
  }

  // Deploy MWXT token
  console.log("Deploying Mock Token...");
  const MockToken = await ethers.getContractFactory("MockERC20");
  const mockToken = await MockToken.deploy(tokenName, tokenSymbol, tokenTotalSupply);
  await mockToken.waitForDeployment();
  console.log("Mock Token deployed to:", await mockToken.getAddress());

  console.log("\n=== Deployment Summary ===");
  console.log("Mock Token:", await mockToken.getAddress());
  console.log("Token Name:", tokenName);
  console.log("Token Symbol:", tokenSymbol);
  console.log("Token Total Supply:", tokenTotalSupply);
  console.log("Token Owner:", deployer.address);
  console.log("Token Decimals:", await mockToken.decimals());

  await run("verify:verify", {
    address: await mockToken.getAddress(),
    constructorArguments: [
      tokenName,
      tokenSymbol, 
      tokenTotalSupply, // 1 billion tokens
    ]
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 