# Smart contract template

### Using zeppelin & truffle framework

How to use:
```
> npm install
```

For deploy development:
```
> npm run deploy-dev
```
Or:
```
> truffle deploy development
```


Config truffle: truffle.js
```
module.exports = {
  networks: {
    development: {
      provider: provider,
      gas: 3000000,
      network_id: '*' // Match any network id
    }
  }
}
```

Config provider: 
```
var HDWalletProvider = require('truffle-hdwallet-provider');
var mnemonic = '<fill your mnemonic phrase>';
provider = new HDWalletProvider(mnemonic, '<your json rpc>')
```