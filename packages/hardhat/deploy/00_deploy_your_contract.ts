import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { Contract } from "ethers";

/**
 * Deploys a contract named "YourContract" using the deployer account and
 * constructor arguments set to the deployer address
 *
 * @param hre HardhatRuntimeEnvironment object.
 */
const deployYourContract: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  /*
    On localhost, the deployer account is the one that comes with Hardhat, which is already funded.

    When deploying to live networks (e.g `yarn deploy --network sepolia`), the deployer account
    should have sufficient balance to pay for the gas fees for contract creation.

    You can generate a random account with `yarn generate` or `yarn account:import` to import your
    existing PK which will fill DEPLOYER_PRIVATE_KEY_ENCRYPTED in the .env file (then used on hardhat.config.ts)
    You can run the `yarn account` command to check your balance in every network.
  */
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;

  // 1. Deploy DAppToken
  const dappTokenDeployment = await deploy("DAppToken", {
    from: deployer,
    args: [deployer], // initialOwner
    log: true,
    autoMine: true,
  });

  // 2. Deploy LPToken
  const lpTokenDeployment = await deploy("LPToken", {
    from: deployer,
    args: [deployer], // initialOwner
    log: true,
    autoMine: true,
  });

  await deploy("TokenFarm", {
    from: deployer,
    // Contract constructor arguments
    args: [dappTokenDeployment.address, lpTokenDeployment.address],
    log: true,
    // autoMine: can be passed to the deploy function to make the deployment process faster on local networks by
    // automatically mining the contract deployment transaction. There is no effect on live networks.
    autoMine: true,
  });

  // Get the deployed contract to interact with it after deploying.
  const TokenFarm = await hre.ethers.getContract<Contract>("TokenFarm", deployer);
  console.log("You have deployed the TokenFarm contract to:", TokenFarm.address);
  const DAppToken = await hre.ethers.getContract<Contract>("DAppToken", deployer);
  console.log("You have deployed the DAppToken contract to:", DAppToken.address);
  const LPToken = await hre.ethers.getContract<Contract>("LPToken", deployer);
  console.log("You have deployed the LPToken contract to:", LPToken.address);
};

export default deployYourContract;

// Tags are useful if you have multiple deploy files and only want to run one of them.
// e.g. yarn deploy --tags YourContract
deployYourContract.tags = ["TokenFarm"];
