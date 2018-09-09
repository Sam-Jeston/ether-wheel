/*
   Oraclize random-datasource example
   This contract uses the random-datasource to securely generate off-chain N random bytes
*/

pragma solidity ^0.4.23;

import "./OricalizeApi.sol";
import "./StringUtils.sol";

contract EtherWheel is usingOraclize {
    struct Bet {
      address better;
      string status;
      bytes32 queryId;
      uint betAmount;
      string betType;
    }

    event newRandomNumber_bytes(bytes);
    event newRandomNumber_uint(uint);

    /* The key is the queryId. The resultant uint is the random number */
    mapping(bytes32 => uint) public randomNumbers;

    /* The key is the betters id, and their list of bets */
    mapping(address => Bet[]) public betsByAccount;

    /* The key is the query id, and the associated bet */
    mapping(bytes32 => Bet) public betsByQueryId;

    /* The key is the betters id, and their list of queryIds */
    mapping(address => bytes32[]) public querysByAccount;

    function EtherWheel() {
        oraclize_setProof(proofType_Ledger); // sets the Ledger authenticity proof in the constructor
    }

    // the callback function is called by Oraclize when the result is ready
    // the oraclize_randomDS_proofVerify modifier prevents an invalid proof to execute this function code:
    // the proof validity is fully verified on-chain
    function __callback(bytes32 _queryId, string _result, bytes _proof) {
        require(msg.sender != oraclize_cbAddress());
        require(oraclize_randomDS_proofVerify__returnCode(_queryId, _result, _proof) == 0);

        // the proof verification has passed
        // now that we know that the random number was safely generated, let's use it..

        // for simplicity of use, let's also convert the random bytes to uint if we need
        uint maxRange = 99; // this is the highest uint we want to get. It should never be greater than 2^(8*N), where N is the number of random bytes we had asked the datasource to return
        uint randomNumber = uint(sha3(_result)) % maxRange; // this is an efficient way to get the uint out in the [0, maxRange] range

        randomNumbers[_queryId] = randomNumber;

        Bet storage bet = betsByQueryId[_queryId];

        /* House Advantage. Always a loss */
        if (randomNumber == 0) {
          bet.status = "loss";
          return;
        }

        /* Odd Bet Win */
        if (StringUtils.equal(bet.betType, "odd") && randomNumber % 2 == 1) {
          bet.status = "win";
          bet.better.transfer(bet.betAmount * 2);
          return;
        }

        /* Odd Bet Loss */
        if (StringUtils.equal(bet.betType, "odd") && randomNumber % 2 == 0) {
          bet.status = "loss";
          return;
        }

        /* Even Bet Win */
        if (StringUtils.equal(bet.betType, "even") && randomNumber % 2 == 0) {
          bet.status = "win";
          bet.better.transfer(bet.betAmount * 2);
          return;
        }

        /* Even Bet Loss */
        if (StringUtils.equal(bet.betType, "even") && randomNumber % 2 == 1) {
          bet.status = "loss";
          return;
        }
    }

    function placeBet(string _betType) public payable {
        uint N = 1; // number of random bytes we want the datasource to return
        uint delay = 0; // number of seconds to wait before the execution takes place
        uint callbackGas = 200000; // amount of gas we want Oraclize to set for the callback function
        bytes32 queryId = oraclize_newRandomDSQuery(delay, N, callbackGas); // this function internally generates the correct oraclize_query and returns its queryId

        querysByAccount[msg.sender].push(queryId);

        /* I assume we need to handle the callback gas value somewhere */
        /* TODO: Also make a max configurable value */
        require(msg.value > 0);

        require(StringUtils.equal(_betType, "even") || StringUtils.equal(_betType, "odd"));

        Bet memory bet = Bet(msg.sender, "placed", queryId, msg.value, _betType);
        betsByAccount[msg.sender].push(bet);
        betsByQueryId[queryId] = bet;
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}
