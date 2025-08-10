const BabyBonkMigration = artifacts.require("BabyBonkMigration");
const BabyBonkV2 = artifacts.require("BabyBonkV2");
const BabyBonkV1 = artifacts.require("BabyBonk");
const IERC20 = artifacts.require("IERC20");
const IUniswapV2Router = artifacts.require("IUniswapV2Router02");
const IUniswapV2Factory = artifacts.require("IUniswapV2Factory");
const { advanceTimeAndBlock, getCurrentBlockTime } = require("./helper/time");
const {takeSnapshot, revertSnapshot} = require("./helper/snapshot");

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

/*
 * uncomment accounts to access the test accounts made available by the
 * Ethereum client
 * See docs: https://www.trufflesuite.com/docs/truffle/testing/writing-tests-in-javascript
 * start ganache-cli using this command. This test need mainnet bsc fork.
 * ganache-cli   --fork https://rpc.ankr.com/bsc/385e4834e32a582cf24cc4881a8269265b95a4aab8ef0134ff28b2512a16d5eb  --unlock 0xC3dcd744db3f114f0edF03682b807b78A227Bf74 --gasLimit 75000000 --gasPrice 110000000   --unlock 0x00AB0490dAE37A0086Ff4967E388Ac774bC711De   --accounts 10
 */
