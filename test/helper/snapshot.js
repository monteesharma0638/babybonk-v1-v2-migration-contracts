async function takeSnapshot() {
  return new Promise((resolve, reject) => {
    web3.currentProvider.send(
      { jsonrpc: '2.0', method: 'evm_snapshot', id: new Date().getTime() },
      (err, result) => {
        if (err) return reject(err);
        resolve(result.result);
      }
    );
  });
}

const revertSnapshot = (snapshotId) => {
  return new Promise((resolve, reject) => {
    web3.currentProvider.send(
      {
        jsonrpc: '2.0',
        method: 'evm_revert',
        params: [snapshotId],
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

module.exports = {
  takeSnapshot,
  revertSnapshot,
};