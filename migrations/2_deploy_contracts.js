var LetBetCreditManager = artifacts.require("./LetBetCreditManager.sol");
var LetBetSlotGame = artifacts.require("./LetBetSlotGame.sol");
var LetBetRouletteGame = artifacts.require("./LetBetRouletteGame.sol");
var LetBetSportGameEuropeanBetting = artifacts.require("./LetBetSportGameEuropeanBetting.sol");
var LetBetSportGameAsianBetting = artifacts.require("./LetBetSportGameAsianBetting.sol");
var LetBetSportGameOverUnderBetting = artifacts.require("./LetBetSportGameOverUnderBetting.sol");
var LetBetSportGameP2PBetting = artifacts.require("./LetBetSportGameP2PBetting.sol");

var LetBetCreditManagerAddress = "";

module.exports = function (deployer, network, accounts) {

  if (LetBetCreditManagerAddress == "") {
    deployer.deploy(LetBetCreditManager).then(function (instance) {

      deployer.deploy(LetBetSlotGame, LetBetCreditManager.address).then(function (instance) {
        LetBetCreditManager.deployed().then(function (instance) {
          instance.addFriend(LetBetSlotGame.address);
        })
      });

      deployer.deploy(LetBetRouletteGame, LetBetCreditManager.address).then(function (instance) {
        LetBetCreditManager.deployed().then(function (instance) {
          instance.addFriend(LetBetRouletteGame.address);
        })
      });

      deployer.deploy(LetBetSportGameEuropeanBetting, LetBetCreditManager.address).then(function (instance) {
        LetBetCreditManager.deployed().then(function (instance) {
          instance.addFriend(LetBetSportGameEuropeanBetting.address);
        })
      });

      deployer.deploy(LetBetSportGameAsianBetting, LetBetCreditManager.address).then(function (instance) {
        LetBetCreditManager.deployed().then(function (instance) {
          instance.addFriend(LetBetSportGameAsianBetting.address);
        })
      });

      deployer.deploy(LetBetSportGameOverUnderBetting, LetBetCreditManager.address).then(function (instance) {
        LetBetCreditManager.deployed().then(function (instance) {
          instance.addFriend(LetBetSportGameOverUnderBetting.address);
        })
      });

    });
  } else {

    deployer.deploy(LetBetSlotGame, LetBetCreditManagerAddress).then(function (instance) {
      LetBetCreditManager.at(LetBetCreditManagerAddress).addFriend(LetBetSlotGame.address);
    });
    deployer.deploy(LetBetRouletteGame, LetBetCreditManagerAddress).then(function (instance) {
      LetBetCreditManager.at(LetBetCreditManagerAddress).addFriend(LetBetRouletteGame.address);
    });

    deployer.deploy(LetBetSportGameEuropeanBetting, LetBetCreditManagerAddress).then(function (instance) {
      LetBetCreditManager.at(LetBetCreditManagerAddress).addFriend(LetBetSportGameEuropeanBetting.address);
    });

    deployer.deploy(LetBetSportGameAsianBetting, LetBetCreditManagerAddress).then(function (instance) {
      LetBetCreditManager.at(LetBetCreditManagerAddress).addFriend(LetBetSportGameAsianBetting.address);
    });

    deployer.deploy(LetBetSportGameOverUnderBetting, LetBetCreditManagerAddress).then(function (instance) {
      LetBetCreditManager.at(LetBetCreditManagerAddress).addFriend(LetBetSportGameOverUnderBetting.address);
    });

    deployer.deploy(LetBetSportGameP2PBetting, LetBetCreditManagerAddress).then(function (instance) {
      LetBetCreditManager.at(LetBetCreditManagerAddress).addFriend(LetBetSportGameP2PBetting.address);
    });

  }

};