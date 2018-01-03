const fs = require('fs')
const WalletProvider = require("truffle-wallet-provider");

var developmentWallet = require('ethereumjs-wallet').fromPrivateKey(Buffer.from("private_hex", "hex"));
var developmentProvider = new WalletProvider(developmentWallet, "https://jsonrpc")

module.exports = {
  networks: {
    development: {
      provider: developmentProvider,
      gas: 10000000,
      gasPrice: 0,
      network_id: '*'
    }

  }
}