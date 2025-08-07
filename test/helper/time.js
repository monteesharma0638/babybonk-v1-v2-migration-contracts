// In a file like './test/helpers/time.js'
const advanceTime = (time) => {
  return new Promise((resolve, reject) => {
    web3.currentProvider.send(
      {
        jsonrpc: '2.0',
        method: 'evm_increaseTime',
        params: [time],
        id: new Date().getTime(),
      },
      (err, result) => {
        if (err) {
          return reject(err);
        }
        return resolve(result);
      }
    );
  });
};

const advanceBlock = () => {
  return new Promise((resolve, reject) => {
    web3.currentProvider.send(
      {
        jsonrpc: '2.0',
        method: 'evm_mine',
        id: new Date().getTime(),
      },
      (err, result) => {
        if (err) {
          return reject(err);
        }
        const newBlockHash = web3.eth.getBlock('latest').hash;
        return resolve(newBlockHash);
      }
    );
  });
};

// A combined helper is even more useful
const advanceTimeAndBlock = async (time) => {
  await advanceTime(time);
  await advanceBlock();
  return;
};

const getCurrentBlockTime = async () => {
  const block = await web3.eth.getBlock('latest');
  return block.timestamp;
};

module.exports = {
  advanceTime,
  advanceBlock,
  advanceTimeAndBlock,
  getCurrentBlockTime
};