const BabyBonkMigration = artifacts.require("BabyBonkMigration");
const BabyBonkV2 = artifacts.require("BabyBonkV2");
const BabyBonkV1 = artifacts.require("BabyBonk");
const IERC20 = artifacts.require("IERC20");
const IUniswapV2Router = artifacts.require("IUniswapV2Router02");
const IUniswapV2Factory = artifacts.require("IUniswapV2Factory");
const fs = require('fs');
const Web3 = require('web3');

const { getCurrentBlockTime, advanceTimeAndBlock } = require('../test/helper/time');

module.exports = async (deployer, network, accounts) => {
	const web3 = new Web3(deployer.provider);
	global.web3 = web3;
	const whaleAddressOld = "0x00AB0490dAE37A0086Ff4967E388Ac774bC711De";
	// const whale2AddressOld = "0xC3dcd744db3f114f0edF03682b807b78A227Bf74";
	const testAddress = "0xbd003Afb4Fd1CB2e18bd3b8a0AFaEb3b29E91849";

	// const amountV1 = 900000000000n;
	const owner = accounts[0];
	// const whaleAddress = accounts[1];
	
	// const block = await web3.eth.getBlock("latest");
	// router = await IUniswapV2Router.at("0x10ED43C718714eb63d5aA57B78B54704E256024E"); // PancakeSwap Router v2 mainnet
	// v1 token logic here
	const babybonkv1 = await BabyBonkV1.at("0xBb2826Ab03B6321E170F0558804F2B6488C98775"); // Replace with actual deployed address
	// let whaleBalance = await babybonkv1.balanceOf(whaleAddressOld);
	// await web3.eth.sendTransaction({
	// 	from: whaleAddress,
	// 	to: whaleAddressOld,
	// 	value: Web3.utils.toWei("1", "ether")
	// });
	// Deploying the v2 token contract.
	const blockTime = await getCurrentBlockTime();
	console.log("🚀 ~ blockTime:", blockTime);
	const babybonkv2 = await deployer.deploy(BabyBonkV2, blockTime + 2000 + 1.814e6, { 
		// gas: 6000000, 
		from: owner });

	const babybonkmigration = await deployer.deploy(
		BabyBonkMigration,
		babybonkv1.address,
		babybonkv2.address,
		blockTime + 2000, // Migration starts in the future
		{ from: owner, 
			// gas: 6000000 
		}
	);
	const jsonData = {
		migration: babybonkmigration.address,
		babybonkv2: babybonkv2.address
	}
	fs.writeFileSync("../frontend/src/deployed.json", JSON.stringify(jsonData, null, 2));

	const balanceOfOwner = await babybonkv2.balanceOf(owner);
                                              
	// doing necessary transfers and approvals
	const [approveTx, excludeFromPauseTx, excludeFromFeesTx, excludeFromMaxTransactionLimitTx, excludeFromMaxWalletTx ] = await Promise.all(
		[
			// web3.eth.sendTransaction({
				// 	from: whaleAddress,
				// 	to: testAddress,
				// 	value: Web3.utils.toWei("10", "ether")
				// }),
				// babybonkv1.transfer(testAddress, whaleBalance, {from: whaleAddressOld}),
				babybonkv2.approve(babybonkmigration.address, balanceOfOwner, {from: owner}),
				babybonkv2.excludeFromPause(babybonkmigration.address, true, {from: owner}),
				babybonkv2.excludeFromFees(babybonkmigration.address, true, {from: owner}),
				babybonkv2.excludeFromMaxTransactionLimit(babybonkmigration.address, true, {from: owner}),
				babybonkv2.excludeFromMaxWallet(babybonkmigration.address, true, {from: owner}),
			]
		);
		
		console.log("🚀 ~ excludeFromMaxWalletTx:", excludeFromMaxWalletTx?.receipt?.gasUsed);
		console.log("🚀 ~ excludeFromMaxWalletTx:", excludeFromPauseTx?.receipt?.gasUsed);
		console.log("🚀 ~ excludeFromMaxTransactionLimitTx:", excludeFromMaxTransactionLimitTx?.receipt?.gasUsed);
		console.log("🚀 ~ excludeFromFeesTx:", excludeFromFeesTx?.receipt?.gasUsed);
		console.log("🚀 ~ approveTx:", approveTx?.receipt?.gasUsed);
	

	console.log("balanceOf Owner", Number(web3.utils.fromWei(await web3.eth.getBalance(owner)), "ether"));
	// await advanceTimeAndBlock(10000, web3);
}


async function addLiquidity(babybonkv2, owner) {
  const router = await IUniswapV2Router.at("0x10ED43C718714eb63d5aA57B78B54704E256024E"); // PancakeSwap Router v2 mainnet
  const factory = await IUniswapV2Factory.at("0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73");
  const weth = '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c';
  const ownerBabyBonkV2Balance = await babybonkv2.balanceOf(owner);
  const tx = await factory.createPair(babybonkv2.address, weth, {from: owner});
  const pair = await factory.getPair(babybonkv2.address, weth, {from: owner});
  await babybonkv2.setPair(pair, {from: owner});
  // await babybonkv2.enableTrading(pair, {from: owner});
  // await babybonkv2.pairIsSet({from: owner});
  // Approve Pancake Router to spend tokens
  await babybonkv2.approve(router.address, ownerBabyBonkV2Balance, { from: owner });
  const blockTime = await getCurrentBlockTime();
  const deadline = blockTime + 1200; // 20 minutes from now
  const amountToDeposit = BigInt(Math.floor(Number(ownerBabyBonkV2Balance) * 0.5));
  assert.isTrue(amountToDeposit < BigInt(Number(ownerBabyBonkV2Balance)), "deposit amount is greater then the balance");
  // console.log("🚀 ~ addLiquidity ~ amountToDeposit:", amountToDeposit)
  // Add Liquidity to PancakeSwap: BabyBonkV2 <-> WBNB
  const ownerETHBalance = await web3.eth.getBalance(owner);
  const ethAmountToDeposit = web3.utils.toWei("10", "ether");
  assert.isTrue(ownerETHBalance > ethAmountToDeposit, `Eth balance should be greater then 10: Current balance = ${web3.utils.fromWei(ownerETHBalance, 'ether')}`);
  await router.addLiquidityETH(
    babybonkv2.address,
    amountToDeposit.toString(),
    0,
    0,
    owner,
    deadline,
    {from: owner, value: ethAmountToDeposit}
  );
  await babybonkv2.enableTrading(pair, { from: owner });
}