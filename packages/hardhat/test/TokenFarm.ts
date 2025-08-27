import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

describe("Token Farm contract", function () {
  async function deployAllFixture() {
    const [owner, user1, user2] = await ethers.getSigners();

    // Tokens deployment
    const LPToken = await ethers.getContractFactory("LPToken");
    const lpToken = await LPToken.deploy(owner.address);
    await lpToken.waitForDeployment();

    const DAppToken = await ethers.getContractFactory("DAppToken");
    const dappToken = await DAppToken.deploy(owner.address);
    await dappToken.waitForDeployment();

    // Adresses Requier Contracts
    const lpTokenAddress = await lpToken.getAddress();
    const dappTokenAddress = await dappToken.getAddress();

    const TokenFarm = await ethers.getContractFactory("TokenFarm");
    const tokenFarm = await TokenFarm.deploy(dappTokenAddress, lpTokenAddress);
    await tokenFarm.waitForDeployment();

    // Adress deployed contract
    const tokenFarmAddress = await tokenFarm.getAddress();

    // Transfer ownership
    await dappToken.connect(owner).transferOwnership(tokenFarmAddress);

    // Mint LP tokens to users
    await lpToken.connect(owner).mint(user1.address, ethers.parseEther("100"));
    await lpToken.connect(owner).mint(user2.address, ethers.parseEther("200"));

    return { owner, user1, user2, lpToken, dappToken, tokenFarm };
  }

  it("Minteo de tokens LP para un usuario y depósito de esos tokens.", async function () {
    const { user1, lpToken, tokenFarm } = await loadFixture(deployAllFixture);

    await lpToken.connect(user1).approve(await tokenFarm.getAddress(), ethers.parseEther("100"));
    expect(await lpToken.balanceOf(await tokenFarm.getAddress())).to.equal(0n); // Use BigInt
    await expect(tokenFarm.connect(user1).deposit(ethers.parseEther("100")))
      .to.emit(tokenFarm, "SuccessDeposit")
      .withArgs(user1.address, ethers.parseEther("100"));

    expect(await lpToken.balanceOf(await tokenFarm.getAddress())).to.equal(ethers.parseEther("100")); // Use BigInt
    const user1Info = await tokenFarm.usersInfo(user1.address);
    expect(user1Info.stakingBalance).to.equal(ethers.parseEther("100")); // Use BigInt
  });

  it("Distribucion recompensas usuarios en staking.", async function () {
    const { owner, user1, user2, lpToken, tokenFarm } = await loadFixture(deployAllFixture);

    const tokenFarmAddress = await tokenFarm.getAddress();
    // const user1Info = await tokenFarm.usersInfo(user1.address);
    // const user2Info = await tokenFarm.usersInfo(user2.address);
    await lpToken.connect(user1).approve(tokenFarmAddress, ethers.parseEther("100"));
    await tokenFarm.connect(user1).deposit(ethers.parseEther("100"));
    await lpToken.connect(user2).approve(tokenFarmAddress, ethers.parseEther("200"));
    await tokenFarm.connect(user2).deposit(ethers.parseEther("200"));

    // console.log("user1Info.pendingRewards before", user1Info.pendingRewards);
    // console.log("user2Info.pendingRewards before", user2Info.pendingRewards);

    // Avanzar 10 bloques
    for (let i = 0; i < 10; i++) {
      await ethers.provider.send("evm_mine", []);
    }

    // Distribuir recompensas
    await expect(tokenFarm.connect(owner).distributeRewardsAll()).to.emit(tokenFarm, "RewardsDistributed");

    const user1Info = await tokenFarm.usersInfo(user1.address);
    const user2Info = await tokenFarm.usersInfo(user2.address);

    console.log("user1Info.pendingRewards after", user1Info.pendingRewards);
    console.log("user2Info.pendingRewards after", user2Info.pendingRewards);

    // Verificar recompensas
    console.log("user1Info.pendingRewards", user1Info.pendingRewards);
    console.log("user2Info.pendingRewards", user2Info.pendingRewards);
    console.log("user1Info.checkpoints", user1Info.checkpoints);
    expect(user2Info.pendingRewards).to.be.gt(user1Info.pendingRewards); // Use BigInt
    expect(user1Info.pendingRewards).to.be.gt(0n); // Use BigInt
    expect(user2Info.pendingRewards).to.be.gt(0n); // Use BigInt
  });

  it("Reclamo de recompensas y transferencia correcta.", async function () {
    const { owner, user1, lpToken, dappToken, tokenFarm } = await loadFixture(deployAllFixture);

    await lpToken.connect(user1).approve(await tokenFarm.getAddress(), ethers.parseEther("100"));
    await tokenFarm.connect(user1).deposit(ethers.parseEther("100"));
    await ethers.provider.send("evm_mine", []);
    await tokenFarm.connect(owner).distributeRewardsAll();

    const pendingRewards = (await tokenFarm.usersInfo(user1.address)).pendingRewards;
    const balanceBefore = await dappToken.balanceOf(user1.address);

    await expect(tokenFarm.connect(user1).claimRewards())
      .to.emit(tokenFarm, "SuccessClaimRewards")
      .withArgs(user1.address, pendingRewards);

    const balanceAfter = await dappToken.balanceOf(user1.address);
    expect(balanceAfter - balanceBefore).to.equal(pendingRewards);
    expect((await tokenFarm.usersInfo(user1.address)).pendingRewards).to.equal(0n); // Use BigInt
  });

  it("Deshacer staking y reclamar recompensas pendientes.", async function () {
    const { owner, user1, lpToken, tokenFarm } = await loadFixture(deployAllFixture);

    await lpToken.connect(user1).approve(await tokenFarm.getAddress(), ethers.parseEther("100"));
    await tokenFarm.connect(user1).deposit(ethers.parseEther("100"));
    await ethers.provider.send("evm_mine", []);
    await tokenFarm.connect(owner).distributeRewardsAll();

    // Retira el staking
    await expect(tokenFarm.connect(user1).withdraw())
      .to.emit(tokenFarm, "SuccessWithdraw")
      .withArgs(user1.address, ethers.parseEther("100"));

    // Puede reclamar recompensas pendientes aunque ya no esté en staking
    const pending = (await tokenFarm.usersInfo(user1.address)).pendingRewards;
    await expect(tokenFarm.connect(user1).claimRewards())
      .to.emit(tokenFarm, "SuccessClaimRewards")
      .withArgs(user1.address, pending);

    expect((await tokenFarm.usersInfo(user1.address)).pendingRewards).to.equal(0);
  });
});

// Verificar:
// Acuñar (mint) tokens LP para un usuario y realizar un depósito de esos tokens.
// Que la plataforma distribuya correctamente las recompensas a todos los usuarios en staking.
// Que un usuario pueda reclamar recompensas y verificar que se transfirieron correctamente a su cuenta.
// Que un usuario pueda deshacer el staking de todos los tokens LP depositados y reclamar recompensas pendientes, si las hay.