contract("BabyBonkMigration", function (accounts) {
  let babybonkmigration, babybonkv2, snapshotId, babybonkv1, router;
  const whaleAddress = "0x00AB0490dAE37A0086Ff4967E388Ac774bC711De";
  const whale2Address = "0xC3dcd744db3f114f0edF03682b807b78A227Bf74";
  const amountV1 = 900000000000n;
  const owner = accounts[0];
  // const user1 = accounts[1];
  // const user2 = accounts[2];
  beforeEach(async () => {
    advanceTimeAndBlock(100);
    snapshotId = await takeSnapshot();
    const block = await web3.eth.getBlock("latest");
    router = await IUniswapV2Router.at("0x10ED43C718714eb63d5aA57B78B54704E256024E"); // PancakeSwap Router v2 mainnet

    babybonkv1 = await BabyBonkV1.at("0xBb2826Ab03B6321E170F0558804F2B6488C98775"); // Replace with actual deployed address
    // Deploying the v2 token contract.
    const blockTime = await getCurrentBlockTime();
    babybonkv2 = await BabyBonkV2.new(blockTime + 300, {gas: 6000000, from: owner});

    babybonkmigration = await BabyBonkMigration.new(
      babybonkv1.address,
      babybonkv2.address,
      blockTime + 10000, // Migration starts in the future
      { from: owner, gas: 6000000}
    );
    const balanceOfowner = await babybonkv2.balanceOf(owner);

    // doing necessary transfers and approvals
    await Promise.all(
      [
        web3.eth.sendTransaction({
          from: owner,
          to: whaleAddress,
          value: web3.utils.toWei("1", "ether"),
        }),
        web3.eth.sendTransaction({
          from: owner,
          to: whale2Address,
          value: web3.utils.toWei("1", "ether"),
        }),
        babybonkv1.approve(babybonkmigration.address, amountV1, {from: whaleAddress}),
        babybonkv1.approve(babybonkmigration.address, amountV1, {from: whale2Address}),
        babybonkv2.approve(babybonkmigration.address, balanceOfowner, {from: owner}),
        babybonkv2.excludeFromFees(babybonkmigration.address, true, {from: owner}),
        babybonkv2.excludeFromMaxTransactionLimit(babybonkmigration.address, true, {from: owner}),
        babybonkv2.excludeFromMaxWallet(babybonkmigration.address, true, {from: owner}),
      ]
    )
  })

  // After each test, revert to the last snapshot.
  afterEach(async () => {
    await revertSnapshot(snapshotId);
  });

  it("Just a normal before and after each test", async () => {
    assert.ok(babybonkv1.address, "babybonkv2 should be deployed");
  })

  it("Whale should not excluded from babybonk v1", async () => {
    for(i = 0; i < 2; i++) {
      const address = i = 1? whaleAddress : whale2Address;
      const isExcludedFromMaxWalletLimit = await babybonkv1.isExcludedFromMaxWalletLimit(address);
      const isExcludedFromMaxTransaction = await babybonkv1.isExcludedFromMaxTransaction(address);
      const isExcludedFromFees = await babybonkv1.isExcludedFromFees(address);
      assert.isTrue(!isExcludedFromFees, `${address} included in isExcludedFromFees`);
      assert.isTrue(!isExcludedFromMaxTransaction, `${address} included in isExcludedFromMaxTransaction`);
      assert.isTrue(!isExcludedFromMaxWalletLimit, `${address} included in isExcludedFromMaxWalletLimit`);
    }
  })

  it("should not allow migration before start time", async () => {
    try {
      await babybonkmigration.migrate(amountV1, 0, { from: whaleAddress });
      assert.fail("Migration should not be allowed before start time");
    } catch (error) {
      assert.include(error?.message, "TokenMigrator: Migration not yet active");
    }
  });

  it("should able to migrate after start time", async () => {
    try {
      await advanceTimeAndBlock(10000);
      await babybonkmigration.migrate(amountV1, 0, {from: whaleAddress});
    }
    catch(error) {
      assert.fail(error?.message, "Migration not done properly even after started.");
    }
  })

  it("should not able to migrate after phase 2 starts before adding liquidity", async () => {
    try {
      await advanceTimeAndBlock(10000);
      await babybonkmigration.migrate(amountV1, 0, {from: whaleAddress});
      await advanceTimeAndBlock(1.914e6);
      await babybonkv1.approve(babybonkmigration.address, amountV1, {from: whale2Address});
      await babybonkmigration.migrate(amountV1, 0, {from: whale2Address});
      assert.fail("Migration should not be allowed before adding liquidity");
    }
    catch(error) {
      assert.ok(true, "TokenMigrator: Liquidity not added yet.");
    }
  })

  it("validate transfer amount on phase 1", async () => {
    try {
      await advanceTimeAndBlock(10000);
      const [bWhaleV1Prev, bWhaleV2Prev, bMigrationV1Prev, bOwnerV2Prev] = await Promise.all([
        babybonkv1.balanceOf(whale2Address),
        babybonkv2.balanceOf(whale2Address),
        babybonkv1.balanceOf(babybonkmigration.address),
        babybonkv2.balanceOf(owner),
      ]);
      await babybonkmigration.migrate(amountV1, 0, {from: whale2Address});
      const [bWhaleV1After, bWhaleV2After, bMigrationV1After, bOwnerV2After] = await Promise.all([
        babybonkv1.balanceOf(whale2Address),
        babybonkv2.balanceOf(whale2Address),
        babybonkv1.balanceOf(babybonkmigration.address),
        babybonkv2.balanceOf(owner),
      ])
      assert.equal(Number(bMigrationV1After - bMigrationV1Prev), Number(amountV1), "amount received must be same as the amount sent in transaction.");
      assert.isTrue(Number(bWhaleV1Prev - bWhaleV1After)/Number(bMigrationV1After - bMigrationV1Prev) > 0.99, "Received v1 token amount mismatch.");
      assert.isTrue(Number(bOwnerV2Prev - bOwnerV2After)/Number(bWhaleV2After - bWhaleV2Prev) > 0.99, "Received token amount should be equal what is sent.");
    }
    catch(err) {
      assert.fail(err?.message);
    }
  })

  it("Babybonk v2 transferFrom should work", async () => {
    await advanceTimeAndBlock(10000);
    await babybonkv2.approve(whale2Address,  amountV1, {from: owner});
    await babybonkv2.transferFrom(owner, whaleAddress, amountV1, {from: whale2Address});
    const bWhaleAddress = await babybonkv2.balanceOf(whaleAddress);
    assert.equal(bWhaleAddress, amountV1, "Balance transfer is not equal");
  })
  
  it("should be able to migrate after phase 2 starts and after adding liquidity", async () => {
      const owner = accounts[0];
        // Step 1: Phase 1 migration
      await advanceTimeAndBlock(10000);
      const amountToMigrate = BigInt(10**12);
      await babybonkv1.approve(babybonkmigration.address, amountToMigrate, {from: whale2Address})
      await babybonkmigration.migrate(amountToMigrate, 0, { from: whale2Address });
      // Step 3: Advance time to Phase 2
      await advanceTimeAndBlock(1.914e6); // 22 days
      await addLiquidity(babybonkv2, owner); // adding liquidity
      // Step 4: Whale2 migrates after liquidity is added
      const weth = await router.WETH();
      const path = [babybonkv1.address, weth, babybonkv2.address];
      const [,,expectedAmount] = await router.getAmountsOut(
        amountToMigrate,
        path
      );
      // console.log("🚀 ~ expectedAmount:", expectedAmount.toString())
      await babybonkv1.approve(router.address, amountToMigrate, { from: whaleAddress });
      // console.log("🚀 ~ weth:", weth)
      const blockTime = await getCurrentBlockTime();
      const initialBalance = await babybonkv2.balanceOf(whaleAddress);
      await router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
        amountToMigrate,
        0,
        path,
        whaleAddress,
        BigInt(blockTime + 300).toString(),
        {
          from: whaleAddress
        }
      )
      const finalBalance = await babybonkv2.balanceOf(whaleAddress);
      const actualAmount = finalBalance - initialBalance;
      // console.log("🚀 ~ actualAmount:", actualAmount)
      const calculation = actualAmount/expectedAmount;
      // console.log("🚀 ~ calculation:", calculation);
      assert.isTrue(1 > calculation > 0.90, "Very low output:::" + calculation);
  });
});
