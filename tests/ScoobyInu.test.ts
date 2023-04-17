import { expect } from "chai";
import hre from "hardhat";
import {Contract, Signer, BigNumber} from "ethers";
import colors from "ansi-colors";
import {HardhatRuntimeEnvironment} from "hardhat/types";

const advanceBlock = async (blocks: number) => {
  const hre = require("hardhat");
  if (blocks >= 10000) {
    console.log(`${colors.black.bgYellow('WARN')} travel through many blocks maybe slow`);
  }
  for (let i=0; i < blocks; i++) {
    await hre.ethers.provider.send("evm_mine", []);
  }
  return Promise.resolve(hre.ethers.provider.getBlock('latest'));
}

const deploySwap = async(admin: Signer) => {
  // setup
  const WETH = await hre.ethers.getContractFactory("WETH");
  const weth = await WETH.deploy();
  await weth.deployed();

  const Factory = await hre.ethers.getContractFactory("UniswapV2Factory");
  const factory = await Factory.deploy(await admin.getAddress());
  await factory.deployed();

  const Router = await hre.ethers.getContractFactory("UniswapV2Router02");
  const router = await Router.deploy(factory.address, weth.address);
  await factory.deployed();

  return {weth, factory, router};
}


const deployScoobyInu = async(): Promise<{
  admin: Signer, users: Signer[], marketing: string,
  weth: Contract, factory: Contract, router: Contract, scooby: Contract
}> =>{
  const signers = await hre.ethers.getSigners();
  const admin = signers[0];
  const marketing = "0xE193F09e19f536dAC5A69513DD4505475C29bdec";
  const users = signers.slice(1,);

  const {weth, factory, router} = await deploySwap(admin);

  const Scooby = await hre.ethers.getContractFactory("ScoobyInu");
  let scooby;
  try {
    scooby = await Scooby.deploy(router.address, marketing);
    await scooby.deployed();
  } catch(e) {
    console.error(e);
  }

  return {admin, users, marketing, weth, factory, router, scooby};
};


describe("ScoobyInu", function () {
  it("deploy", async()=>{
    const {users, scooby, router, weth} = await deployScoobyInu();
  });

  it("first liquidity", async function() {
    const {admin, users, scooby, router, weth} = await deployScoobyInu();

    const totalSupply = await scooby.totalSupply();
    // must > maxTransactionAmount
    let initAmount = totalSupply.div(users.length).div(10);

    await (await scooby.transfer(await users[0].getAddress(), initAmount)).wait();
    await (await scooby.connect(users[0]).approve(
      router.address, hre.ethers.constants.MaxUint256
    )).wait();

    const ethInput = BigNumber.from(10).mul(1e9).mul(1e9);

    expect(await scooby.buyTax()).to.eq(15);
    expect(await scooby.sellTax()).to.eq(17);

    await (await scooby.excludeFromTax(await users[0].getAddress(), true)).wait();
    await (await router.connect(users[0]).addLiquidityETH(
      scooby.address,
      initAmount,
      0, 0,
      await users[0].getAddress(),
      Math.floor(new Date().getTime()/1000)+3600,
      {value: ethInput}
    )).wait();

    await advanceBlock(3);
    await(await scooby.transfer(await admin.getAddress(), 1)).wait();

    expect(await scooby.buyTax()).to.eq(10);
    expect(await scooby.sellTax()).to.eq(10);
  });

});
