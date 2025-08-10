const {Web3} = require("web3");

const web3 = new Web3("http://127.0.0.1:8545");
global.web3 = web3;

const { advanceTimeAndBlock } = require("./test/helper/time");

advanceTimeAndBlock(1.914e6, web3);